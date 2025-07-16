import Foundation
import UIKit
import os.log

/// Service for caching Square catalog images locally with persistence and cleanup
///
/// IMPORTANT: Images are stored at FULL RESOLUTION without compression
/// - Original image data is preserved for high-quality display
/// - Thumbnails use the same full-resolution data, scaled in UI
/// - Perfect for enlarging thumbnails to full-size views
@MainActor
class ImageCacheService: ObservableObject {

    // MARK: - Shared Instance
    private static var _shared: ImageCacheService?
    private static let staticLogger = Logger(subsystem: "com.joylabs.native", category: "ImageCacheService")

    static var shared: ImageCacheService {
        if let instance = _shared {
            return instance
        }

        // Fallback initialization if not properly initialized
        staticLogger.warning("⚠️ ImageCacheService.shared accessed before proper initialization - creating fallback instance")
        let sharedDbManager = SquareAPIServiceFactory.createDatabaseManager()
        let imageURLManager = ImageURLManager(databaseManager: sharedDbManager)
        let instance = ImageCacheService(imageURLManager: imageURLManager)
        _shared = instance
        return instance
    }

    static func initializeShared(with imageURLManager: ImageURLManager) {
        staticLogger.info("🖼️ Initializing shared ImageCacheService with provided ImageURLManager")
        _shared = ImageCacheService(imageURLManager: imageURLManager)
        staticLogger.info("✅ Shared ImageCacheService initialized successfully")
    }
    
    // MARK: - Published Properties
    
    @Published var isClearing = false
    @Published var cacheSize: Int64 = 0
    @Published var cachedImagesCount: Int = 0
    
    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private var imageURLManager: ImageURLManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageCache")
    
    // MARK: - Cache Configuration
    
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB max cache
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    // MARK: - In-Memory Cache

    private var memoryCache = NSCache<NSString, UIImage>()
    private var downloadTasks: [String: Task<UIImage?, Error>] = [:]

    // MARK: - On-Demand Loading with Rate Limiting

    private let urlSession: URLSession
    private let maxConcurrentDownloads = 6 // Conservative limit for AWS
    private let requestSpacing: TimeInterval = 0.1 // 100ms between requests
    private let maxRequestsPerSecond = 10 // AWS CloudFront typical limit
    private var activeDownloads: Set<String> = []
    private var lastRequestTime: Date = Date.distantPast
    private var requestCount = 0
    private var requestWindowStart = Date()
    
    // MARK: - Initialization

    init(imageURLManager: ImageURLManager? = nil) {
        // Create cache directory in Documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("ImageCache")

        // Initialize URL manager (use shared database manager)
        if let urlManager = imageURLManager {
            self.imageURLManager = urlManager
        } else {
            // Use shared database manager instead of creating new one
            let sharedDbManager = SquareAPIServiceFactory.createDatabaseManager()
            self.imageURLManager = ImageURLManager(databaseManager: sharedDbManager)
        }
        
        // Configure URLSession for on-demand loading
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)

        // Configure memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit

        // Create cache directory if needed
        createCacheDirectoryIfNeeded()
        
        // Calculate initial cache size
        Task {
            await updateCacheStats()
        }

