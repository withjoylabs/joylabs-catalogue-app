import SwiftUI
import UIKit

enum ReordersSheet: Identifiable {
    case itemDetails(ReorderItem)
    case quantityModal(SearchResultItem)

    var id: String {
        switch self {
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
    @StateObject private var barcodeManager = ReorderBarcodeScanningManager(searchManager: SwiftDataSearchManager(databaseManager: SquareAPIServiceFactory.createDatabaseManager()))
    @StateObject private var dataManager = ReorderDataManager()
    // NOTE: Notification handling is now centralized in CentralItemUpdateManager
    // Remove focus monitor - using direct focus state instead
    
    @FocusState private var isScannerFieldFocused: Bool
    @State private var showingImagePicker = false
    @State private var imagePickerItem: ReorderItem?
    @State private var enlargementItem: ReorderItem?
    @State private var showingEnlargement = false

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
                    selectedCategories: $viewModel.selectedCategories,
                    availableCategories: viewModel.availableCategories,
                    scannerSearchText: $barcodeManager.scannerSearchText,
                    isScannerFieldFocused: $isScannerFieldFocused,
                    onManagementAction: viewModel.handleManagementAction,
                    onExportTap: { viewModel.showingExportModal = true },
                    onStatusChange: viewModel.updateItemStatus,
                    onQuantityChange: viewModel.updateItemQuantity,
                    onRemoveItem: viewModel.removeItem,
                    onBarcodeScanned: barcodeManager.handleBarcodeScanned,
                    onImageTap: { item in
                        enlargementItem = item
                        showingEnlargement = true
                    },
                    onImageLongPress: { item in
                        imagePickerItem = item
                        showingImagePicker = true
                    },
                    onQuantityTap: viewModel.showQuantityModal,
                    onItemDetailsLongPress: viewModel.showItemDetails
                )

            }
        }
        .onAppear {
            setupViewModels()
            viewModel.loadReorderDataIfNeeded()  // Only loads on first appearance, not tab switches
        }
        .onChange(of: isScannerFieldFocused) { oldValue, newValue in
            // Notify ContentView of focus state changes for AppLevelHIDScanner
            onFocusStateChanged?(newValue)
        }
        .onChange(of: viewModel.sortOption) { _, _ in viewModel.saveFilterPreferences() }
        .onChange(of: viewModel.filterOption) { _, _ in viewModel.saveFilterPreferences() }
        .onChange(of: viewModel.organizationOption) { _, _ in viewModel.saveFilterPreferences() }
        .onChange(of: viewModel.displayMode) { _, _ in viewModel.saveFilterPreferences() }
        .onChange(of: viewModel.selectedCategories) { _, _ in viewModel.saveFilterPreferences() }
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
            // Export Options Modal
            .sheet(isPresented: $viewModel.showingExportModal) {
            ExportOptionsModal(
                isPresented: $viewModel.showingExportModal,
                items: viewModel.reorderItems,
                onExport: { format in
                    await viewModel.handleExportSelection(format)
                }
            )
            .nestedComponentModal()
        }
        // Unified Sheet Modal
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.itemId),
                    onDismiss: {
                        viewModel.dismissActiveSheet()
                    },
                    onSave: { itemData in
                        viewModel.dismissActiveSheet()
                        // NOTE: Item updates are handled automatically by CentralItemUpdateManager 
                        // via catalogSyncCompleted notifications. No manual refresh needed.
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
                    .quantityModal()
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            if let item = imagePickerItem {
                UnifiedImagePickerModal(
                    context: .reordersViewLongPress(
                        itemId: item.itemId,
                        imageId: item.imageId
                    ),
                    onDismiss: {
                        showingImagePicker = false
                        imagePickerItem = nil
                    },
                    onImageUploaded: { result in
                        showingImagePicker = false
                        imagePickerItem = nil
                    }
                )
                .imagePickerFormSheet()
            }
        }
        .sheet(isPresented: $showingEnlargement) {
            if let item = enlargementItem, let imageId = item.imageId {
                ImagePreviewModal(
                    imageId: imageId,
                    isPrimary: true,
                    onDelete: nil,
                    onDismiss: { showingEnlargement = false }
                )
            }
        }
    }

    // MARK: - Setup
    private func setupViewModels() {
        barcodeManager.setViewModel(viewModel)
        dataManager.setViewModel(viewModel)
        
        // Setup centralized item update manager with ReordersView services
        // This ensures the global service can update this view's data
        CentralItemUpdateManager.shared.setup(
            searchManager: barcodeManager.searchManager, // ReordersView's SearchManager for barcode scanning
            reorderDataManager: dataManager,
            reorderBarcodeManager: barcodeManager,
            viewName: "ReordersView"
        )
    }
}

#Preview {
    ReordersView()
}