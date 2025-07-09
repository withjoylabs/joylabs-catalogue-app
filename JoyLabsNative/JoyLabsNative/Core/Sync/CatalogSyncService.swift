import Foundation
import SQLite3

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
    
    private let apiClient: SquareCatalogAPIClient
    private let databaseManager: CatalogDatabaseManager
    private let squareAPIService: SquareAPIService
    
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
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.apiClient = SquareCatalogAPIClient(accessToken: squareAPIService.accessToken ?? "")
        self.databaseManager = CatalogDatabaseManager()
        
        // Load last sync time
        loadLastSyncTime()
    }
    
    // MARK: - Public Sync Methods
    
    /// Perform full catalog sync - downloads entire catalog
    func performFullSync() async {
        guard syncState != .syncing else { return }
        
        await MainActor.run {
            syncState = .syncing
            syncProgress = SyncProgress()
            errorMessage = nil
        }
        
        do {
            // Initialize database if needed
            try await databaseManager.initializeDatabase()
            
            // Record sync start
            let syncId = try await databaseManager.startSyncSession(type: "full")
            
            var syncStartTime = Date()
            var processedObjects = 0
            
            // Process catalog objects
            for try await progress in apiClient.performFullCatalogSync() {
                // Update progress
                await MainActor.run {
                    syncProgress.totalObjects = progress.totalObjects
                    syncProgress.syncedObjects = progress.syncedObjects
                    syncProgress.currentObjectType = progress.currentObject.type
                    syncProgress.currentObjectName = extractObjectName(from: progress.currentObject)
                    syncProgress.progressPercentage = progress.progressPercentage
                    
                    // Calculate estimated time remaining
                    let elapsed = Date().timeIntervalSince(syncStartTime)
                    if progress.syncedObjects > 0 {
                        let avgTimePerObject = elapsed / Double(progress.syncedObjects)
                        let remainingObjects = progress.totalObjects - progress.syncedObjects
                        syncProgress.estimatedTimeRemaining = avgTimePerObject * Double(remainingObjects)
                    }
                }
                
                // Store object in database
                try await databaseManager.storeCatalogObject(progress.currentObject)
                processedObjects += 1
                
                // Batch commit every 100 objects for performance
                if processedObjects % 100 == 0 {
                    try await databaseManager.commitTransaction()
                    try await databaseManager.beginTransaction()
                }
            }
            
            // Complete sync
            try await databaseManager.completeSyncSession(syncId: syncId)
            
            await MainActor.run {
                syncState = .completed
                lastSyncTime = Date()
                saveLastSyncTime()
            }
            
        } catch {
            await MainActor.run {
                syncState = .failed
                errorMessage = error.localizedDescription
            }
            
            print("Full sync failed: \(error)")
        }
    }
    
    /// Perform incremental sync - only sync changes since last sync
    func performIncrementalSync() async {
        guard syncState != .syncing else { return }
        guard let lastSync = lastSyncTime else {
            // No previous sync, perform full sync
            await performFullSync()
            return
        }
        
        await MainActor.run {
            syncState = .syncing
            syncProgress = SyncProgress()
            errorMessage = nil
        }
        
        do {
            // Format last sync time for Square API
            let formatter = ISO8601DateFormatter()
            let beginTime = formatter.string(from: lastSync)
            
            // Record sync start
            let syncId = try await databaseManager.startSyncSession(type: "incremental")
            
            var syncStartTime = Date()
            var processedObjects = 0
            
            // Process changed objects since last sync
            for try await progress in apiClient.performIncrementalCatalogSync(since: beginTime) {
                // Update progress
                await MainActor.run {
                    syncProgress.totalObjects = progress.totalObjects
                    syncProgress.syncedObjects = progress.syncedObjects
                    syncProgress.currentObjectType = progress.currentObject.type
                    syncProgress.currentObjectName = extractObjectName(from: progress.currentObject)
                    syncProgress.progressPercentage = progress.progressPercentage
                    
                    // Calculate estimated time remaining
                    let elapsed = Date().timeIntervalSince(syncStartTime)
                    if progress.syncedObjects > 0 {
                        let avgTimePerObject = elapsed / Double(progress.syncedObjects)
                        let remainingObjects = progress.totalObjects - progress.syncedObjects
                        syncProgress.estimatedTimeRemaining = avgTimePerObject * Double(remainingObjects)
                    }
                }
                
                // Store or update object in database
                if progress.currentObject.isDeleted == true {
                    try await databaseManager.deleteCatalogObject(progress.currentObject.id)
                } else {
                    try await databaseManager.storeCatalogObject(progress.currentObject)
                }
                
                processedObjects += 1
                
                // Batch commit every 50 objects for incremental sync
                if processedObjects % 50 == 0 {
                    try await databaseManager.commitTransaction()
                    try await databaseManager.beginTransaction()
                }
            }
            
            // Complete sync
            try await databaseManager.completeSyncSession(syncId: syncId)
            
            await MainActor.run {
                syncState = .completed
                lastSyncTime = Date()
                saveLastSyncTime()
            }
            
        } catch {
            await MainActor.run {
                syncState = .failed
                errorMessage = error.localizedDescription
            }
            
            print("Incremental sync failed: \(error)")
        }
    }
    
    /// Cancel ongoing sync operation
    func cancelSync() {
        guard syncState == .syncing else { return }
        
        syncState = .idle
        syncProgress = SyncProgress()
    }
    
    // MARK: - Helper Methods
    
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
}
