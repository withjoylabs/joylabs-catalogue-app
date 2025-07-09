import Foundation
import Network
import Combine

/// OfflineDataManager - Handles offline data management and sync queue
/// Provides robust offline-first data management with conflict resolution
@MainActor
class OfflineDataManager: ObservableObject {
    // MARK: - Singleton
    static let shared = OfflineDataManager()
    
    // MARK: - Published Properties
    @Published var isOnline: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    @Published var syncQueueCount: Int = 0
    @Published var lastSyncAttempt: Date?
    @Published var syncErrors: [SyncError] = []
    
    // MARK: - Private Properties
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()
    
    // Sync management
    private let syncInterval: TimeInterval = 30.0 // 30 seconds
    private var syncTimer: Timer?
    private var isProcessingSync = false
    
    // Data persistence
    private let userDefaults = UserDefaults.standard
    private let syncQueueKey = "offline_sync_queue"
    private let lastSyncKey = "last_sync_timestamp"
    
    // MARK: - Initialization
    private init() {
        setupNetworkMonitoring()
        loadSyncQueue()
        setupPeriodicSync()
    }
    
    deinit {
        networkMonitor.cancel()
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Queue an operation for offline sync
    func queueOperation(_ operation: OfflineOperation) {
        Logger.info("OfflineData", "Queuing operation: \(operation.type) for \(operation.entityType)")
        
        var queue = loadSyncQueueFromStorage()
        queue.append(operation)
        saveSyncQueueToStorage(queue)
        
        syncQueueCount = queue.count
        
        // Try immediate sync if online
        if isOnline {
            Task {
                await processSyncQueue()
            }
        }
    }
    
    /// Process all queued operations
    func processSyncQueue() async {
        guard isOnline && !isProcessingSync else {
            Logger.info("OfflineData", "Cannot process sync queue: offline or already processing")
            return
        }
        
        isProcessingSync = true
        lastSyncAttempt = Date()
        
        var queue = loadSyncQueueFromStorage()
        guard !queue.isEmpty else {
            isProcessingSync = false
            return
        }
        
        Logger.info("OfflineData", "Processing \(queue.count) queued operations")
        
        var processedOperations: [OfflineOperation] = []
        var failedOperations: [OfflineOperation] = []
        
        for operation in queue {
            do {
                try await processOperation(operation)
                processedOperations.append(operation)
                
                Logger.debug("OfflineData", "Successfully processed operation: \(operation.id)")
                
            } catch {
                Logger.error("OfflineData", "Failed to process operation \(operation.id): \(error)")
                
                // Check if operation should be retried
                if operation.retryCount < operation.maxRetries {
                    var retryOperation = operation
                    retryOperation.retryCount += 1
                    retryOperation.lastAttempt = Date()
                    failedOperations.append(retryOperation)
                } else {
                    // Max retries reached, add to error list
                    let syncError = SyncError(
                        operationId: operation.id,
                        error: error,
                        timestamp: Date()
                    )
                    syncErrors.append(syncError)
                    
                    // Keep only last 50 errors
                    if syncErrors.count > 50 {
                        syncErrors = Array(syncErrors.suffix(50))
                    }
                }
            }
        }
        
        // Update queue with failed operations
        saveSyncQueueToStorage(failedOperations)
        syncQueueCount = failedOperations.count
        
        // Update last sync time if any operations were processed
        if !processedOperations.isEmpty {
            userDefaults.set(Date(), forKey: lastSyncKey)
        }
        
        isProcessingSync = false
        
        Logger.info("OfflineData", "Sync completed: \(processedOperations.count) successful, \(failedOperations.count) failed")
    }
    
    /// Clear all queued operations
    func clearSyncQueue() {
        saveSyncQueueToStorage([])
        syncQueueCount = 0
        Logger.info("OfflineData", "Sync queue cleared")
    }
    
    /// Clear sync errors
    func clearSyncErrors() {
        syncErrors = []
        Logger.info("OfflineData", "Sync errors cleared")
    }
    
    /// Get offline status summary
    func getOfflineStatus() -> OfflineStatus {
        return OfflineStatus(
            isOnline: isOnline,
            connectionType: connectionType,
            queuedOperations: syncQueueCount,
            lastSyncAttempt: lastSyncAttempt,
            errorCount: syncErrors.count
        )
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path)
            }
        }
        
        networkMonitor.start(queue: monitorQueue)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        let wasOnline = isOnline
        isOnline = path.status == .satisfied
        
        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
        
        Logger.info("OfflineData", "Network status: \(isOnline ? "online" : "offline") (\(connectionType))")
        
        // If we just came online, process sync queue
        if isOnline && !wasOnline {
            Logger.info("OfflineData", "Network restored, processing sync queue")
            Task {
                await processSyncQueue()
            }
        }
    }
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isOnline else { return }
            
            Task {
                await self.processSyncQueue()
            }
        }
    }
    
    private func processOperation(_ operation: OfflineOperation) async throws {
        switch operation.entityType {
        case .teamData:
            try await processTeamDataOperation(operation)
        case .catalogItem:
            try await processCatalogItemOperation(operation)
        case .userPreferences:
            try await processUserPreferencesOperation(operation)
        }
    }
    
    private func processTeamDataOperation(_ operation: OfflineOperation) async throws {
        let teamSyncService = TeamDataSyncService.shared
        
        switch operation.type {
        case .create, .update:
            guard let data = operation.data as? CaseUpcData else {
                throw OfflineError.invalidOperationData
            }
            
            try await teamSyncService.upsertTeamData(operation.entityId, data)
            
        case .delete:
            // TODO: Implement team data deletion
            throw OfflineError.operationNotSupported
        }
    }
    
    private func processCatalogItemOperation(_ operation: OfflineOperation) async throws {
        // TODO: Implement catalog item sync operations
        throw OfflineError.operationNotSupported
    }
    
    private func processUserPreferencesOperation(_ operation: OfflineOperation) async throws {
        // TODO: Implement user preferences sync operations
        throw OfflineError.operationNotSupported
    }
    
    private func loadSyncQueue() {
        let queue = loadSyncQueueFromStorage()
        syncQueueCount = queue.count
        
        if let lastSync = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncAttempt = lastSync
        }
    }
    
    private func loadSyncQueueFromStorage() -> [OfflineOperation] {
        guard let data = userDefaults.data(forKey: syncQueueKey),
              let queue = try? JSONDecoder().decode([OfflineOperation].self, from: data) else {
            return []
        }
        return queue
    }
    
    private func saveSyncQueueToStorage(_ queue: [OfflineOperation]) {
        do {
            let data = try JSONEncoder().encode(queue)
            userDefaults.set(data, forKey: syncQueueKey)
        } catch {
            Logger.error("OfflineData", "Failed to save sync queue: \(error)")
        }
    }
}

