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
    private let migrationService = DatabaseMigrationService()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftCatalogSync")
    
    // MARK: - State

    private var isSyncInProgress = false
    private var hasMigrated = false
    private var progressUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.databaseManager = SQLiteSwiftCatalogManager()
        
        // Perform migration on first use
        Task {
            await performMigrationIfNeeded()
        }
    }
    
    // MARK: - Migration
    
    private func performMigrationIfNeeded() async {
        guard !hasMigrated else { return }
        
        do {
            logger.info("Performing database migration to SQLite.swift...")
            try await migrationService.migrateToSQLiteSwift()
            self.databaseManager = migrationService.getNewDatabaseManager()
            hasMigrated = true
            logger.info("✅ Database migration completed successfully")
        } catch {
            logger.error("❌ Database migration failed: \(error)")
            errorMessage = "Database migration failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sync Operations
    
    func performSync(isManual: Bool = false) async throws {
        guard !isSyncInProgress else {
            throw SyncError.syncInProgress
        }
        
        // Ensure migration is complete
        await performMigrationIfNeeded()
        
        isSyncInProgress = true
        syncState = .syncing
        errorMessage = nil
        
        defer {
            isSyncInProgress = false
        }
        
        do {
            logger.info("Starting catalog sync with SQLite.swift - manual: \(isManual)")

            // Initialize progress tracking
            syncProgress = SyncProgress()
            syncProgress.startTime = Date()

            // Start UI update timer (every 1 second)
            startProgressUpdateTimer()

            // Clear existing data
            try databaseManager.clearAllData()
            logger.info("✅ Existing data cleared")

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

        // Update progress for fetch phase
        syncProgress.currentObjectType = "FETCHING"
        syncProgress.currentObjectName = "Connecting to Square API..."

        // Use the actual Square API service to fetch catalog data
        let catalogObjects = try await squareAPIService.fetchCatalog()

        logger.info("✅ Fetched \(catalogObjects.count) objects from Square API")

        // Update progress
        syncProgress.currentObjectName = "Ready to process \(catalogObjects.count) objects"

        return catalogObjects
    }
    
    private func processCatalogDataWithProgress(_ objects: [CatalogObject]) async throws {
        syncProgress.syncedObjects = 0
        syncProgress.syncedItems = 0

        logger.info("Processing \(objects.count) catalog objects...")

        for (index, object) in objects.enumerated() {
            try databaseManager.insertCatalogObject(object)

            // Update progress
            syncProgress.syncedObjects = index + 1

            // Count items specifically
            if object.type == "ITEM" {
                syncProgress.syncedItems += 1
            }

            syncProgress.currentObjectType = object.type
            syncProgress.currentObjectName = extractObjectName(from: object)

            // Log progress every 1000 objects
            if index % 1000 == 0 && index > 0 {
                logger.info("📊 Processed \(index) objects so far...")
            }

            // Small delay every 100 objects to allow UI updates
            if index % 100 == 0 {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms to allow UI updates
            }
        }

        logger.info("✅ Processed all \(objects.count) catalog objects")
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
