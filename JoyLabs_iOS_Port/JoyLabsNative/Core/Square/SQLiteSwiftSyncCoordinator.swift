import Foundation
import SwiftUI
import OSLog
import Combine

/// Modern sync coordinator using SQLite.swift
/// Replaces the broken raw SQLite3 implementation
@MainActor
class SQLiteSwiftSyncCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var syncState: SyncState = .idle
    @Published var lastSyncResult: SyncResult?
    // Removed syncProgress - using direct object count instead
    @Published var error: Error?
    // MARK: - Dependencies

    let catalogSyncService: SQLiteSwiftCatalogSyncService  // Made public for UI access
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftSyncCoordinator")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.catalogSyncService = SQLiteSwiftCatalogSyncService(squareAPIService: squareAPIService)
        
        setupObservers()
        loadLastSyncResult()
    }
    
    deinit {
        // No background timer to clean up
    }
    
    // MARK: - Setup

    private func loadLastSyncResult() {
        // Load last sync result from UserDefaults for persistence
        if let data = UserDefaults.standard.data(forKey: "lastSyncResult"),
           let result = try? JSONDecoder().decode(SyncResult.self, from: data) {

            // Validate cache against actual database contents
            Task {
                await validateSyncResultCache(result)
            }
        }
    }

    private func validateSyncResultCache(_ cachedResult: SyncResult) async {
        do {
            // RACE CONDITION FIX: Ensure database connection is established before accessing
            try catalogSyncService.sharedDatabaseManager.connect()
            
            // Get actual database counts
            let actualItemCount = try await catalogSyncService.sharedDatabaseManager.getItemCount()

            // Check if cached result matches reality
            if cachedResult.totalProcessed > 0 && actualItemCount == 0 {
                logger.warning("[SyncCoordinator] STALE CACHE DETECTED: Cached result shows \(cachedResult.totalProcessed) objects but database has 0 items")
                logger.info("[SyncCoordinator] Clearing stale sync result cache")

                // Clear the stale cache
                UserDefaults.standard.removeObject(forKey: "lastSyncResult")
                self.lastSyncResult = nil

            } else {
                // Cache appears valid
                self.lastSyncResult = cachedResult
                logger.info("[SyncCoordinator] Loaded previous sync result: \(cachedResult.totalProcessed) objects at \(cachedResult.timestamp)")
            }

        } catch {
            logger.error("[SyncCoordinator] Failed to validate sync cache: \(error)")
            // Keep the cached result if we can't validate
            self.lastSyncResult = cachedResult
            logger.info("[SyncCoordinator] Loaded previous sync result (unvalidated): \(cachedResult.totalProcessed) objects at \(cachedResult.timestamp)")
        }
    }

    private func saveLastSyncResult(_ result: SyncResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: "lastSyncResult")
            logger.debug("[SyncCoordinator] Saved sync result: \(result.totalProcessed) objects")
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
                // Force UI update by triggering objectWillChange
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods

    func cancelSync() {
        logger.info("[SyncCoordinator] Manual sync cancellation requested")
        catalogSyncService.cancelSync()
    }

    func performManualSync() async {
        logger.info("[SyncCoordinator] Manual sync triggered")

        guard syncState != .syncing else {
            logger.warning("[SyncCoordinator] Sync already in progress, ignoring manual trigger")
            return
        }

        syncState = .syncing

        // Run sync in detached task so it can't be interrupted by navigation
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                try await self.catalogSyncService.performSync(isManual: true)

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let syncEndTime = Date()
                    let syncDuration = syncEndTime.timeIntervalSince(self.catalogSyncService.syncProgress.startTime)
                    
                    let result = SyncResult(
                        syncType: .full,
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
                    self.logger.info("[SyncCoordinator] Manual sync completed: \(result.summary)")
                }

            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.logger.error("[SyncCoordinator] Manual sync failed: \(error)")
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

    /// Perform incremental sync - only fetches and processes changes since last sync
    func performIncrementalSync() async {
        logger.debug("[SyncCoordinator] Starting incremental sync")

        guard syncState != .syncing else {
            logger.warning("[SyncCoordinator] Sync already in progress, ignoring incremental trigger")
            return
        }

        syncState = .syncing

        // Run sync in detached task so it can't be interrupted by navigation
        Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                try await self.catalogSyncService.performIncrementalSync()

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let syncEndTime = Date()
                    let syncDuration = syncEndTime.timeIntervalSince(self.catalogSyncService.syncProgress.startTime)
                    
                    let result = SyncResult(
                        syncType: .incremental,
                        duration: syncDuration,
                        totalProcessed: self.catalogSyncService.syncProgress.syncedObjects,
                        itemsProcessed: self.catalogSyncService.syncProgress.syncedItems,
                        inserted: 0, // Keep as 0 - database uses upsert so can't distinguish easily
                        updated: self.catalogSyncService.syncProgress.syncedObjects,
                        deleted: 0,
                        errors: [],
                        timestamp: syncEndTime
                    )
                    
                    self.logger.info("[SyncCoordinator] 🎯 Setting lastSyncResult: \(result.summary)")
                    self.lastSyncResult = result
                    self.saveLastSyncResult(result)
                    self.syncState = .idle
                    self.logger.info("[SyncCoordinator] ✅ Incremental sync completed and result saved")
                }

            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.logger.error("[SyncCoordinator] ❌ Incremental sync failed: \(error)")
                    self.logger.warning("[SyncCoordinator] ⚠️ No lastSyncResult will be set due to sync failure")
                    self.error = error
                    self.syncState = .idle
                }
            }
        }
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
