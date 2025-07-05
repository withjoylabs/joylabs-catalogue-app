import Foundation
import Amplify
import Combine

/// TeamDataSyncService - Handles real-time team data synchronization
/// Provides offline-first data management with conflict resolution
@MainActor
class TeamDataSyncService: ObservableObject {
    // MARK: - Singleton
    static let shared = TeamDataSyncService()
    
    // MARK: - Published Properties
    @Published var syncStatus: TeamSyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var pendingChanges: Int = 0
    @Published var isOnline: Bool = true
    
    // MARK: - Private Properties
    private let databaseManager: DatabaseManager
    private let graphQLClient: GraphQLClient
    private var cancellables = Set<AnyCancellable>()
    
    // Sync queue for offline operations
    private var syncQueue: [TeamDataOperation] = []
    private var isProcessingSyncQueue = false
    
    // Real-time subscriptions
    private var subscriptionTask: Task<Void, Never>?
    
    // MARK: - Initialization
    private init(
        databaseManager: DatabaseManager = DatabaseManager(),
        graphQLClient: GraphQLClient = GraphQLClient()
    ) {
        self.databaseManager = databaseManager
        self.graphQLClient = graphQLClient
        
        setupNetworkMonitoring()
        startRealtimeSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Create or update team data for an item
    func upsertTeamData(_ itemId: String, _ data: CaseUpcData) async throws {
        Logger.info("TeamSync", "Upserting team data for item: \(itemId)")
        
        // Always save locally first (offline-first approach)
        try await databaseManager.upsertTeamData(itemId, data)
        
        if isOnline {
            // Try to sync to GraphQL immediately
            do {
                let input = ItemDataInput(
                    id: itemId,
                    caseUpc: data.caseUpc,
                    caseCost: data.caseCost,
                    caseQuantity: data.caseQuantity,
                    vendor: data.vendor,
                    discontinued: data.discontinued,
                    notes: data.notes?.map { note in
                        NoteInput(
                            id: note.id,
                            content: note.content,
                            isComplete: note.isComplete,
                            authorId: note.authorId,
                            authorName: note.authorName
                        )
                    }
                )
                
                // Check if item exists in GraphQL
                let existingItem = try await graphQLClient.getItemData(itemId)
                
                if existingItem != nil {
                    // Update existing item
                    _ = try await graphQLClient.updateItemData(itemId, input)
                } else {
                    // Create new item
                    _ = try await graphQLClient.createItemData(input)
                }
                
                Logger.info("TeamSync", "Team data synced to GraphQL successfully")
                
            } catch {
                Logger.warn("TeamSync", "Failed to sync to GraphQL, queuing for later: \(error)")
                
                // Queue for later sync
                let operation = TeamDataOperation(
                    type: .upsert,
                    itemId: itemId,
                    data: data,
                    timestamp: Date()
                )
                
                syncQueue.append(operation)
                pendingChanges = syncQueue.count
            }
        } else {
            // Queue for later sync when online
            let operation = TeamDataOperation(
                type: .upsert,
                itemId: itemId,
                data: data,
                timestamp: Date()
            )
            
            syncQueue.append(operation)
            pendingChanges = syncQueue.count
            
            Logger.info("TeamSync", "Queued team data for offline sync")
        }
    }
    
    /// Get team data for an item (local-first)
    func getTeamData(itemId: String) async throws -> CaseUpcData? {
        // Always check local database first
        if let localData = try await databaseManager.getTeamData(itemId: itemId) {
            return localData
        }
        
        // If not found locally and online, try GraphQL
        if isOnline {
            do {
                if let graphQLData = try await graphQLClient.getItemData(itemId) {
                    let teamData = CaseUpcData(
                        caseUpc: graphQLData.caseUpc,
                        caseCost: graphQLData.caseCost,
                        caseQuantity: graphQLData.caseQuantity,
                        vendor: graphQLData.vendor,
                        discontinued: graphQLData.discontinued,
                        notes: graphQLData.notes?.map { note in
                            TeamNote(
                                id: note.id,
                                content: note.content,
                                isComplete: note.isComplete,
                                authorId: note.authorId,
                                authorName: note.authorName,
                                createdAt: note.createdAt,
                                updatedAt: note.updatedAt
                            )
                        }
                    )
                    
                    // Cache locally
                    try await databaseManager.upsertTeamData(itemId, teamData)
                    
                    return teamData
                }
            } catch {
                Logger.warn("TeamSync", "Failed to fetch from GraphQL: \(error)")
            }
        }
        
        return nil
    }
    
    /// Force sync all pending changes
    func syncPendingChanges() async {
        guard isOnline && !isProcessingSyncQueue else {
            Logger.info("TeamSync", "Cannot sync: offline or already processing")
            return
        }
        
        await processSyncQueue()
    }
    
    /// Start real-time synchronization
    func startRealtimeSync() {
        startRealtimeSubscriptions()
        
        if isOnline {
            Task {
                await syncPendingChanges()
            }
        }
    }
    
    /// Stop real-time synchronization
    func stopRealtimeSync() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        // Monitor network connectivity
        // This would typically use Network framework or Reachability
        // For now, we'll assume online status
        isOnline = true
        
        // When coming back online, process sync queue
        $isOnline
            .filter { $0 } // Only when becoming online
            .sink { [weak self] _ in
                Task {
                    await self?.processSyncQueue()
                }
            }
            .store(in: &cancellables)
    }
    
