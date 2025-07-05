import Foundation
import OSLog

/// Coordinates Square API synchronization with background scheduling and conflict resolution
/// Manages sync timing, error recovery, and user notifications
@MainActor
class SquareSyncCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var syncState: SyncState = .idle
    @Published var lastSyncResult: SyncResult?
    @Published var syncProgress: Double = 0.0
    @Published var error: Error?
    
    // MARK: - Dependencies
    
    private let catalogSyncService: CatalogSyncService
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareSyncCoordinator")
    
    // MARK: - Background Sync
    
    private var backgroundSyncTimer: Timer?
    private var isBackgroundSyncEnabled = true
    private let backgroundSyncInterval: TimeInterval = 5 * 60 // 5 minutes
    
    // MARK: - Initialization
    
    init(catalogSyncService: CatalogSyncService, squareAPIService: SquareAPIService) {
        self.catalogSyncService = catalogSyncService
        self.squareAPIService = squareAPIService
        
        logger.info("SquareSyncCoordinator initialized")
        
        // Start background sync if authenticated
        Task {
            await checkAuthenticationAndStartBackgroundSync()
        }
    }
    
    deinit {
        stopBackgroundSync()
    }
    
    // MARK: - Public Sync Methods
    
    /// Trigger manual sync
    func triggerSync() async {
        logger.info("Manual sync triggered")
        
        guard syncState != .syncing else {
            logger.warning("Sync already in progress")
            return
        }
        
        await performSync(isManual: true)
    }
    
    /// Force full sync
    func forceFullSync() async {
        logger.info("Force full sync triggered")
        
        guard syncState != .syncing else {
            logger.warning("Sync already in progress")
            return
        }
        
        syncState = .syncing
        error = nil
        
        do {
            let result = try await catalogSyncService.performFullSync()
            await handleSyncSuccess(result, isManual: true)
        } catch {
            await handleSyncError(error, isManual: true)
        }
    }
    
    /// Check if sync is needed
    func checkSyncNeeded() async -> Bool {
        guard await squareAPIService.isAuthenticated else {
            return false
        }
        
        return await catalogSyncService.isSyncNeeded()
    }
    
    /// Start background sync
    func startBackgroundSync() {
        guard isBackgroundSyncEnabled else { return }
        
        logger.info("Starting background sync timer")
        
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: backgroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackgroundSync()
            }
        }
    }
    
    /// Stop background sync
    func stopBackgroundSync() {
        logger.info("Stopping background sync timer")
        
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
    }
    
    /// Enable/disable background sync
    func setBackgroundSyncEnabled(_ enabled: Bool) {
        isBackgroundSyncEnabled = enabled
        
        if enabled {
            startBackgroundSync()
        } else {
            stopBackgroundSync()
        }
        
        logger.info("Background sync \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Private Implementation
    
    private func performSync(isManual: Bool) async {
        logger.debug("Performing sync - manual: \(isManual)")
        
        // Check authentication
        guard await squareAPIService.isAuthenticated else {
            logger.warning("Cannot sync - not authenticated")
            if isManual {
                error = SyncCoordinatorError.notAuthenticated
            }
            return
        }
        
        // Check if sync is needed (skip for manual sync)
        if !isManual {
            let syncNeeded = await catalogSyncService.isSyncNeeded()
            if !syncNeeded {
                logger.debug("Sync not needed, skipping")
                return
            }
        }
        
        syncState = .syncing
        error = nil
        
        // Monitor sync progress
        let progressTask = Task {
            await monitorSyncProgress()
        }
        
        do {
            let result = try await catalogSyncService.performSync()
            progressTask.cancel()
            await handleSyncSuccess(result, isManual: isManual)
        } catch {
            progressTask.cancel()
            await handleSyncError(error, isManual: isManual)
        }
    }
    
    private func performBackgroundSync() async {
        logger.debug("Performing background sync check")
        
        guard syncState == .idle else {
            logger.debug("Skipping background sync - not idle")
            return
        }
        
        await performSync(isManual: false)
    }
    
    private func monitorSyncProgress() async {
        while syncState == .syncing {
            let progress = await catalogSyncService.getSyncProgress()
            
            switch progress {
            case .syncing(_, let progressValue):
                syncProgress = progressValue
            case .completed(let result):
                lastSyncResult = result
                syncState = .completed
                return
            case .failed(let error):
                self.error = error
                syncState = .failed
                return
            default:
                break
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    private func handleSyncSuccess(_ result: SyncResult, isManual: Bool) async {
        logger.info("Sync completed successfully: \(result.summary)")
        
        lastSyncResult = result
        syncState = .completed
        syncProgress = 1.0
        error = nil
        
        // Reset to idle after a delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        if syncState == .completed {
            syncState = .idle
            syncProgress = 0.0
        }
    }
    
    private func handleSyncError(_ syncError: Error, isManual: Bool) async {
        logger.error("Sync failed: \(syncError.localizedDescription)")
        
        error = syncError
        syncState = .failed
        syncProgress = 0.0
        
        // Reset to idle after a delay for background sync
        if !isManual {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if syncState == .failed {
                syncState = .idle
                error = nil
            }
        }
    }
    
    private func checkAuthenticationAndStartBackgroundSync() async {
        let isAuthenticated = await squareAPIService.isAuthenticated
        
        if isAuthenticated && isBackgroundSyncEnabled {
            startBackgroundSync()
        }
    }
}

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case completed
    case failed
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    var isActive: Bool {
        return self == .syncing
    }
}

// MARK: - Sync Coordinator Errors

enum SyncCoordinatorError: LocalizedError {
    case notAuthenticated
    case syncInProgress
    case configurationError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Cannot sync - not authenticated with Square"
        case .syncInProgress:
            return "Sync operation already in progress"
        case .configurationError:
            return "Sync configuration error"
        }
    }
}

