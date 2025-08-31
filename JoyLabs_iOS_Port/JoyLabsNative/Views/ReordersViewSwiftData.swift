import SwiftUI
import SwiftData
import UIKit

// MARK: - Supporting Types for ReordersViewSwiftData

enum ReordersSheet: Identifiable {
    case imagePicker(ReorderItem)
    case itemDetails(ReorderItem)
    case quantityModal(SearchResultItem)
    
    var id: String {
        switch self {
        case .imagePicker(let item): return "imagePicker-\(item.id)"
        case .itemDetails(let item): return "itemDetails-\(item.id)"
        case .quantityModal(let item): return "quantityModal-\(item.id)"
        }
    }
}

class QuantityModalStateManager: ObservableObject {
    @Published var showingQuantityModal = false
    @Published var selectedItemForQuantity: SearchResultItem?
    @Published var modalQuantity: Int = 1
    @Published var isExistingItem = false
    @Published var modalJustPresented = false
    
    func setItem(_ item: SearchResultItem, quantity: Int, isExisting: Bool) {
        selectedItemForQuantity = item
        modalQuantity = quantity
        isExistingItem = isExisting
    }
    
    func showModal() {
        modalJustPresented = true
        showingQuantityModal = true
        // Clear the flag after a short delay to allow normal dismiss behavior
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.modalJustPresented = false
        }
    }
    
    func clearState() {
        selectedItemForQuantity = nil
        showingQuantityModal = false
        isExistingItem = false
        modalJustPresented = false
    }
}

// MARK: - Professional ReordersView with SwiftData Backend (Fully Restored)
struct ReordersViewSwiftData: SwiftUI.View {
    // SwiftData as single source of truth for data
    @Query(sort: \ReorderItemModel.addedDate, order: .reverse) private var reorderItems: [ReorderItemModel]
    
    // Professional state management (restored from original)
    @State private var sortOption: ReorderSortOption = .timeNewest
    @State private var filterOption: ReorderFilterOption = .all
    @State private var organizationOption: ReorderOrganizationOption = .none
    @State private var displayMode: ReorderDisplayMode = .list
    
    // Professional sheet management (restored original ReordersSheet enum)
    @State private var activeSheet: ReordersSheet?
    @State private var showingExportModal = false
    @State private var showingClearAlert = false
    @State private var showingMarkAllReceivedAlert = false
    
    // Scanner state
    @State private var scannerSearchText = ""
    @FocusState private var isScannerFieldFocused: Bool
    
    // RESTORED: Professional Quantity Modal State Management
    @StateObject private var modalStateManager = QuantityModalStateManager()
    @State private var currentModalQuantity: Int = 1
    
    // Barcode scanning manager
    @StateObject private var barcodeManager = ReorderBarcodeScanningManager(searchManager: SearchManager(databaseManager: SquareAPIServiceFactory.createDatabaseManager()))
    
    // Binding for focus state to pass up to ContentView
    let onFocusStateChanged: ((Bool) -> Void)?
    
    // Default initializer
    init(onFocusStateChanged: ((Bool) -> Void)? = nil) {
        self.onFocusStateChanged = onFocusStateChanged
    }
    
    // MARK: - Professional Bridge: SwiftData → ReorderItem Conversion
    private var bridgedReorderItems: [ReorderItem] {
        reorderItems.map { convertToReorderItem($0) }
    }
    
    // MARK: - Computed Properties (Professional Implementation Restored)
    var totalItems: Int { bridgedReorderItems.count }
    var unpurchasedItems: Int { bridgedReorderItems.filter { $0.status == .added }.count }
    var purchasedItems: Int { bridgedReorderItems.filter { $0.status == .purchased || $0.status == .received }.count }
    var totalQuantity: Int { bridgedReorderItems.reduce(0) { $0 + $1.quantity } }
    
