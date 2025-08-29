import Foundation
import Combine

/// Centralized Item Update Manager - THE SINGLE SOURCE OF TRUTH for all app-wide item updates
/// This service handles ALL catalog item notifications and coordinates updates across ALL views
@MainActor
class CentralItemUpdateManager: ObservableObject {
    static let shared = CentralItemUpdateManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    // CENTRALIZED: All managers that need item updates
    private weak var searchManager: SearchManager?
    private weak var reorderDataManager: ReorderDataManager?
    private weak var reorderBarcodeManager: ReorderBarcodeScanningManager?
    private weak var catalogStatsService: CatalogStatsService?
    
    // CENTRALIZED: Registry for ItemDetailsModals that need refreshing
    private var activeItemDetailsModals: [String: WeakReference<ItemDetailsViewModel>] = [:]
    
    private init() {}
    
    /// Register an ItemDetailsModal that needs to be refreshed when its item is updated
    func registerItemDetailsModal(itemId: String, viewModel: ItemDetailsViewModel) {
        activeItemDetailsModals[itemId] = WeakReference(viewModel)
        print("🎯 [CentralItemUpdateManager] Registered ItemDetailsModal for item: \(itemId)")
    }
    
    /// Unregister an ItemDetailsModal when it's dismissed
    func unregisterItemDetailsModal(itemId: String) {
        activeItemDetailsModals.removeValue(forKey: itemId)
        print("🎯 [CentralItemUpdateManager] Unregistered ItemDetailsModal for item: \(itemId)")
    }
    
    /// Setup method to register ALL services that need item updates
    func setup(
        searchManager: SearchManager,
        reorderDataManager: ReorderDataManager,
        reorderBarcodeManager: ReorderBarcodeScanningManager? = nil,
        catalogStatsService: CatalogStatsService? = nil
    ) {
        print("🎯 [CentralItemUpdateManager] Setting up with searchManager: \(ObjectIdentifier(searchManager))")
        
        self.searchManager = searchManager
        self.reorderDataManager = reorderDataManager
        self.reorderBarcodeManager = reorderBarcodeManager
        self.catalogStatsService = catalogStatsService
        
        setupNotificationObservers()
        print("🎯 [CentralItemUpdateManager] Initialized with all app services")
    }
    
