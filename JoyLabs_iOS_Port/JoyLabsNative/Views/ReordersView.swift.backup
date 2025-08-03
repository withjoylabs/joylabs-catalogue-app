import SwiftUI

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
import UIKit
import SQLite

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
    
    // Force list mode on iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // Image enlargement
    @State private var selectedItemForEnlargement: ReorderItem?
    @State private var showingImageEnlargement = false

    // Unified sheet management
    @State private var activeSheet: ReordersSheet?
    @State private var selectedItemForImageUpdate: ReorderItem?
    
    // Item details modal state

    // Barcode scanner state
    @State private var scannerSearchText = ""
    @FocusState private var isScannerFieldFocused: Bool
    @State private var searchDebounceTimer: Timer?

    // Barcode processing state (simplified - no queue needed)
    @State private var isProcessingBarcode = false


    // Current modal quantity tracking
    @State private var currentModalQuantity: Int = 1

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

    var body: some SwiftUI.View {
        NavigationStack {
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
                        print("[ReordersView] Image tapped for item: \(item.name)")
                    },
                    onImageLongPress: { item in
                        print("[ReordersView] onImageLongPress called with item: \(item.name)")
                        activeSheet = .imagePicker(item)
                        print("[ReordersView] Set activeSheet = .imagePicker(\(item.name))")
                    },
                    onQuantityTap: showQuantityModalForItem,
                    onItemDetailsLongPress: { item in
                        print("[ReordersView] onItemDetailsLongPress called with item: \(item.name)")
                        activeSheet = .itemDetails(item)
                        print("[ReordersView] Set activeSheet = .itemDetails(\(item.name))")
                    }
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
            .onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { _ in
                // Refresh reorder items data when catalog sync completes (for webhook updates)
                print("🔄 Catalog sync completed - refreshing reorder items data")
                Task {
                    await refreshDynamicDataForReorderItems()
                }
                
                // Also refresh search results if there's an active search
                if !scannerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("🔄 Catalog sync completed - refreshing reorders search results for: '\(scannerSearchText)'")
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: scannerSearchText, filters: filters)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
                print("🔔 [ReordersView] Received .imageUpdated notification")
                if let userInfo = notification.userInfo {
                    print("🔔 [ReordersView] Image updated notification userInfo: \(userInfo)")
                }
                
                // Refresh reorder items data when image is updated (for real-time image updates)
                print("🔄 [ReordersView] Image updated - refreshing reorder items data")
                Task {
                    await refreshDynamicDataForReorderItems()
                }
                
                // Also refresh search results if there's an active search
                if !scannerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("🔄 [ReordersView] Image updated - refreshing reorders search results for: '\(scannerSearchText)'")
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: scannerSearchText, filters: filters)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .forceImageRefresh)) { notification in
                print("🔔 [ReordersView] Received .forceImageRefresh notification")
                if let userInfo = notification.userInfo {
                    print("🔔 [ReordersView] Force image refresh notification userInfo: \(userInfo)")
                }
                
                // Force refresh of reorder items data when images need to be refreshed
                print("🔄 [ReordersView] Force image refresh - refreshing reorder items data")
                Task {
                    await refreshDynamicDataForReorderItems()
                }
                
                // Also refresh search results if there's an active search
                if !scannerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("🔄 [ReordersView] Force image refresh - refreshing reorders search results for: '\(scannerSearchText)'")
                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: scannerSearchText, filters: filters)
                }
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
        // Unified Sheet Modal (SINGLE SHEET SOLUTION - fixes multiple sheet modifier issue)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .imagePicker(let item):
                UnifiedImagePickerModal(
                    context: .reordersViewLongPress(
                        itemId: item.itemId,
                        imageId: item.imageId
                    ),
                    onDismiss: {
                        activeSheet = nil
                    },
                    onImageUploaded: { result in
                        activeSheet = nil
                    }
                )
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.itemId),
                    onDismiss: {
                        activeSheet = nil
                    },
                    onSave: { itemData in
                        activeSheet = nil
                        loadReorderData() // Refresh data after edit
                    }
                )
            case .quantityModal(let searchItem):
                EmbeddedQuantitySelectionModal(
                    item: searchItem,
                    currentQuantity: modalStateManager.modalQuantity,
                    isExistingItem: modalStateManager.isExistingItem,
                    isPresented: .constant(true),
                    onSubmit: { quantity in
                        handleQuantityModalSubmit(quantity)
                        activeSheet = nil
                    },
                    onCancel: {
                        activeSheet = nil
                    },
                    onQuantityChange: { newQuantity in
                        currentModalQuantity = newQuantity
                    }
                )
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
            
            // DEBUG: Log image URLs
            for item in items {
                print("📸 [ReorderLoad] Item '\(item.name)' imageUrl: \(item.imageUrl ?? "nil")")
            }
            
            // Refresh dynamic data from database for all items
            Task {
                await refreshDynamicDataForReorderItems()
            }
        } else {
            reorderItems = []
            print("📦 No saved reorder items found")
        }
    }
    
    /// Refresh ALL data from database - using pre-computed columns (efficient like SearchManager)
    private func refreshDynamicDataForReorderItems() async {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            print("❌ [ReorderRefresh] Database not connected")
            return
        }
        
        var updatedItems: [ReorderItem] = []
        
        for item in reorderItems {
            do {
                // Query catalog_items table directly to get pre-computed category names (same pattern as SearchManager)
                let itemQuery = CatalogTableDefinitions.catalogItems
                    .select(CatalogTableDefinitions.itemCategoryName,
                           CatalogTableDefinitions.itemReportingCategoryName,
                           CatalogTableDefinitions.itemDataJson)
                    .filter(CatalogTableDefinitions.itemId == item.itemId)
                    .filter(CatalogTableDefinitions.itemIsDeleted == false)
                
                guard let itemRow = try db.pluck(itemQuery) else {
                    print("⚠️ [ReorderRefresh] Item not found in database: \(item.itemId)")
                    updatedItems.append(item)
                    continue
                }
                
                // Get pre-computed category names (exact same logic as SearchManager)
                let reportingCategoryName = try? itemRow.get(CatalogTableDefinitions.itemReportingCategoryName)
                let regularCategoryName = try? itemRow.get(CatalogTableDefinitions.itemCategoryName)
                let categoryName = reportingCategoryName ?? regularCategoryName
                
                let dataJson = try? itemRow.get(CatalogTableDefinitions.itemDataJson)
                
                // Get first variation data for price (same pattern as SearchManager)
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
                
                // Check if item has taxes (same logic as SearchManager)
                let hasTax = checkItemHasTaxFromDataJson(dataJson)
                
                // Get primary image data (same pattern as SearchManager)
                print("   - Getting image data for itemId: \(item.itemId)")
                let images = getPrimaryImageForReorderItem(itemId: item.itemId)
                print("   - Found \(images?.count ?? 0) images")
                
                // Update reorder item with fresh data
                var updatedItem = item
                updatedItem.price = price
                if let categoryName = categoryName {
                    updatedItem.categoryName = categoryName
                }
                updatedItem.hasTax = hasTax
                
                // Update image data - PRESERVE existing if no new data found
                if let images = images, let firstImage = images.first {
                    updatedItem.imageId = firstImage.id
                    updatedItem.imageUrl = firstImage.imageData?.url
                    print("   - Found fresh image data")
                } else {
                    // PRESERVE existing image data if refresh fails to find images
                    print("   - No fresh image data found, preserving existing: imageId=\(item.imageId ?? "nil"), imageUrl=\(item.imageUrl ?? "nil")")
                    // updatedItem already has item's existing imageId and imageUrl
                }
                
                print("🔄 [ReorderRefresh] Updated ALL data for '\(item.name)'")
                print("   - Price: \(updatedItem.price?.description ?? "nil")")
                print("   - Category: \(updatedItem.categoryName ?? "nil")")
                print("   - Image URL: \(updatedItem.imageUrl ?? "nil")")
                print("   - Has Tax: \(updatedItem.hasTax)")
                
                updatedItems.append(updatedItem)
                
            } catch {
                print("❌ [ReorderRefresh] Failed to refresh item \(item.itemId): \(error)")
                updatedItems.append(item)
            }
        }
        
        await MainActor.run {
            reorderItems = updatedItems
            saveReorderData()
            print("🔄 [ReorderRefresh] Refreshed ALL data for \(updatedItems.count) reorder items using pre-computed columns")
        }
    }
    
    // MARK: - Helper functions (same patterns as SearchManager)
    
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
        print("🖼️ [ReorderRefresh] Getting images for item: \(itemId)")
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            print("🖼️ [ReorderRefresh] ❌ Database not connected")
            return nil
        }
        
        do {
            // Get item's image_ids array from database (same approach as SearchManager)
            let selectQuery = """
            SELECT data_json FROM catalog_items 
            WHERE id = ? AND is_deleted = 0
            """
            
            for row in try db.prepare(selectQuery, itemId) {
                guard let dataJson = row[0] as? String,
                      let data = dataJson.data(using: .utf8) else {
                    continue
                }
                
                // Parse the CatalogObject to get images
                let decoder = JSONDecoder()
                let catalogObject = try decoder.decode(CatalogObject.self, from: data)
                
                return catalogObject.itemData?.images
            }
        } catch {
            print("❌ [ReorderRefresh] Failed to get images for item \(itemId): \(error)")
        }
        
        return nil
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
        let itemsToUpdate = reorderItems.filter { $0.status == .added }
        let updatedCount = itemsToUpdate.count
        
        for item in reorderItems {
            updateItemStatus(itemId: item.id, newStatus: .received)
        }
        
        if updatedCount > 0 {
            ToastNotificationService.shared.showSuccess("Marked \(updatedCount) items as received")
        }
    }

    private func clearAllItems() {
        let clearedCount = reorderItems.count
        reorderItems.removeAll()
        saveReorderData()
        
        if clearedCount > 0 {
            ToastNotificationService.shared.showSuccess("Cleared \(clearedCount) reorder items")
        }
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
            let itemName = reorderItems[index].name
            
            if newStatus == .received {
                // When item is marked as received, remove it from the list
                reorderItems[index].receivedDate = Date()
                reorderItems.remove(at: index)
                ToastNotificationService.shared.showSuccess("\(itemName) marked as received")
            } else {
                // Update status for added/purchased
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

        // Clear the search field immediately for next scan
        scannerSearchText = ""

        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if modalStateManager.showingQuantityModal {
            print("🔗 INSTANT CHAIN SCAN: Modal is open, submitting current item and switching to new item")

            // Get current item info for success notification
            let currentItem = modalStateManager.selectedItemForQuantity
            let currentQuantity = currentModalQuantity // Use actual current quantity from modal
            print("🔗 CHAIN SCAN DEBUG: Submitting '\(currentItem?.name ?? "Unknown")' with quantity: \(currentQuantity)")

            // Submit current item asynchronously in background (WITHOUT CLEARING MODAL)
            Task {
                await MainActor.run {
                    // Direct database operation without modal state changes
                    if let item = currentItem {
                        print("📱 Chain scan: submitting \(item.name ?? "Unknown") with quantity: \(currentQuantity)")
                        addOrUpdateItemInReorderList(item, quantity: currentQuantity)

                        // Show success notification for submitted item
                        let itemName = item.name ?? "Item"
                        let truncatedName = itemName.count > 15 ? String(itemName.prefix(12)) + "..." : itemName
                        ToastNotificationService.shared.showSuccess("\(truncatedName) (Qty: \(currentQuantity)) added")
                    }
                }
            }

            // Reset processing flag and immediately process new barcode
            isProcessingBarcode = false
            processSingleBarcode(barcode)
            return
        }

        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }

    private func handleGlobalBarcodeScanned(_ barcode: String) {
        print("🌍 Global barcode input received (NO FOCUS REQUIRED): \(barcode)")

        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if modalStateManager.showingQuantityModal {
            print("🔗 INSTANT CHAIN SCAN: Modal is open, submitting current item and switching to new item")

            // Get current item info for success notification
            let currentItem = modalStateManager.selectedItemForQuantity
            let currentQuantity = currentModalQuantity // Use actual current quantity from modal
            print("🔗 CHAIN SCAN DEBUG: Submitting '\(currentItem?.name ?? "Unknown")' with quantity: \(currentQuantity)")

            // Submit current item asynchronously in background (WITHOUT CLEARING MODAL)
            Task {
                await MainActor.run {
                    // Direct database operation without modal state changes
                    if let item = currentItem {
                        print("📱 Chain scan: submitting \(item.name ?? "Unknown") with quantity: \(currentQuantity)")
                        addOrUpdateItemInReorderList(item, quantity: currentQuantity)

                        // Show success notification for submitted item
                        let itemName = item.name ?? "Item"
                        let truncatedName = itemName.count > 15 ? String(itemName.prefix(12)) + "..." : itemName
                        ToastNotificationService.shared.showSuccess("\(truncatedName) (Qty: \(currentQuantity)) added")
                    }
                }
            }

            // Reset processing flag and immediately process new barcode
            isProcessingBarcode = false
            processSingleBarcode(barcode)
            return
        }

        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }


    private func processSingleBarcode(_ barcode: String) {
        guard !isProcessingBarcode else {
            print("⚠️ Already processing a barcode, ignoring: \(barcode)")
            return
        }

        isProcessingBarcode = true
        print("🔄 Processing single barcode: \(barcode)")

        // CRITICAL FIX: Clear search manager state to ensure fresh search with offset 0
        searchManager.clearSearch()

        // Use EXACT same pattern as scan page - immediate search without debounce for barcode scans
        Task {
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)

            // Process results immediately (same performance as scan page)
            await MainActor.run {
                print("🔍 Search results count: \(results.count)")
                if let foundItem = results.first {
                    print("🔍 Found item: \(foundItem.name ?? "Unknown") - calling showQuantityModalForItem")
                    // Show quantity modal (or repopulate existing modal instantly)
                    showQuantityModalForItem(foundItem)
                } else {
                    print("❌ No item found for barcode: \(barcode)")
                    // Mark processing complete for failed searches
                    isProcessingBarcode = false
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

        print("🔢 QUANTITY DEBUG: Item '\(foundItem.name ?? "Unknown")' - existing qty: \(existingItemForQuantity?.quantity ?? 0), final qty: \(quantity), isExisting: \(isExisting)")

        // Initialize current modal quantity tracking
        currentModalQuantity = quantity
        print("🔢 QUANTITY DEBUG: Set currentModalQuantity to \(quantity)")

        modalStateManager.setItem(foundItem, quantity: quantity, isExisting: isExisting)
        
        // Use unified sheet system
        activeSheet = .quantityModal(foundItem)
        print("Set activeSheet = .quantityModal")
        
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
    }

    private func handleQuantityModalCancel() {
        print("📱 Modal cancelled")

        // Clear modal state using StateObject
        modalStateManager.clearState()

        // Mark processing complete
        isProcessingBarcode = false
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
    }

    private func addItemToReorderList(_ foundItem: SearchResultItem) {
        print("🔍 DEPRECATED: addItemToReorderList should not be called - use quantity modal system instead")
        print("� This function is deprecated and should be removed once modal system is fully implemented")

        // This function is now deprecated in favor of the quantity modal system
        // All item additions should go through the modal workflow
        // Keeping this as a fallback for now, but it should be removed

        // Simple fallback: just add item with quantity 1
        addOrUpdateItemInReorderList(foundItem, quantity: 1)
    }

    // MARK: - Simplified Item Management (No Complex Reorder Logic)

    private func addOrUpdateItemInReorderList(_ foundItem: SearchResultItem, quantity: Int) {
        print("🔍 Adding/updating item in reorder list: \(foundItem.name ?? "Unknown Item") with quantity: \(quantity)")

        // Check if item already exists
        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == foundItem.id }) {
            // Update existing item with new quantity (replace, don't increment)
            reorderItems[existingIndex].quantity = quantity
            // REMOVED: timestamp updating logic - no longer needed with modal system
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

            // SIMPLIFIED: Just append to end - no complex positioning logic
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
struct ReorderContentView: SwiftUI.View {
    let reorderItems: [ReorderItem]
    let filteredItems: [ReorderItem]
    let organizedItems: [(String, [ReorderItem])]
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @SwiftUI.Binding var sortOption: ReorderSortOption
    @SwiftUI.Binding var filterOption: ReorderFilterOption

    @SwiftUI.Binding var organizationOption: ReorderOrganizationOption
    @SwiftUI.Binding var displayMode: ReorderDisplayMode
    @SwiftUI.Binding var scannerSearchText: String
    @FocusState.Binding var isScannerFieldFocused: Bool

    let onManagementAction: (ManagementAction) -> Void
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onBarcodeScanned: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onImageLongPress: (ReorderItem) -> Void // NEW: For updating item images
    let onQuantityTap: (SearchResultItem) -> Void // NEW: For opening quantity modal
    let onItemDetailsLongPress: (ReorderItem) -> Void // NEW: For item details modal

    var body: some SwiftUI.View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            // Content area
                            if reorderItems.isEmpty {
                                ReordersEmptyState()
                                    .frame(maxHeight: .infinity)
                            } else {
                                ReorderItemsContent(
                                    organizedItems: organizedItems,
                                    displayMode: displayMode,
                                    onStatusChange: onStatusChange,
                                    onQuantityChange: onQuantityChange,
                                    onRemoveItem: onRemoveItem,
                                    onImageTap: onImageTap,
                                    onImageLongPress: onImageLongPress,
                                    onQuantityTap: onQuantityTap,
                                    onItemDetailsLongPress: onItemDetailsLongPress
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
                .clipped() // Prevent content from bleeding through status bar
            }
        }
        .ignoresSafeArea(.all, edges: []) // Respect safe area boundaries
        // TEXT FIELD REMOVED: Global HID scanner handles all barcode input without focus requirement
    }
}

// MARK: - Reorder Header Section
struct ReorderHeaderSection: SwiftUI.View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @SwiftUI.Binding var sortOption: ReorderSortOption
    @SwiftUI.Binding var filterOption: ReorderFilterOption

    @SwiftUI.Binding var organizationOption: ReorderOrganizationOption
    @SwiftUI.Binding var displayMode: ReorderDisplayMode

    let onManagementAction: (ManagementAction) -> Void

    var body: some SwiftUI.View {
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
struct ReorderItemsContent: SwiftUI.View {
    let organizedItems: [(String, [ReorderItem])]
    let displayMode: ReorderDisplayMode
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onImageLongPress: (ReorderItem) -> Void // NEW: For updating item images
    let onQuantityTap: (SearchResultItem) -> Void // NEW: For opening quantity modal
    let onItemDetailsLongPress: (ReorderItem) -> Void // NEW: For item details modal

    var body: some SwiftUI.View {
        // Capture the callback to avoid scope issues
        let itemDetailsCallback = onItemDetailsLongPress
        
        LazyVStack(spacing: 0) {
            // ELEGANT SOLUTION: Manual rendering to avoid SwiftUI ForEach compiler bug
            if organizedItems.count == 1 {
                // Single section - render directly
                let (_, items) = organizedItems[0]
                renderItemsSection(
                    items: items, 
                    displayMode: displayMode,
                    onStatusChange: onStatusChange,
                    onQuantityChange: onQuantityChange,
                    onRemoveItem: onRemoveItem,
                    onImageTap: onImageTap,
                    onImageLongPress: onImageLongPress,
                    onQuantityTap: onQuantityTap,
                    onItemDetailsLongPress: itemDetailsCallback
                )
            } else if organizedItems.count > 1 {
                // Multiple sections - render each manually
                let (sectionTitle1, items1) = organizedItems[0]
                if !sectionTitle1.isEmpty {
                    sectionHeader(title: sectionTitle1, itemCount: items1.count)
                }
                renderItemsSection(
                    items: items1, 
                    displayMode: displayMode,
                    onStatusChange: onStatusChange,
                    onQuantityChange: onQuantityChange,
                    onRemoveItem: onRemoveItem,
                    onImageTap: onImageTap,
                    onImageLongPress: onImageLongPress,
                    onQuantityTap: onQuantityTap,
                    onItemDetailsLongPress: itemDetailsCallback
                )

                if organizedItems.count > 1 {
                    let (sectionTitle2, items2) = organizedItems[1]
                    if !sectionTitle2.isEmpty {
                        sectionHeader(title: sectionTitle2, itemCount: items2.count)
                    }
                    renderItemsSection(
                        items: items2, 
                        displayMode: displayMode,
                        onStatusChange: onStatusChange,
                        onQuantityChange: onQuantityChange,
                        onRemoveItem: onRemoveItem,
                        onImageTap: onImageTap,
                        onImageLongPress: onImageLongPress,
                        onQuantityTap: onQuantityTap,
                        onItemDetailsLongPress: itemDetailsCallback
                    )
                }

                if organizedItems.count > 2 {
                    let (sectionTitle3, items3) = organizedItems[2]
                    if !sectionTitle3.isEmpty {
                        sectionHeader(title: sectionTitle3, itemCount: items3.count)
                    }
                    renderItemsSection(
                        items: items3, 
                        displayMode: displayMode,
                        onStatusChange: onStatusChange,
                        onQuantityChange: onQuantityChange,
                        onRemoveItem: onRemoveItem,
                        onImageTap: onImageTap,
                        onImageLongPress: onImageLongPress,
                        onQuantityTap: onQuantityTap,
                        onItemDetailsLongPress: itemDetailsCallback
                    )
                }
            }
        }
    }

    // MARK: - Helper Functions
    @ViewBuilder
    private func sectionHeader(title: String, itemCount: Int) -> some SwiftUI.View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
            Text("\(itemCount) items")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func renderItemsSection(
        items: [ReorderItem], 
        displayMode: ReorderDisplayMode,
        onStatusChange: @escaping (String, ReorderStatus) -> Void,
        onQuantityChange: @escaping (String, Int) -> Void,
        onRemoveItem: @escaping (String) -> Void,
        onImageTap: @escaping (ReorderItem) -> Void,
        onImageLongPress: @escaping (ReorderItem) -> Void,
        onQuantityTap: @escaping (SearchResultItem) -> Void,
        onItemDetailsLongPress: @escaping (ReorderItem) -> Void
    ) -> some SwiftUI.View {
        switch displayMode {
        case .list:
            ForEach(items, id: \.id) { (item: ReorderItem) in
                SwipeableReorderCard(
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
                        // CRITICAL: Populate images array with unified image data
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

                        let searchItem = SearchResultItem(
                            id: item.itemId,
                            name: item.name,
                            sku: item.sku,
                            price: item.price,
                            barcode: item.barcode,
                            categoryId: nil,
                            categoryName: item.categoryName,
                            images: images, // ✅ PROPERLY POPULATED!
                            matchType: "reorder",
                            matchContext: item.name,
                            isFromCaseUpc: false,
                            caseUpcData: nil,
                            hasTax: item.hasTax
                        )
                        onQuantityTap(searchItem)
                    },
                    onRemove: {
                        onRemoveItem(item.id)
                    },
                    onImageTap: {
                        onImageTap(item)
                    },
                    onImageLongPress: { _ in
                        onImageLongPress(item)
                    },
                    onItemDetailsLongPress: { _ in
                        onItemDetailsLongPress(item)
                    }
                )
            }

        case .photosLarge, .photosMedium, .photosSmall:
            // Use proper column count for each display mode
            let columnCount = displayMode.columnsPerRow
            // Responsive spacing: smaller on iPhone for better fit
            let spacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items, id: \.id) { (item: ReorderItem) in
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
                            // Image tap toggles bought status (already handled in ReorderPhotoCard)
                        },
                        onImageLongPress: { _ in
                            onImageLongPress(item)
                        },
                        onItemDetailsTap: {
                            // Convert ReorderItem to SearchResultItem for quantity modal
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
                                images.append(catalogImage)
                            }
                            
                            let searchItem = SearchResultItem(
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
                            onQuantityTap(searchItem)
                        },
                        onItemDetailsLongPress: { item in
                            onItemDetailsLongPress(item)
                        }
                    )
                }
            }
            .id("photo-grid-\(displayMode.rawValue)")
            .padding(.horizontal, 16)
        }
    }
}


#Preview {
    ReordersView()
}
