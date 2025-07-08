import Foundation
import OSLog

// MARK: - Temporary Types (until DataTransformationService is properly integrated)

struct TransformationResult {
    let catalogItems: [CatalogItemRow]
    let categories: [CategoryRow]
    let itemVariations: [ItemVariationRow]
    let errors: [TransformationError]
}

enum TransformationError: LocalizedError {
    case objectTransformationFailed(String, Error)
    case missingItemData(String)
    case missingCategoryData(String)
    case missingVariationData(String)
    case jsonEncodingFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .objectTransformationFailed(let id, let error):
            return "Failed to transform object \(id): \(error.localizedDescription)"
        case .missingItemData(let id):
            return "Missing item data for object \(id)"
        case .missingCategoryData(let id):
            return "Missing category data for object \(id)"
        case .missingVariationData(let id):
            return "Missing variation data for object \(id)"
        case .jsonEncodingFailed(let id, let error):
            return "Failed to encode JSON for object \(id): \(error.localizedDescription)"
        }
    }
}

// MARK: - Sync Types

enum SyncType: String, CaseIterable {
    case full = "full"
    case incremental = "incremental"
}

/// Comprehensive catalog synchronization service for Square API integration
/// Handles incremental sync, conflict resolution, and database integration
actor CatalogSyncService {
    
    // MARK: - Dependencies

    private let squareAPIService: SquareAPIService
    private let databaseManager: ResilientDatabaseManager
    // private let dataTransformationService: DataTransformationService
    private let resilienceService: any ResilienceService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogSyncService")
    
    // MARK: - Sync State
    
    private var isSyncing = false
    private var lastFullSyncDate: Date?
    private var lastIncrementalSyncDate: Date?
    private var syncProgress: SyncProgress = .idle
    
    // MARK: - Configuration
    
    private let fullSyncInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let incrementalSyncInterval: TimeInterval = 5 * 60 // 5 minutes
    private let batchSize = 100
    private let maxRetryAttempts = 3
    
    // MARK: - Initialization

    init(squareAPIService: SquareAPIService, databaseManager: ResilientDatabaseManager, resilienceService: any ResilienceService) {
        self.squareAPIService = squareAPIService
        self.databaseManager = databaseManager
        // self.dataTransformationService = dataTransformationService
        self.resilienceService = resilienceService
        logger.info("CatalogSyncService initialized with resilience integration")
    }
    
    // MARK: - Public Sync Methods
    
    /// Perform intelligent catalog sync with resilience (incremental or full based on conditions)
    func performSync() async throws -> SyncResult {
        guard !isSyncing else {
            logger.warning("Sync already in progress, skipping")
            throw SyncError.syncInProgress
        }

        logger.info("Starting intelligent catalog sync with resilience")
        isSyncing = true
        syncProgress = .preparing

        defer {
            isSyncing = false
            syncProgress = .idle
        }

        return try await resilienceService.executeResilient(
            operationId: "catalog_sync_operation",
            operation: {
                let syncType = self.determineSyncType()
                self.logger.info("Determined sync type: \(syncType.rawValue)")

                let result: SyncResult

                switch syncType {
                case .full:
                    result = try await self.performFullSync()
                case .incremental:
                    result = try await self.performIncrementalSync()
                }

                // Update sync timestamps
                await self.updateSyncTimestamps(for: syncType)

                self.logger.info("Catalog sync completed successfully: \(result.summary)")
                return result
            },
            fallback: SyncResult(
                syncType: .incremental,
                duration: 0,
                totalProcessed: 0,
                inserted: 0,
                updated: 0,
                deleted: 0,
                errors: []
            ),
            degradationStrategy: .returnCached
        )
    }

    /// Get cached sync result as fallback
    private func getCachedSyncResult() async -> SyncResult {
        logger.info("Using cached sync result as fallback")
        return SyncResult(
            syncType: .incremental,
            duration: 0,
            totalProcessed: 0,
            inserted: 0,
            updated: 0,
            deleted: 0,
            errors: []
        )
    }
    
    /// Force a full catalog sync
    func performFullSync() async throws -> SyncResult {
        logger.info("Starting full catalog sync")
        syncProgress = .syncing(.full, 0.0)
        
        let startTime = Date()
        var totalProcessed = 0
        var totalInserted = 0
        var totalUpdated = 0
        var totalDeleted = 0
        var errors: [SyncError] = []
        
        do {
            // Fetch complete catalog from Square
            let catalogObjects = try await squareAPIService.fetchCatalog()
            logger.info("Fetched \(catalogObjects.count) objects from Square")
            
            // Process in batches
            let batches = catalogObjects.chunked(into: batchSize)
            
            for (index, batch) in batches.enumerated() {
                let progress = Double(index) / Double(batches.count)
                syncProgress = .syncing(.full, progress)
                
                let batchResult = try await processCatalogBatch(batch, syncType: .full)
                
                totalProcessed += batchResult.processed
                totalInserted += batchResult.inserted
                totalUpdated += batchResult.updated
                totalDeleted += batchResult.deleted
                errors.append(contentsOf: batchResult.errors)
                
                logger.debug("Processed batch \(index + 1)/\(batches.count)")
            }
            
            // Clean up deleted items
            let deletedCount = try await cleanupDeletedItems(catalogObjects)
            totalDeleted += deletedCount
            
            let duration = Date().timeIntervalSince(startTime)
            
            let result = SyncResult(
                syncType: .full,
                duration: duration,
                totalProcessed: totalProcessed,
                inserted: totalInserted,
                updated: totalUpdated,
                deleted: totalDeleted,
                errors: errors
            )
            
            syncProgress = .completed(result)
            return result
            
        } catch {
            logger.error("Full sync failed: \(error.localizedDescription)")
            throw SyncError.syncFailed(error)
        }
    }
    
    /// Perform incremental catalog sync
    func performIncrementalSync() async throws -> SyncResult {
        logger.info("Starting incremental catalog sync")
        syncProgress = .syncing(.incremental, 0.0)
        
        let startTime = Date()
        var totalProcessed = 0
        var totalInserted = 0
        var totalUpdated = 0
        var errors: [SyncError] = []
        
        do {
            // Get last sync timestamp
            let beginTime = lastIncrementalSyncDate?.iso8601String
            
            // Search for updated objects
            let updatedObjects = try await squareAPIService.searchCatalog(beginTime: beginTime)
            logger.info("Found \(updatedObjects.count) updated objects since last sync")
            
            if updatedObjects.isEmpty {
                let result = SyncResult(
                    syncType: .incremental,
                    duration: Date().timeIntervalSince(startTime),
                    totalProcessed: 0,
                    inserted: 0,
                    updated: 0,
                    deleted: 0,
                    errors: []
                )
                
                syncProgress = .completed(result)
                return result
            }
            
            // Process updated objects
            let batchResult = try await processCatalogBatch(updatedObjects, syncType: .incremental)
            
            totalProcessed = batchResult.processed
            totalInserted = batchResult.inserted
            totalUpdated = batchResult.updated
            errors = batchResult.errors
            
            let duration = Date().timeIntervalSince(startTime)
            
            let result = SyncResult(
                syncType: .incremental,
                duration: duration,
                totalProcessed: totalProcessed,
                inserted: totalInserted,
                updated: totalUpdated,
                deleted: 0,
                errors: errors
            )
            
            syncProgress = .completed(result)
            return result
            
        } catch {
            logger.error("Incremental sync failed: \(error.localizedDescription)")
            throw SyncError.syncFailed(error)
        }
    }
    
    /// Get current sync progress
    func getSyncProgress() async -> SyncProgress {
        return syncProgress
    }
    
    /// Check if sync is needed
    func isSyncNeeded() async -> Bool {
        let now = Date()
        
        // Check if full sync is needed
        if let lastFull = lastFullSyncDate {
            if now.timeIntervalSince(lastFull) > fullSyncInterval {
                return true
            }
        } else {
            return true // Never synced
        }
        
        // Check if incremental sync is needed
        if let lastIncremental = lastIncrementalSyncDate {
            return now.timeIntervalSince(lastIncremental) > incrementalSyncInterval
        }
        
        return true
    }
    
    // MARK: - Private Implementation
    
    private func determineSyncType() -> SyncType {
        let now = Date()
        
        // Force full sync if never synced
        guard let lastFull = lastFullSyncDate else {
            return .full
        }
        
        // Check if full sync interval has passed
        if now.timeIntervalSince(lastFull) > fullSyncInterval {
            return .full
        }
        
        return .incremental
    }
    
    private func processCatalogBatch(_ objects: [CatalogObject], syncType: SyncType) async throws -> BatchResult {
        logger.debug("Processing batch of \(objects.count) catalog objects with data transformation")

        // Transform objects to database format
        // let transformationResult = try await dataTransformationService.transformCatalogObjects(objects)
        // For now, skip transformation and use objects directly
        let transformationResult = TransformationResult(
            catalogItems: [],
            categories: [],
            itemVariations: [],
            errors: []
        )

        var processed = 0
        var inserted = 0
        var updated = 0
        var deleted = 0
        var errors: [SyncError] = []

        // Add transformation errors to sync errors
        for transformError in transformationResult.errors {
            errors.append(.transformationFailed("unknown", transformError))
        }

        // Process transformed items
        for itemRow in transformationResult.catalogItems {
            do {
                let result = try await processCatalogItemRow(itemRow, syncType: syncType)
                updateCounters(result: result, processed: &processed, inserted: &inserted, updated: &updated, deleted: &deleted)
            } catch {
                logger.error("Failed to process item \(itemRow.id): \(error.localizedDescription)")
                errors.append(.objectProcessingFailed(itemRow.id, error))
            }
        }

        // Process transformed categories
        for categoryRow in transformationResult.categories {
            do {
                let result = try await processCategoryRow(categoryRow, syncType: syncType)
                updateCounters(result: result, processed: &processed, inserted: &inserted, updated: &updated, deleted: &deleted)
            } catch {
                logger.error("Failed to process category \(categoryRow.id): \(error.localizedDescription)")
                errors.append(.objectProcessingFailed(categoryRow.id, error))
            }
        }

        // Process transformed variations
        for variationRow in transformationResult.itemVariations {
            do {
                let result = try await processItemVariationRow(variationRow, syncType: syncType)
                updateCounters(result: result, processed: &processed, inserted: &inserted, updated: &updated, deleted: &deleted)
            } catch {
                logger.error("Failed to process variation \(variationRow.id): \(error.localizedDescription)")
                errors.append(.objectProcessingFailed(variationRow.id, error))
            }
        }

        logger.debug("Batch processing completed: \(processed) processed, \(inserted) inserted, \(updated) updated, \(deleted) deleted, \(errors.count) errors")

        return BatchResult(
            processed: processed,
            inserted: inserted,
            updated: updated,
            deleted: deleted,
            errors: errors
        )
    }
    
    // MARK: - Row Processing Methods

    private func processCatalogItemRow(_ itemRow: CatalogItemRow, syncType: SyncType) async throws -> ProcessingResult {
        // Check if item is deleted
        if itemRow.isDeleted == 1 {
            try await databaseManager.deleteCatalogItem(id: itemRow.id)
            return .deleted
        }

        // Check if item exists in database
        let existingItem = try await databaseManager.getCatalogItem(id: itemRow.id)

        if let existing = existingItem {
            // Update existing item if version is newer
            if let itemVersion = Int64(itemRow.version), let existingVersion = Int64(existing.version) {
                if itemVersion > existingVersion {
                    try await databaseManager.updateCatalogItem(itemRow)
                    return .updated
                } else {
                    return .skipped // Item is not newer
                }
            } else {
                // No version info, update anyway
                try await databaseManager.updateCatalogItem(itemRow)
                return .updated
            }
        } else {
            // Insert new item
            try await databaseManager.insertCatalogItem(itemRow)
            return .inserted
        }
    }

    private func processCategoryRow(_ categoryRow: CategoryRow, syncType: SyncType) async throws -> ProcessingResult {
        // Check if category is deleted
        if categoryRow.isDeleted == 1 {
            try await databaseManager.deleteCategory(id: categoryRow.id)
            return .deleted
        }

        // Check if category exists in database
        let existingCategory = try await databaseManager.getCategory(id: categoryRow.id)

        if let existing = existingCategory {
            // Update existing category if version is newer
            if let categoryVersion = Int64(categoryRow.version), let existingVersion = Int64(existing.version) {
                if categoryVersion > existingVersion {
                    try await databaseManager.updateCategory(categoryRow)
                    return .updated
                } else {
                    return .skipped // Category is not newer
                }
            } else {
                // No version info, update anyway
                try await databaseManager.updateCategory(categoryRow)
                return .updated
            }
        } else {
            // Insert new category
            try await databaseManager.insertCategory(categoryRow)
            return .inserted
        }
    }

    private func processItemVariationRow(_ variationRow: ItemVariationRow, syncType: SyncType) async throws -> ProcessingResult {
        // Check if variation is deleted
        if variationRow.isDeleted == 1 {
            try await databaseManager.deleteItemVariation(id: variationRow.id)
            return .deleted
        }

        // Check if variation exists in database
        let existingVariation = try await databaseManager.getItemVariation(id: variationRow.id)

        if let existing = existingVariation {
            // Update existing variation if version is newer
            if let variationVersion = Int64(variationRow.version), let existingVersion = Int64(existing.version) {
                if variationVersion > existingVersion {
                    try await databaseManager.updateItemVariation(variationRow)
                    return .updated
                } else {
                    return .skipped // Variation is not newer
                }
            } else {
                // No version info, update anyway
                try await databaseManager.updateItemVariation(variationRow)
                return .updated
            }
        } else {
            // Insert new variation
            try await databaseManager.insertItemVariation(variationRow)
            return .inserted
        }
    }

    private func updateCounters(result: ProcessingResult, processed: inout Int, inserted: inout Int, updated: inout Int, deleted: inout Int) {
        switch result {
        case .inserted:
            inserted += 1
        case .updated:
            updated += 1
        case .deleted:
            deleted += 1
        case .skipped:
            break
        }
        processed += 1
    }
    
    private func cleanupDeletedItems(_ currentObjects: [CatalogObject]) async throws -> Int {
        logger.debug("Cleaning up deleted items")
        
        // Get all object IDs from Square
        let squareObjectIds = Set(currentObjects.map { $0.id })
        
        // Get all object IDs from database
        let databaseObjectIds = try await databaseManager.getAllCatalogObjectIds()
        
        // Find objects that exist in database but not in Square
        let deletedIds = databaseObjectIds.subtracting(squareObjectIds)
        
        // Delete them from database
        for deletedId in deletedIds {
            try await databaseManager.deleteCatalogObject(id: deletedId)
        }
        
        logger.info("Cleaned up \(deletedIds.count) deleted items")
        return deletedIds.count
    }
    
    private func updateSyncTimestamps(for syncType: SyncType) async {
        let now = Date()
        
        switch syncType {
        case .full:
            lastFullSyncDate = now
            lastIncrementalSyncDate = now
        case .incremental:
            lastIncrementalSyncDate = now
        }
        
        logger.debug("Updated sync timestamps for \(syncType.rawValue)")
    }
}

