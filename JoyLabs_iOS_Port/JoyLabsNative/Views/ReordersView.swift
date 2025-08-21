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
    
    // Computed property to track if any modal is presented
    private var isAnyModalPresented: Bool {
        return viewModel.activeSheet != nil || 
               viewModel.showingExportOptions || 
               viewModel.showingClearAlert || 
               viewModel.showingMarkAllReceivedAlert
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

                // CRITICAL: App-level HID scanner using UIKeyCommand (no TextField, no keyboard issues)
                AppLevelHIDScanner(
                    onBarcodeScanned: { barcode, context in
                        print("🌍 App-level HID scanner received barcode: '\(barcode)' in context: \(context)")
                        if context == .reordersView {
                            barcodeManager.handleGlobalBarcodeScanned(barcode)
                        }
                    },
                    context: .reordersView,
                    isTextFieldFocused: false,  // No visible text fields in ReordersView
                    isModalPresented: isAnyModalPresented
                )
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            }
            .navigationBarHidden(true)
            .onAppear {
                setupViewModels()
                viewModel.loadReorderData()
            }
            // No visible text fields to track in ReordersView
            .actionSheet(isPresented: $viewModel.showingExportOptions) {
                ActionSheet(
                    title: Text("Export Reorders"),
                    buttons: [
                        .default(Text("Share List")) { viewModel.shareList() },
                        .default(Text("Print")) { viewModel.printList() },
                        .default(Text("Save as PDF")) { viewModel.saveAsPDF() },
                        .cancel()
                    ]
                )
            }
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