// MARK: - Sync Statistics

struct SyncStatistics {
    let totalSyncs: Int
    let successfulSyncs: Int
    let failedSyncs: Int
    let lastSyncDate: Date?
    let averageSyncDuration: TimeInterval
    let totalItemsSynced: Int
    
    var successRate: Double {
        guard totalSyncs > 0 else { return 0.0 }
        return Double(successfulSyncs) / Double(totalSyncs)
    }
    
    var formattedSuccessRate: String {
        return String(format: "%.1f%%", successRate * 100)
    }
    
    var formattedAverageDuration: String {
        return String(format: "%.1fs", averageSyncDuration)
    }
}

// MARK: - Sync Coordinator Factory

struct SquareSyncCoordinatorFactory {
    
    static func createCoordinator(
        databaseManager: ResilientDatabaseManager,
        squareAPIService: SquareAPIService
    ) -> SquareSyncCoordinator {
        let catalogSyncService = CatalogSyncService(
            squareAPIService: squareAPIService,
            databaseManager: databaseManager
        )
        
        return SquareSyncCoordinator(
            catalogSyncService: catalogSyncService,
            squareAPIService: squareAPIService
        )
    }
}

// MARK: - Sync Coordinator Extensions

extension SquareSyncCoordinator {
    
    /// Get sync status summary
    var syncStatusSummary: String {
        switch syncState {
        case .idle:
            if let lastResult = lastSyncResult {
                return "Last sync: \(lastResult.syncType.rawValue) - \(lastResult.summary)"
            } else {
                return "Ready to sync"
            }
        case .syncing:
            let progressPercent = Int(syncProgress * 100)
            return "Syncing... \(progressPercent)%"
        case .completed:
            return "Sync completed successfully"
        case .failed:
            return "Sync failed: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
    
    /// Check if manual sync is available
    var canTriggerManualSync: Bool {
        return syncState == .idle || syncState == .failed
    }
    
    /// Get sync progress percentage
    var syncProgressPercentage: Int {
        return Int(syncProgress * 100)
    }
    
    /// Get time since last sync
    var timeSinceLastSync: String? {
        guard let lastResult = lastSyncResult else { return nil }
        
        // This would need to be implemented with actual timestamp tracking
        return "Recently"
    }
}
