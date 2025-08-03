import SwiftUI
import Foundation

@MainActor
class ReorderAppState: ObservableObject {
    // MARK: - Core Data State
    @Published var reorderItems: [ReorderItem] = []
    
    // MARK: - UI State
    @Published var activeSheet: ReordersSheet?
    @Published var showingExportOptions = false
    @Published var showingClearAlert = false
    @Published var showingMarkAllReceivedAlert = false
    
    // MARK: - Image Enlargement State
    @Published var selectedItemForEnlargement: ReorderItem?
    @Published var showingImageEnlargement = false
    
    // MARK: - Barcode Processing State
    @Published var isProcessingBarcode = false
    @Published var scannerSearchText = ""
    @Published var currentModalQuantity: Int = 1
    
    // MARK: - Focus State (Note: @FocusState must remain in view due to SwiftUI property wrapper limitations)
    // isScannerFieldFocused will remain as @FocusState in the view
    
    // MARK: - Computed Statistics Properties
    var totalItems: Int { 
        ReorderStatisticsCalculator.calculateTotalItems(from: reorderItems)
    }
    
    var unpurchasedItems: Int { 
        ReorderStatisticsCalculator.calculateUnpurchasedItems(from: reorderItems)
    }
    
    var purchasedItems: Int { 
        ReorderStatisticsCalculator.calculatePurchasedItems(from: reorderItems)
    }
    
    var totalQuantity: Int { 
        ReorderStatisticsCalculator.calculateTotalQuantity(from: reorderItems)
    }
    
    var comprehensiveStatistics: ReorderStatistics {
        ReorderStatisticsCalculator.calculateAllStatistics(from: reorderItems)
    }
    
    var categoryBreakdown: [CategoryStatistics] {
        ReorderStatisticsCalculator.calculateCategoryBreakdown(from: reorderItems)
    }
    
    var statusDistribution: StatusDistribution {
        ReorderStatisticsCalculator.calculateStatusDistribution(from: reorderItems)
    }
    
    // MARK: - Initialization
    init() {
        loadReorderData()
    }
    
    // MARK: - Data Management
    func loadReorderData() {
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            reorderItems = items
            print("📦 [ReorderAppState] Loaded \(items.count) reorder items from storage")
        } else {
            reorderItems = []
            print("📦 [ReorderAppState] No saved reorder items found")
        }
    }
    
    func saveReorderData() {
        if let data = try? JSONEncoder().encode(reorderItems) {
            UserDefaults.standard.set(data, forKey: "reorderItems")
            print("💾 [ReorderAppState] Saved \(reorderItems.count) reorder items to storage")
        }
    }
    
    // MARK: - Item Management
    func updateItemStatus(itemId: String, newStatus: ReorderStatus) {
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
            print("🗑️ [ReorderAppState] Removed item from reorder list: \(item.name)")
        }
    }
    
    func addOrUpdateItemInReorderList(_ foundItem: SearchResultItem, quantity: Int) {
        print("🔍 [ReorderAppState] Adding/updating item: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")

        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == foundItem.id }) {
            reorderItems[existingIndex].quantity = quantity
            saveReorderData()
            print("✅ [ReorderAppState] Updated existing item quantity to \(quantity): \(foundItem.name ?? "Unknown Item")")
        } else {
            let newItem = ReorderItem(
                id: UUID().uuidString,
                itemId: foundItem.id,
                name: foundItem.name ?? "Unknown Item",
                sku: foundItem.sku,
                barcode: foundItem.barcode,
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
            print("✅ [ReorderAppState] Added new item to reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")
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

        currentModalQuantity = quantity
        activeSheet = .quantityModal(item)
        
        print("🔢 [ReorderAppState] Showing quantity modal for: \(item.name ?? "Unknown"), qty: \(quantity), existing: \(isExisting)")
    }
    
    func dismissActiveSheet() {
        activeSheet = nil
    }
    
    // MARK: - Barcode Processing State
    func setProcessingBarcode(_ processing: Bool) {
        isProcessingBarcode = processing
    }
    
    func updateScannerSearchText(_ text: String) {
        scannerSearchText = text
    }
    
    // MARK: - Image Enlargement
    func showImageEnlargement(for item: ReorderItem) {
        selectedItemForEnlargement = item
        showingImageEnlargement = true
    }
    
    func hideImageEnlargement() {
        selectedItemForEnlargement = nil
        showingImageEnlargement = false
    }
    
    // MARK: - Management Actions
    func handleManagementAction(_ action: ManagementAction) {
        switch action {
        case .markAllReceived:
            showingMarkAllReceivedAlert = true
        case .clearAll:
            showingClearAlert = true
        case .export:
            showingExportOptions = true
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
    
    // MARK: - Export Functions
    func shareList() {
        print("[ReorderAppState] Sharing list...")
    }
    
    func printList() {
        print("[ReorderAppState] Printing list...")
    }
    
    func saveAsPDF() {
        print("[ReorderAppState] Saving as PDF...")
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
            images: images,
            matchType: "reorder",
            matchContext: item.name,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: item.hasTax
        )
    }
}