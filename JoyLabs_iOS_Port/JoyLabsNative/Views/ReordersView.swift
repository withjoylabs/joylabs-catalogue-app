import SwiftUI
import UIKit

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

struct ReordersView: View {
    @State private var reorderItems: [ReorderItem] = []
    @State private var showingExportOptions = false
    @State private var showingClearAlert = false
    @State private var showingMarkAllReceivedAlert = false

    // Filter and sort state
    @State private var sortOption: ReorderSortOption = .timeNewest
    @State private var filterOption: ReorderFilterOption = .all


    // View organization and display options
    @State private var organizationOption: ReorderOrganizationOption = .none
    @State private var displayMode: ReorderDisplayMode = .list

    // Image enlargement
    @State private var selectedItemForEnlargement: ReorderItem?
    @State private var showingImageEnlargement = false

    // Barcode scanner state
    @State private var scannerSearchText = ""
    @FocusState private var isScannerFieldFocused: Bool
    @State private var searchDebounceTimer: Timer?

    // Barcode processing queue
    @State private var barcodeQueue: [String] = []
    @State private var isProcessingBarcode = false

    // Quantity selection modal state - INDUSTRY STANDARD SOLUTION
    @StateObject private var modalStateManager = QuantityModalStateManager()

    // Search manager (same as scan page)
    @StateObject private var searchManager: SearchManager = {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SearchManager(databaseManager: databaseManager)
    }()

    // Database service for reorder items (TODO: Implement database integration)
    // @StateObject private var reorderDatabase: ReorderDatabaseService = {
    //     let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
    //     return ReorderDatabaseService(database: databaseManager.database)
    // }()

    // Computed properties for stats
    private var totalItems: Int { reorderItems.count }
    private var unpurchasedItems: Int { reorderItems.filter { $0.status == .added }.count }
    private var purchasedItems: Int { reorderItems.filter { $0.status == .purchased || $0.status == .received }.count }
    private var totalQuantity: Int { reorderItems.reduce(0) { $0 + $1.quantity } }

