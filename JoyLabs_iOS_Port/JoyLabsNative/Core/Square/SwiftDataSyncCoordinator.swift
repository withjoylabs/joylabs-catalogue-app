import Foundation
import SwiftUI
import SwiftData
import OSLog
import Combine

/// SwiftData-based sync coordinator
/// Replaces SQLiteSwiftSyncCoordinator with native SwiftData persistence
@MainActor
class SwiftDataSyncCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var syncState: SyncState = .idle
    @Published var lastSyncResult: SyncResult?
    @Published var error: Error?
    
    // MARK: - Dependencies
    
    let catalogSyncService: SwiftDataCatalogSyncService
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataSyncCoordinator")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.catalogSyncService = SwiftDataCatalogSyncService(squareAPIService: squareAPIService)
        
        setupObservers()
        loadLastSyncResult()
    }
    
    // MARK: - Setup
    
    private func loadLastSyncResult() {
        // Load last sync result from UserDefaults for persistence
        if let data = UserDefaults.standard.data(forKey: "swiftdata_lastSyncResult"),
           let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
            
            // Validate cache against actual database contents
            Task {
                await validateSyncResultCache(result)
            }
        }
    }
    
    private func validateSyncResultCache(_ cachedResult: SyncResult) async {
        do {
            // Get actual database counts from SwiftData
            let catalogManager = SquareAPIServiceFactory.createDatabaseManager()
            let actualItemCount = try await catalogManager.getItemCount()
            
            // Check if cached result matches reality
            if cachedResult.totalProcessed > 0 && actualItemCount == 0 {
                logger.warning("[SwiftDataSync] Stale cache detected: Cached shows \(cachedResult.totalProcessed) but database has 0")
                UserDefaults.standard.removeObject(forKey: "swiftdata_lastSyncResult")
                self.lastSyncResult = nil
            } else {
                self.lastSyncResult = cachedResult
                logger.info("[SwiftDataSync] Loaded previous sync: \(cachedResult.totalProcessed) objects")
            }
        } catch {
            logger.error("[SwiftDataSync] Failed to validate cache: \(error)")
            self.lastSyncResult = cachedResult
        }
    }
    
    private func saveLastSyncResult(_ result: SyncResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: "swiftdata_lastSyncResult")
            logger.debug("[SwiftDataSync] Saved sync result: \(result.totalProcessed) objects")
        }
    }
    
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
        
        // Forward sync progress changes to trigger UI updates
        catalogSyncService.$syncProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func cancelSync() {
        logger.info("[SwiftDataSync] Manual sync cancellation requested")
        catalogSyncService.cancelSync()
    }
    
    func performManualSync() async {
        logger.info("[SwiftDataSync] Manual sync triggered")
        
        guard syncState != .syncing else {
            logger.warning("[SwiftDataSync] Sync already in progress")
            return
        }
        
        syncState = .syncing
        
        // Run sync in detached task
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.catalogSyncService.performSync(isManual: true)
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let syncEndTime = Date()
                    let syncDuration = syncEndTime.timeIntervalSince(self.catalogSyncService.syncProgress.startTime)
                    
                    let result = SyncResult(
                        syncType: SyncType.full,
                        duration: syncDuration,
                        totalProcessed: self.catalogSyncService.syncProgress.syncedObjects,
                        itemsProcessed: self.catalogSyncService.syncProgress.syncedItems,
                        inserted: self.catalogSyncService.syncProgress.syncedObjects,
                        updated: 0,
                        deleted: 0,
                        errors: [],
                        timestamp: syncEndTime
                    )
                    
                    self.lastSyncResult = result
                    self.saveLastSyncResult(result)
                    self.syncState = .idle
                    self.logger.info("[SwiftDataSync] Manual sync completed: \(result.summary)")
                }
                
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.logger.error("[SwiftDataSync] Manual sync failed: \(error)")
                    
                    // Handle authentication failures
                    if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
                        self.logger.error("[SwiftDataSync] Authentication failed - clearing tokens")
                        
                        Task {
                            let tokenService = SquareAPIServiceFactory.createTokenService()
                            try? await tokenService.clearAuthData()
                            
                            let apiService = SquareAPIServiceFactory.createService()
                            apiService.setAuthenticated(false)
                            
                            await MainActor.run {
                                WebhookNotificationService.shared.addAuthenticationFailureNotification()
                                ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")
                            }
                        }
                    }
                    
                    self.error = error
                    self.syncState = .idle
                }
            }
        }
    }
    
    /// Perform incremental sync - only fetches changes since last sync
    func performIncrementalSync() async {
        logger.debug("[SwiftDataSync] Starting incremental sync")
        
        guard syncState != .syncing else {
            logger.warning("[SwiftDataSync] Sync already in progress")
            return
        }
        
        syncState = .syncing
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.catalogSyncService.performIncrementalSync()
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let syncEndTime = Date()
                    let syncDuration = syncEndTime.timeIntervalSince(self.catalogSyncService.syncProgress.startTime)
                    
                    let result = SyncResult(
                        syncType: SyncType.incremental,
                        duration: syncDuration,
                        totalProcessed: self.catalogSyncService.syncProgress.syncedObjects,
                        itemsProcessed: self.catalogSyncService.syncProgress.syncedItems,
                        inserted: 0,
                        updated: self.catalogSyncService.syncProgress.syncedObjects,
                        deleted: 0,
                        errors: [],
                        timestamp: syncEndTime
                    )
                    
                    self.logger.info("[SwiftDataSync] Setting lastSyncResult: \(result.summary)")
                    self.lastSyncResult = result
                    self.saveLastSyncResult(result)
                    self.syncState = .idle
                    self.logger.info("[SwiftDataSync] Incremental sync completed")
                }
                
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.logger.error("[SwiftDataSync] Incremental sync failed: \(error)")
                    
                    // Handle authentication failures
                    if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
                        self.logger.error("[SwiftDataSync] Authentication failed")
                        
                        Task {
                            let tokenService = SquareAPIServiceFactory.createTokenService()
                            try? await tokenService.clearAuthData()
                            
                            let apiService = SquareAPIServiceFactory.createService()
                            apiService.setAuthenticated(false)
                            
                            await MainActor.run {
                                WebhookNotificationService.shared.addAuthenticationFailureNotification()
                                ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")
                            }
                        }
                    }
                    
                    self.error = error
                    self.syncState = .idle
                }
            }
        }
    }
    
    // MARK: - Computed Properties for UI
    
    var syncedObjectsCount: Int {
        return catalogSyncService.syncProgress.syncedObjects
    }
    
    var syncStatusSummary: String {
        switch syncState {
        case .idle:
            return "Ready to sync"
        case .syncing:
            let progress = catalogSyncService.syncProgress
            return "\(progress.syncedObjects) objects synced"
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
        guard let result = lastSyncResult else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: result.timestamp, relativeTo: Date())
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
    
    // MARK: - Factory Method
    
    static func createCoordinator(squareAPIService: SquareAPIService) -> SwiftDataSyncCoordinator {
        return SwiftDataSyncCoordinator(squareAPIService: squareAPIService)
    }
}

// MARK: - Shared Types (for compatibility with existing code)

enum SyncType: String, CaseIterable, Codable {
    case full = "full"
    case incremental = "incremental"
    case delta = "delta"
}

struct SyncResult: Codable {
    let syncType: SyncType
    let duration: TimeInterval
    let totalProcessed: Int
    let itemsProcessed: Int  // Track items specifically
    let inserted: Int
    let updated: Int
    let deleted: Int
    let errors: [SyncError]
    let timestamp: Date

    var summary: String {
        return "Processed: \(itemsProcessed) items (\(totalProcessed) total objects), Inserted: \(inserted), Updated: \(updated), Deleted: \(deleted), Errors: \(errors.count)"
    }
}

struct SyncError: Error, Codable {
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

// MARK: - Supporting Types (Shared with SQLiteSwiftSyncCoordinator)

extension SwiftDataSyncCoordinator {
    
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