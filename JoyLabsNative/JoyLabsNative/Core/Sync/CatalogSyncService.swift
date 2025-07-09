import Foundation
import SwiftUI
import SQLite3

// MARK: - Sync Result Types (to match SquareSyncCoordinator)
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

/// Comprehensive catalog sync service with full Square API coverage
/// Handles 18,000+ item catalogs with efficient batch processing and error recovery
@MainActor
class CatalogSyncService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var syncState: SyncState = .idle
    @Published var syncProgress: SyncProgress = SyncProgress()
    @Published var lastSyncTime: Date?
    @Published var errorMessage: String?
    
    // MARK: - Dependencies

    private var apiClient: SquareCatalogAPIClient
    private let databaseManager: CatalogDatabaseManager
    private let squareAPIService: SquareAPIService
    private let tokenService = TokenService()

    // MARK: - Sync Lock
    private var isSyncInProgress = false

    // MARK: - Database Corruption Detection

    /// Detects various types of SQLite database corruption
    private func isDatabaseCorrupted(_ error: Error) -> Bool {
        let errorDescription = error.localizedDescription.lowercased()

        // Common SQLite corruption indicators
        let corruptionIndicators = [
            "malformed",
            "corruption",
            "corrupt",
            "database disk image is malformed",
            "index corruption",
            "database or disk is full",
            "sqlite_corrupt",
            "sqlite_notadb",
            "file is not a database",
            "database schema has changed",
            "no such table",
            "sql logic error"
        ]

        return corruptionIndicators.contains { indicator in
            errorDescription.contains(indicator)
        }
    }

    // MARK: - Sync State
    
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
        case databaseCorrupted
        case apiError(String)
        case networkError(String)
    }



    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        // Initialize with empty token - will be set when needed
        self.apiClient = SquareCatalogAPIClient(accessToken: "")
        self.databaseManager = CatalogDatabaseManager()
        
        // Load last sync time
        loadLastSyncTime()
    }
    
    // MARK: - Public Sync Methods
    

    

    
    /// Cancel ongoing sync operation
    func cancelSync() {
        guard syncState == .syncing else { return }
        
        syncState = .idle
        syncProgress = SyncProgress()
    }
    
    // MARK: - Helper Methods

    /// Ensure API client has a valid access token
    private func ensureValidAPIClient() async throws {
        guard let accessToken = await tokenService.ensureValidToken() else {
            throw SyncError.apiError("No valid access token available")
        }

        // Update API client with fresh token
        apiClient = SquareCatalogAPIClient(accessToken: accessToken)
    }

    private func extractObjectName(from object: SquareCatalogAPIClient.CatalogObject) -> String {
        switch object.type {
        case "ITEM":
            return object.itemData?.name ?? "Unknown Item"
        case "ITEM_VARIATION":
            return object.itemVariationData?.name ?? "Unknown Variation"
        case "CATEGORY":
            return object.categoryData?.name ?? "Unknown Category"
        case "TAX":
            return object.taxData?.name ?? "Unknown Tax"
        case "DISCOUNT":
            return object.discountData?.name ?? "Unknown Discount"
        case "MODIFIER_LIST":
            return object.modifierListData?.name ?? "Unknown Modifier List"
        case "MODIFIER":
            return object.modifierData?.name ?? "Unknown Modifier"
        case "IMAGE":
            return object.imageData?.name ?? "Unknown Image"
        default:
            return "Unknown Object"
        }
    }
    
    private func loadLastSyncTime() {
        if let timestamp = UserDefaults.standard.object(forKey: "lastCatalogSyncTime") as? Date {
            lastSyncTime = timestamp
        }
    }
    
    private func saveLastSyncTime() {
        if let lastSync = lastSyncTime {
            UserDefaults.standard.set(lastSync, forKey: "lastCatalogSyncTime")
        }
    }
    
    // MARK: - Computed Properties
    
    var timeSinceLastSync: String? {
        guard let lastSync = lastSyncTime else { return nil }
        
        let interval = Date().timeIntervalSince(lastSync)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        
        if interval < 60 {
            return "Just now"
        } else {
            return "\(formatter.string(from: interval) ?? "Unknown") ago"
        }
    }
    
    var shouldPerformIncrementalSync: Bool {
        guard let lastSync = lastSyncTime else { return false }
        
        // Perform incremental sync if last sync was more than 1 hour ago
        let hoursSinceLastSync = Date().timeIntervalSince(lastSync) / 3600
        return hoursSinceLastSync >= 1.0
    }
    
    var syncStatusText: String {
        switch syncState {
        case .idle:
            return timeSinceLastSync ?? "Never synced"
        case .syncing:
            if syncProgress.totalObjects > 0 {
                return "Syncing \(syncProgress.syncedObjects)/\(syncProgress.totalObjects) items..."
            } else {
                return "Preparing sync..."
            }
        case .completed:
            return "Sync completed"
        case .failed:
            return "Sync failed"
        }
    }

    // MARK: - Public Sync Methods

    func performSync() async throws -> SyncResult {
        // Prevent parallel sync operations
        if isSyncInProgress {
            throw SyncError.syncInProgress
        }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        syncState = .syncing
        let _ = Date() // startTime for future use

        do {
            // Check for database corruption and recreate if needed
            do {
                // Test database with a simple query
                _ = try await databaseManager.getLastSyncTime()
            } catch {
                if isDatabaseCorrupted(error) {
                    print("Database corruption detected, recreating database...")
                    try await databaseManager.recreateDatabase()
                }
            }

            // Perform full sync by default
            let result = try await performFullSync()
            syncState = .completed
            lastSyncTime = Date()
            saveLastSyncTime()
            return result
        } catch {
            // Check if this is a database corruption error during sync
            if isDatabaseCorrupted(error) {
                print("Database corruption detected during sync, attempting recovery...")
                do {
                    try await databaseManager.recreateDatabase()
                    // Retry the sync after database recreation
                    let result = try await performFullSync()
                    syncState = .completed
                    lastSyncTime = Date()
                    saveLastSyncTime()
                    return result
                } catch {
                    syncState = .failed
                    errorMessage = "Database corruption recovery failed: \(error.localizedDescription)"
                    throw error
                }
            } else {
                syncState = .failed
                errorMessage = error.localizedDescription
                throw error
            }
        }
    }

    func performIncrementalSync() async throws -> SyncResult {
        syncState = .syncing
        let _ = Date() // startTime for future use

        do {
            // For now, perform full sync - incremental can be optimized later
            let result = try await performFullSync()
            syncState = .completed
            lastSyncTime = Date()
            saveLastSyncTime()
            return result
        } catch {
            // Check if this is a database corruption error during incremental sync
            if isDatabaseCorrupted(error) {
                print("Database corruption detected during incremental sync, attempting recovery...")
                do {
                    try await databaseManager.recreateDatabase()
                    // Retry the sync after database recreation
                    let result = try await performFullSync()
                    syncState = .completed
                    lastSyncTime = Date()
                    saveLastSyncTime()
                    return result
                } catch {
                    syncState = .failed
                    errorMessage = "Database corruption recovery failed: \(error.localizedDescription)"
                    throw error
                }
            } else {
                syncState = .failed
                errorMessage = error.localizedDescription
                throw error
            }
        }
    }

    func getSyncProgress() async -> SyncProgressState {
        switch syncState {
        case .idle:
            return .idle
        case .syncing:
            return .syncing(syncProgress, syncProgress.progressPercentage / 100.0)
        case .completed:
            // Return a mock result for now
            return .completed(SyncResult(
                syncType: .full,
                duration: 0,
                totalProcessed: 0,
                inserted: 0,
                updated: 0,
                deleted: 0,
                errors: []
            ))
        case .failed:
            return .failed(NSError(domain: "CatalogSync", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "Unknown error"]))
        }
    }

    func performFullSync() async throws -> SyncResult {
        let startTime = Date()
        var totalProcessed = 0
        var inserted = 0
        var updated = 0
        var deleted = 0
        // Create proper SyncError array (using the struct type from SquareSyncCoordinator)
        let errors: [SyncResultError] = []

        do {
            // Ensure we have a valid API client
            try await ensureValidAPIClient()

            // Initialize database
            try await databaseManager.initializeDatabase()

            // Clear existing catalog data for fresh sync (matching React Native behavior)
            try await databaseManager.clearCatalogData()

            // Start sync session
            let syncId = try await databaseManager.startSyncSession(type: "full")

            // Begin transaction
            try await databaseManager.beginTransaction()

            // Process catalog objects
            for try await progress in apiClient.performFullCatalogSync() {
                // Store object in database
                try await databaseManager.storeCatalogObject(progress.currentObject)
                totalProcessed += 1

                // Update counters based on object state
                if progress.currentObject.isDeleted == true {
                    deleted += 1
                } else {
                    // For now, count all as inserted (could be enhanced to detect updates)
                    inserted += 1
                }

                // Commit every 100 objects for performance
                if totalProcessed % 100 == 0 {
                    try await databaseManager.commitTransaction()
                    try await databaseManager.beginTransaction()
                }
            }

            // Final commit
            try await databaseManager.commitTransaction()

            // Complete sync session
            try await databaseManager.completeSyncSession(syncId: syncId)

            // Update last sync time
            await MainActor.run {
                lastSyncTime = Date()
                saveLastSyncTime()
            }

        } catch {
            // Note: errors array expects a different SyncError type, so we'll handle this differently

            // Rollback transaction if active
            try? await databaseManager.rollbackTransaction()

            throw error
        }

        let duration = Date().timeIntervalSince(startTime)

        return SyncResult(
            syncType: .full,
            duration: duration,
            totalProcessed: totalProcessed,
            inserted: inserted,
            updated: updated,
            deleted: deleted,
            errors: [] // Empty errors array for now - error handling can be enhanced later
        )
    }

    func isSyncNeeded() async -> Bool {
        // Check if sync is needed based on last sync time
        guard let lastSync = lastSyncTime else { return true }

        // Sync needed if more than 24 hours since last sync
        let hoursSinceLastSync = Date().timeIntervalSince(lastSync) / 3600
        return hoursSinceLastSync >= 24.0
    }
}

// MARK: - Sync Progress State

enum SyncProgressState {
    case idle
    case syncing(CatalogSyncService.SyncProgress, Double)
    case completed(SyncResult)
    case failed(Error)
}
