import SwiftUI
import Combine
import SQLite

@MainActor
class ReorderViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var reorderItems: [ReorderItem] = []
    @Published var isProcessingBarcode = false
    @Published var scannerSearchText = ""
    @Published var currentModalQuantity: Int = 1
    @Published var hasLoadedInitialData = false  // Prevents reloading on tab switches
    
    // Filter and sort state
    @Published var sortOption: ReorderSortOption = .timeNewest
    @Published var filterOption: ReorderFilterOption = .all
    @Published var organizationOption: ReorderOrganizationOption = .none
    @Published var displayMode: ReorderDisplayMode = .list
    @Published var selectedCategories: Set<String> = []

    // Sheet management
    @Published var activeSheet: ReordersSheet?
    @Published var showingExportModal = false
    @Published var showingClearAlert = false
    @Published var showingMarkAllReceivedAlert = false
    
    // Image enlargement
    @Published var selectedItemForEnlargement: ReorderItem?
    @Published var showingImageEnlargement = false
    
    // MARK: - Services
    let modalStateManager = QuantityModalStateManager()
    let searchManager: SearchManager  // Made accessible for SearchRefreshService
    
    private var cancellables = Set<AnyCancellable>()
    private var searchDebounceTimer: Timer?
    
    // MARK: - Computed Properties
    var totalItems: Int { reorderItems.count }
    var unpurchasedItems: Int { reorderItems.filter { $0.status == .added }.count }
    var purchasedItems: Int { reorderItems.filter { $0.status == .purchased || $0.status == .received }.count }
    var totalQuantity: Int { reorderItems.reduce(0) { $0 + $1.quantity } }

    var availableCategories: [String] {
        let categories = reorderItems.compactMap { $0.categoryName }
        return Array(Set(categories)).sorted()
    }

    // Filtered and sorted items
    var filteredItems: [ReorderItem] {
        var filtered = reorderItems.filter { item in
            switch filterOption {
            case .all:
                return true
            case .unpurchased:
                return item.status == .added
            case .purchased:
                return item.status == .purchased
            case .received:
                return item.status == .received
            }
        }

        if !selectedCategories.isEmpty {
            filtered = filtered.filter { item in
                if let categoryName = item.categoryName {
                    return selectedCategories.contains(categoryName)
                }
                return false
            }
        }

        return filtered.sorted { item1, item2 in
            switch sortOption {
            case .timeNewest:
                return item1.addedDate > item2.addedDate
            case .timeOldest:
                return item1.addedDate < item2.addedDate
            case .alphabeticalAZ:
                return item1.name < item2.name
            case .alphabeticalZA:
                return item1.name > item2.name
            }
        }
    }
    
    // Organized items for sectioned display
    var organizedItems: [(String, [ReorderItem])] {
        switch organizationOption {
        case .none:
            return [("", filteredItems)]
        case .category:
            return Dictionary(grouping: filteredItems) { item in
                item.categoryName ?? "Uncategorized"
            }.sorted { $0.key < $1.key }
        case .vendor:
            return Dictionary(grouping: filteredItems) { item in
                item.vendor ?? "Unknown Vendor"
            }.sorted { $0.key < $1.key }
        case .vendorThenCategory:
            // Group by vendor first, then by category within each vendor
            let vendorGroups = Dictionary(grouping: filteredItems) { item in
                item.vendor ?? "Unknown Vendor"
            }

            var result: [(String, [ReorderItem])] = []
            for (vendor, items) in vendorGroups.sorted(by: { $0.key < $1.key }) {
                let categoryGroups = Dictionary(grouping: items) { item in
                    item.categoryName ?? "Uncategorized"
                }

                for (category, categoryItems) in categoryGroups.sorted(by: { $0.key < $1.key }) {
                    let sectionTitle = "\(vendor) - \(category)"
                    result.append((sectionTitle, categoryItems))
                }
            }
            return result
        }
    }
    
    // MARK: - Initialization
    init() {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        self.searchManager = SwiftDataSearchManager(databaseManager: databaseManager)
    }
    
    // MARK: - Data Management
    
    /// Loads reorder data only if it hasn't been loaded yet - prevents reloading on tab switches
    func loadReorderDataIfNeeded() {
        guard !hasLoadedInitialData else {
            print("📦 Reorder data already loaded - skipping reload to preserve updates")
            return
        }
        
        hasLoadedInitialData = true
        loadReorderData()
    }
    
    /// Force loads reorder data from storage (used internally and for manual refresh)
    func loadReorderData() {
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            reorderItems = items
            print("📦 Loaded \(items.count) reorder items from storage")
            
            // Refresh dynamic data from database for all items
            Task {
                await refreshDynamicDataForReorderItems()
            }
        } else {
            reorderItems = []
            print("📦 No saved reorder items found")
        }
    }
    
    func saveReorderData() {
        if let data = try? JSONEncoder().encode(reorderItems) {
            UserDefaults.standard.set(data, forKey: "reorderItems")
            print("💾 Saved \(reorderItems.count) reorder items to storage")
        }
    }
    
    // MARK: - Item Management
    func updateItemStatus(itemId: String, newStatus: ReorderItemStatus) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            let itemName = reorderItems[index].name
            
            if newStatus == .received {
                reorderItems[index].receivedDate = Date()
                reorderItems.remove(at: index)
                ToastNotificationService.shared.showSuccess("\(itemName) marked as received")
            } else {
                reorderItems[index].status = newStatus

                switch newStatus {
                case .purchased:
                    reorderItems[index].purchasedDate = Date()
                    ToastNotificationService.shared.showSuccess("\(itemName) marked as purchased")
                case .added:
                    reorderItems[index].purchasedDate = nil
                    reorderItems[index].receivedDate = nil
                    ToastNotificationService.shared.showInfo("\(itemName) added to reorder list")
                case .received:
                    break
                }
            }

            saveReorderData()
        }
    }
    
    func updateItemQuantity(itemId: String, newQuantity: Int) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            reorderItems[index].quantity = max(1, newQuantity)
            saveReorderData()
        }
    }
    
    func removeItem(itemId: String) {
        if let item = reorderItems.first(where: { $0.id == itemId }) {
            reorderItems.removeAll { $0.id == itemId }
            saveReorderData()
            print("🗑️ Removed item from reorder list: \(item.name)")
        }
    }
    
    func addOrUpdateItemInReorderList(_ foundItem: SearchResultItem, quantity: Int) {
        print("🔍 Adding/updating item in reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")

        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == foundItem.id }) {
            reorderItems[existingIndex].quantity = quantity
            saveReorderData()
            print("✅ Updated existing item quantity to \(quantity): \(foundItem.name ?? "Unknown Item")")
        } else {
            let newItem = ReorderItem(
                id: UUID().uuidString,
                itemId: foundItem.id,
                name: foundItem.name ?? "Unknown Item",
                sku: foundItem.sku,
                barcode: foundItem.barcode,
                variationName: foundItem.variationName,
                quantity: quantity,
                status: .added
            )

            var updatedItem = newItem
            updatedItem.categoryName = foundItem.categoryName
            updatedItem.price = foundItem.price
            updatedItem.hasTax = foundItem.hasTax

            if let images = foundItem.images, let firstImage = images.first {
                updatedItem.imageId = firstImage.id
                updatedItem.imageUrl = firstImage.imageData?.url
            }

            reorderItems.append(updatedItem)
            saveReorderData()
            print("✅ Added new item to reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")
        }
    }
    
    func removeItemFromReorderList(_ itemId: String) {
        print("🗑️ Removing item from reorder list: \(itemId)")

        if let index = reorderItems.firstIndex(where: { $0.itemId == itemId }) {
            let removedItem = reorderItems.remove(at: index)
            saveReorderData()
            print("✅ Removed item: \(removedItem.name)")
        } else {
            print("❌ Item not found in reorder list: \(itemId)")
        }
    }
    
    // MARK: - Management Actions
    func handleManagementAction(_ action: ManagementAction) {
        switch action {
        case .markAllReceived:
            showingMarkAllReceivedAlert = true
        case .clearAll:
            showingClearAlert = true
        }
    }
    
    func markAllAsReceived() {
        let itemsToUpdate = reorderItems.filter { $0.status == .added }
        let updatedCount = itemsToUpdate.count
        
        for item in reorderItems {
            updateItemStatus(itemId: item.id, newStatus: .received)
        }
        
        if updatedCount > 0 {
            ToastNotificationService.shared.showSuccess("Marked \(updatedCount) items as received")
        }
    }
    
    func clearAllItems() {
        let clearedCount = reorderItems.count
        reorderItems.removeAll()
        saveReorderData()
        
        if clearedCount > 0 {
            ToastNotificationService.shared.showSuccess("Cleared \(clearedCount) reorder items")
        }
    }
    
    // MARK: - Sheet Management
    func showImagePicker(for item: ReorderItem) {
        activeSheet = .imagePicker(item)
    }
    
    func showItemDetails(for item: ReorderItem) {
        activeSheet = .itemDetails(item)
    }
    
    func showQuantityModal(for item: SearchResultItem) {
        let existingItemForQuantity = reorderItems.first(where: { $0.itemId == item.id })
        let quantity = existingItemForQuantity?.quantity ?? 1
        let isExisting = existingItemForQuantity != nil

        print("🔢 Showing quantity modal for: \(item.name ?? "Unknown"), qty: \(quantity), existing: \(isExisting)")
        
        // BATCH ALL STATE UPDATES TO PREVENT MULTIPLE RE-RENDERS
        // Use DispatchQueue to batch all updates into single render cycle
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update modal state manager
            self.modalStateManager.setItem(item, quantity: quantity, isExisting: isExisting)
            self.modalStateManager.showModal()
            
            // Update view model properties
            self.currentModalQuantity = quantity
            
            // Only set activeSheet if modal is not already showing
            if self.activeSheet == nil {
                self.activeSheet = .quantityModal(item)
            }
        }
    }
    
    func dismissActiveSheet() {
        activeSheet = nil
    }
    
    // MARK: - Quantity Modal Management
    func handleQuantityModalSubmit(_ quantity: Int) {
        guard let item = modalStateManager.selectedItemForQuantity else { return }

        if quantity == 0 {
            removeItemFromReorderList(item.id)
        } else {
            addOrUpdateItemInReorderList(item, quantity: quantity)
        }

        modalStateManager.clearState()
        isProcessingBarcode = false
        activeSheet = nil
    }
    
    func handleQuantityModalCancel() {
        modalStateManager.clearState()
        isProcessingBarcode = false
        activeSheet = nil
    }
    
    // MARK: - Export Functions
    func handleExportSelection(_ format: ExportFormat) async {
        // This will be called from the export modal
        print("Export selected: \(format.displayName)")
    }
    
    // MARK: - Helper Methods
    func convertReorderItemToSearchResult(_ item: ReorderItem) -> SearchResultItem {
        var images: [CatalogImage] = []
        if let imageUrl = item.imageUrl, let imageId = item.imageId {
            let catalogImage = CatalogImage(
                id: imageId,
                type: "IMAGE",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: nil,
                isDeleted: false,
                presentAtAllLocations: true,
                imageData: ImageData(
                    name: nil,
                    url: imageUrl,
                    caption: nil,
                    photoStudioOrderId: nil
                )
            )
            images = [catalogImage]
        }

        return SearchResultItem(
            id: item.itemId,
            name: item.name,
            sku: item.sku,
            price: item.price,
            barcode: item.barcode,
            categoryId: nil,
            categoryName: item.categoryName,
            variationName: item.variationName,
            images: images,
            matchType: "reorder",
            matchContext: item.name,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: item.hasTax
        )
    }
    
    // MARK: - Data Refresh (will be moved to ReorderDataManager)
    private func refreshDynamicDataForReorderItems() async {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            print("❌ [ReorderRefresh] Database not connected")
            return
        }
        
        var updatedItems: [ReorderItem] = []
        
        for item in reorderItems {
            do {
                let itemQuery = CatalogTableDefinitions.catalogItems
                    .select(CatalogTableDefinitions.itemCategoryName,
                           CatalogTableDefinitions.itemReportingCategoryName,
                           CatalogTableDefinitions.itemDataJson)
                    .filter(CatalogTableDefinitions.itemId == item.itemId)
                    .filter(CatalogTableDefinitions.itemIsDeleted == false)
                
                guard let itemRow = try db.pluck(itemQuery) else {
                    // Item not found or is deleted - skip it (don't add to updated items)
                    print("⚠️ [ReorderRefresh] Item not found or deleted, removing from reorder list: \(item.itemId)")
                    // Don't add to updatedItems - effectively removes it from the list
                    continue
                }
                
                let reportingCategoryName = try? itemRow.get(CatalogTableDefinitions.itemReportingCategoryName)
                let regularCategoryName = try? itemRow.get(CatalogTableDefinitions.itemCategoryName)
                let categoryName = reportingCategoryName ?? regularCategoryName
                
                let dataJson = try? itemRow.get(CatalogTableDefinitions.itemDataJson)
                
                let variationQuery = CatalogTableDefinitions.itemVariations
                    .select(CatalogTableDefinitions.variationPriceAmount)
                    .filter(CatalogTableDefinitions.variationItemId == item.itemId)
                    .filter(CatalogTableDefinitions.variationIsDeleted == false)
                    .limit(1)
                
                var price: Double? = nil
                if let variationRow = try db.pluck(variationQuery) {
                    let priceAmount = try? variationRow.get(CatalogTableDefinitions.variationPriceAmount)
                    if let amount = priceAmount, amount > 0 {
                        let convertedPrice = Double(amount) / 100.0
                        if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                            price = convertedPrice
                        }
                    }
                }
                
                let hasTax = checkItemHasTaxFromDataJson(dataJson)
                let images = getPrimaryImageForReorderItem(itemId: item.itemId)
                
                var updatedItem = item
                updatedItem.price = price
                if let categoryName = categoryName {
                    updatedItem.categoryName = categoryName
                }
                updatedItem.hasTax = hasTax
                
                if let images = images, let firstImage = images.first {
                    updatedItem.imageId = firstImage.id
                    updatedItem.imageUrl = firstImage.imageData?.url
                }
                
                updatedItems.append(updatedItem)
                
            } catch {
                print("❌ [ReorderRefresh] Failed to refresh item \(item.itemId): \(error)")
                updatedItems.append(item)
            }
        }
        
        await MainActor.run {
            reorderItems = updatedItems
            saveReorderData()
            print("🔄 [ReorderRefresh] Refreshed ALL data for \(updatedItems.count) reorder items")
        }
    }
    
    private func checkItemHasTaxFromDataJson(_ dataJson: String?) -> Bool {
        guard let dataJson = dataJson,
              let data = dataJson.data(using: .utf8) else {
            return false
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taxIds = json["tax_ids"] as? [String] {
                return !taxIds.isEmpty
            }
        } catch {
            print("❌ [ReorderRefresh] Failed to parse tax data: \(error)")
        }
        
        return false
    }
    
    private func getPrimaryImageForReorderItem(itemId: String) -> [CatalogImage]? {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            return nil
        }
        
        do {
            let selectQuery = """
            SELECT data_json FROM catalog_items 
            WHERE id = ? AND is_deleted = 0
            """
            
            for row in try db.prepare(selectQuery, itemId) {
                guard let dataJson = row[0] as? String,
                      let data = dataJson.data(using: .utf8) else {
                    continue
                }
                
                let decoder = JSONDecoder()
                let catalogObject = try decoder.decode(CatalogObject.self, from: data)
                
                return catalogObject.itemData?.images
            }
        } catch {
            print("❌ [ReorderRefresh] Failed to get images for item \(itemId): \(error)")
        }
        
        return nil
    }
}