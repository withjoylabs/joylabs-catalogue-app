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
        print("🚨 DEBUG: QuantityModalStateManager - Set item: \(item.name ?? "Unknown"), qty: \(quantity), existing: \(isExisting)")
    }

    func showModal() {
        modalJustPresented = true
        showingQuantityModal = true
        print("🚨 DEBUG: QuantityModalStateManager - Modal shown")

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
        print("🚨 DEBUG: QuantityModalStateManager - State cleared")
    }
}

// MARK: - Global Barcode Receiving UIViewController
class GlobalBarcodeReceivingViewController: UIViewController {
    var onBarcodeScanned: ((String) -> Void)?

    // Barcode accumulation
    private var barcodeBuffer = ""
    private var barcodeTimer: Timer?
    private let barcodeTimeout: TimeInterval = 0.1 // 100ms timeout for barcode completion

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // CRITICAL: Become first responder to receive global keyboard input
        becomeFirstResponder()
        print("🎯 Global barcode receiver became first responder")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
        print("🎯 Global barcode receiver resigned first responder")
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Numbers 0-9 (most common in barcodes)
        for i in 0...9 {
            commands.append(UIKeyCommand(
                input: "\(i)",
                modifierFlags: [],
                action: #selector(handleBarcodeCharacter(_:))
            ))
        }

        // Letters A-Z (some barcodes include letters)
        for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleBarcodeCharacter(_:))
            ))
        }

        // Lowercase letters a-z
        for char in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleBarcodeCharacter(_:))
            ))
        }

        // Special characters common in barcodes
        let specialChars = ["-", "_", ".", " ", "/", "\\", "+", "=", "*", "%", "$", "#", "@", "!", "?"]
        for char in specialChars {
            commands.append(UIKeyCommand(
                input: char,
                modifierFlags: [],
                action: #selector(handleBarcodeCharacter(_:))
            ))
        }

        // Return key (end of barcode scan)
        commands.append(UIKeyCommand(
            input: "\r",
            modifierFlags: [],
            action: #selector(handleBarcodeComplete)
        ))

        // Enter key (alternative end of barcode)
        commands.append(UIKeyCommand(
            input: "\n",
            modifierFlags: [],
            action: #selector(handleBarcodeComplete)
        ))

        return commands
    }

    @objc private func handleBarcodeCharacter(_ command: UIKeyCommand) {
        guard let input = command.input else { return }

        // Add character to buffer
        barcodeBuffer += input
        // Reduced logging: only log first character to indicate scan started
        if barcodeBuffer.count == 1 {
            print("🔤 Global barcode scan started...")
        }

        // Reset completion timer
        barcodeTimer?.invalidate()
        barcodeTimer = Timer.scheduledTimer(withTimeInterval: barcodeTimeout, repeats: false) { [weak self] _ in
            self?.completeBarcodeInput()
        }
    }

    @objc private func handleBarcodeComplete() {
        print("🔚 Global barcode complete signal received")
        completeBarcodeInput()
    }

    private func completeBarcodeInput() {
        guard !barcodeBuffer.isEmpty else { return }

        let finalBarcode = barcodeBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ Global barcode completed: '\(finalBarcode)'")

        // Clear buffer
        barcodeBuffer = ""
        barcodeTimer?.invalidate()

        // Send to callback
        DispatchQueue.main.async {
            self.onBarcodeScanned?(finalBarcode)
        }
    }

    // Enhanced key handling for better HID device support
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                let characters = key.characters
                // Reduced logging: only log if this is fallback handling

                // Handle any characters not caught by keyCommands
                if !characters.isEmpty {
                    // Check if this is likely from an external device
                    if event?.allPresses.first?.gestureRecognizers?.isEmpty == true {
                        // Add to buffer if not already handled by keyCommands
                        if !barcodeBuffer.hasSuffix(characters) {
                            if barcodeBuffer.isEmpty {
                                print("🔌 External device fallback handling started...")
                            }
                            barcodeBuffer += characters

                            // Reset completion timer
                            barcodeTimer?.invalidate()
                            barcodeTimer = Timer.scheduledTimer(withTimeInterval: barcodeTimeout, repeats: false) { [weak self] _ in
                                self?.completeBarcodeInput()
                            }
                        }
                    }
                }
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

// MARK: - SwiftUI Wrapper for Global Barcode Receiver
struct GlobalBarcodeReceiver: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> GlobalBarcodeReceivingViewController {
        let controller = GlobalBarcodeReceivingViewController()
        controller.onBarcodeScanned = onBarcodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: GlobalBarcodeReceivingViewController, context: Context) {
        uiViewController.onBarcodeScanned = onBarcodeScanned
    }
}

struct ReordersView: SwiftUI.View {
    @StateObject private var viewModel = ReorderViewModel()
    @StateObject private var barcodeManager = ReorderBarcodeScanningManager(searchManager: SearchManager(databaseManager: SquareAPIServiceFactory.createDatabaseManager()))
    @StateObject private var dataManager = ReorderDataManager()
    @StateObject private var notificationManager = ReorderNotificationManager()
    
    @FocusState private var isScannerFieldFocused: Bool

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

                // CRITICAL: Global barcode receiver (invisible, handles external keyboard input)
                GlobalBarcodeReceiver { barcode in
                    print("🌍 Global barcode received: '\(barcode)'")
                    barcodeManager.handleGlobalBarcodeScanned(barcode)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            }
            .navigationBarHidden(true)
            .onAppear {
                setupViewModels()
                viewModel.loadReorderData()
            }
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
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.itemId),
                    onDismiss: {
                        viewModel.dismissActiveSheet()
                    },
                    onSave: { itemData in
                        viewModel.dismissActiveSheet()
                        viewModel.loadReorderData() // Refresh data after edit
                    }
                )
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