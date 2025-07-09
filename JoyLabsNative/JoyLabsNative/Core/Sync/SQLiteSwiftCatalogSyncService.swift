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
            
            // Clear existing data
            try databaseManager.clearAllData()
            logger.info("✅ Existing data cleared")
            
            // Fetch catalog data from Square API
            let catalogData = try await fetchCatalogFromSquare()
            logger.info("✅ Fetched \(catalogData.count) objects from Square API")
            
            // Process and insert data
            try await processCatalogData(catalogData)
            logger.info("✅ Catalog data processed successfully")
            
            // Update sync completion
            syncState = .completed
            lastSyncTime = Date()

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
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchCatalogFromSquare() async throws -> [CatalogObject] {
        logger.info("Fetching catalog data from Square API...")

        // Use the actual Square API service to fetch catalog data
        let catalogObjects = try await squareAPIService.fetchCatalog()

        logger.info("✅ Fetched \(catalogObjects.count) objects from Square API")
        return catalogObjects
    }
    
    private func processCatalogData(_ objects: [CatalogObject]) async throws {
        syncProgress.totalObjects = objects.count
        syncProgress.syncedObjects = 0
        
        for (index, object) in objects.enumerated() {
            try databaseManager.insertCatalogObject(object)
            
            syncProgress.syncedObjects = index + 1
            syncProgress.progressPercentage = Double(syncProgress.syncedObjects) / Double(syncProgress.totalObjects)
            syncProgress.currentObjectType = object.type
            syncProgress.currentObjectName = extractObjectName(from: object)
            
            // Update UI every 10 objects
            if index % 10 == 0 {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms to allow UI updates
            }
        }
    }
    
    private func extractObjectName(from object: CatalogObject) -> String {
        if let categoryData = object.categoryData {
            return categoryData.name ?? "Unnamed Category"
        } else if let itemData = object.itemData {
            return itemData.name ?? "Unnamed Item"
        } else if let variationData = object.itemVariationData {
            return variationData.name ?? "Unnamed Variation"
        }
        return "Unknown Object"
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
        var totalObjects: Int = 0
        var syncedObjects: Int = 0
        var currentObjectType: String = ""
        var currentObjectName: String = ""
        var progressPercentage: Double = 0.0
        var estimatedTimeRemaining: TimeInterval = 0
        
        var isActive: Bool {
            return totalObjects > 0 && syncedObjects < totalObjects
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
