import Foundation
import UIKit
import os.log

/// Service for caching Square catalog images locally with persistence and cleanup
@MainActor
class ImageCacheService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isClearing = false
    @Published var cacheSize: Int64 = 0
    @Published var cachedImagesCount: Int = 0
    
    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private let imageURLManager: ImageURLManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageCache")
    
    // MARK: - Cache Configuration
    
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB max cache
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    // MARK: - In-Memory Cache
    
    private var memoryCache = NSCache<NSString, UIImage>()
    private var downloadTasks: [String: Task<UIImage?, Error>] = [:]
    
    // MARK: - Initialization

    init(imageURLManager: ImageURLManager? = nil) {
        // Create cache directory in Documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("ImageCache")

        // Initialize URL manager (create default if not provided)
        if let urlManager = imageURLManager {
            self.imageURLManager = urlManager
        } else {
            let dbManager = SQLiteSwiftCatalogManager()
            self.imageURLManager = ImageURLManager(databaseManager: dbManager)
        }
        
        // Configure memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit
        
        // Create cache directory if needed
        createCacheDirectoryIfNeeded()
        
        // Calculate initial cache size
        Task {
            await updateCacheStats()
        }
        
        logger.info("🖼️ ImageCacheService initialized with cache directory: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Public Methods

    /// Load image from URL with caching (handles both AWS URLs and internal cache URLs)
    func loadImage(from urlString: String) async -> UIImage? {
        // Handle internal cache URLs (cache://key)
        if urlString.hasPrefix("cache://") {
            let cacheKey = String(urlString.dropFirst(8)) // Remove "cache://"
            return loadImageFromDisk(cacheKey: cacheKey)
        }

        return await loadImageFromAWSUrl(urlString)
    }

    /// Load image specifically from AWS URL with full caching pipeline
    func loadImageFromAWSUrl(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL string: \(urlString)")
            return nil
        }

        // Try to get existing cache key from URL manager first
        let cacheKey: String
        if let existingKey = try? imageURLManager.getLocalCacheKey(for: urlString) {
            cacheKey = existingKey
        } else {
            cacheKey = cacheKeyForURL(urlString)
        }
        
        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: cacheKey as NSString) {
            logger.debug("📱 Image loaded from memory cache: \(urlString)")
            return cachedImage
        }
        
        // Check disk cache
        if let diskImage = loadImageFromDisk(cacheKey: cacheKey) {
            // Store in memory cache for faster access
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString)
            logger.debug("💾 Image loaded from disk cache: \(urlString)")
            return diskImage
        }
        
        // Check if already downloading
        if let existingTask = downloadTasks[cacheKey] {
            logger.debug("⏳ Image already downloading, waiting: \(urlString)")
            return try? await existingTask.value
        }
        
        // Download image
        let downloadTask = Task<UIImage?, Error> {
            return try await downloadAndCacheImage(from: url, cacheKey: cacheKey)
        }
        
        downloadTasks[cacheKey] = downloadTask
        
        do {
            let image = try await downloadTask.value
            downloadTasks.removeValue(forKey: cacheKey)
            return image
        } catch {
            downloadTasks.removeValue(forKey: cacheKey)
            logger.error("❌ Failed to download image: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Cache image with proper URL mapping (used during sync)
    func cacheImageWithMapping(
        awsUrl: String,
        squareImageId: String,
        objectType: String,
        objectId: String,
        imageType: String = "PRIMARY"
    ) async -> String? {

        do {
            // Store URL mapping first
            let cacheKey = try imageURLManager.storeImageMapping(
                squareImageId: squareImageId,
                awsUrl: awsUrl,
                objectType: objectType,
                objectId: objectId,
                imageType: imageType
            )

            // Download and cache the image
            if let _ = await loadImageFromAWSUrl(awsUrl) {
                logger.info("✅ Cached image with mapping: \(squareImageId) -> \(cacheKey)")
                return "cache://\(cacheKey)"
            }

        } catch {
            logger.error("❌ Failed to cache image with mapping: \(error.localizedDescription)")
        }

        return nil
    }

    /// Clear all cached images (for full sync cleanup)
    func clearAllImages() async {
        isClearing = true
        
        logger.info("🧹 Clearing all cached images...")
        
        // Clear memory cache
        memoryCache.removeAllObjects()
        
        // Cancel ongoing downloads
        for task in downloadTasks.values {
            task.cancel()
        }
        downloadTasks.removeAll()
        
        // Clear URL mappings (gracefully handle database unavailability)
        do {
            try imageURLManager.clearAllImageMappings()
            logger.debug("✅ Image URL mappings cleared")
        } catch {
            logger.warning("⚠️ Could not clear image URL mappings (database may not be ready): \(error.localizedDescription)")
        }

        // Clear disk cache
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
            }
            createCacheDirectoryIfNeeded()

            await updateCacheStats()
            logger.info("✅ All cached images and mappings cleared successfully")

        } catch {
            logger.error("❌ Failed to clear image cache: \(error.localizedDescription)")
        }
        
        isClearing = false
    }
    
    /// Clean up old cached images
    func cleanupOldImages() async {
        logger.info("🧹 Cleaning up old cached images...")
        
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        var cleanedCount = 0
        var freedSpace: Int64 = 0
        
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            
            for fileURL in files {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                
                if let modificationDate = attributes[.modificationDate] as? Date,
                   modificationDate < cutoffDate {
                    
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    try fileManager.removeItem(at: fileURL)
                    
                    cleanedCount += 1
                    freedSpace += fileSize
                    
                    // Remove from memory cache too
                    let fileName = fileURL.lastPathComponent
                    memoryCache.removeObject(forKey: fileName as NSString)
                }
            }
            
            await updateCacheStats()
            logger.info("✅ Cleaned up \(cleanedCount) old images, freed \(freedSpace) bytes")
            
        } catch {
            logger.error("❌ Failed to cleanup old images: \(error.localizedDescription)")
        }
    }
    
    /// Get cache statistics
    func updateCacheStats() async {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            var totalSize: Int64 = 0
            var count = 0
            
            for fileURL in files {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                totalSize += attributes[.size] as? Int64 ?? 0
                count += 1
            }
            
            self.cacheSize = totalSize
            self.cachedImagesCount = count
            
        } catch {
            logger.error("❌ Failed to calculate cache stats: \(error.localizedDescription)")
            self.cacheSize = 0
            self.cachedImagesCount = 0
        }
    }
    
    // MARK: - Private Methods
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                logger.info("📁 Created image cache directory")
            } catch {
                logger.error("❌ Failed to create cache directory: \(error.localizedDescription)")
            }
        }
    }
    
    private func cacheKeyForURL(_ urlString: String) -> String {
        // Create a safe filename from URL
        return urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
    }
    
    private func loadImageFromDisk(cacheKey: String) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let imageData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: imageData) else {
            return nil
        }
        
        // Update file modification date for LRU cleanup
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        
        return image
    }
    
    private func downloadAndCacheImage(from url: URL, cacheKey: String) async throws -> UIImage? {
        logger.info("⬇️ Downloading image: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = UIImage(data: data) else {
            throw ImageCacheError.invalidResponse
        }
        
        // Save to disk cache
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        try data.write(to: fileURL)
        
        // Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey as NSString, cost: data.count)
        
        // Update cache stats
        await updateCacheStats()
        
        logger.info("✅ Image downloaded and cached: \(url.absoluteString)")
        return image
    }
}

// MARK: - Supporting Types

enum ImageCacheError: Error, LocalizedError {
    case invalidResponse
    case downloadFailed
    case cacheWriteFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from image server"
        case .downloadFailed:
            return "Failed to download image"
        case .cacheWriteFailed:
            return "Failed to write image to cache"
        }
    }
}

// MARK: - Cache Statistics

struct ImageCacheStats {
    let totalSize: Int64
    let imageCount: Int
    let memoryUsage: Int
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedMemoryUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsage), countStyle: .memory)
    }
}