    // Filtered and sorted items
    private var filteredItems: [ReorderItem] {
        let filtered = reorderItems.filter { item in
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

    // Organized items for sectioned display
    private var organizedItems: [(String, [ReorderItem])] {
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

    var body: some View {
        NavigationView {
            ZStack {
                // Main reorder content
                ReorderContentView(
                    reorderItems: reorderItems,
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
                    scannerSearchText: $scannerSearchText,
                    isScannerFieldFocused: $isScannerFieldFocused,
                    onManagementAction: handleManagementAction,
                    onStatusChange: updateItemStatus,
                    onQuantityChange: updateItemQuantity,
                    onRemoveItem: removeItem,
                    onBarcodeScanned: handleBarcodeScanned,
                    onImageTap: { item in
                        // TODO: Implement image enlargement when ImageEnlargementView is added to project
                        print("🖼️ Image tapped for item: \(item.name)")
                    },
                    onQuantityTap: showQuantityModalForItem
                )

                // CRITICAL: Global barcode receiver (invisible, handles external keyboard input)
                GlobalBarcodeReceiver { barcode in
                    print("🌍 Global barcode received: '\(barcode)'")
                    handleGlobalBarcodeScanned(barcode)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadReorderData()
                // Auto-focus removed - user can manually tap to focus
            }
            // TODO: Add ImageEnlargementView when file is properly included in Xcode project
            // .sheet(isPresented: $showingImageEnlargement) {
            //     if let item = selectedItemForEnlargement {
            //         ImageEnlargementView(item: item, isPresented: $showingImageEnlargement)
            //     }
            // }
            .actionSheet(isPresented: $showingExportOptions) {
                ActionSheet(
                    title: Text("Export Reorders"),
                    buttons: [
                        .default(Text("Share List")) { shareList() },
                        .default(Text("Print")) { printList() },
                        .default(Text("Save as PDF")) { saveAsPDF() },
                        .cancel()
                    ]
                )
            }
            .alert("Clear All Items", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllItems()
                }
            } message: {
                Text("Are you sure you want to clear all reorder items? This action cannot be undone.")
            }
            .alert("Mark All as Received", isPresented: $showingMarkAllReceivedAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Mark All") {
                    markAllAsReceived()
                }
            } message: {
                Text("Mark all items as received? This will move them to the received state.")
            }

        }
        // Quantity Selection Modal (INDUSTRY STANDARD SOLUTION)
        .sheet(isPresented: $modalStateManager.showingQuantityModal, onDismiss: handleQuantityModalDismiss) {
            if let item = modalStateManager.selectedItemForQuantity {
                EmbeddedQuantitySelectionModal(
                    item: item,
                    currentQuantity: modalStateManager.modalQuantity,
                    isExistingItem: modalStateManager.isExistingItem,
                    isPresented: $modalStateManager.showingQuantityModal,
                    onSubmit: handleQuantityModalSubmit,
                    onCancel: handleQuantityModalCancel
                )
                .presentationDetents([.fraction(0.75)])
                .presentationDragIndicator(.visible)
                .onAppear {
                    print("🚨 DEBUG: Sheet presentation triggered! Using StateObject item: \(item.name ?? "Unknown")")
                }
            } else {
                Text("Error: No item selected")
                    .onAppear {
                        print("🚨 DEBUG: ERROR - StateObject selectedItemForQuantity is nil!")
                    }
            }
        }
    }

    // MARK: - Data Management

    private func loadReorderData() {
        // Load reorder items from UserDefaults for persistence
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            reorderItems = items
            print("📦 Loaded \(items.count) reorder items from storage")
        } else {
            reorderItems = []
            print("📦 No saved reorder items found")
        }
    }

    private func saveReorderData() {
        // Save reorder items to UserDefaults for persistence
        if let data = try? JSONEncoder().encode(reorderItems) {
            UserDefaults.standard.set(data, forKey: "reorderItems")
            print("💾 Saved \(reorderItems.count) reorder items to storage")
        }
    }

    // MARK: - Management Actions

    private func handleManagementAction(_ action: ManagementAction) {
        switch action {
        case .markAllReceived:
            showingMarkAllReceivedAlert = true
        case .clearAll:
            showingClearAlert = true
        case .export:
            showingExportOptions = true
        }
    }

    private func markAllAsReceived() {
        // Mark all items as received (which removes them from the list)
        for item in reorderItems {
            updateItemStatus(itemId: item.id, newStatus: .received)
        }
    }

    private func clearAllItems() {
        reorderItems.removeAll()
        saveReorderData()
    }

    // MARK: - Item Actions

    private func removeItem(itemId: String) {
        if let item = reorderItems.first(where: { $0.id == itemId }) {
            reorderItems.removeAll { $0.id == itemId }
            saveReorderData()
            print("🗑️ Removed item from reorder list: \(item.name)")
        }
    }

    private func updateItemStatus(itemId: String, newStatus: ReorderStatus) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            if newStatus == .received {
                // When item is marked as received, remove it from the list
                reorderItems[index].receivedDate = Date()
                reorderItems.remove(at: index)
                print("✅ Item marked as received and removed from list")
            } else {
                // Update status for added/purchased
                reorderItems[index].status = newStatus

                switch newStatus {
                case .purchased:
                    reorderItems[index].purchasedDate = Date()
                case .added:
                    reorderItems[index].purchasedDate = nil
                    reorderItems[index].receivedDate = nil
                case .received:
                    // This case is handled above
                    break
                }
            }

            saveReorderData()
        }
    }

    private func updateItemQuantity(itemId: String, newQuantity: Int) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            reorderItems[index].quantity = max(1, newQuantity)
            saveReorderData()
        }
    }

    // MARK: - Export Functions

    private func shareList() {
        // Share functionality using iOS share sheet
        print("Sharing list...")
    }

    private func printList() {
        // Print functionality
        print("Printing list...")
    }

    private func saveAsPDF() {
        // PDF export functionality
        print("Saving as PDF...")
    }

    // MARK: - Search Functions (using same path as scan page)

    // Removed debounced search - only barcode scanning on return key press

    private func handleBarcodeScanned(_ barcode: String) {
        print("🔍 Barcode input received from text field: \(barcode)")

        // DUPLICATE PREVENTION: Check if this barcode is already in queue
        if barcodeQueue.contains(barcode) {
            print("⚠️ DUPLICATE BARCODE DETECTED - Ignoring text field input: \(barcode)")
            scannerSearchText = ""
            return
        }

        // Add barcode to processing queue
        barcodeQueue.append(barcode)
        print("📥 Added barcode to queue: \(barcode) (Queue size: \(barcodeQueue.count))")

        // Clear the search field immediately for next scan
        scannerSearchText = ""

        // Process queue if not already processing
        if !isProcessingBarcode {
            processNextBarcodeInQueue()
        }
    }

    private func handleGlobalBarcodeScanned(_ barcode: String) {
        print("🌍 Global barcode input received (NO FOCUS REQUIRED): \(barcode)")

        // DUPLICATE PREVENTION: Check if this barcode is already in queue
        if barcodeQueue.contains(barcode) {
            print("⚠️ DUPLICATE BARCODE DETECTED - Ignoring global input: \(barcode)")
            return
        }

        // Add barcode to processing queue (same as text field input)
        barcodeQueue.append(barcode)
        print("📥 Added global barcode to queue: \(barcode) (Queue size: \(barcodeQueue.count))")

        // Process queue if not already processing
        if !isProcessingBarcode {
            processNextBarcodeInQueue()
        }
    }

    private func processNextBarcodeInQueue() {
        guard !barcodeQueue.isEmpty && !isProcessingBarcode else { return }

        isProcessingBarcode = true
        let barcodeToProcess = barcodeQueue.removeFirst()

        print("🔄 Processing barcode from queue: \(barcodeToProcess) (Remaining in queue: \(barcodeQueue.count))")

        // CRITICAL FIX: Clear search manager state to ensure fresh search with offset 0
        searchManager.clearSearch()

        // Use EXACT same pattern as scan page - immediate search without debounce for barcode scans
        Task {
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            let results = await searchManager.performSearch(searchTerm: barcodeToProcess, filters: filters)

            // Process results immediately (same performance as scan page)
            await MainActor.run {
                print("🔍 Search results count: \(results.count)")
                if let foundItem = results.first {
                    print("🔍 Found item: \(foundItem.name ?? "Unknown") - calling showQuantityModalForItem")
                    // NEW LOGIC: Show quantity modal instead of directly adding
                    showQuantityModalForItem(foundItem)
                } else {
                    print("❌ No item found for barcode: \(barcodeToProcess)")
                    // Mark processing complete for failed searches
                    isProcessingBarcode = false

                    // Process next barcode in queue if any
                    if !barcodeQueue.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            processNextBarcodeInQueue()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quantity Modal Logic

    private func showQuantityModalForItem(_ foundItem: SearchResultItem) {
        print("� DEBUG: showQuantityModalForItem() called for: \(foundItem.name ?? "Unknown Item")")
        print("🚨 DEBUG: Current modal state: showing=\(modalStateManager.showingQuantityModal), item=\(modalStateManager.selectedItemForQuantity?.name ?? "nil")")

        // CRITICAL FIX: Set item data FIRST, then show modal
        // This prevents blank modal from appearing when selectedItemForQuantity is nil

        // Set the selected item FIRST
        // Will be set via modalStateManager.setItem() below
        print("🚨 DEBUG: Set selectedItemForQuantity to: \(foundItem.name ?? "Unknown Item")")

        // Check if item already exists in reorder list
        if let existingItem = reorderItems.first(where: { $0.itemId == foundItem.id }) {
            // Item exists - show current quantity and mark as existing
            // Will be set via modalStateManager.setItem() below
            print("� DEBUG: Item already in list with quantity: \(existingItem.quantity)")
        } else {
            // New item - default quantity 1
            // Will be set via modalStateManager.setItem() below
            print("� DEBUG: New item - default quantity: 1")
        }

        // INDUSTRY STANDARD: Use StateObject methods for atomic state updates
        let existingItemForQuantity = reorderItems.first(where: { $0.itemId == foundItem.id })
        let quantity = existingItemForQuantity?.quantity ?? 1
        let isExisting = existingItemForQuantity != nil
        modalStateManager.setItem(foundItem, quantity: quantity, isExisting: isExisting)
        modalStateManager.showModal()

        // Note: isProcessingBarcode remains true until modal is dismissed
        // This prevents new barcodes from being processed while modal is open
    }

    private func handleQuantityModalSubmit(_ quantity: Int) {
        guard let item = modalStateManager.selectedItemForQuantity else { return }

        print("📱 Modal submitted with quantity: \(quantity)")

        if quantity == 0 {
            // Zero quantity = delete item from list
            removeItemFromReorderList(item.id)
        } else {
            // Add or update item with specified quantity
            addOrUpdateItemInReorderList(item, quantity: quantity)
        }

        // Clear modal state using StateObject
        modalStateManager.clearState()

        // Mark processing complete
        isProcessingBarcode = false

        // REMOVED: Auto-processing next barcode after modal dismissal
        // User should scan next barcode manually to avoid confusion
        // Clear any remaining barcodes in queue
        if !barcodeQueue.isEmpty {
            print("🗑️ Clearing remaining barcodes in queue: \(barcodeQueue)")
            barcodeQueue.removeAll()
        }
    }

    private func handleQuantityModalCancel() {
        print("📱 Modal cancelled")

        // Clear modal state using StateObject
        modalStateManager.clearState()

        // Mark processing complete
        isProcessingBarcode = false

        // REMOVED: Auto-processing next barcode after modal dismissal
        // User should scan next barcode manually to avoid confusion
        // Clear any remaining barcodes in queue
        if !barcodeQueue.isEmpty {
            print("🗑️ Clearing remaining barcodes in queue: \(barcodeQueue)")
            barcodeQueue.removeAll()
        }
    }

    private func handleQuantityModalDismiss() {
        print("� DEBUG: handleQuantityModalDismiss() called")
        print("🚨 DEBUG: modalJustPresented = \(modalStateManager.modalJustPresented)")

        // CRITICAL FIX: Prevent premature dismiss from clearing state
        if modalStateManager.modalJustPresented {
            print("🚨 DEBUG: Modal just presented - ignoring premature dismiss")
            return
        }

        print("�📱 Modal dismissed (swiped away)")

        // Clear modal state using StateObject - same as cancel
        modalStateManager.clearState()

        // Mark processing complete
        isProcessingBarcode = false

        // REMOVED: Auto-processing next barcode after modal dismissal
        // User should scan next barcode manually to avoid confusion
        // Clear any remaining barcodes in queue
        if !barcodeQueue.isEmpty {
            print("🗑️ Clearing remaining barcodes in queue: \(barcodeQueue)")
            barcodeQueue.removeAll()
        }
    }

    private func addItemToReorderList(_ foundItem: SearchResultItem) {
        print("🔍 Attempting to add item to reorder list: \(foundItem.name ?? "Unknown Item") (ID: \(foundItem.id))")

        // CRITICAL FIX: Implement proper reorder logic as specified by user

        // 1. Check if item already exists in reorder list (any status)
        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == foundItem.id }) {
            let existingItem = reorderItems[existingIndex]

            // 2. If item is at the top (index 0), increment quantity
            if existingIndex == 0 {
                reorderItems[0].quantity += 1
                reorderItems[0].addedDate = Date() // Update timestamp
                saveReorderData()
                print("🔄 Item at top - incremented quantity to \(reorderItems[0].quantity): \(foundItem.name ?? "Unknown Item")")
                return
            }

            // 3. If item exists but not at top, move to top and update timestamp
            reorderItems.remove(at: existingIndex)
            var movedItem = existingItem
            movedItem.addedDate = Date() // Update timestamp
            reorderItems.insert(movedItem, at: 0)
            saveReorderData()
            print("🔄 Moved existing item to top: \(foundItem.name ?? "Unknown Item")")
            return
        }

        // 4. Item doesn't exist - create new item and add to top
        let newItem = ReorderItem(
            id: UUID().uuidString,
            itemId: foundItem.id,
            name: foundItem.name ?? "Unknown Item",
            sku: foundItem.sku,
            barcode: foundItem.barcode,
            quantity: 1,
            status: .added
        )

        // Copy additional data from search result
        var updatedItem = newItem
        updatedItem.categoryName = foundItem.categoryName
        updatedItem.price = foundItem.price
        updatedItem.hasTax = foundItem.hasTax

        // Extract image data from SearchResultItem.images array
        if let images = foundItem.images, let firstImage = images.first {
            updatedItem.imageId = firstImage.id
            updatedItem.imageUrl = firstImage.imageData?.url
        }

        // Add to reorder list at top for visibility
        reorderItems.insert(updatedItem, at: 0)

        // Save to persistence immediately
        saveReorderData()

        print("✅ Added new item to reorder list: \(foundItem.name ?? "Unknown Item")")
    }

    // MARK: - Simplified Item Management (No Complex Reorder Logic)

    private func addOrUpdateItemInReorderList(_ foundItem: SearchResultItem, quantity: Int) {
        print("🔍 Adding/updating item in reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")

        // Check if item already exists
        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == foundItem.id }) {
            // Update existing item with new quantity (replace, don't increment)
            reorderItems[existingIndex].quantity = quantity
            reorderItems[existingIndex].addedDate = Date() // Update timestamp
            saveReorderData()
            print("✅ Updated existing item quantity to \(quantity): \(foundItem.name ?? "Unknown Item")")
        } else {
            // Create new item
            let newItem = ReorderItem(
                id: UUID().uuidString,
                itemId: foundItem.id,
                name: foundItem.name ?? "Unknown Item",
                sku: foundItem.sku,
                barcode: foundItem.barcode,
                quantity: quantity,
                status: .added
            )

            // Copy additional data from search result
            var updatedItem = newItem
            updatedItem.categoryName = foundItem.categoryName
            updatedItem.price = foundItem.price
            updatedItem.hasTax = foundItem.hasTax

            // Extract image data from SearchResultItem.images array
            if let images = foundItem.images, let firstImage = images.first {
                updatedItem.imageId = firstImage.id
                updatedItem.imageUrl = firstImage.imageData?.url
            }

            reorderItems.append(updatedItem)
            saveReorderData()
            print("✅ Added new item to reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")
        }
    }

    private func removeItemFromReorderList(_ itemId: String) {
        print("🗑️ Removing item from reorder list: \(itemId)")

        if let index = reorderItems.firstIndex(where: { $0.itemId == itemId }) {
            let removedItem = reorderItems.remove(at: index)
            saveReorderData()
            print("✅ Removed item: \(removedItem.name)")
        } else {
            print("❌ Item not found in reorder list: \(itemId)")
        }
    }
}

