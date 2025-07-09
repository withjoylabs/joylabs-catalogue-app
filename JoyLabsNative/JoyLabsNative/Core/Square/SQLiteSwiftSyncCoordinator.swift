import Foundation
import SwiftUI
import OSLog

/// Modern sync coordinator using SQLite.swift
/// Replaces the broken raw SQLite3 implementation
@MainActor
class SQLiteSwiftSyncCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var syncState: SyncState = .idle
    @Published var lastSyncResult: SyncResult?
    @Published var syncProgress: Double = 0.0
    @Published var error: Error?
    // MARK: - Dependencies

    let catalogSyncService: SQLiteSwiftCatalogSyncService  // Made public for UI access
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftSyncCoordinator")
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.catalogSyncService = SQLiteSwiftCatalogSyncService(squareAPIService: squareAPIService)
        
        setupObservers()
    }
    
    deinit {
        // No background timer to clean up
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe catalog sync service state
        catalogSyncService.$syncState
            .receive(on: DispatchQueue.main)
            .map { syncState in
                switch syncState {
                case .idle: return SyncState.idle
                case .syncing: return SyncState.syncing
                case .completed: return SyncState.completed
                case .failed: return SyncState.failed
                }
            }
            .assign(to: &$syncState)

        catalogSyncService.$errorMessage
            .receive(on: DispatchQueue.main)
            .map { $0.map { SyncCoordinatorError.syncFailed($0) } }
            .assign(to: &$error)

        catalogSyncService.$syncProgress
            .receive(on: DispatchQueue.main)
            .map { $0.progressPercentage }
            .assign(to: &$syncProgress)
    }
    
    // MARK: - Public Methods
    
    func performManualSync() async {
        logger.info("Manual sync triggered")
        
        guard syncState != .syncing else {
            logger.warning("Sync already in progress, ignoring manual trigger")
            return
        }
        
        do {
            try await catalogSyncService.performSync(isManual: true)
            
            let result = SyncResult(
                syncType: .full,
                duration: 0, // TODO: Track actual duration
                totalProcessed: catalogSyncService.syncProgress.totalObjects,
                inserted: catalogSyncService.syncProgress.syncedObjects,
                updated: 0,
                deleted: 0,
                errors: []
            )
            
            lastSyncResult = result
            logger.info("Manual sync completed: \(result.summary)")
            
        } catch {
            logger.error("Manual sync failed: \(error)")
            self.error = error
        }
    }
    
    // MARK: - Computed Properties for UI

    var syncProgressPercentage: Int {
        return Int(syncProgress * 100)
    }

    var syncStatusSummary: String {
        switch syncState {
        case .idle:
            return "Ready to sync"
        case .syncing:
            let progress = catalogSyncService.syncProgress
            if progress.totalObjects > 0 {
                return "\(progress.syncedObjects) / \(progress.totalObjects) objects"
            } else {
                return "\(progress.syncedObjects) objects processed"
            }
        case .completed:
            if let result = lastSyncResult {
                return "Completed: \(result.totalProcessed) objects"
            }
            return "Sync completed"
        case .failed:
            return "Sync failed"
        }
    }

    var timeSinceLastSync: String? {
        guard lastSyncResult != nil else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(), relativeTo: Date())
    }

    var canTriggerManualSync: Bool {
        return syncState != .syncing
    }

    // MARK: - Public Sync Methods

    func triggerSync() async {
        await performManualSync()
    }

    func forceFullSync() async {
        await performManualSync()
    }

    // Background sync methods removed - no automatic syncing
    
    // MARK: - Factory Method
    
    static func createCoordinator(squareAPIService: SquareAPIService) -> SQLiteSwiftSyncCoordinator {
        return SQLiteSwiftSyncCoordinator(squareAPIService: squareAPIService)
    }
}

// MARK: - Supporting Types

extension SQLiteSwiftSyncCoordinator {
    
    enum SyncState {
        case idle
        case syncing
        case completed
        case failed
        
        var isActive: Bool {
            return self == .syncing
        }

        var description: String {
            switch self {
            case .idle: return "Idle"
            case .syncing: return "Syncing"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }
}

// MARK: - Shared Types

enum SyncType: String, CaseIterable {
    case full = "full"
    case incremental = "incremental"
    case delta = "delta"
}

struct SyncResult {
    let syncType: SyncType
    let duration: TimeInterval
    let totalProcessed: Int
    let inserted: Int
    let updated: Int
    let deleted: Int
    let errors: [SyncError]
    
    var summary: String {
        return "Processed: \(totalProcessed), Inserted: \(inserted), Updated: \(updated), Deleted: \(deleted), Errors: \(errors.count)"
    }
}

struct SyncError: Error {
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

enum SyncCoordinatorError: Error {
    case syncFailed(String)
    case migrationFailed(String)
    case apiError(String)
}
