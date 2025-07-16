import UIKit
import os.log

/// Progressive image loader with thumbnail generation for optimal UI performance
/// Provides immediate thumbnails while full-resolution images load in background
@MainActor
class ProgressiveImageLoader: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = ProgressiveImageLoader()
    
    // MARK: - Published Properties
    @Published var loadingStates: [String: ImageLoadingState] = [:]
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ProgressiveImageLoader")
    private let backgroundDownloader = BackgroundImageDownloader.shared
    
    // MARK: - Configuration
    private let thumbnailSize = CGSize(width: 150, height: 150)
    private let thumbnailQuality: CGFloat = 0.7
    private let fullImageQuality: CGFloat = 0.9
    
    // MARK: - Cache Management
    private var thumbnailCache = NSCache<NSString, UIImage>()
    private var fullImageCache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    
    // MARK: - File Management
    private let fileManager = FileManager.default
    private let thumbnailDirectory: URL
    private let fullImageDirectory: URL
    
    // MARK: - Initialization
    private init() {
        // Setup cache directories
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.thumbnailDirectory = documentsPath.appendingPathComponent("Thumbnails")
        self.fullImageDirectory = documentsPath.appendingPathComponent("FullImages")
        
        setupCaches()
        setupDirectories()
        
        logger.info("🖼️ ProgressiveImageLoader initialized")
    }
    
    // MARK: - Public Methods
    
    /// Load image progressively (thumbnail first, then full resolution)
    func loadImageProgressively(
        from urlString: String,
        cacheKey: String,
        priority: DownloadPriority = .normal
    ) -> ImageLoadingState {
        
        // Return existing state if already loading/loaded
        if let existingState = loadingStates[cacheKey] {
            return existingState
        }
        
        // Initialize loading state
        let initialState = ImageLoadingState(
            cacheKey: cacheKey,
            thumbnail: nil,
            fullImage: nil,
            isLoadingThumbnail: true,
            isLoadingFullImage: false,
            error: nil
        )
        
        loadingStates[cacheKey] = initialState
        
        // Start progressive loading
        startProgressiveLoading(urlString: urlString, cacheKey: cacheKey, priority: priority)
        
        return initialState
    }
    
    /// Get immediate thumbnail if available
    func getImmediateThumbnail(for cacheKey: String) -> UIImage? {
        // Check memory cache first
        if let thumbnail = thumbnailCache.object(forKey: cacheKey as NSString) {
            return thumbnail
        }
        
        // Check disk cache
        return loadThumbnailFromDisk(cacheKey: cacheKey)
    }
    
    /// Get immediate full image if available
    func getImmediateFullImage(for cacheKey: String) -> UIImage? {
        // Check memory cache first
        if let fullImage = fullImageCache.object(forKey: cacheKey as NSString) {
            return fullImage
        }
        
        // Check disk cache
        return loadFullImageFromDisk(cacheKey: cacheKey)
    }
    
    /// Cancel loading for specific cache key
    func cancelLoading(for cacheKey: String) {
        loadingTasks[cacheKey]?.cancel()
        loadingTasks.removeValue(forKey: cacheKey)
        
        loadingStates[cacheKey] = nil
        
        logger.debug("🛑 Cancelled progressive loading: \(cacheKey)")
    }
    
    /// Clear all caches
    func clearAllCaches() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
        loadingStates.removeAll()
        
        // Cancel all loading tasks
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
        
        // Clear disk caches
        clearDiskCache(directory: thumbnailDirectory)
        clearDiskCache(directory: fullImageDirectory)
        
        logger.info("🧹 Cleared all progressive image caches")
    }
    
    // MARK: - Private Methods
    
    private func setupCaches() {
        // Configure thumbnail cache (smaller, more items)
        thumbnailCache.countLimit = 200
        thumbnailCache.totalCostLimit = 20 * 1024 * 1024 // 20MB
        
        // Configure full image cache (larger, fewer items)
        fullImageCache.countLimit = 50
        fullImageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    private func setupDirectories() {
        do {
            try fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: fullImageDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("❌ Failed to create image directories: \(error)")
        }
    }
    
    private func startProgressiveLoading(urlString: String, cacheKey: String, priority: DownloadPriority) {
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Try to load existing thumbnail
            if let existingThumbnail = await self.getImmediateThumbnail(for: cacheKey) {
                await self.updateLoadingState(cacheKey: cacheKey) { state in
                    state.thumbnail = existingThumbnail
                    state.isLoadingThumbnail = false
                }
            }
            
            // Step 2: Try to load existing full image
            if let existingFullImage = await self.getImmediateFullImage(for: cacheKey) {
                await self.updateLoadingState(cacheKey: cacheKey) { state in
                    state.fullImage = existingFullImage
                    state.isLoadingFullImage = false
                }
                return // Already have full image, no need to download
            }
            
            // Step 3: Download full image and generate thumbnail
            await self.downloadAndProcessImage(urlString: urlString, cacheKey: cacheKey, priority: priority)
        }
        
        loadingTasks[cacheKey] = task
    }
    
    private func downloadAndProcessImage(urlString: String, cacheKey: String, priority: DownloadPriority) async {
        await updateLoadingState(cacheKey: cacheKey) { state in
            state.isLoadingFullImage = true
        }
        
        await withCheckedContinuation { continuation in
            backgroundDownloader.downloadImage(
                from: urlString,
                cacheKey: cacheKey,
                priority: priority
            ) { [weak self] result in
                Task { [weak self] in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    switch result {
                    case .success(let fileURL):
                        await self.processDownloadedImage(fileURL: fileURL, cacheKey: cacheKey)
                        
                    case .failure(let error):
                        await self.updateLoadingState(cacheKey: cacheKey) { state in
                            state.error = error
                            state.isLoadingThumbnail = false
                            state.isLoadingFullImage = false
                        }
                        
                        self.logger.error("❌ Failed to download image: \(error)")
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    private func processDownloadedImage(fileURL: URL, cacheKey: String) async {
        do {
            // Load the downloaded image
            let imageData = try Data(contentsOf: fileURL)
            guard let originalImage = UIImage(data: imageData) else {
                throw ImageProcessingError.invalidImageData
            }
            
            // Generate thumbnail
            let thumbnail = generateThumbnail(from: originalImage)
            
            // Save thumbnail to disk
            try saveThumbnailToDisk(thumbnail, cacheKey: cacheKey)
            
            // Save full image to disk (copy from download location)
            try saveFullImageToDisk(imageData, cacheKey: cacheKey)
            
            // Update caches
            thumbnailCache.setObject(thumbnail, forKey: cacheKey as NSString)
            fullImageCache.setObject(originalImage, forKey: cacheKey as NSString)
            
            // Update loading state
            await updateLoadingState(cacheKey: cacheKey) { state in
                state.thumbnail = thumbnail
                state.fullImage = originalImage
                state.isLoadingThumbnail = false
                state.isLoadingFullImage = false
            }
            
            logger.info("✅ Processed progressive image: \(cacheKey)")
            
        } catch {
            await updateLoadingState(cacheKey: cacheKey) { state in
                state.error = error
                state.isLoadingThumbnail = false
                state.isLoadingFullImage = false
            }
            
            logger.error("❌ Failed to process downloaded image: \(error)")
        }
    }
    
    private func generateThumbnail(from image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
    }
    
    private func saveThumbnailToDisk(_ thumbnail: UIImage, cacheKey: String) throws {
        guard let data = thumbnail.jpegData(compressionQuality: thumbnailQuality) else {
            throw ImageProcessingError.thumbnailGenerationFailed
        }
        
        let fileURL = thumbnailDirectory.appendingPathComponent(cacheKey)
        try data.write(to: fileURL)
    }
    
    private func saveFullImageToDisk(_ imageData: Data, cacheKey: String) throws {
        let fileURL = fullImageDirectory.appendingPathComponent(cacheKey)
        try imageData.write(to: fileURL)
    }
    
    private func loadThumbnailFromDisk(cacheKey: String) -> UIImage? {
        let fileURL = thumbnailDirectory.appendingPathComponent(cacheKey)
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Cache in memory for faster access
        thumbnailCache.setObject(image, forKey: cacheKey as NSString)
        
        return image
    }
    
    private func loadFullImageFromDisk(cacheKey: String) -> UIImage? {
        let fileURL = fullImageDirectory.appendingPathComponent(cacheKey)
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Cache in memory for faster access
        fullImageCache.setObject(image, forKey: cacheKey as NSString)
        
        return image
    }
    
    private func clearDiskCache(directory: URL) {
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            logger.error("❌ Failed to clear disk cache: \(error)")
        }
    }
    
    private func updateLoadingState(cacheKey: String, update: (inout ImageLoadingState) -> Void) async {
        await MainActor.run {
            guard var state = loadingStates[cacheKey] else { return }
            update(&state)
            loadingStates[cacheKey] = state
        }
    }
}

// MARK: - Supporting Types

struct ImageLoadingState {
    let cacheKey: String
    var thumbnail: UIImage?
    var fullImage: UIImage?
    var isLoadingThumbnail: Bool
    var isLoadingFullImage: Bool
    var error: Error?
    
    var isLoading: Bool {
        return isLoadingThumbnail || isLoadingFullImage
    }
    
    var hasAnyImage: Bool {
        return thumbnail != nil || fullImage != nil
    }
}

enum ImageProcessingError: LocalizedError {
    case invalidImageData
    case thumbnailGenerationFailed
    case diskWriteFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .diskWriteFailed:
            return "Failed to write to disk"
        }
    }
}