// MARK: - Reorder Content View (Separated to fix compiler type-checking)
struct ReorderContentView: View {
    let reorderItems: [ReorderItem]
    let filteredItems: [ReorderItem]
    let organizedItems: [(String, [ReorderItem])]
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption

    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode
    @Binding var scannerSearchText: String
    @FocusState.Binding var isScannerFieldFocused: Bool

    let onManagementAction: (ManagementAction) -> Void
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onBarcodeScanned: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onQuantityTap: (SearchResultItem) -> Void // NEW: For opening quantity modal

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            // Content area
                            if reorderItems.isEmpty {
                                ReordersEmptyState()
                                    .frame(height: geometry.size.height - 200)
                            } else {
                                ReorderItemsContent(
                                    organizedItems: organizedItems,
                                    displayMode: displayMode,
                                    onStatusChange: onStatusChange,
                                    onQuantityChange: onQuantityChange,
                                    onRemoveItem: onRemoveItem,
                                    onImageTap: onImageTap,
                                    onQuantityTap: onQuantityTap
                                )
                            }
                        } header: {
                            ReorderHeaderSection(
                                totalItems: totalItems,
                                unpurchasedItems: unpurchasedItems,
                                purchasedItems: purchasedItems,
                                totalQuantity: totalQuantity,
                                sortOption: $sortOption,
                                filterOption: $filterOption,

                                organizationOption: $organizationOption,
                                displayMode: $displayMode,
                                onManagementAction: onManagementAction
                            )
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
            }
        }
        // TEXT FIELD REMOVED: Global HID scanner handles all barcode input without focus requirement
    }
}

