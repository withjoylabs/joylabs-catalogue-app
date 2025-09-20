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
    
    // PERFORMANCE FIX: Cache converted items to prevent expensive recomputation
    @State private var cachedBridgedItems: [ReorderItem] = []
    @State private var cachedStats: (total: Int, unpurchased: Int, purchased: Int, quantity: Int) = (0, 0, 0, 0)
    @State private var lastReorderItemsCount: Int = 0
    
    // Scanner state
    @State private var scannerSearchText = ""
    @FocusState private var isScannerFieldFocused: Bool
    
    // RESTORED: Professional Quantity Modal State Management
    @StateObject private var modalStateManager = QuantityModalStateManager()
    @State private var currentModalQuantity: Int = 1
    
    // Barcode scanning manager
    @StateObject private var barcodeManager = ReorderBarcodeScanningManager(searchManager: SwiftDataSearchManager(databaseManager: SquareAPIServiceFactory.createDatabaseManager()))
    
    // Binding for focus state to pass up to ContentView
    let onFocusStateChanged: ((Bool) -> Void)?
    
    // Default initializer
    init(onFocusStateChanged: ((Bool) -> Void)? = nil) {
        self.onFocusStateChanged = onFocusStateChanged
    }
    
    // MARK: - Professional Bridge: SwiftData → ReorderItem Conversion
    private var bridgedReorderItems: [ReorderItem] {
        // PERFORMANCE: Return cached items instead of converting every access
        return cachedBridgedItems
    }
    
    // Update cache when source data changes
    private func updateCachedBridgedItems() {
        // Only update if items actually changed
        if reorderItems.count != lastReorderItemsCount {
            // PERFORMANCE OPTIMIZATION: Use batch conversion to reduce database queries
            cachedBridgedItems = convertToReorderItemsBatch(reorderItems)
            lastReorderItemsCount = reorderItems.count
            
            // PERFORMANCE: Also update stats cache in single pass
            updateCachedStats()
        }
    }
    
    // Force update cache regardless of count changes (for property changes like status updates)
    private func forceUpdateCachedBridgedItems() {
        // FIX: Always update cache when individual item properties change
        cachedBridgedItems = convertToReorderItemsBatch(reorderItems)
        lastReorderItemsCount = reorderItems.count
        
        // Update stats cache to reflect status changes
        updateCachedStats()
        
        print("🔄 [ReordersViewSwiftData] Force updated cached bridged items due to property changes")
    }
    
    private func updateCachedStats() {
        var total = 0
        var unpurchased = 0
        var purchased = 0
        var quantity = 0
        
        for item in cachedBridgedItems {
            total += 1
            quantity += item.quantity
            
            switch item.status {
            case .added:
                unpurchased += 1
            case .purchased, .received:
                purchased += 1
            }
        }
        
        cachedStats = (total, unpurchased, purchased, quantity)
    }
    
    // MARK: - Computed Properties (Professional Implementation Restored)
    // PERFORMANCE: Use cached stats instead of recomputing
    var totalItems: Int { cachedStats.total }
    var unpurchasedItems: Int { cachedStats.unpurchased }
    var purchasedItems: Int { cachedStats.purchased }
    var totalQuantity: Int { cachedStats.quantity }
    
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
                // Break up the complex initializer to help type checker
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
                    onImageTap: handleImageTap,
                    onImageLongPress: showImagePicker,
                    onQuantityTap: showQuantityModal,
                    onItemDetailsLongPress: showItemDetails
                )
            }
        }
        .onAppear {
            setupServices()
            // PERFORMANCE: Initialize cache on appear
            updateCachedBridgedItems()
        }
        .onChange(of: reorderItems.count) { _, _ in
            // PERFORMANCE: Update cache when item count changes
            updateCachedBridgedItems()
        }
        .onChange(of: reorderItems) { _, _ in
            // FIX: Update cache when individual item properties change (status, quantity, etc.)
            forceUpdateCachedBridgedItems()
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
                    .quantityModal()
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
        
        // FIX: Force immediate cache refresh to ensure UI updates instantly
        // The onChange(of: reorderItems) will also trigger, but this ensures immediate response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.forceUpdateCachedBridgedItems()
        }
        
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

    private func handleImageTap(_ item: ReorderItem) {
        print("[ReordersViewSwiftData] Image tapped for item: \(item.name)")
    }

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
    
    /// Batch conversion method that pre-fetches all catalog data to avoid N+1 queries
    private func convertToReorderItemsBatch(_ swiftDataItems: [ReorderItemModel]) -> [ReorderItem] {
        guard !swiftDataItems.isEmpty else { return [] }
        
        // PERFORMANCE: Collect all unique catalog item IDs for batch lookup
        let catalogItemIds = Array(Set(swiftDataItems.map { $0.catalogItemId }))
        
        // PERFORMANCE: Batch fetch all catalog items needed in one query
        let catalogItems = CatalogLookupService.shared.getItems(ids: catalogItemIds)
        let catalogItemsDict = Dictionary(uniqueKeysWithValues: catalogItems.map { ($0.id, $0) })
        
        // Convert all items using pre-fetched catalog data
        return swiftDataItems.map { swiftDataItem in
            convertToReorderItemWithCatalogData(swiftDataItem, catalogItem: catalogItemsDict[swiftDataItem.catalogItemId])
        }
    }
    
    /// Convert single item using pre-fetched catalog data (eliminates computed property database calls)
    private func convertToReorderItemWithCatalogData(_ swiftDataItem: ReorderItemModel, catalogItem: CatalogItemModel?) -> ReorderItem {
        var reorderItem = ReorderItem(
            id: swiftDataItem.id,
            itemId: swiftDataItem.catalogItemId,
            name: swiftDataItem.nameOverride ?? catalogItem?.name ?? "Unknown Item",
            sku: catalogItem?.variations?.first(where: { !$0.isDeleted })?.sku,
            barcode: catalogItem?.variations?.first(where: { !$0.isDeleted })?.upc,
            variationName: catalogItem?.variations?.first(where: { !$0.isDeleted })?.name,
            quantity: swiftDataItem.quantity,
            status: swiftDataItem.statusEnum,
            addedDate: swiftDataItem.addedDate,
            notes: swiftDataItem.notes
        )
        
        // Set additional properties from catalog data (not computed properties)
        reorderItem.categoryName = catalogItem?.reportingCategoryName ?? catalogItem?.categoryName
        reorderItem.vendor = nil  // Team data not implemented yet
        reorderItem.unitCost = nil  // Team data not implemented yet  
        reorderItem.caseUpc = nil  // Team data not implemented yet
        reorderItem.caseCost = nil  // Team data not implemented yet
        reorderItem.caseQuantity = nil  // Team data not implemented yet
        
        // Calculate price from variation data directly
        if let variation = catalogItem?.variations?.first(where: { !$0.isDeleted }),
           let priceAmount = variation.priceAmount, priceAmount > 0 {
            let convertedPrice = Double(priceAmount) / 100.0
            reorderItem.price = convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
        }
        
        // Get image URL from catalog data directly
        reorderItem.imageUrl = catalogItem?.primaryImageUrl
        reorderItem.imageId = nil  // Not stored directly, use imageUrl
        
        // Calculate tax status from catalog data directly
        reorderItem.hasTax = (catalogItem?.taxes?.count ?? 0) > 0
        
        reorderItem.priority = swiftDataItem.priorityEnum
        reorderItem.purchasedDate = swiftDataItem.purchasedDate
        reorderItem.receivedDate = swiftDataItem.receivedDate
        
        return reorderItem
    }
    
    private func convertToReorderItem(_ swiftDataItem: ReorderItemModel) -> ReorderItem {
        // Professional conversion: SwiftData → ReorderItem for UI compatibility
        
        var reorderItem = ReorderItem(
            id: swiftDataItem.id,
            itemId: swiftDataItem.catalogItemId,  // Updated field name
            name: swiftDataItem.name,
            sku: swiftDataItem.sku,
            barcode: swiftDataItem.barcode,
            variationName: swiftDataItem.variationName,
            quantity: swiftDataItem.quantity,
            status: swiftDataItem.statusEnum,
            addedDate: swiftDataItem.addedDate,
            notes: swiftDataItem.notes
        )
        
        // Set additional properties from computed properties
        reorderItem.categoryName = swiftDataItem.categoryName
        reorderItem.vendor = nil  // Team data not implemented yet
        reorderItem.unitCost = nil  // Team data not implemented yet  
        reorderItem.caseUpc = nil  // Team data not implemented yet
        reorderItem.caseCost = nil  // Team data not implemented yet
        reorderItem.caseQuantity = nil  // Team data not implemented yet
        reorderItem.price = swiftDataItem.price
        reorderItem.imageUrl = swiftDataItem.imageUrl
        reorderItem.imageId = nil  // Not stored directly, use imageUrl
        reorderItem.hasTax = swiftDataItem.hasTax
        reorderItem.priority = swiftDataItem.priorityEnum
        reorderItem.purchasedDate = swiftDataItem.purchasedDate
        reorderItem.receivedDate = swiftDataItem.receivedDate
        
        return reorderItem
    }
}

// NOTE: Using original ReordersSheet enum from ReordersView.swift - no need to redefine