    // Professional filtered items (using original logic)
    var filteredItems: [ReorderItem] {
        let filtered = bridgedReorderItems.filter { item in
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
    
    // Professional organized items (using original sophisticated logic)
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
            // Sophisticated vendor-then-category grouping (restored)
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // RESTORED: Use original professional ReorderContentView
                ReorderContentView(
                    reorderItems: bridgedReorderItems,
                    filteredItems: filteredItems,
                    organizedItems: organizedItems,
                    totalItems: totalItems,
                    unpurchasedItems: unpurchasedItems,
                    purchasedItems: purchasedItems,
                    totalQuantity: totalQuantity,
                    sortOption: $sortOption,
                    filterOption: $filterOption,
                    organizationOption: $organizationOption,
                    displayMode: $displayMode,
                    scannerSearchText: $barcodeManager.scannerSearchText,
                    isScannerFieldFocused: $isScannerFieldFocused,
                    onManagementAction: handleManagementAction,
                    onExportTap: { showingExportModal = true },
                    onStatusChange: updateItemStatus,
                    onQuantityChange: updateItemQuantity,
                    onRemoveItem: removeItem,
                    onBarcodeScanned: barcodeManager.handleBarcodeScanned,
                    onImageTap: { item in
                        print("[ReordersViewSwiftData] Image tapped for item: \(item.name)")
                    },
                    onImageLongPress: showImagePicker,
                    onQuantityTap: showQuantityModal,
                    onItemDetailsLongPress: showItemDetails
                )
            }
        }
        .onAppear {
            setupServices()
        }
        .onChange(of: isScannerFieldFocused) { oldValue, newValue in
            // Notify ContentView of focus state changes for AppLevelHIDScanner
            onFocusStateChanged?(newValue)
        }
        // No visible text fields to track in ReordersView
        .alert("Clear All Items", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    ReorderService.shared.clearAllItems()
                }
            } message: {
                Text("Are you sure you want to clear all reorder items? This action cannot be undone.")
            }
            .alert("Mark All as Received", isPresented: $showingMarkAllReceivedAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Mark All") {
                    ReorderService.shared.markAllAsReceived()
                }
            } message: {
                Text("Mark all items as received? This will move them to the received state.")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GlobalBarcodeScannedReorders"))) { notification in
                // Handle global barcode scan from app-level HID scanner
                if let barcode = notification.object as? String {
                    barcodeManager.handleGlobalBarcodeScanned(barcode)
                }
            }
            // RESTORED: Full export functionality with professional ExportOptionsModal
        .sheet(isPresented: $showingExportModal) {
            ExportOptionsModal(
                isPresented: $showingExportModal,
                items: bridgedReorderItems,  // Use professional bridge conversion
                onExport: { format in
                    await handleExportSelection(format)
                }
            )
            .nestedComponentModal()
        }
        // RESTORED: Professional unified sheet modal with original ReordersSheet enum
        .sheet(item: $activeSheet) { (sheet: ReordersSheet) in
            switch sheet {
            case .imagePicker(let item):
                UnifiedImagePickerModal(
                    context: .reordersViewLongPress(
                        itemId: item.itemId,
                        imageId: item.imageId
                    ),
                    onDismiss: {
                        dismissActiveSheet()
                    },
                    onImageUploaded: { result in
                        dismissActiveSheet()
                    }
                )
                .imagePickerModal()
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.itemId),
                    onDismiss: {
                        dismissActiveSheet()
                    },
                    onSave: { itemData in
                        dismissActiveSheet()
                        // NOTE: Item updates are handled automatically by CentralItemUpdateManager 
                        // via catalogSyncCompleted notifications. No manual refresh needed.
                    }
                )
                .fullScreenModal()
            case .quantityModal(_):
                // RESTORED: Professional Quantity Modal Implementation
                if let selectedItem = modalStateManager.selectedItemForQuantity {
                    EmbeddedQuantitySelectionModal(
                        item: selectedItem,
                        currentQuantity: modalStateManager.modalQuantity,
                        isExistingItem: modalStateManager.isExistingItem,
                        isPresented: .constant(true),
                        onSubmit: { quantity in
                            handleQuantityModalSubmit(quantity)
                        },
                        onCancel: {
                            handleQuantityModalCancel()
                        },
                        onQuantityChange: { newQuantity in
                            currentModalQuantity = newQuantity
                            modalStateManager.modalQuantity = newQuantity
                        }
                    )
                    .imagePickerModal()
                }
            }
        }
    }
    
    // MARK: - Professional Setup and Helper Methods (Fully Restored)
    
    private func setupServices() {
        // Setup CentralItemUpdateManager with services
        CentralItemUpdateManager.shared.setup(
            reorderBarcodeManager: barcodeManager,
            viewName: "ReordersViewSwiftData"
        )
        
        // Setup barcode manager with ReorderService  
        barcodeManager.setReorderService(ReorderService.shared)
        
        // Connect barcode manager modal handlers using closures
        barcodeManager.setModalHandlers(
            showQuantityModal: showQuantityModal,
            isModalShowing: { modalStateManager.showingQuantityModal },
            getCurrentItem: { modalStateManager.selectedItemForQuantity },
            getCurrentQuantity: { currentModalQuantity },
            dismissModal: { handleQuantityModalCancel() }
        )
    }
    
    // Protocol methods now handled via closures in setModalHandlers
    
    private func handleManagementAction(_ action: ManagementAction) {
        switch action {
        case .clearAll:
            showingClearAlert = true
        case .markAllReceived:
            showingMarkAllReceivedAlert = true
        }
    }
    
    // MARK: - Professional Item Management (SwiftData Backend)
    
    private func updateItemStatus(_ itemId: String, _ newStatus: ReorderItemStatus) {
        ReorderService.shared.updateItemStatus(itemId, status: newStatus)
        
        let statusName = newStatus.displayName
        ToastNotificationService.shared.showSuccess("Item marked as \(statusName)")
    }
    
    private func updateItemQuantity(_ itemId: String, _ newQuantity: Int) {
        ReorderService.shared.updateItemQuantity(itemId, quantity: newQuantity)
        ToastNotificationService.shared.showSuccess("Quantity updated to \(newQuantity)")
    }
    
    private func removeItem(_ itemId: String) {
        ReorderService.shared.removeItem(itemId)
        ToastNotificationService.shared.showSuccess("Item removed from reorder list")
    }
    
    // MARK: - RESTORED: Professional Quantity Modal Management
    
    private func handleQuantityModalSubmit(_ quantity: Int) {
        guard let item = modalStateManager.selectedItemForQuantity else { return }
        if quantity == 0 {
            removeItemFromReorderList(item.id)
        } else {
            addOrUpdateItemInReorderList(item, quantity: quantity)
        }
        modalStateManager.clearState()
        barcodeManager.resetProcessingState() // Reset barcode processing
        activeSheet = nil
    }
    
    private func handleQuantityModalCancel() {
        modalStateManager.clearState()
        barcodeManager.resetProcessingState() // Reset barcode processing
        activeSheet = nil
    }
    
    // MARK: - RESTORED: SwiftData CRUD Operations
    
    private func addOrUpdateItemInReorderList(_ foundItem: SearchResultItem, quantity: Int) {
        print("🔍 Adding/updating item in reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")
        
        // Use ReorderService to add/update with SwiftData
        ReorderService.shared.addOrUpdateItem(from: foundItem, quantity: quantity)
        
        // Show success feedback
        let itemName = foundItem.name ?? "Item"
        let truncatedName = itemName.count > 15 ? String(itemName.prefix(12)) + "..." : itemName
        ToastNotificationService.shared.showSuccess("\(truncatedName) (Qty: \(quantity)) added")
    }
    
    private func removeItemFromReorderList(_ itemId: String) {
        print("🗑️ Removing item from reorder list: \(itemId)")
        
        // Use ReorderService to remove with SwiftData
        ReorderService.shared.removeItem(itemId)
        
        // Show success feedback  
        ToastNotificationService.shared.showSuccess("Item removed from reorder list")
    }
    
    // MARK: - Professional Sheet Management (Restored)
    
    private func showImagePicker(_ item: ReorderItem) {
        activeSheet = .imagePicker(item)
    }
    
    private func showItemDetails(_ item: ReorderItem) {
        activeSheet = .itemDetails(item)
    }
    
    private func showQuantityModal(_ searchResult: SearchResultItem) {
        // FIXED: Properly set up modal state like original
        let existingItemForQuantity = bridgedReorderItems.first(where: { $0.itemId == searchResult.id })
        let quantity = existingItemForQuantity?.quantity ?? 1
        let isExisting = existingItemForQuantity != nil
        
        // Update modal state manager
        modalStateManager.setItem(searchResult, quantity: quantity, isExisting: isExisting)
        modalStateManager.showModal()
        
        // Update view model properties
        currentModalQuantity = quantity
        
        // Only set activeSheet if modal is not already showing
        if activeSheet == nil {
            activeSheet = .quantityModal(searchResult)
        }
    }
    
    private func dismissActiveSheet() {
        activeSheet = nil
    }
    
    // MARK: - RESTORED: Full Export System Integration
    
    private func handleExportSelection(_ format: ExportFormat) async {
        // FIXED: Don't duplicate export - ExportOptionsModal handles export internally
        // This method is just for additional app-level handling after export completes
        await MainActor.run {
            print("✅ [ReordersViewSwiftData] Export completed: \(format.displayName)")
            // ExportOptionsModal handles the actual export, ShareSheet, and user feedback
            // No additional action needed here
        }
    }
    
    // MARK: - CRITICAL: Professional Bridge Conversion Functions
    
    private func convertToReorderItem(_ swiftDataItem: ReorderItemModel) -> ReorderItem {
        // Professional conversion: SwiftData → ReorderItem for UI compatibility
        
        var reorderItem = ReorderItem(
            id: swiftDataItem.id,
            itemId: swiftDataItem.itemId,
            name: swiftDataItem.name,
            sku: swiftDataItem.sku,
            barcode: swiftDataItem.barcode,
            variationName: swiftDataItem.variationName,
            quantity: swiftDataItem.quantity,
            status: swiftDataItem.statusEnum,
            addedDate: swiftDataItem.addedDate,
            notes: swiftDataItem.notes
        )
        
        // Set additional properties that aren't in the constructor
        reorderItem.categoryName = swiftDataItem.categoryName
        reorderItem.vendor = swiftDataItem.vendor
        reorderItem.unitCost = swiftDataItem.unitCost
        reorderItem.caseUpc = swiftDataItem.caseUpc
        reorderItem.caseCost = swiftDataItem.caseCost
        reorderItem.caseQuantity = swiftDataItem.caseQuantity
        reorderItem.price = swiftDataItem.price
        reorderItem.imageUrl = swiftDataItem.imageUrl
        reorderItem.imageId = swiftDataItem.imageId
        reorderItem.hasTax = swiftDataItem.hasTax
        reorderItem.priority = swiftDataItem.priorityEnum
        reorderItem.purchasedDate = swiftDataItem.purchasedDate
        reorderItem.receivedDate = swiftDataItem.receivedDate
        
        return reorderItem
    }
}

// NOTE: Using original ReordersSheet enum from ReordersView.swift - no need to redefine