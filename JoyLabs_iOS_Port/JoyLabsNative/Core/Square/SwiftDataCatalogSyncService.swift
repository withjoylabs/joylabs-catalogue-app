import Foundation
import SwiftUI
import SwiftData
import OSLog
import Combine

/// SwiftData-based catalog sync service
/// Replaces SQLiteSwiftCatalogSyncService with native SwiftData persistence
@MainActor
class SwiftDataCatalogSyncService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var syncState: SyncState = .idle
    @Published var syncProgress = SyncProgress()
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let squareAPIService: SquareAPIService
    private let catalogManager: SwiftDataCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataCatalogSync")
    
    /// Compatibility property for existing code
    var sharedDatabaseManager: SwiftDataCatalogManager {
        return catalogManager
    }
    
    private var syncTask: Task<Void, Error>?
    private var isCancelled = false
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        
        // Use factory to get shared database manager
        self.catalogManager = SquareAPIServiceFactory.createDatabaseManager()
        
        logger.info("[Sync] SwiftDataCatalogSyncService initialized with shared database manager")
    }
    
    // MARK: - Public Methods
    
    func performSync(isManual: Bool) async throws {
        logger.info("[Sync] Starting full sync (manual: \(isManual))")
        
        guard syncState != .syncing else {
            logger.warning("[Sync] Sync already in progress")
            return
        }
        
        syncState = .syncing
        syncProgress = SyncProgress()
        errorMessage = nil
        isCancelled = false
        
        syncTask = Task {
            do {
                try await performFullSync()
                
                await MainActor.run {
                    self.syncState = .completed
                    self.logger.info("[Sync] Full sync completed successfully")

                    // Notify completion for statistics refresh and cache clearing
                    NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil, userInfo: nil)
                }
                
            } catch is CancellationError {
                await MainActor.run {
                    self.syncState = .idle
                    self.logger.info("[Sync] Sync cancelled")
                }
                throw CancellationError()
                
            } catch {
                await MainActor.run {
                    self.syncState = .failed
                    self.errorMessage = error.localizedDescription
                    self.logger.error("[Sync] Sync failed: \(error)")
                }
                throw error
            }
        }
        
        try await syncTask?.value
    }
    
    func performIncrementalSync() async throws {
        logger.info("[Sync] Starting incremental sync")
        
        guard syncState != .syncing else {
            logger.warning("[Sync] Sync already in progress")
            return
        }
        
        syncState = .syncing
        syncProgress = SyncProgress()
        errorMessage = nil
        isCancelled = false
        
        syncTask = Task {
            do {
                try await performIncrementalSyncInternal()
                
                await MainActor.run {
                    self.syncState = .completed
                    self.logger.info("[Sync] Incremental sync completed successfully")

                    // Notify completion for statistics refresh and cache clearing
                    NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil, userInfo: nil)
                }
                
            } catch is CancellationError {
                await MainActor.run {
                    self.syncState = .idle
                    self.logger.info("[Sync] Incremental sync cancelled")
                }
                throw CancellationError()
                
            } catch {
                await MainActor.run {
                    self.syncState = .failed
                    self.errorMessage = error.localizedDescription
                    self.logger.error("[Sync] Incremental sync failed: \(error)")
                }
                throw error
            }
        }
        
        try await syncTask?.value
    }
    
    func cancelSync() {
        logger.info("[Sync] Cancelling sync operation")
        isCancelled = true
        syncTask?.cancel()
        syncState = .idle
    }
    
    // MARK: - Private Methods
    
    private func performFullSync() async throws {
        logger.info("[Sync] Performing full catalog sync")
        
        // Clear existing data
        try catalogManager.clearAllData()
        logger.info("[Sync] Cleared existing catalog data")
        
        // Update sync progress
        updateSyncProgress(currentObjectType: "Clearing data", syncedObjects: 0, syncedItems: 0)
        
        // Update progress to show downloading
        updateSyncProgress(currentObjectType: "DOWNLOADING", syncedObjects: 0, syncedItems: 0)
        
        logger.info("[Sync] Fetching catalog data from Square API...")
        
        // Use the actual Square API service to fetch catalog data (matches original exactly)
        let allObjects = try await squareAPIService.fetchCatalog()
        
        logger.info("[Sync] Fetched \(allObjects.count) objects from Square API")
        
        // Update progress to show ready for processing
        let _ = allObjects.filter { $0.type == "ITEM" }.count
        updateSyncProgress(
            currentObjectType: "READY", 
            syncedObjects: 0, 
            syncedItems: 0
        )
        
        logger.info("[Sync] Fetched \(allObjects.count) total objects, processing...")
        
        // Process objects in dependency order
        let sortedObjects = sortObjectsByDependency(allObjects)
        
        // Process in batches
        try await processCatalogObjectsBatch(sortedObjects)
        
        // Process image URL mappings (matching original implementation)
        let imageObjects = sortedObjects.filter { $0.type == "IMAGE" }
        for imageObject in imageObjects {
            await processImageURLMapping(imageObject)
        }
        
        // Final save
        try catalogManager.save()
        
        logger.info("[Sync] Full sync completed: \(self.syncProgress.syncedObjects) objects processed")
    }
    
    private func performIncrementalSyncInternal() async throws {
        logger.info("[Sync] Performing incremental sync")
        
        // Get the last sync timestamp
        let lastUpdateTime = try await catalogManager.getLatestUpdatedAt()
        
        if let lastUpdate = lastUpdateTime {
            let formatter = ISO8601DateFormatter()
            let beginTime = formatter.string(from: lastUpdate)
            logger.info("[Sync] Incremental sync from: \(beginTime)")
            
            // Fetch updated objects since last sync using SquareAPIService
            let updatedObjects = try await squareAPIService.searchCatalog(beginTime: beginTime)
            
            logger.info("[Sync] Found \(updatedObjects.count) updated objects")
            
            if updatedObjects.isEmpty {
                updateSyncProgress(currentObjectType: "Up to date", syncedObjects: 0, syncedItems: 0)
                return
            }
            
            // Sort and process updated objects
            let sortedObjects = sortObjectsByDependency(updatedObjects)
            try await processCatalogObjectsBatch(sortedObjects)
            
            // Save changes
            try catalogManager.save()
            
        } else {
            logger.info("[Sync] No previous sync found, performing full sync")
            try await performFullSync()
        }
    }
    
    private func processCatalogObjectsBatch(_ objects: [CatalogObject]) async throws {
        let _ = objects.count
        var processed = 0
        var itemsProcessed = 0
        
        for object in objects {
            if isCancelled { throw CancellationError() }
            
            // Insert object into SwiftData
            try await catalogManager.insertCatalogObject(object)
            
            processed += 1
            if object.type == "ITEM" {
                itemsProcessed += 1
            }
            
            // Update progress periodically
            if processed % 50 == 0 {
                updateSyncProgress(
                    currentObjectType: object.type,
                    syncedObjects: processed,
                    syncedItems: itemsProcessed
                )
                
                // Save periodically and allow UI updates
                try catalogManager.save()
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }
        }
        
        // Final progress update
        updateSyncProgress(
            currentObjectType: "Completed",
            syncedObjects: processed,
            syncedItems: itemsProcessed
        )
        
        logger.info("[Sync] Processed \(processed) objects (\(itemsProcessed) items)")
    }
    
    private func sortObjectsByDependency(_ objects: [CatalogObject]) -> [CatalogObject] {
        // Sort by dependency order to ensure proper relationships (matching original)
        let order: [String: Int] = [
            "CATEGORY": 1,      // Categories must come first
            "TAX": 2,           // Taxes needed for items
            "MODIFIER_LIST": 3, // Modifier lists before modifiers
            "MODIFIER": 4,      // Modifiers before items use them
            "ITEM": 5,          // Items before their variations
            "ITEM_VARIATION": 6,// Variations after items
            "IMAGE": 7,         // Images after everything else
            "DISCOUNT": 8       // Discounts last
        ]
        
        return objects.sorted { first, second in
            let firstOrder = order[first.type] ?? 999
            let secondOrder = order[second.type] ?? 999
            return firstOrder < secondOrder
        }
    }
    
    private func updateSyncProgress(currentObjectType: String, syncedObjects: Int, syncedItems: Int) {
        var progress = self.syncProgress
        progress.currentObjectType = currentObjectType
        progress.syncedObjects = syncedObjects
        progress.syncedItems = syncedItems
        self.syncProgress = progress
    }
    
    private func processImageURLMapping(_ object: CatalogObject) async {
        guard let imageData = object.imageData else {
            logger.warning("[Sync] IMAGE object \(object.id) missing imageData")
            return
        }
        
        guard let awsUrl = imageData.url, !awsUrl.isEmpty else {
            logger.warning("[Sync] IMAGE object \(object.id) missing URL")
            return
        }
        
        // Skip processing deleted images to avoid wasting overhead
        if object.safeIsDeleted {
            return
        }
        
        // For SwiftData, we store the image URL directly in the ImageModel
        // Native URLCache and AsyncImage handle the actual image caching
        logger.debug("[Sync] Processed image URL mapping for: \(object.id) -> \(awsUrl)")
    }
}

// MARK: - Supporting Types

enum SyncState: String, CaseIterable {
    case idle = "idle"
    case syncing = "syncing"
    case completed = "completed"
    case failed = "failed"
}

struct SyncProgress {
    var startTime: Date = Date()
    var currentObjectType: String = ""
    var syncedObjects: Int = 0
    var syncedItems: Int = 0
    var totalObjects: Int = 0
    
    var isActive: Bool {
        return syncedObjects > 0
    }
}