// MARK: - Supporting Types
enum ConnectionType: String, CaseIterable {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case unknown = "Unknown"
}

struct OfflineOperation: Codable, Identifiable {
    let id: UUID
    let type: OperationType
    let entityType: EntityType
    let entityId: String
    let data: Data?
    let timestamp: Date
    var retryCount: Int
    let maxRetries: Int
    var lastAttempt: Date?
    
    enum OperationType: String, Codable {
        case create
        case update
        case delete
    }
    
    enum EntityType: String, Codable {
        case teamData
        case catalogItem
        case userPreferences
    }
    
    init(
        type: OperationType,
        entityType: EntityType,
        entityId: String,
        data: Codable? = nil,
        maxRetries: Int = 3
    ) {
        self.id = UUID()
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.timestamp = Date()
        self.retryCount = 0
        self.maxRetries = maxRetries
        
        // Encode data if provided
        if let data = data {
            self.data = try? JSONEncoder().encode(data)
        } else {
            self.data = nil
        }
    }
}

struct SyncError: Identifiable {
    let id = UUID()
    let operationId: UUID
    let error: Error
    let timestamp: Date
    
    var localizedDescription: String {
        error.localizedDescription
    }
}

struct OfflineStatus {
    let isOnline: Bool
    let connectionType: ConnectionType
    let queuedOperations: Int
    let lastSyncAttempt: Date?
    let errorCount: Int
}

enum OfflineError: LocalizedError {
    case invalidOperationData
    case operationNotSupported
    case networkUnavailable
    case syncInProgress
    
    var errorDescription: String? {
        switch self {
        case .invalidOperationData:
            return "Invalid operation data"
        case .operationNotSupported:
            return "Operation not supported"
        case .networkUnavailable:
            return "Network unavailable"
        case .syncInProgress:
            return "Sync already in progress"
        }
    }
}
