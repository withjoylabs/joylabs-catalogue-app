import Foundation
import OSLog

// MARK: - Sync Types (shared with CatalogSyncService)

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
    private let resilienceService: any ResilienceService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareSyncCoordinator")
    
    // MARK: - Background Sync

    private var backgroundSyncTimer: Timer?
    private var isBackgroundSyncEnabled = true
    private let backgroundSyncInterval: TimeInterval = 5 * 60 // 5 minutes

    // MARK: - Catchup Sync & Webhook Integration

    private var lastWebhookTimestamp: Date?
    private var catchupSyncInProgress = false
    private let catchupSyncThreshold: TimeInterval = 15 * 60 // 15 minutes
    private let maxCatchupRetries = 3
    
    // MARK: - Initialization

    init(catalogSyncService: CatalogSyncService, squareAPIService: SquareAPIService, resilienceService: any ResilienceService) {
        self.catalogSyncService = catalogSyncService
        self.squareAPIService = squareAPIService
        self.resilienceService = resilienceService

        logger.info("SquareSyncCoordinator initialized with resilience")

        // Start background sync if authenticated
        Task {
            await checkAuthenticationAndStartBackgroundSync()
        }
    }

    /// Factory method to create coordinator with proper dependencies
    static func createCoordinator(databaseManager: ResilientDatabaseManager, squareAPIService: SquareAPIService) -> SquareSyncCoordinator {
        let resilienceService = ErrorRecoveryManager()

        let catalogSyncService = CatalogSyncService(
            squareAPIService: squareAPIService
        )

        return SquareSyncCoordinator(
            catalogSyncService: catalogSyncService,
            squareAPIService: squareAPIService,
            resilienceService: resilienceService
        )
    }
    
    deinit {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
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
        guard squareAPIService.isAuthenticated else {
            return false
        }

        return await catalogSyncService.isSyncNeeded()
    }

    /// Perform catchup sync for missed updates
    func performCatchupSync(since timestamp: Date? = nil) async {
        logger.info("Catchup sync triggered")

        guard !catchupSyncInProgress else {
            logger.warning("Catchup sync already in progress")
            return
        }

        guard syncState != .syncing else {
            logger.warning("Regular sync in progress, deferring catchup sync")
            return
        }

        catchupSyncInProgress = true
        defer { catchupSyncInProgress = false }

        let catchupTimestamp = timestamp ?? lastWebhookTimestamp ?? Date().addingTimeInterval(-catchupSyncThreshold)

        logger.info("Performing catchup sync since: \(catchupTimestamp)")

        do {
            let result = try await performCatchupSyncInternal(since: catchupTimestamp)
            await handleCatchupSyncSuccess(result)
        } catch {
            await handleCatchupSyncError(error)
        }
    }

    /// Process webhook notification
    func processWebhookNotification(timestamp: Date, eventType: WebhookEventType) async {
        logger.info("Processing webhook notification: \(eventType.rawValue) at \(timestamp)")

        // Update last webhook timestamp
        lastWebhookTimestamp = timestamp

        // Determine if immediate sync is needed based on event type
        let needsImmediateSync = shouldTriggerImmediateSync(for: eventType)

        if needsImmediateSync {
            logger.info("Webhook event requires immediate sync")
            await performCatchupSync(since: timestamp.addingTimeInterval(-60)) // 1 minute buffer
        } else {
            logger.debug("Webhook event will be handled in next scheduled sync")
        }
    }

    /// Check for missed webhook updates and trigger catchup if needed
    func checkForMissedUpdates() async {
        guard let lastWebhook = lastWebhookTimestamp else {
            logger.debug("No webhook timestamp available, skipping missed update check")
            return
        }

        let timeSinceLastWebhook = Date().timeIntervalSince(lastWebhook)

        if timeSinceLastWebhook > catchupSyncThreshold {
            logger.warning("Potential missed updates detected (last webhook: \(timeSinceLastWebhook)s ago)")
            await performCatchupSync(since: lastWebhook)
        }
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
        logger.debug("Performing sync with resilience - manual: \(isManual)")

        // Check authentication
        guard squareAPIService.isAuthenticated else {
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
            let result = try await resilienceService.executeResilient(
                operationId: "sync_coordinator_operation",
                operation: {
                    return try await self.catalogSyncService.performSync()
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

            progressTask.cancel()
            await handleSyncSuccess(result, isManual: isManual)
        } catch {
            progressTask.cancel()
            await handleSyncError(error, isManual: isManual)
        }
    }

    /// Get fallback sync result when main sync fails
    private func getFallbackSyncResult() async -> SyncResult {
        logger.info("Using fallback sync result")
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
    
    private func performBackgroundSync() async {
        logger.debug("Performing background sync check")

        guard syncState == .idle else {
            logger.debug("Skipping background sync - not idle")
            return
        }

        // Check for missed webhook updates first
        await checkForMissedUpdates()

        // Then perform regular sync
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
        let isAuthenticated = squareAPIService.isAuthenticated

        if isAuthenticated && isBackgroundSyncEnabled {
            startBackgroundSync()
        }
    }

    // MARK: - Catchup Sync Implementation

    private func performCatchupSyncInternal(since timestamp: Date) async throws -> SyncResult {
        logger.debug("Performing internal catchup sync since: \(timestamp)")

        // Use incremental sync with specific timestamp
        let result = try await catalogSyncService.performIncrementalSync()

        // Additional catchup-specific processing could be added here
        // For example, checking for specific object types that need special handling

        return result
    }

    private func handleCatchupSyncSuccess(_ result: SyncResult) async {
        logger.info("Catchup sync completed successfully: \(result.summary)")

        // Update last sync result if it's more recent
        if lastSyncResult == nil || result.totalProcessed > 0 {
            lastSyncResult = result
        }

        // Don't change the main sync state for catchup syncs
        logger.debug("Catchup sync handled without affecting main sync state")
    }

    private func handleCatchupSyncError(_ error: Error) async {
        logger.error("Catchup sync failed: \(error.localizedDescription)")

        // For catchup sync errors, we don't want to affect the main UI state
        // Just log the error and potentially schedule a retry
        logger.warning("Catchup sync error will be retried in next background sync")
    }

    private func shouldTriggerImmediateSync(for eventType: WebhookEventType) -> Bool {
        switch eventType {
        case .catalogUpdated, .catalogDeleted:
            return true
        case .inventoryUpdated:
            return true
        case .locationUpdated:
            return false // Less critical, can wait for scheduled sync
        case .unknown:
            return false
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
    case catchupSyncFailed
    case webhookProcessingFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Cannot sync - not authenticated with Square"
        case .syncInProgress:
            return "Sync operation already in progress"
        case .configurationError:
            return "Sync configuration error"
        case .catchupSyncFailed:
            return "Catchup sync failed to complete"
        case .webhookProcessingFailed:
            return "Failed to process webhook notification"
        }
    }
}

// MARK: - Webhook Event Types

enum WebhookEventType: String, CaseIterable {
    case catalogUpdated = "catalog.version.updated"
    case catalogDeleted = "catalog.version.deleted"
    case inventoryUpdated = "inventory.count.updated"
    case locationUpdated = "location.updated"
    case unknown = "unknown"

    var description: String {
        switch self {
        case .catalogUpdated:
            return "Catalog Updated"
        case .catalogDeleted:
            return "Catalog Deleted"
        case .inventoryUpdated:
            return "Inventory Updated"
        case .locationUpdated:
            return "Location Updated"
        case .unknown:
            return "Unknown Event"
        }
    }

    var priority: WebhookPriority {
        switch self {
        case .catalogUpdated, .catalogDeleted:
            return .high
        case .inventoryUpdated:
            return .medium
        case .locationUpdated:
            return .low
        case .unknown:
            return .low
        }
    }
}

enum WebhookPriority: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    var description: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
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
    let catchupSyncs: Int
    let webhookNotifications: Int
    let lastWebhookDate: Date?

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

    var webhookEfficiency: String {
        guard webhookNotifications > 0 else { return "N/A" }
        let ratio = Double(catchupSyncs) / Double(webhookNotifications)
        return String(format: "%.1f%%", ratio * 100)
    }
}

// MARK: - Webhook Notification

struct WebhookNotification {
    let id: String
    let eventType: WebhookEventType
    let timestamp: Date
    let merchantId: String?
    let locationId: String?
    let entityId: String?
    let processed: Bool

    init(eventType: WebhookEventType, timestamp: Date = Date(), merchantId: String? = nil, locationId: String? = nil, entityId: String? = nil) {
        self.id = UUID().uuidString
        self.eventType = eventType
        self.timestamp = timestamp
        self.merchantId = merchantId
        self.locationId = locationId
        self.entityId = entityId
        self.processed = false
    }
}

// MARK: - Sync Coordinator Factory

struct SquareSyncCoordinatorFactory {

    @MainActor
    static func createCoordinator(
        databaseManager: ResilientDatabaseManager,
        squareAPIService: SquareAPIService
    ) -> SquareSyncCoordinator {
        let resilienceService = BasicResilienceService()

        let catalogSyncService = CatalogSyncService(
            squareAPIService: squareAPIService
        )

        return SquareSyncCoordinator(
            catalogSyncService: catalogSyncService,
            squareAPIService: squareAPIService,
            resilienceService: resilienceService
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
        guard lastSyncResult != nil else { return nil }

        // This would need to be implemented with actual timestamp tracking
        return "Recently"
    }

    /// Get catchup sync status
    var catchupSyncStatus: String {
        if catchupSyncInProgress {
            return "Catchup sync in progress..."
        } else if let lastWebhook = lastWebhookTimestamp {
            let timeSinceWebhook = Date().timeIntervalSince(lastWebhook)
            if timeSinceWebhook > catchupSyncThreshold {
                return "Catchup sync needed"
            } else {
                return "Up to date with webhooks"
            }
        } else {
            return "No webhook data"
        }
    }

    /// Check if catchup sync is available
    var canTriggerCatchupSync: Bool {
        return !catchupSyncInProgress && syncState != .syncing && lastWebhookTimestamp != nil
    }

    /// Get webhook integration status
    var webhookIntegrationStatus: String {
        if let lastWebhook = lastWebhookTimestamp {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last webhook: \(formatter.localizedString(for: lastWebhook, relativeTo: Date()))"
        } else {
            return "No webhooks received"
        }
    }

}
