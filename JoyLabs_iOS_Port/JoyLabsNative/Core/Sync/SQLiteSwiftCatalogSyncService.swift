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
    private let imageCacheService = ImageCacheService()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftCatalogSync")

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

        // Store the sync task for cancellation
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
                logger.info("✅ Existing data cleared")

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



        var processedItems = 0
        let totalObjects = objects.count

        for (index, object) in objects.enumerated() {
            // Check for cancellation
            if isCancellationRequested {
                logger.info("🛑 Sync cancelled during processing at object \(index + 1)/\(totalObjects)")
                throw SyncError.cancelled
            }

            // Update sync status based on object type being processed
            updateSyncStatusForObjectType(object.type, index: index, total: totalObjects)

            // Process images for this object before inserting
            await processCatalogObjectImages(object)

            try databaseManager.insertCatalogObject(object)

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

        logger.info("✅ Processed all \(objects.count) catalog objects")
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

        // Handle IMAGE objects directly - check if this object has image data
        if object.type == "IMAGE" {
            // For IMAGE type objects, we'd need to extract the image URL from the object
            // This would typically be in a nested structure - for now we'll log it
            logger.debug("📷 Processing IMAGE object: \(objectId)")
            return
        }

        // Process item images - check if itemData has images property
        if let itemData = object.itemData {
            // For now, just log that we found item data
            // The actual image processing will be implemented when we have the correct model structure
            logger.debug("📷 Found item data for \(objectId), name: \(itemData.name ?? "unknown")")

            // TODO: Process item images when model structure is confirmed
            // This would involve checking for images array or imageIds array depending on the actual model
        }

        // Process category image references
        if let categoryData = object.categoryData {
            // For now, just log that we found category data
            logger.debug("📷 Found category data for \(objectId), name: \(categoryData.name ?? "unknown")")

            // TODO: Process category images when model structure is confirmed
            // This would involve checking for imageIds array depending on the actual model
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