        // Only log initialization for non-shared instances (debugging purposes)
        if imageURLManager == nil {
            logger.debug("🖼️ ImageCacheService instance created with cache directory: \(self.cacheDirectory.path)")
        }
    }

    // REMOVED: updateImageURLManager method - this was causing redundant initialization

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

        // Create meaningful image ID from URL for cache lookup
        let imageId = createImageIdFromUrl(urlString)

        // Try to get existing cache key from URL manager first
        let cacheKey: String
        if let existingKey = try? imageURLManager.getLocalCacheKey(for: imageId) {
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

            // Download and cache the image WITHOUT storing mapping again
            if let _ = await downloadAndCacheImageOnly(awsUrl: awsUrl, imageId: squareImageId) {
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

    /// Cache image data with database mapping for on-demand loading
    func cacheImageWithMapping(imageData: Data, imageId: String, awsUrl: String) async -> String {
        // Generate cache filename
        let fileName = "\(imageId).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)

        do {
            // Save to disk
            try imageData.write(to: fileURL)

            // Create UIImage and cache in memory
            if let image = UIImage(data: imageData) {
                memoryCache.setObject(image, forKey: fileName as NSString)
            }

            // Create internal cache URL
            // Removed unused cacheUrl variable - using finalCacheUrl instead

            // Check if mapping already exists to avoid duplicate storage
            let cacheKey: String
            if let existingMapping = try? imageURLManager.getLocalCacheKey(for: imageId) {
                // Mapping already exists from sync - use existing cache key
                cacheKey = existingMapping
                logger.debug("📋 Using existing image mapping: \(imageId) -> \(cacheKey)")
            } else {
                // No existing mapping - create new one (for on-demand downloads)
                do {
                    cacheKey = try imageURLManager.storeImageMapping(
                        squareImageId: imageId,
                        awsUrl: awsUrl,
                        objectType: "ITEM",
                        objectId: imageId,
                        imageType: "PRIMARY"
                    )
                    logger.debug("📝 Created new image mapping: \(imageId) -> \(cacheKey)")
                } catch {
                    logger.error("❌ Failed to store image mapping: \(error)")
                    cacheKey = fileName // Fallback to filename
                }
            }

            await updateCacheStats()

            // Create cache URL using the returned cache key for consistency
            let finalCacheUrl = "cache://\(cacheKey)"
            logger.info("✅ Cached image with mapping: \(imageId) -> \(finalCacheUrl)")

            return finalCacheUrl

        } catch {
            logger.error("❌ Failed to cache image with mapping \(imageId): \(error)")
            return awsUrl // Return original URL as fallback
        }
    }

    /// Get cached image URL for an image ID
    func getCachedImageURL(for imageId: String) async -> String? {
        do {
            if let cacheKey = try imageURLManager.getLocalCacheKey(for: imageId) {
                return "cache://\(cacheKey)"
            }
        } catch {
            logger.error("❌ Failed to get cached image URL: \(error)")
        }
        return nil
    }

    /// Load image on-demand with rate limiting and caching
    func loadImageOnDemand(imageId: String, awsUrl: String, priority: TaskPriority = .medium) async -> UIImage? {
        // Check cache first (fastest path)
        if let cacheUrl = await getCachedImageURL(for: imageId) {
            if let cachedImage = await loadImage(from: cacheUrl) {
                logger.debug("💾 Cache hit for image: \(imageId)")
                return cachedImage
            }
        }

        logger.debug("💾 Cache miss for image: \(imageId) - downloading from AWS")

        // Simple download without complex rate limiting for now
        return await simpleDownloadAndCache(imageId: imageId, awsUrl: awsUrl)
    }

    /// Download and cache image without storing database mapping (used when mapping already exists)
    private func downloadAndCacheImageOnly(awsUrl: String, imageId: String) async -> UIImage? {
        guard let url = URL(string: awsUrl) else {
            logger.error("Invalid AWS URL: \(awsUrl)")
            return nil
        }

        do {
            // Rate limiting
            await self.enforceRateLimit()

            logger.debug("📥 Downloading image: \(imageId) from AWS")
            let (data, _) = try await URLSession.shared.data(from: url)

            // Save to disk
            let fileName = createImageIdFromUrl(awsUrl) + ".jpg"
            let fileURL = cacheDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL)

            // Cache in memory
            if let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: fileName as NSString)
                await updateCacheStats()
                logger.debug("✅ Downloaded and cached image (no mapping): \(imageId)")
                return image
            }

        } catch {
            logger.error("❌ Download failed for image \(imageId): \(error)")
        }

        return nil
    }

    /// Load multiple images concurrently for search results (maintains performance)
    func loadImagesForSearchResults(_ imageRequests: [(imageId: String, awsUrl: String)]) async -> [String: UIImage] {
        logger.info("📱 Loading \(imageRequests.count) images for search results")

        var results: [String: UIImage] = [:]

        // Use TaskGroup for concurrent loading while respecting rate limits
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for (imageId, awsUrl) in imageRequests {
                group.addTask(priority: .high) {
                    let image = await self.loadImageOnDemand(imageId: imageId, awsUrl: awsUrl, priority: .high)
                    return (imageId, image)
                }
            }

            for await (imageId, image) in group {
                if let image = image {
                    results[imageId] = image
                }
            }
        }

        logger.info("✅ Loaded \(results.count)/\(imageRequests.count) images for search results")
        return results
    }

    /// Simple download and cache method
    private func simpleDownloadAndCache(imageId: String, awsUrl: String) async -> UIImage? {
        // Basic rate limiting - wait a bit between requests
        let now = Date()
        if now.timeIntervalSince(lastRequestTime) < requestSpacing {
            let waitTime = requestSpacing - now.timeIntervalSince(lastRequestTime)
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        lastRequestTime = Date()

        do {
            logger.debug("📥 Downloading image: \(imageId) from AWS")

            guard let url = URL(string: awsUrl) else {
                logger.error("❌ Invalid AWS URL: \(awsUrl)")
                return nil
            }

            let (data, response) = try await urlSession.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.error("❌ HTTP error for image: \(imageId)")
                return nil
            }

            guard let image = UIImage(data: data) else {
                logger.error("❌ Failed to create image from data: \(imageId)")
                return nil
            }

            // Cache the image with mapping
            let _ = await cacheImageWithMapping(
                imageData: data,
                imageId: imageId,
                awsUrl: awsUrl
            )

            logger.debug("✅ Downloaded and cached image: \(imageId)")
            return image

        } catch {
            logger.error("❌ Download failed for image \(imageId): \(error)")
            return nil
        }
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

    /// Enforce rate limiting for AWS requests
    private func enforceRateLimit() async {
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)

        if timeSinceLastRequest < requestSpacing {
            let delay = requestSpacing - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        lastRequestTime = Date()
    }

    private func cacheKeyForURL(_ urlString: String) -> String {
        // Create a safe filename from URL
        return urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
    }

    private func createImageIdFromUrl(_ urlString: String) -> String {
        // Create a unique, meaningful image ID from AWS URL
        let urlHash = urlString.sha256

        // Try to extract meaningful parts from URL path
        if let urlObj = URL(string: urlString) {
            let pathComponents = urlObj.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                // Use last two path components for more meaningful ID
                let meaningfulPart = pathComponents.suffix(2).joined(separator: "_")
                return "\(meaningfulPart)_\(urlHash.prefix(8))"
            }
        }

        // Fallback to hash-based ID
        return "img_\(urlHash.prefix(12))"
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

    // MARK: - Webhook Support Methods

    /// Invalidate cached images for webhook processing
    func invalidateImagesForObject(objectId: String, objectType: String) async {
        do {
            // Get affected image mappings
            let mappings = try imageURLManager.getImageMappings(for: objectId, objectType: objectType)

            // Remove from memory cache
            for mapping in mappings {
                memoryCache.removeObject(forKey: mapping.localCacheKey as NSString)
            }

            // Mark mappings as deleted in database
            try imageURLManager.invalidateImagesForObject(objectId: objectId, objectType: objectType)

            logger.info("🔄 Invalidated \(mappings.count) images for \(objectType): \(objectId)")

        } catch {
            logger.error("❌ Failed to invalidate images for \(objectType) \(objectId): \(error)")
        }
    }

    /// Invalidate a specific image by Square image ID
    func invalidateImageById(squareImageId: String) async {
        do {
            // Get cache key for this image
            if let cacheKey = try imageURLManager.getLocalCacheKey(for: squareImageId) {
                // Remove from memory cache
                memoryCache.removeObject(forKey: cacheKey as NSString)
            }

            // Mark mapping as deleted in database
            try imageURLManager.invalidateImageById(squareImageId: squareImageId)

            logger.info("🔄 Invalidated image: \(squareImageId)")

        } catch {
            logger.error("❌ Failed to invalidate image \(squareImageId): \(error)")
        }
    }

    /// Clean up stale cache files (for webhook processing)
    func cleanupStaleCache() async {
        do {
            // Get stale cache keys from database
            let staleCacheKeys = try imageURLManager.getStaleImageCacheKeys()

            var deletedCount = 0
            for cacheKey in staleCacheKeys {
                let fileURL = cacheDirectory.appendingPathComponent(cacheKey)

                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                }

                // Also remove from memory cache if present
                memoryCache.removeObject(forKey: cacheKey as NSString)
            }

            // Clean up database mappings
            try imageURLManager.cleanupStaleImageMappings()

            // Update cache stats
            await updateCacheStats()

            logger.info("🧹 Cleaned up \(deletedCount) stale cache files")

        } catch {
            logger.error("❌ Failed to cleanup stale cache: \(error)")
        }
    }

    /// Clear all cached images and database mappings (for fresh start)
    func clearAllCachedImages() async {
        logger.info("🗑️ Clearing all cached images and database mappings...")

        // Clear memory cache
        memoryCache.removeAllObjects()

        // Clear disk cache
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            logger.info("🗑️ Cleared \(files.count) cached image files from disk")
        } catch {
            logger.error("❌ Failed to clear disk cache: \(error)")
        }

        // Clear cache references but preserve essential URL mappings
        // Note: URL mappings (image ID -> AWS URL) are preserved for future downloads
        logger.info("🧹 Cache cleared (URL mappings preserved for future downloads)")

        await updateCacheStats()
        logger.info("✅ Image cache completely cleared - ready for fresh images")
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
