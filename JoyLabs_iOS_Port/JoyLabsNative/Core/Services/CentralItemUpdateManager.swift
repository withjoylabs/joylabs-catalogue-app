import Foundation
import Combine

/// Centralized Item Update Manager - THE SINGLE SOURCE OF TRUTH for all app-wide item updates
/// This service handles ALL catalog item notifications and coordinates updates across ALL views
@MainActor
class CentralItemUpdateManager: ObservableObject {
    static let shared = CentralItemUpdateManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    // CENTRALIZED: All managers that need item updates
    // Using arrays to support multiple instances (e.g., multiple SearchManagers from different views)
    private var searchManagers: [WeakReference<SearchManager>] = []
    // Legacy ReorderDataManager removed - using SwiftData ReorderService only
    private weak var reorderBarcodeManager: ReorderBarcodeScanningManager?
    private weak var catalogStatsService: CatalogStatsService?
    
    // SwiftData service (single source of truth)
    private var reorderService: ReorderService? {
        return ReorderService.shared  // Always use the singleton
    }
    
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
    
    /// Setup method to register services that need item updates - ADDITIVE, not destructive
    /// Can be called multiple times from different views without overwriting existing services
    func setup(
        searchManager: SearchManager? = nil,
        reorderDataManager: AnyObject? = nil,  // Ignored - legacy parameter
        reorderBarcodeManager: ReorderBarcodeScanningManager? = nil,
        catalogStatsService: CatalogStatsService? = nil,
        viewName: String = "Unknown"  // For debugging which view is registering
    ) {
        print("🎯 [CentralItemUpdateManager] Setup called from \(viewName)")
        
        // Add SearchManager if provided (supports multiple instances)
        if let searchManager = searchManager {
            // Clean up any dead references first
            searchManagers.removeAll { $0.value == nil }
            
            // Check if this exact instance is already registered
            let isAlreadyRegistered = searchManagers.contains { $0.value === searchManager }
            
            if !isAlreadyRegistered {
                searchManagers.append(WeakReference(searchManager))
                print("✅ [CentralItemUpdateManager] Registered SearchManager from \(viewName): \(ObjectIdentifier(searchManager))")
            } else {
                print("⚠️ [CentralItemUpdateManager] SearchManager from \(viewName) already registered: \(ObjectIdentifier(searchManager))")
            }
        }
        
        // Legacy ReorderDataManager parameter is ignored - using SwiftData only
        
        // Only update ReorderBarcodeManager if provided
        if let reorderBarcodeManager = reorderBarcodeManager {
            if self.reorderBarcodeManager == nil {
                self.reorderBarcodeManager = reorderBarcodeManager
                print("✅ [CentralItemUpdateManager] Registered ReorderBarcodeManager from \(viewName)")
            }
        }
        
        // Only update CatalogStatsService if provided
        if let catalogStatsService = catalogStatsService {
            if self.catalogStatsService == nil {
                self.catalogStatsService = catalogStatsService
                print("✅ [CentralItemUpdateManager] Registered CatalogStatsService from \(viewName)")
            }
        }
        
        // Setup observers only on first call
        if cancellables.isEmpty {
            setupNotificationObservers()
            print("🎯 [CentralItemUpdateManager] Notification observers initialized")
        }
        
        // Log current state
        print("📊 [CentralItemUpdateManager] Current state:")
        print("   - SearchManagers registered: \(searchManagers.compactMap { $0.value }.count)")
        print("   - ReorderBarcodeManager: \(reorderBarcodeManager != nil ? "✅" : "❌")")
        print("   - CatalogStatsService: \(catalogStatsService != nil ? "✅" : "❌")")
        print("   - ReorderService: \(reorderService != nil ? "✅" : "❌")")
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
        
        // Update ALL registered SearchManagers
        searchManagers.removeAll { $0.value == nil }  // Clean up dead references
        for weakRef in searchManagers {
            if let searchManager = weakRef.value,
               searchManager.itemMatchesCurrentSearch(itemId: itemId) {
                // Re-run current search to naturally include new item
                if let currentTerm = searchManager.currentSearchTerm {
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
                    print("🔄 [CentralItemUpdateManager] Refreshed search in SearchManager: \(ObjectIdentifier(searchManager))")
                }
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
        
        // Update ALL registered SearchManagers
        searchManagers.removeAll { $0.value == nil }  // Clean up dead references
        var updatedCount = 0
        for weakRef in searchManagers {
            if let searchManager = weakRef.value {
                print("🎯 [CentralItemUpdateManager] Updating SearchManager \(ObjectIdentifier(searchManager)) for item: \(itemId)")
                searchManager.updateItemInSearchResults(itemId: itemId)
                updatedCount += 1
            }
        }
        
        if updatedCount == 0 {
            print("⚠️ [CentralItemUpdateManager] No SearchManagers registered to update")
        } else {
            print("✅ [CentralItemUpdateManager] Updated \(updatedCount) SearchManager(s)")
        }
        
        // ReordersView: Update reorder items that reference this catalog item (SwiftData)
        if let reorderService = reorderService {
            await reorderService.updateItemsFromCatalog(itemId: itemId)
            print("✅ [CentralItemUpdateManager] Updated SwiftData ReorderService for item: \(itemId)")
        } else {
            print("⚠️ [CentralItemUpdateManager] ReorderService not available")
        }
        
        // Legacy ReorderDataManager removed - using SwiftData ReorderService only
        
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
        
        // Remove from ALL registered SearchManagers
        searchManagers.removeAll { $0.value == nil }  // Clean up dead references
        for weakRef in searchManagers {
            if let searchManager = weakRef.value {
                searchManager.removeItemFromSearchResults(itemId: itemId)
                print("🗑️ [CentralItemUpdateManager] Removed item from SearchManager: \(ObjectIdentifier(searchManager))")
            }
        }
        
        // ReordersView: Remove reorder items that reference the deleted catalog item (SwiftData)
        if let reorderService = reorderService {
            await reorderService.removeItemsForDeletedCatalogItem(itemId: itemId)
        }
        
        // Legacy ReorderDataManager removed - using SwiftData ReorderService only
        
        // CatalogManagementView: Refresh statistics when items are deleted
        catalogStatsService?.refreshStats()
        
        // Future views: Add handling here as needed
    }
    
    /// Handles image updates across all views
    private func handleImageUpdate() {
        print("🖼️ [CentralItemUpdateManager] Handling image update across all views")
        
        Task {
            // Update ALL registered SearchManagers
            searchManagers.removeAll { $0.value == nil }  // Clean up dead references
            for weakRef in searchManagers {
                if let searchManager = weakRef.value,
                   let currentTerm = searchManager.currentSearchTerm {
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
                    print("🖼️ [CentralItemUpdateManager] Refreshed images in SearchManager: \(ObjectIdentifier(searchManager))")
                }
            }
            
            // ReordersView: Image updates handled by SwiftData ReorderService automatically
            
            // ReordersView: Refresh barcode search if active
            reorderBarcodeManager?.refreshSearchResults()
            
            // Future views: Add handling here as needed
        }
    }
    
    /// Handles force image refresh across all views
    private func handleForceImageRefresh() {
        print("🔄 [CentralItemUpdateManager] Handling force image refresh across all views")
        
        Task {
            // Force refresh ALL registered SearchManagers
            searchManagers.removeAll { $0.value == nil }  // Clean up dead references
            for weakRef in searchManagers {
                if let searchManager = weakRef.value,
                   let currentTerm = searchManager.currentSearchTerm {
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
                    print("🔄 [CentralItemUpdateManager] Force refreshed SearchManager: \(ObjectIdentifier(searchManager))")
                }
            }
            
            // ReordersView: Force refresh handled by SwiftData ReorderService automatically
            
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