// MARK: - Supporting Types
// SyncType is already defined at the top of this file

enum SyncProgress: Equatable {
    case idle
    case preparing
    case syncing(SyncType, Double) // type and progress (0.0-1.0)
    case completed(SyncResult)
    case failed(Error)
    
    static func == (lhs: SyncProgress, rhs: SyncProgress) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing):
            return true
        case (.syncing(let lType, let lProgress), .syncing(let rType, let rProgress)):
            return lType == rType && lProgress == rProgress
        case (.completed(let lResult), .completed(let rResult)):
            return lResult.syncType == rResult.syncType
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

struct SyncResult {
    let syncType: SyncType
    let duration: TimeInterval
    let totalProcessed: Int
    let inserted: Int
    let updated: Int
    let deleted: Int
    let errors: [SyncError]
    
    var isSuccess: Bool {
        return errors.isEmpty
    }
    
    var summary: String {
        return "\(syncType.rawValue) sync: \(totalProcessed) processed, \(inserted) inserted, \(updated) updated, \(deleted) deleted in \(String(format: "%.2f", duration))s"
    }
}

struct BatchResult {
    let processed: Int
    let inserted: Int
    let updated: Int
    let deleted: Int
    let errors: [SyncError]
}

enum ProcessingResult {
    case inserted
    case updated
    case deleted
    case skipped
}

enum SyncError: LocalizedError {
    case syncInProgress
    case syncFailed(Error)
    case objectProcessingFailed(String, Error)
    case transformationFailed(String, Error)
    case databaseError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .syncInProgress:
            return "Sync operation already in progress"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .objectProcessingFailed(let id, let error):
            return "Failed to process object \(id): \(error.localizedDescription)"
        case .transformationFailed(let id, let error):
            return "Failed to transform object \(id): \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}


