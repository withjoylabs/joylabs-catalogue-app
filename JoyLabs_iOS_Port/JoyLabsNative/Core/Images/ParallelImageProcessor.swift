import Foundation
import os.log

/// High-performance parallel image processor for catalog sync operations
/// Processes multiple images concurrently with intelligent batching and resource management
actor ParallelImageProcessor {
    
    // MARK: - Configuration
    private let maxConcurrentOperations: Int
    private let batchSize: Int
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ParallelImageProcessor")
    
    // MARK: - Dependencies
    private let imageCacheService: ImageCacheService
    private let backgroundDownloader: BackgroundImageDownloader
    
    // MARK: - State
    private var activeOperations: Set<String> = []
    private var processedCount: Int = 0
    private var totalCount: Int = 0
    
    // MARK: - Progress Tracking
    private var progressCallback: ((Int, Int) -> Void)?
    
    // MARK: - Initialization
    init(
        imageCacheService: ImageCacheService,
        backgroundDownloader: BackgroundImageDownloader = .shared,
        maxConcurrentOperations: Int = 8,
        batchSize: Int = 20
    ) {
        self.imageCacheService = imageCacheService
        self.backgroundDownloader = backgroundDownloader
        self.maxConcurrentOperations = maxConcurrentOperations
        self.batchSize = batchSize
    }
    
    // MARK: - Public Methods
    
    /// Process catalog objects with parallel image downloading
    func processCatalogObjectImages(
        _ objects: [CatalogObject],
        progressCallback: @escaping (Int, Int) -> Void
    ) async throws {
        
        self.progressCallback = progressCallback
        self.processedCount = 0
        self.totalCount = objects.count
        
        logger.info("🚀 Starting parallel image processing for \(objects.count) objects")
        
        // Extract all image processing tasks
        let imageTasks = extractImageTasks(from: objects)
        
        logger.info("📊 Found \(imageTasks.count) images to process across \(objects.count) objects")
        
        // Process images in parallel batches
        try await processImageTasksInBatches(imageTasks)
        
        logger.info("✅ Completed parallel image processing: \(imageTasks.count) images processed")
    }
    
    /// Cancel all ongoing operations
    func cancelAllOperations() async {
        logger.info("🛑 Cancelling all parallel image operations")
        
        // Cancel background downloads
        await MainActor.run {
            backgroundDownloader.cancelAllDownloads()
        }
        
        activeOperations.removeAll()
        processedCount = 0
        totalCount = 0
    }
    
    // MARK: - Private Methods
    
    private func extractImageTasks(from objects: [CatalogObject]) -> [ImageProcessingTask] {
        var tasks: [ImageProcessingTask] = []
        
        for object in objects {
            // Handle IMAGE objects directly
            if object.type == "IMAGE", let imageData = object.imageData, let awsUrl = imageData.url, !awsUrl.isEmpty {
                tasks.append(ImageProcessingTask(
                    awsUrl: awsUrl,
                    squareImageId: object.id,
                    objectType: "IMAGE",
                    objectId: object.id,
                    imageType: "PRIMARY",
                    priority: .normal
                ))
            }
            
            // Handle item images
            if let itemData = object.itemData, let imageIds = itemData.imageIds {
                for imageId in imageIds {
                    // Note: These will be processed when we encounter the actual IMAGE objects
                    // This is just for tracking - the actual URLs come from IMAGE objects
                    logger.debug("📷 Item \(object.id) references image: \(imageId)")
                }
            }
            
            // Handle category images
            if let categoryData = object.categoryData, let imageUrl = categoryData.imageUrl, !imageUrl.isEmpty {
                tasks.append(ImageProcessingTask(
                    awsUrl: imageUrl,
                    squareImageId: "category_\(object.id)",
                    objectType: "CATEGORY",
                    objectId: object.id,
                    imageType: "PRIMARY",
                    priority: .normal
                ))
            }
        }
        
        return tasks
    }
    
    private func processImageTasksInBatches(_ tasks: [ImageProcessingTask]) async throws {
        // Process tasks in batches to manage memory and network resources
        let batches = tasks.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            logger.info("📦 Processing batch \(batchIndex + 1)/\(batches.count) with \(batch.count) images")
            
            try await processBatch(batch)
            
            // Brief pause between batches to prevent overwhelming the system
            if batchIndex < batches.count - 1 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func processBatch(_ batch: [ImageProcessingTask]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            
            for task in batch {
                // Respect concurrent operation limit
                while activeTasks >= maxConcurrentOperations {
                    // Wait for a task to complete
                    _ = try await group.next()
                    activeTasks -= 1
                }
                
                // Add new task to group
                group.addTask { [weak self] in
                    await self?.processImageTask(task)
                }
                activeTasks += 1
            }
            
            // Wait for all remaining tasks to complete
            while activeTasks > 0 {
                _ = try await group.next()
                activeTasks -= 1
            }
        }
    }
    
    private func processImageTask(_ task: ImageProcessingTask) async {
        let taskId = "\(task.objectType)_\(task.objectId)"
        activeOperations.insert(taskId)
        
        defer {
            activeOperations.remove(taskId)
            processedCount += 1
            
            // Report progress
            if let callback = progressCallback {
                Task { @MainActor in
                    callback(processedCount, totalCount)
                }
            }
        }
        
        logger.debug("📷 Processing \(task.objectType) image: \(task.squareImageId)")
        
        // Use the background downloader for better performance and background capability
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                backgroundDownloader.downloadImage(
                    from: task.awsUrl,
                    cacheKey: task.squareImageId,
                    priority: task.priority
                ) { result in
                    switch result {
                    case .success(let fileURL):
                        // Store the mapping in the database
                        Task {
                            do {
                                let cacheKey = try await self.imageCacheService.imageURLManager.storeImageMapping(
                                    squareImageId: task.squareImageId,
                                    awsUrl: task.awsUrl,
                                    objectType: task.objectType,
                                    objectId: task.objectId,
                                    imageType: task.imageType
                                )
                                
                                await self.logger.info("✅ Cached \(task.objectType) image: \(task.squareImageId) -> \(cacheKey)")
                            } catch {
                                await self.logger.error("❌ Failed to store image mapping: \(error)")
                            }
                            
                            continuation.resume()
                        }
                        
                    case .failure(let error):
                        Task {
                            await self.logger.error("❌ Failed to cache \(task.objectType) image \(task.squareImageId): \(error)")
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct ImageProcessingTask {
    let awsUrl: String
    let squareImageId: String
    let objectType: String
    let objectId: String
    let imageType: String
    let priority: DownloadPriority
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
