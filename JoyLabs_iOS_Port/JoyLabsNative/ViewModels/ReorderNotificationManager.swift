import Foundation
import Combine

@MainActor
class ReorderNotificationManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private weak var dataManager: ReorderDataManager?
    private weak var barcodeManager: ReorderBarcodeScanningManager?
    
    func setup(dataManager: ReorderDataManager, barcodeManager: ReorderBarcodeScanningManager) {
        self.dataManager = dataManager
        self.barcodeManager = barcodeManager
        
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Clear any existing subscriptions to prevent duplicates
        cancellables.removeAll()
        
        // CONSOLIDATED: Single notification observer that handles all catalog updates
        NotificationCenter.default.publisher(for: .catalogSyncCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("🔔 [ReorderNotificationManager] Catalog sync completed")
                self?.handleCatalogUpdate()
            }
            .store(in: &cancellables)
        
        // CONSOLIDATED: Single notification observer that handles all image updates
        NotificationCenter.default.publisher(for: .imageUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("🔔 [ReorderNotificationManager] Image updated")
                if let userInfo = notification.userInfo {
                    print("🔔 [ReorderNotificationManager] Image updated userInfo: \(userInfo)")
                }
                self?.handleImageUpdate()
            }
            .store(in: &cancellables)
        
        // CONSOLIDATED: Single notification observer that handles force refresh
        NotificationCenter.default.publisher(for: .forceImageRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("🔔 [ReorderNotificationManager] Force image refresh")
                if let userInfo = notification.userInfo {
                    print("🔔 [ReorderNotificationManager] Force refresh userInfo: \(userInfo)")
                }
                self?.handleForceRefresh()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Consolidated Notification Handlers
    private func handleCatalogUpdate() {
        print("🔄 [ReorderNotificationManager] Handling catalog sync completion")
        
        Task {
            // Refresh reorder data
            await dataManager?.handleCatalogSyncCompleted()
            
            // Refresh search results if active
            barcodeManager?.refreshSearchResults()
        }
    }
    
    private func handleImageUpdate() {
        print("🔄 [ReorderNotificationManager] Handling image update")
        
        Task {
            // Refresh reorder data
            await dataManager?.handleImageUpdated()
            
            // Refresh search results if active
            barcodeManager?.refreshSearchResults()
        }
    }
    
    private func handleForceRefresh() {
        print("🔄 [ReorderNotificationManager] Handling force image refresh")
        
        Task {
            // Refresh reorder data
            await dataManager?.handleForceImageRefresh()
            
            // Refresh search results if active
            barcodeManager?.refreshSearchResults()
        }
    }
    
    deinit {
        cancellables.removeAll()
    }
}