import Foundation
import Combine

/// CatalogSyncService - Handles synchronization with Square API
/// Ports the sophisticated sync logic from React Native
@MainActor
class CatalogSyncService: ObservableObject {
    // MARK: - Singleton
    static let shared = CatalogSyncService()
    
    // MARK: - Published Properties
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncProgress: Double = 0.0
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    
    // MARK: - Private Properties
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient
    private let tokenService: TokenService
    
    private var syncTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager = DatabaseManager(),
        apiClient: APIClient = APIClient(),
        tokenService: TokenService = TokenService()
    ) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.tokenService = tokenService
    }
    
    // MARK: - Public Methods
    func runIncrementalSync() async throws {
        Logger.info("Sync", "Starting incremental catalog sync")
        
        // Cancel any existing sync
        syncTask?.cancel()
        
        syncTask = Task {
            await performIncrementalSync()
        }
        
        await syncTask?.value
    }
    
    func runFullSync() async throws {
        Logger.info("Sync", "Starting full catalog sync")
        
        // Cancel any existing sync
        syncTask?.cancel()
        
        syncTask = Task {
            await performFullSync()
        }
        
        await syncTask?.value
    }
    
    func cancelSync() {
        Logger.info("Sync", "Cancelling catalog sync")
        syncTask?.cancel()
        syncStatus = .idle
        syncProgress = 0.0
    }
    
    // MARK: - Private Methods
    private func performIncrementalSync() async {
        do {
            syncStatus = .syncing
            syncProgress = 0.0
            syncError = nil
            
            // Check authentication
            guard await tokenService.ensureValidToken() != nil else {
                throw SyncError.notAuthenticated
            }
            
            // Get last sync cursor
            let lastCursor = await getLastSyncCursor()
            
            Logger.info("Sync", "Starting incremental sync with cursor: \(lastCursor ?? "none")")
            
            var hasMore = true
            var currentCursor = lastCursor
            var totalProcessed = 0
            
            while hasMore && !Task.isCancelled {
                // Fetch page from Square API
                let response = try await apiClient.fetchCatalogPage(cursor: currentCursor)
                
                if let objects = response.objects, !objects.isEmpty {
                    // Process objects
                    try await processCatalogObjects(objects)
                    totalProcessed += objects.count
                    
                    Logger.debug("Sync", "Processed \(objects.count) objects, total: \(totalProcessed)")
                }
                
                // Update cursor and check for more
                currentCursor = response.cursor
                hasMore = response.cursor != nil
                
                // Update progress (estimate based on processed count)
                syncProgress = min(0.9, Double(totalProcessed) / 1000.0)
            }
            
            // Save final cursor
            if let finalCursor = currentCursor {
                try await saveLastSyncCursor(finalCursor)
            }
            
            // Update sync timestamp
            try await updateLastSyncTime()
            
            syncStatus = .completed
            syncProgress = 1.0
            lastSyncTime = Date()
            
            Logger.info("Sync", "Incremental sync completed successfully. Processed \(totalProcessed) objects")
            
        } catch {
            Logger.error("Sync", "Incremental sync failed: \(error)")
            syncStatus = .failed(error)
            syncError = error.localizedDescription
        }
    }
    
    private func performFullSync() async {
        do {
            syncStatus = .syncing
            syncProgress = 0.0
            syncError = nil
            
            // Check authentication
            guard await tokenService.ensureValidToken() != nil else {
                throw SyncError.notAuthenticated
            }
            
            Logger.info("Sync", "Starting full catalog sync")
            
            var hasMore = true
            var cursor: String?
            var totalProcessed = 0
            
            while hasMore && !Task.isCancelled {
                // Fetch page from Square API
                let response = try await apiClient.fetchCatalogPage(cursor: cursor)
                
                if let objects = response.objects, !objects.isEmpty {
                    // Process objects
                    try await processCatalogObjects(objects)
                    totalProcessed += objects.count
                    
                    Logger.debug("Sync", "Processed \(objects.count) objects, total: \(totalProcessed)")
                }
                
                // Update cursor and check for more
                cursor = response.cursor
                hasMore = response.cursor != nil
                
                // Update progress (estimate based on processed count)
                syncProgress = min(0.9, Double(totalProcessed) / 5000.0)
            }
            
            // Save final cursor
            if let finalCursor = cursor {
                try await saveLastSyncCursor(finalCursor)
            }
            
            // Update sync timestamp
            try await updateLastSyncTime()
            
            syncStatus = .completed
            syncProgress = 1.0
            lastSyncTime = Date()
            
            Logger.info("Sync", "Full sync completed successfully. Processed \(totalProcessed) objects")
            
        } catch {
            Logger.error("Sync", "Full sync failed: \(error)")
            syncStatus = .failed(error)
            syncError = error.localizedDescription
        }
    }
    
    private func processCatalogObjects(_ objects: [CatalogObject]) async throws {
        // Port the upsertCatalogObjects logic from React Native
        Logger.debug("Sync", "Processing \(objects.count) catalog objects")

        // Use the database manager's upsert method
        try await databaseManager.upsertCatalogObjects(objects)
    }
    

    
    // MARK: - Cursor Management
    private func getLastSyncCursor() async -> String? {
        return await databaseManager.getLastSyncCursor()
    }

    private func saveLastSyncCursor(_ cursor: String) async throws {
        try await databaseManager.saveLastSyncCursor(cursor)
    }

    private func updateLastSyncTime() async throws {
        try await databaseManager.updateSyncStatus(isSync: false)
    }
}

// MARK: - Supporting Types
enum SyncError: LocalizedError {
    case notAuthenticated
    case networkError
    case databaseError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .networkError:
            return "Network connection error"
        case .databaseError:
            return "Database error during sync"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

// Placeholder types - will be implemented in detail later
struct CatalogObject {
    let id: String
    let type: String
    let updatedAt: String
    let version: Int64
    let isDeleted: Bool
    let presentAtAllLocations: Bool
    let itemData: ItemData?
    let categoryData: CategoryData?
    let itemVariationData: ItemVariationData?
    
    func toDictionary() -> [String: Any] {
        // Convert to dictionary for JSON storage
        return [:]
    }
}

struct ItemData {
    let name: String?
    let description: String?
    let categoryId: String?
}

struct CategoryData {
    let name: String?
}

struct ItemVariationData {
    let itemId: String?
    let name: String?
    let sku: String?
    let pricingType: String?
    let priceAmount: Int?
    let priceCurrency: String?
}

struct CatalogResponse {
    let objects: [CatalogObject]?
    let cursor: String?
}