    private func setupNotificationObservers() {
        // Clear any existing subscriptions to prevent duplicates
        cancellables.removeAll()
        
        // THE SINGLE APP-WIDE HANDLER for all catalog item updates
        NotificationCenter.default.publisher(for: .catalogSyncCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let itemId = userInfo["itemId"] as? String,
                      let operation = userInfo["operation"] as? String else {
                    // Ignore bulk sync notifications without specific item info
                    return
                }
                
                print("🎯 [CentralItemUpdateManager] Handling catalog item \(operation): \(itemId)")
                self?.handleCatalogItemUpdate(itemId: itemId, operation: operation)
            }
            .store(in: &cancellables)
        
        // CENTRALIZED: Image update notifications for all views
        NotificationCenter.default.publisher(for: .imageUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("🎯 [CentralItemUpdateManager] Handling image update")
                if let userInfo = notification.userInfo {
                    print("🎯 [CentralItemUpdateManager] Image updated userInfo: \(userInfo)")
                }
                self?.handleImageUpdate()
            }
            .store(in: &cancellables)
        
        // CENTRALIZED: Force image refresh notifications for all views
        NotificationCenter.default.publisher(for: .forceImageRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("🎯 [CentralItemUpdateManager] Handling force image refresh")
                if let userInfo = notification.userInfo {
                    print("🎯 [CentralItemUpdateManager] Force refresh userInfo: \(userInfo)")
                }
                self?.handleForceImageRefresh()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - CENTRALIZED HANDLERS - All view logic consolidated here
    
    /// THE SINGLE HANDLER for all catalog item updates across the entire app
    private func handleCatalogItemUpdate(itemId: String, operation: String) {
        print("🎯 [CentralItemUpdateManager] Processing \(operation) for item: \(itemId)")
        
        Task {
            switch operation {
            case "create":
                await handleItemCreation(itemId: itemId)
            case "update":
                await handleItemUpdate(itemId: itemId)
            case "delete":
                await handleItemDeletion(itemId: itemId)
            default:
                print("⚠️ [CentralItemUpdateManager] Unknown operation: \(operation)")
            }
        }
    }
    
    /// Handles new item creation - affects search results if they match current search
    private func handleItemCreation(itemId: String) async {
        print("🆕 [CentralItemUpdateManager] Handling item creation: \(itemId)")
        
        // ScanView: Check if new item matches current search criteria
        if let searchManager = searchManager,
           searchManager.itemMatchesCurrentSearch(itemId: itemId) {
            // Re-run current search to naturally include new item
            if let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
        }
        
        // ReordersView: New items don't affect existing reorder items - no action needed
        
        // CatalogManagementView: Refresh statistics when new items are created
        catalogStatsService?.refreshStats()
        
        // Future views: Add handling here as needed
    }
    
    /// Handles item updates - updates all views displaying this item
    private func handleItemUpdate(itemId: String) async {
        print("🔄 [CentralItemUpdateManager] Handling item update: \(itemId)")
        
        // ScanView: Update specific item in search results (no full refresh)
        if let searchManager = searchManager {
            print("🎯 [CentralItemUpdateManager] Calling searchManager.updateItemInSearchResults for \(itemId)")
            searchManager.updateItemInSearchResults(itemId: itemId)
        } else {
            print("❌ [CentralItemUpdateManager] searchManager is nil - cannot update search results")
        }
        
        // ReordersView: Update reorder items that reference this catalog item
        await reorderDataManager?.updateReorderItemsReferencingCatalogItem(itemId: itemId)
        
        // ReordersView: Refresh barcode search if active
        reorderBarcodeManager?.refreshSearchResults()
        
        // CatalogManagementView: Refresh statistics when items are updated
        catalogStatsService?.refreshStats()
        
        // ItemDetailsModal: Refresh any active modal showing this item
        await refreshItemDetailsModal(itemId: itemId)
        
        // Future views: Add handling here as needed
    }
    
    /// Handles item deletion - removes item from all views
    private func handleItemDeletion(itemId: String) async {
        print("🗑️ [CentralItemUpdateManager] Handling item deletion: \(itemId)")
        
        // ScanView: Remove specific item from search results
        searchManager?.removeItemFromSearchResults(itemId: itemId)
        
        // ReordersView: Remove reorder items that reference the deleted catalog item
        await reorderDataManager?.removeReorderItemsReferencingCatalogItem(itemId: itemId)
        
        // CatalogManagementView: Refresh statistics when items are deleted
        catalogStatsService?.refreshStats()
        
        // Future views: Add handling here as needed
    }
    
    /// Handles image updates across all views
    private func handleImageUpdate() {
        print("🖼️ [CentralItemUpdateManager] Handling image update across all views")
        
        Task {
            // ScanView: Refresh search results for image updates
            if let searchManager = searchManager,
               let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
            
            // ReordersView: Refresh reorder data for image updates
            await reorderDataManager?.handleImageUpdated()
            
            // ReordersView: Refresh barcode search if active
            reorderBarcodeManager?.refreshSearchResults()
            
            // Future views: Add handling here as needed
        }
    }
    
    /// Handles force image refresh across all views
    private func handleForceImageRefresh() {
        print("🔄 [CentralItemUpdateManager] Handling force image refresh across all views")
        
        Task {
            // ScanView: Force refresh search results
            if let searchManager = searchManager,
               let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
            
            // ReordersView: Force refresh reorder data
            await reorderDataManager?.handleForceImageRefresh()
            
            // ReordersView: Refresh barcode search if active
            reorderBarcodeManager?.refreshSearchResults()
            
            // Future views: Add handling here as needed
        }
    }
    
    // MARK: - Helper Methods
    
    /// Refreshes any active ItemDetailsModal showing the specified item
    private func refreshItemDetailsModal(itemId: String) async {
        guard let weakRef = activeItemDetailsModals[itemId],
              let viewModel = weakRef.value else {
            // Clean up dead references
            activeItemDetailsModals.removeValue(forKey: itemId)
            return
        }
        
        print("📋 [CentralItemUpdateManager] Refreshing ItemDetailsModal for item: \(itemId)")
        
        // Add small delay to prevent race conditions during modal presentation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await viewModel.refreshItemData(itemId: itemId)
    }
    
    deinit {
        cancellables.removeAll()
    }
}

// MARK: - Supporting Classes

/// Weak reference wrapper to prevent retain cycles in the modal registry
class WeakReference<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T) {
        self.value = value
    }
}