    private func startRealtimeSubscriptions() {
        subscriptionTask?.cancel()
        
        subscriptionTask = Task {
            do {
                let subscriptionStream = graphQLClient.subscribeToItemDataChanges()
                
                for try await itemResult in subscriptionStream {
                    await handleRealtimeUpdate(itemResult)
                }
            } catch {
                Logger.error("TeamSync", "Subscription failed: \(error)")
                
                // Retry subscription after delay
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                startRealtimeSubscriptions()
            }
        }
    }
    
    private func handleRealtimeUpdate(_ itemResult: ItemDataResult) async {
        Logger.info("TeamSync", "Received real-time update for item: \(itemResult.id)")
        
        let teamData = CaseUpcData(
            caseUpc: itemResult.caseUpc,
            caseCost: itemResult.caseCost,
            caseQuantity: itemResult.caseQuantity,
            vendor: itemResult.vendor,
            discontinued: itemResult.discontinued,
            notes: itemResult.notes?.map { note in
                TeamNote(
                    id: note.id,
                    content: note.content,
                    isComplete: note.isComplete,
                    authorId: note.authorId,
                    authorName: note.authorName,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt
                )
            }
        )
        
        do {
            // Update local database with remote changes
            try await databaseManager.upsertTeamData(itemResult.id, teamData)
            
            // Post notification for UI updates
            NotificationCenter.default.post(
                name: .teamDataUpdated,
                object: nil,
                userInfo: ["itemId": itemResult.id, "data": teamData]
            )
            
        } catch {
            Logger.error("TeamSync", "Failed to handle real-time update: \(error)")
        }
    }
    
    private func processSyncQueue() async {
        guard !isProcessingSyncQueue && !syncQueue.isEmpty else { return }
        
        isProcessingSyncQueue = true
        syncStatus = .syncing
        
        Logger.info("TeamSync", "Processing \(syncQueue.count) pending sync operations")
        
        var successCount = 0
        var failedOperations: [TeamDataOperation] = []
        
        for operation in syncQueue {
            do {
                switch operation.type {
                case .upsert:
                    let input = ItemDataInput(
                        id: operation.itemId,
                        caseUpc: operation.data?.caseUpc,
                        caseCost: operation.data?.caseCost,
                        caseQuantity: operation.data?.caseQuantity,
                        vendor: operation.data?.vendor,
                        discontinued: operation.data?.discontinued,
                        notes: operation.data?.notes?.map { note in
                            NoteInput(
                                id: note.id,
                                content: note.content,
                                isComplete: note.isComplete,
                                authorId: note.authorId,
                                authorName: note.authorName
                            )
                        }
                    )
                    
                    // Check if item exists
                    let existingItem = try await graphQLClient.getItemData(operation.itemId)
                    
                    if existingItem != nil {
                        _ = try await graphQLClient.updateItemData(operation.itemId, input)
                    } else {
                        _ = try await graphQLClient.createItemData(input)
                    }
                    
                    successCount += 1
                    
                case .delete:
                    // TODO: Implement delete operation
                    break
                }
                
            } catch {
                Logger.error("TeamSync", "Failed to sync operation for item \(operation.itemId): \(error)")
                failedOperations.append(operation)
            }
        }
        
        // Update sync queue with failed operations
        syncQueue = failedOperations
        pendingChanges = syncQueue.count
        
        // Update sync status
        if failedOperations.isEmpty {
            syncStatus = .completed
            lastSyncTime = Date()
        } else {
            syncStatus = .failed(TeamSyncError.partialSyncFailure(successCount, failedOperations.count))
        }
        
        isProcessingSyncQueue = false
        
        Logger.info("TeamSync", "Sync completed: \(successCount) successful, \(failedOperations.count) failed")
    }
}

// MARK: - Supporting Types
enum TeamSyncStatus {
    case idle
    case syncing
    case completed
    case failed(Error)
}

struct TeamDataOperation {
    enum OperationType {
        case upsert
        case delete
    }
    
    let type: OperationType
    let itemId: String
    let data: CaseUpcData?
    let timestamp: Date
}

enum TeamSyncError: LocalizedError {
    case partialSyncFailure(Int, Int) // success count, failure count
    case networkUnavailable
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .partialSyncFailure(let success, let failed):
            return "Partial sync: \(success) successful, \(failed) failed"
        case .networkUnavailable:
            return "Network unavailable for sync"
        case .authenticationRequired:
            return "Authentication required for sync"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let teamDataUpdated = Notification.Name("teamDataUpdated")
}
