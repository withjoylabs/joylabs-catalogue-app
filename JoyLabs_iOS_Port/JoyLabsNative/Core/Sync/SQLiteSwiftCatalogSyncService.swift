import Foundation
import SwiftUI
import os.log

/// Modern catalog sync service using SQLite.swift
/// Replaces the broken raw SQLite3 implementation
@MainActor
class SQLiteSwiftCatalogSyncService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var syncState: SyncState = .idle
    @Published var syncProgress: SyncProgress = SyncProgress()
    @Published var lastSyncTime: Date?
    @Published var errorMessage: String?

    
    // MARK: - Dependencies

    private let squareAPIService: SquareAPIService
    private var databaseManager: SQLiteSwiftCatalogManager
    private var imageCacheService: ImageCacheService!
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftCatalogSync")

    // Configuration: Skip orphaned images to reduce overhead
    // Based on Square API behavior: ListCatalog excludes deleted items but includes their orphaned images
    private let skipOrphanedImages = true

    // MARK: - Public Access

    var sharedDatabaseManager: SQLiteSwiftCatalogManager {
        return databaseManager
    }
    
    // MARK: - State

    private var isSyncInProgress = false
    private var progressUpdateTimer: Timer?
    private var syncTask: Task<Void, Error>?
    private var isCancellationRequested = false

    // MARK: - Initialization

    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()

        // Use the shared ImageCacheService instance instead of creating a new one
        self.imageCacheService = ImageCacheService.shared

        // Initialize database connection
        Task {
            await initializeDatabaseConnection()
        }
    }


    // MARK: - Database Initialization

    private func initializeDatabaseConnection() async {
        do {
            // Simply connect to SQLite.swift database
            try databaseManager.connect()
            logger.info("✅ Connected to SQLite.swift database")
        } catch {
            logger.error("❌ Database connection failed: \(error)")
            errorMessage = "Database connection failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sync Operations

    func cancelSync() {
        logger.info("🛑 Sync cancellation requested")
        isCancellationRequested = true

        // Cancel the background task
        syncTask?.cancel()

        // Force cleanup state immediately
        Task { @MainActor in
            self.isSyncInProgress = false
            self.syncState = .idle
            var progress = self.syncProgress
            progress.currentObjectType = "CANCELLED"
            progress.currentObjectName = "Sync cancelled by user"
            self.syncProgress = progress
            self.stopProgressUpdateTimer()
            self.logger.info("✅ Sync cancellation completed")
        }
    }

    func performSync(isManual: Bool = false) async throws {
        guard !isSyncInProgress else {
            throw SyncError.syncInProgress
        }
        
        // Ensure database is connected
        try databaseManager.connect()
        
        isSyncInProgress = true
        isCancellationRequested = false
        syncState = .syncing
        errorMessage = nil

        // Store the sync task for cancellation with background task management
        syncTask = Task {
            defer {
                Task { @MainActor in
                    self.isSyncInProgress = false
                    self.syncTask = nil
                }
            }

            do {
                logger.info("Starting catalog sync with SQLite.swift - manual: \(isManual)")

                // Initialize progress tracking - RESET TO ZERO
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.startTime = Date()
                    progress.syncedObjects = 0
                    progress.syncedItems = 0
                    progress.currentObjectType = "INITIALIZING"
                    progress.currentObjectName = "Starting sync..."
                    syncProgress = progress
                }



                // Start UI update timer (every 1 second)
                await MainActor.run { startProgressUpdateTimer() }

                // Clear existing data
                await MainActor.run {
                    var progress = syncProgress
                    progress.currentObjectType = "CLEARING"
                    progress.currentObjectName = "Clearing existing data..."
                    syncProgress = progress
                }
                try databaseManager.clearAllData()
                logger.info("✅ Existing catalog data cleared (preserving image cache)")

                // Clear image cache for clean slate
                await MainActor.run {
                    var progress = syncProgress
                    progress.currentObjectType = "CLEARING"
                    progress.currentObjectName = "Clearing cached images..."
                    syncProgress = progress
                }
                await imageCacheService.clearAllImages()
                logger.info("🖼️ Cleared image cache for fresh start")

                // Fetch catalog data from Square API with progress tracking
                let catalogData = try await fetchCatalogFromSquareWithProgress()

                // Process and insert data with progress tracking
                try await processCatalogDataWithProgress(catalogData)
                logger.info("✅ Catalog data processed successfully")

                // Stop progress timer
                await MainActor.run { stopProgressUpdateTimer() }

                // Update sync completion
                await MainActor.run {
                    syncState = .completed
                    lastSyncTime = Date()
                    var progress = syncProgress
                    progress.syncedObjects = catalogData.count
                    progress.currentObjectType = "COMPLETED"
                    progress.currentObjectName = "Sync completed successfully!"
                    syncProgress = progress
                }

                logger.info("🎉 Catalog sync completed successfully!")
                logger.info("📊 Final sync stats: \(catalogData.count) total objects processed")

                // Log summary of object types processed
                let objectTypeCounts = Dictionary(grouping: catalogData) { $0.type }
                    .mapValues { $0.count }
                logger.info("📋 Object types processed: \(objectTypeCounts)")

                // Notify completion for statistics refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil)
                }

            } catch {
                logger.error("❌ Catalog sync failed: \(error)")
                await MainActor.run {
                    syncState = .failed
                    errorMessage = error.localizedDescription
                    stopProgressUpdateTimer()
                }
                throw error
            }
        }

        // Wait for the task to complete
        try await syncTask!.value
    }

    // MARK: - Progress Tracking

    private func startProgressUpdateTimer() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgressPercentage()
            }
        }
    }

    private func stopProgressUpdateTimer() {
        progressUpdateTimer?.invalidate()
        progressUpdateTimer = nil
    }

    private func updateProgressPercentage() {
        // Force UI update by reassigning the published property
        let currentProgress = syncProgress
        syncProgress = currentProgress
    }
    
    // MARK: - Private Methods
    
    private func fetchCatalogFromSquareWithProgress() async throws -> [CatalogObject] {
        await MainActor.run {
            var progress = syncProgress
            progress.currentObjectType = "DOWNLOADING"
            progress.currentObjectName = "Fetching catalog from Square API..."
            syncProgress = progress
        }

        logger.info("🌐 Fetching catalog data from Square API...")

        // Use the actual Square API service to fetch catalog data
        let catalogObjects = try await squareAPIService.fetchCatalog()

        logger.info("✅ Fetched \(catalogObjects.count) objects from Square API")

        // Don't set the final counts here - let processing update them incrementally
        let itemCount = catalogObjects.filter { $0.type == "ITEM" }.count
        await MainActor.run {
            var progress = syncProgress
            progress.currentObjectType = "READY"
            progress.currentObjectName = "Ready to process \(catalogObjects.count) objects (\(itemCount) items)"
            syncProgress = progress
        }

        return catalogObjects
    }
    
    private func processCatalogDataWithProgress(_ objects: [CatalogObject]) async throws {
        logger.info("🔄 Starting to process \(objects.count) objects into database...")

        // RESET PROGRESS TO ZERO AT START OF PROCESSING
        syncProgress.syncedObjects = 0
        syncProgress.syncedItems = 0
        syncProgress.currentObjectType = "PROCESSING"
        syncProgress.currentObjectName = "Starting to process objects..."

        // CRITICAL FIX: Sort objects by type to ensure categories are processed before items
        // This ensures category lookups work correctly during item insertion
        let sortedObjects = objects.sorted { obj1, obj2 in
            let priority1 = getObjectTypePriority(obj1.type)
            let priority2 = getObjectTypePriority(obj2.type)
            return priority1 < priority2
        }

        logger.info("📋 Sorted objects by type priority: Categories first, then Items")

        // First, insert all catalog objects to database (fast operation)
        var processedItems = 0
        let totalObjects = sortedObjects.count

        await MainActor.run {
            var progress = syncProgress
            progress.currentObjectType = "INSERTING"
            progress.currentObjectName = "Inserting catalog objects to database..."
            syncProgress = progress
        }

        for (index, object) in sortedObjects.enumerated() {
            // Check for cancellation
            if isCancellationRequested {
                logger.info("🛑 Sync cancelled during processing at object \(index + 1)/\(totalObjects)")
                throw SyncError.cancelled
            }

            // Update sync status based on object type being processed
            updateSyncStatusForObjectType(object.type, index: index, total: totalObjects)

            try databaseManager.insertCatalogObject(object)

            // Process image URL mappings for on-demand loading
            if object.type == "IMAGE" {
                await processImageURLMapping(object)
            }

            // Count items specifically as we process them
            if object.type == "ITEM" {
                processedItems += 1
            }

            // Update progress with processed counts
            let currentObjectCount = index + 1
            let currentItemCount = processedItems  // Capture the current value
            Task { @MainActor in
                var progress = syncProgress
                progress.syncedObjects = currentObjectCount
                progress.syncedItems = currentItemCount
                syncProgress = progress
            }

            // Small delay every 50 objects to allow UI updates and check for cancellation
            if index % 50 == 0 {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms to allow UI updates
            }
        }

        logger.info("✅ FINAL PROGRESS: \(processedItems) items, \(objects.count) objects processed")

        logger.info("✅ Processed all \(sortedObjects.count) catalog objects")
        logger.info("📷 Image URL mappings and item-to-image mappings created during processing for on-demand downloading")
    }

    /// Get processing priority for object types (lower number = higher priority)
    /// Categories must be processed before items for category name lookups to work
    private func getObjectTypePriority(_ objectType: String) -> Int {
        switch objectType {
        case "CATEGORY":
            return 1  // Process categories first
        case "TAX":
            return 2  // Process taxes second
        case "MODIFIER_LIST":
            return 3  // Process modifier lists third
        case "MODIFIER":
            return 4  // Process modifiers fourth
        case "ITEM":
            return 5  // Process items after categories are available
        case "ITEM_VARIATION":
            return 6  // Process variations after items
        case "IMAGE":
            return 7  // Process images last
        case "DISCOUNT":
            return 8  // Process discounts last
        default:
            return 9  // Unknown types last
        }
    }

    /// Update sync status with detailed information about what's being processed
    private func updateSyncStatusForObjectType(_ objectType: String, index: Int, total: Int) {
        Task { @MainActor in
            var progress = syncProgress
            switch objectType {
            case "ITEM":
                progress.currentObjectType = "ITEMS"
                progress.currentObjectName = "Processing items..."
            case "CATEGORY":
                progress.currentObjectType = "CATEGORIES"
                progress.currentObjectName = "Processing categories..."
            case "IMAGE":
                progress.currentObjectType = "IMAGES"
                progress.currentObjectName = "Processing images..."
            case "TAX":
                progress.currentObjectType = "TAXES"
                progress.currentObjectName = "Processing taxes..."
            case "MODIFIER", "MODIFIER_LIST":
                progress.currentObjectType = "MODIFIERS"
                progress.currentObjectName = "Processing modifiers..."
            case "DISCOUNT":
                progress.currentObjectType = "DISCOUNTS"
                progress.currentObjectName = "Processing discounts..."
            case "ITEM_VARIATION":
                progress.currentObjectType = "VARIATIONS"
                progress.currentObjectName = "Processing variations..."
            default:
                progress.currentObjectType = "PROCESSING"
                progress.currentObjectName = "Processing \(objectType.lowercased())..."
            }
            syncProgress = progress
        }
    }

    /// Process and cache images for a catalog object
    private func processCatalogObjectImages(_ object: CatalogObject) async {
        let objectId = object.id // id is not optional

        // Handle IMAGE objects directly - these contain the actual image data and URLs
        if object.type == "IMAGE" {
            await processImageObject(object)
            return
        }

        // Process item images - check if itemData has imageIds array
        if let itemData = object.itemData {
            await processItemImages(itemData: itemData, itemId: objectId)
        }

        // Process category image references
        if let categoryData = object.categoryData {
            await processCategoryImages(categoryData: categoryData, categoryId: objectId)
        }
    }

    /// Process IMAGE type catalog objects to extract and cache image URLs
    private func processImageObject(_ object: CatalogObject) async {
        guard let imageData = object.imageData else {
            logger.warning("📷 IMAGE object \(object.id) missing imageData")
            return
        }

        guard let awsUrl = imageData.url, !awsUrl.isEmpty else {
            logger.warning("📷 IMAGE object \(object.id) missing URL")
            return
        }

        logger.debug("📷 Processing IMAGE object: \(object.id) with URL: \(awsUrl)")

        // SYNC ONLY STORES URL MAPPINGS - NO DOWNLOADING
        // Images are downloaded on-demand during search
        logger.debug("📋 Storing URL mapping for on-demand loading: \(object.id)")
    }

    /// Process images referenced by item data (via imageIds array)
    private func processItemImages(itemData: ItemData, itemId: String) async {
        // Check for imageIds array in item data
        guard let imageIds = itemData.imageIds, !imageIds.isEmpty else {
            logger.debug("📷 Item \(itemId) has no imageIds")
            return
        }

        logger.debug("📷 Item \(itemId) has \(imageIds.count) image references: \(imageIds)")

        // Note: The actual IMAGE objects will be processed separately when we encounter them
        // This just logs that we found image references - the caching happens when we process the IMAGE objects
        for imageId in imageIds {
            logger.debug("📷 Item \(itemId) references image: \(imageId)")
        }
    }

    /// Process images referenced by category data
    private func processCategoryImages(categoryData: CategoryData, categoryId: String) async {
        // Categories might have imageIds array or direct imageUrl
        if let imageIds = categoryData.imageIds, !imageIds.isEmpty {
            logger.debug("📷 Category \(categoryId) has \(imageIds.count) image references: \(imageIds)")

            for imageId in imageIds {
                logger.debug("📷 Category \(categoryId) references image: \(imageId)")
            }
        }

        // Some categories might have direct imageUrl field
        if let imageUrl = categoryData.imageUrl, !imageUrl.isEmpty {
            logger.debug("📷 Category \(categoryId) has direct image URL: \(imageUrl)")

            // SYNC ONLY STORES URL MAPPINGS - NO DOWNLOADING
            // Category images are downloaded on-demand if needed
            logger.debug("📋 Category image URL stored for on-demand loading: \(categoryId)")
        }
    }





    /// Process image URL mapping for on-demand loading
    private func processImageURLMapping(_ object: CatalogObject) async {
        guard let imageData = object.imageData else {
            logger.warning("📷 IMAGE object \(object.id) missing imageData")
            return
        }

        guard let awsUrl = imageData.url, !awsUrl.isEmpty else {
            logger.warning("📷 IMAGE object \(object.id) missing URL")
            return
        }



        // Skip processing deleted images to avoid wasting overhead
        if object.safeIsDeleted {
            return
        }

        // Store the URL mapping for on-demand loading (don't download yet)
        do {
            let imageURLManager = ImageURLManager(databaseManager: databaseManager)
            let _ = try imageURLManager.storeImageMapping(
                squareImageId: object.id,
                awsUrl: awsUrl,
                objectType: "IMAGE",
                objectId: object.id,
                imageType: "PRIMARY"
            )



            // NOW create item-to-image mappings for any items that reference this image
            await createItemToImageMappingsForImage(imageId: object.id, awsUrl: awsUrl, imageURLManager: imageURLManager)

        } catch {
            logger.error("❌ Failed to store image URL mapping: \(error)")
        }

    }

    /// Create item-to-image mappings when processing an IMAGE object (CORRECT APPROACH)
    private func createItemToImageMappingsForImage(imageId: String, awsUrl: String, imageURLManager: ImageURLManager) async {
        guard let db = databaseManager.getConnection() else {
            logger.error("❌ No database connection for item-to-image mappings")
            return
        }

        do {
            // Find all ITEM objects that reference this image ID in their imageIds array
            let sql = "SELECT id, data_json FROM catalog_items WHERE data_json LIKE ? AND is_deleted = 0"
            let statement = try db.prepare(sql)
            let searchPattern = "%\"\(imageId)\"%"



            var mappingsCreated = 0
            var itemsFound = 0
            for row in try statement.run(searchPattern) {
                itemsFound += 1
                guard let itemId = row[0] as? String,
                      let dataJsonString = row[1] as? String,
                      let dataJsonData = dataJsonString.data(using: .utf8) else {

                    continue
                }

                logger.debug("🔍 FOUND POTENTIAL ITEM: \(itemId)")
                logger.debug("🔍 ITEM JSON: \(dataJsonString.prefix(200))...")

                // Parse the JSON to verify this image ID is actually in the imageIds array
                // Note: We now store the full CatalogObject, so imageIds is in item_data.image_ids (UNDERSCORE!)
                if let catalogObject = try? JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any],
                   let itemData = catalogObject["item_data"] as? [String: Any] {
                    if let imageIds = itemData["image_ids"] as? [String] {
                        if imageIds.contains(imageId) {
                            // Determine if this is the primary image (first in array)
                            let imageType = imageIds.first == imageId ? "PRIMARY" : "SECONDARY"

                            // Create the item-to-image mapping
                            let _ = try imageURLManager.storeImageMapping(
                                squareImageId: imageId,
                                awsUrl: awsUrl,
                                objectType: "ITEM",
                                objectId: itemId,
                                imageType: imageType
                            )

                            mappingsCreated += 1
                        }
                    }
                }
            }

            if mappingsCreated == 0 {

                // Check if any items reference this image, including deleted ones
                let debugSql = "SELECT id, name, is_deleted FROM catalog_items WHERE data_json LIKE ?"
                let debugStatement = try db.prepare(debugSql)
                let debugPattern = "%\(imageId)%"

                var debugCount = 0
                for _ in try debugStatement.run(debugPattern) {
                    debugCount += 1
                }

                // If no items found, this is an orphaned image from Square's deleted items
                if debugCount == 0 {
                    logger.warning("🚨 ORPHANED IMAGE DETECTED: \(imageId) has no associated items in database")
                    logger.warning("🚨 EXPLANATION: Square's ListCatalog excludes deleted items but includes their orphaned images")
                    logger.warning("🚨 This image was processed but wastes storage/bandwidth - removing mapping")

                    // Mark the orphaned image mapping as deleted to free up space
                    do {
                        let imageURLManager = ImageURLManager(databaseManager: databaseManager)
                        try imageURLManager.markImageAsDeleted(squareImageId: imageId)
                    } catch {
                        logger.error("❌ Failed to mark orphaned image mapping as deleted: \(error)")
                    }
                }
            }

        } catch {
            logger.error("❌ Failed to create item-to-image mappings: \(error)")
        }
    }

    /// DEPRECATED: Create item-to-image mappings when processing an ITEM object (WRONG APPROACH - IMAGES NOT PROCESSED YET)
    private func processItemToImageMappings(_ object: CatalogObject) async {
        guard let itemData = object.itemData,
              let imageIds = itemData.imageIds,
              !imageIds.isEmpty else {
            logger.debug("📷 Item \(object.id) has no imageIds")
            return
        }

        logger.debug("📷 Processing item \(object.id) with \(imageIds.count) image references: \(imageIds)")

        guard let db = databaseManager.getConnection() else {
            logger.error("❌ No database connection for item-to-image mappings")
            return
        }

        let imageURLManager = ImageURLManager(databaseManager: databaseManager)
        var mappingsCreated = 0

        for (index, imageId) in imageIds.enumerated() {
            do {
                // Look up the IMAGE object to get its AWS URL
                let sql = "SELECT url FROM images WHERE id = ? AND is_deleted = 0"
                let statement = try db.prepare(sql)

                var awsUrl: String?
                for row in try statement.run(imageId) {
                    awsUrl = row[0] as? String
                    break
                }

                if let awsUrl = awsUrl, !awsUrl.isEmpty {
                    // Determine if this is the primary image (first in array)
                    let imageType = index == 0 ? "PRIMARY" : "SECONDARY"

                    // Create the item-to-image mapping
                    let cacheKey = try imageURLManager.storeImageMapping(
                        squareImageId: imageId,
                        awsUrl: awsUrl,
                        objectType: "ITEM",
                        objectId: object.id,
                        imageType: imageType
                    )

                    mappingsCreated += 1
                    logger.debug("✅ Created item-to-image mapping: Item \(object.id) -> Image \(imageId) -> \(cacheKey)")
                } else {
                    logger.debug("⚠️ Image \(imageId) not found for item \(object.id) - will be processed when IMAGE object is encountered")
                }

            } catch {
                logger.error("❌ Failed to create item-to-image mapping: \(error)")
            }
        }

        if mappingsCreated > 0 {
            logger.debug("📷 Created \(mappingsCreated) item-to-image mappings for item \(object.id)")
        }
    }

    private func extractObjectName(from object: CatalogObject) -> String {
        switch object.type {
        case "ITEM":
            return object.itemData?.name ?? "Unnamed Item"
        case "CATEGORY":
            return object.categoryData?.name ?? "Unnamed Category"
        case "ITEM_VARIATION":
            return object.itemVariationData?.name ?? "Unnamed Variation"
        case "IMAGE":
            return "Image \(object.id)"
        case "TAX":
            return "Tax \(object.id)"
        case "DISCOUNT":
            return "Discount \(object.id)"
        default:
            return object.type
        }
    }
}

// MARK: - Supporting Types

extension SQLiteSwiftCatalogSyncService {
    
    enum SyncState {
        case idle
        case syncing
        case completed
        case failed
    }
    
    struct SyncProgress {
        var syncedObjects: Int = 0
        var syncedItems: Int = 0  // Track items specifically
        var currentObjectType: String = ""
        var currentObjectName: String = ""
        var startTime: Date = Date()

        var isActive: Bool {
            return syncedObjects > 0
        }

        var progressText: String {
            return "\(syncedItems) items synced (\(syncedObjects) total objects)"
        }

        var rateText: String {
            return "" // Rate display removed per user request
        }
    }
    
    enum SyncError: Error {
        case syncInProgress
        case cancelled
        case migrationFailed
        case apiError(String)
        case databaseError(String)
    }
}

// MARK: - Error Types

struct SyncResultError: Error {
    let message: String
    let code: String?
    let objectId: String?
    let timestamp: Date
    
    init(message: String, code: String? = nil, objectId: String? = nil) {
        self.message = message
        self.code = code
        self.objectId = objectId
        self.timestamp = Date()
    }
}