// MARK: - Reorder Header Section
struct ReorderHeaderSection: View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption

    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode

    let onManagementAction: (ManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats (will collapse on scroll)
            ReordersScrollableHeader(
                totalItems: totalItems,
                unpurchasedItems: unpurchasedItems,
                purchasedItems: purchasedItems,
                totalQuantity: totalQuantity,
                onManagementAction: onManagementAction
            )

            // Filter Row (stays pinned)
            ReorderFilterRow(
                sortOption: $sortOption,
                filterOption: $filterOption,

                organizationOption: $organizationOption,
                displayMode: $displayMode
            )
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Old ReorderBottomSearchField removed - replaced with custom BarcodeScannerField

// MARK: - Reorder Items Content (Handles Organization and Display Modes)
struct ReorderItemsContent: View {
    let organizedItems: [(String, [ReorderItem])]
    let displayMode: ReorderDisplayMode
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onQuantityTap: (SearchResultItem) -> Void // NEW: For opening quantity modal

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<organizedItems.count, id: \.self) { sectionIndex in
                let (sectionTitle, items) = organizedItems[sectionIndex]

                // Section header (only show if there's a title and multiple sections)
                if !sectionTitle.isEmpty && organizedItems.count > 1 {
                    HStack {
                        Text(sectionTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(items.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                }

                // Items in this section
                switch displayMode {
                case .list:
                    ForEach(items) { item in
                        ReorderItemCard(
                            item: item,
                            displayMode: displayMode,
                            onStatusChange: { newStatus in
                                onStatusChange(item.id, newStatus)
                            },
                            onQuantityChange: { newQuantity in
                                onQuantityChange(item.id, newQuantity)
                            },
                            onQuantityTap: {
                                // Convert ReorderItem to SearchResultItem and show modal
                                let searchItem = SearchResultItem(
                                    id: item.itemId,
                                    name: item.name,
                                    categoryName: item.categoryName,
                                    sku: item.sku,
                                    barcode: item.barcode,
                                    price: item.price
                                )
                                onQuantityTap(searchItem)
                            },
                            onRemove: {
                                onRemoveItem(item.id)
                            },
                            onImageTap: {
                                onImageTap(item)
                            }
                        )
                    }

                case .photosLarge:
                    ForEach(items) { item in
                        ReorderPhotoCard(
                            item: item,
                            displayMode: displayMode,
                            onStatusChange: { newStatus in
                                onStatusChange(item.id, newStatus)
                            },
                            onQuantityChange: { newQuantity in
                                onQuantityChange(item.id, newQuantity)
                            },
                            onRemove: {
                                onRemoveItem(item.id)
                            },
                            onImageTap: {
                                onImageTap(item)
                            }
                        )
                    }

                case .photosMedium, .photosSmall:
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: displayMode.columnsPerRow)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            ReorderPhotoCard(
                                item: item,
                                displayMode: displayMode,
                                onStatusChange: { newStatus in
                                    onStatusChange(item.id, newStatus)
                                },
                                onQuantityChange: { newQuantity in
                                    onQuantityChange(item.id, newQuantity)
                                },
                                onRemove: {
                                    onRemoveItem(item.id)
                                },
                                onImageTap: {
                                    onImageTap(item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

#Preview {
    ReordersView()
}
