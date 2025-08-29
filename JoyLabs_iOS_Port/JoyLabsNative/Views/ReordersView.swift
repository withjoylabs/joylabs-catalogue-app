import SwiftUI
import UIKit

enum ReordersSheet: Identifiable {
    case imagePicker(ReorderItem)
    case itemDetails(ReorderItem)
    case quantityModal(SearchResultItem)
    
    var id: String {
        switch self {
        case .imagePicker(let item):
            return "imagePicker_\(item.itemId)"
        case .itemDetails(let item):
            return "itemDetails_\(item.itemId)"
        case .quantityModal(let item):
            return "quantityModal_\(item.id)"
        }
    }
}

// MARK: - Quantity Modal State Manager (Industry Standard Solution)
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

// MARK: - Legacy scanner removed - now using SharedHIDScanner

struct ReordersView: SwiftUI.View {
    @StateObject private var viewModel = ReorderViewModel()
    @StateObject private var barcodeManager = ReorderBarcodeScanningManager(searchManager: SearchManager(databaseManager: SquareAPIServiceFactory.createDatabaseManager()))
    @StateObject private var dataManager = ReorderDataManager()
    @StateObject private var notificationManager = ReorderNotificationManager()
    // Remove focus monitor - using direct focus state instead
    
    @FocusState private var isScannerFieldFocused: Bool
    
    // Binding for focus state to pass up to ContentView
    let onFocusStateChanged: ((Bool) -> Void)?
    
    // Default initializer for standalone use (like previews)
    init(onFocusStateChanged: ((Bool) -> Void)? = nil) {
        self.onFocusStateChanged = onFocusStateChanged
    }
    

    var body: some SwiftUI.View {
        NavigationStack {
            ZStack {
                // Main reorder content
                ReorderContentView(
                    reorderItems: viewModel.reorderItems,
                    filteredItems: viewModel.filteredItems,
                    organizedItems: viewModel.organizedItems,
                    totalItems: viewModel.totalItems,
                    unpurchasedItems: viewModel.unpurchasedItems,
                    purchasedItems: viewModel.purchasedItems,
                    totalQuantity: viewModel.totalQuantity,
                    sortOption: $viewModel.sortOption,
                    filterOption: $viewModel.filterOption,
                    organizationOption: $viewModel.organizationOption,
                    displayMode: $viewModel.displayMode,
                    scannerSearchText: $barcodeManager.scannerSearchText,
                    isScannerFieldFocused: $isScannerFieldFocused,
                    onManagementAction: viewModel.handleManagementAction,
                    onExportTap: { viewModel.showingExportModal = true },
                    onStatusChange: viewModel.updateItemStatus,
                    onQuantityChange: viewModel.updateItemQuantity,
                    onRemoveItem: viewModel.removeItem,
                    onBarcodeScanned: barcodeManager.handleBarcodeScanned,
                    onImageTap: { item in
                        print("[ReordersView] Image tapped for item: \(item.name)")
                    },
                    onImageLongPress: viewModel.showImagePicker,
                    onQuantityTap: viewModel.showQuantityModal,
                    onItemDetailsLongPress: viewModel.showItemDetails
                )

            }
        }
        .onAppear {
            setupViewModels()
            viewModel.loadReorderData()
        }
        .onChange(of: isScannerFieldFocused) { oldValue, newValue in
            // Notify ContentView of focus state changes for AppLevelHIDScanner
            onFocusStateChanged?(newValue)
        }
        // No visible text fields to track in ReordersView
        .alert("Clear All Items", isPresented: $viewModel.showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    viewModel.clearAllItems()
                }
            } message: {
                Text("Are you sure you want to clear all reorder items? This action cannot be undone.")
            }
            .alert("Mark All as Received", isPresented: $viewModel.showingMarkAllReceivedAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Mark All") {
                    viewModel.markAllAsReceived()
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
            .onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { notification in
                // Refresh reorder data when catalog sync completes (handles deleted items)
                viewModel.loadReorderData()
                
                // Check if this was a delete operation
                if let userInfo = notification.userInfo,
                   let operation = userInfo["operation"] as? String,
                   operation == "delete" {
                    // Optional: Could show a toast here if an item was removed from reorder list
                }
            }
            // Export Options Modal
            .sheet(isPresented: $viewModel.showingExportModal) {
            ExportOptionsModal(
                isPresented: $viewModel.showingExportModal,
                items: viewModel.reorderItems,
                onExport: { format in
                    await viewModel.handleExportSelection(format)
                }
            )
            .imagePickerModal()
        }
        // Unified Sheet Modal
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .imagePicker(let item):
                UnifiedImagePickerModal(
                    context: .reordersViewLongPress(
                        itemId: item.itemId,
                        imageId: item.imageId
                    ),
                    onDismiss: {
                        viewModel.dismissActiveSheet()
                    },
                    onImageUploaded: { result in
                        viewModel.dismissActiveSheet()
                    }
                )
                .imagePickerModal()
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.itemId),
                    onDismiss: {
                        viewModel.dismissActiveSheet()
                    },
                    onSave: { itemData in
                        viewModel.dismissActiveSheet()
                        viewModel.loadReorderData() // Refresh reorder data after edit
                        
                        // CRITICAL: Also refresh any active search results
                        if let currentTerm = viewModel.searchManager.currentSearchTerm {
                            SearchRefreshService.shared.refreshSearchAfterSave(
                                with: currentTerm,
                                searchManager: viewModel.searchManager
                            )
                        }
                    }
                )
                .fullScreenModal()
            case .quantityModal(_):
                if let selectedItem = viewModel.modalStateManager.selectedItemForQuantity {
                    EmbeddedQuantitySelectionModal(
                        item: selectedItem,
                        currentQuantity: viewModel.modalStateManager.modalQuantity,
                        isExistingItem: viewModel.modalStateManager.isExistingItem,
                        isPresented: .constant(true),
                        onSubmit: { quantity in
                            viewModel.handleQuantityModalSubmit(quantity)
                        },
                        onCancel: {
                            viewModel.handleQuantityModalCancel()
                        },
                        onQuantityChange: { newQuantity in
                            viewModel.currentModalQuantity = newQuantity
                        }
                    )
                    .imagePickerModal()
                }
            }
        }
    }
    
    // MARK: - Setup
    private func setupViewModels() {
        barcodeManager.setViewModel(viewModel)
        dataManager.setViewModel(viewModel)
        notificationManager.setup(dataManager: dataManager, barcodeManager: barcodeManager)
    }
}

#Preview {
    ReordersView()
}