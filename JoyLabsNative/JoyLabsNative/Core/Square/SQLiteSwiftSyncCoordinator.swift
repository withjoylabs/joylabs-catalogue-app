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
    @Published var isBackgroundSyncEnabled: Bool = false  // Disabled to prevent infinite loops
    
    // MARK: - Dependencies
    
    private let catalogSyncService: SQLiteSwiftCatalogSyncService
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftSyncCoordinator")
    
    // MARK: - Background Sync
    
    private var backgroundSyncTimer: Timer?
    private let backgroundSyncInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.catalogSyncService = SQLiteSwiftCatalogSyncService(squareAPIService: squareAPIService)
        
        setupObservers()
        // Don't start background sync timer automatically to prevent infinite loops
        // startBackgroundSyncTimer()
    }
    
    deinit {
        backgroundSyncTimer?.invalidate()
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
    
    func performBackgroundSync() async {
        logger.info("Background sync triggered")
        
        guard syncState != .syncing else {
            logger.info("Sync already in progress, skipping background sync")
            return
        }
        
        guard isBackgroundSyncEnabled else {
            logger.info("Background sync disabled, skipping")
            return
        }
        
        do {
            try await catalogSyncService.performSync(isManual: false)
            logger.info("Background sync completed successfully")
        } catch {
            logger.error("Background sync failed: \(error)")
            // Don't update UI error for background sync failures
        }
    }
    
    func toggleBackgroundSync() {
        isBackgroundSyncEnabled.toggle()
        
        if isBackgroundSyncEnabled {
            startBackgroundSyncTimer()
            logger.info("Background sync enabled")
        } else {
            stopBackgroundSyncTimer()
            logger.info("Background sync disabled")
        }
    }
    
    // MARK: - Background Timer
    
    private func startBackgroundSyncTimer() {
        guard isBackgroundSyncEnabled else { return }
        
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: backgroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackgroundSync()
            }
        }
        
        logger.info("Starting background sync timer")
    }
    
    private func stopBackgroundSyncTimer() {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
        logger.info("Background sync timer stopped")
    }
    
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
