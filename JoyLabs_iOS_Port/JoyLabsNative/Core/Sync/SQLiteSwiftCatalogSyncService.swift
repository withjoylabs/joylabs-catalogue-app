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
    @Published var currentProgressMessage: String = ""
    
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
    
    func performSync(isManual: Bool = false) async throws {
        guard !isSyncInProgress else {
            throw SyncError.syncInProgress
        }
        
        // Ensure database is connected
        try databaseManager.connect()
        
        isSyncInProgress = true
        syncState = .syncing
        errorMessage = nil
        
        defer {
            isSyncInProgress = false
        }
        
        do {
            logger.info("Starting catalog sync with SQLite.swift - manual: \(isManual)")

            // Initialize progress tracking - RESET TO ZERO
            syncProgress = SyncProgress()
            syncProgress.startTime = Date()
            syncProgress.syncedObjects = 0
            syncProgress.syncedItems = 0
            syncProgress.currentObjectType = "INITIALIZING"
            syncProgress.currentObjectName = "Starting sync..."

            logger.info("🔄 Progress initialized: \(self.syncProgress.syncedItems) items, \(self.syncProgress.syncedObjects) objects")

            // Start UI update timer (every 1 second)
            startProgressUpdateTimer()

            // Clear existing data
            try databaseManager.clearAllData()
            logger.info("✅ Existing data cleared")

            // Clear image cache for clean slate
            await imageCacheService.clearAllImages()
            logger.info("🖼️ Cleared image cache for fresh start")

            // Fetch catalog data from Square API with progress tracking
            let catalogData = try await fetchCatalogFromSquareWithProgress()
            logger.info("✅ Fetched \(catalogData.count) objects from Square API")

            // Process and insert data with progress tracking
            try await processCatalogDataWithProgress(catalogData)
            logger.info("✅ Catalog data processed successfully")

            // Stop progress timer
            stopProgressUpdateTimer()

            // Update sync completion
            syncState = .completed
            lastSyncTime = Date()

            // Final progress update
            syncProgress.syncedObjects = catalogData.count

            logger.info("🎉 Catalog sync completed successfully!")
            logger.info("📊 Final sync stats: \(catalogData.count) total objects processed")

            // Log summary of object types processed
            let objectTypeCounts = Dictionary(grouping: catalogData) { $0.type }
                .mapValues { $0.count }
            logger.info("📋 Object types processed: \(objectTypeCounts)")
            
        } catch {
            logger.error("❌ Catalog sync failed: \(error)")
            syncState = .failed
            errorMessage = error.localizedDescription
            stopProgressUpdateTimer()
            throw error
        }
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
        logger.info("Fetching catalog data from Square API...")

        // Update progress message for UI
        currentProgressMessage = "Connecting to Square API..."

        // Use the actual Square API service to fetch catalog data
        let catalogObjects = try await squareAPIService.fetchCatalog()

        logger.info("✅ Fetched \(catalogObjects.count) objects from Square API")
        currentProgressMessage = "✅ Fetched \(catalogObjects.count) total objects from Square API"

        // Don't set the final counts here - let processing update them incrementally
        let itemCount = catalogObjects.filter { $0.type == "ITEM" }.count
        syncProgress.currentObjectType = "PROCESSING"
        syncProgress.currentObjectName = "Ready to process \(catalogObjects.count) objects (\(itemCount) items)"

        return catalogObjects
    }
    
    private func processCatalogDataWithProgress(_ objects: [CatalogObject]) async throws {
        logger.info("🔄 Starting to process \(objects.count) objects into database...")

        // RESET PROGRESS TO ZERO AT START OF PROCESSING
        syncProgress.syncedObjects = 0
        syncProgress.syncedItems = 0
        syncProgress.currentObjectType = "PROCESSING"
        syncProgress.currentObjectName = "Starting to process objects..."

        logger.info("📊 PROGRESS RESET: \(self.syncProgress.syncedItems) items, \(self.syncProgress.syncedObjects) objects")

        var processedItems = 0
        let totalObjects = objects.count

        for (index, object) in objects.enumerated() {
            // Process images for this object before inserting
            await processCatalogObjectImages(object)

            try databaseManager.insertCatalogObject(object)

            // Count items specifically as we process them
            if object.type == "ITEM" {
                processedItems += 1
            }

            // Update progress with processed counts
            let currentObjectCount = index + 1
            syncProgress.syncedObjects = currentObjectCount
            syncProgress.syncedItems = processedItems

            // Update the progress message that UI will display
            currentProgressMessage = "Processing: \(processedItems) items processed (\(currentObjectCount) of \(totalObjects) objects)"

            // Log progress every 500 objects to see what's happening
            if index % 500 == 0 {
                logger.info("📊 PROGRESS UPDATE: \(processedItems) items, \(currentObjectCount)/\(totalObjects) objects")
            }

            // Small delay every 50 objects to allow UI updates
            if index % 50 == 0 {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms to allow UI updates
            }
        }

        logger.info("✅ FINAL PROGRESS: \(processedItems) items, \(objects.count) objects processed")

        logger.info("✅ Processed all \(objects.count) catalog objects")
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
