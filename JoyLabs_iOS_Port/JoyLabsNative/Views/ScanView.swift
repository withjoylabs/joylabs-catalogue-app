import SwiftUI
import UIKit

// MARK: - Scroll Position Detection for Pagination
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Intelligent Dual-Mode Barcode Scanner for Scan Page
class IntelligentBarcodeReceivingViewController: UIViewController {
    var onBarcodeScanned: ((String) -> Void)?

    // Barcode detection state
    private var inputBuffer = ""
    private var inputTimer: Timer?
    private var firstCharTime: Date?
    private let barcodeTimeout: TimeInterval = 0.15 // 150ms timeout
    private let maxHumanTypingSpeed: TimeInterval = 0.08 // 80ms between chars (very fast human typing)

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        // Scanner became first responder
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
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
                action: #selector(handleCharacterInput(_:))
            ))
        }

        // Letters A-Z (some barcodes include letters)
        for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }

        // Lowercase letters a-z
        for char in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }

        // Special characters common in barcodes
        let specialChars = ["-", "_", ".", " ", "/", "\\", "+", "=", "*", "%", "$", "#", "@", "!", "?"]
        for char in specialChars {
            commands.append(UIKeyCommand(
                input: char,
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }

        // Return key (end of barcode scan)
        commands.append(UIKeyCommand(
            input: "\r",
            modifierFlags: [],
            action: #selector(handleReturnKey)
        ))

        // Enter key (alternative end of barcode)
        commands.append(UIKeyCommand(
            input: "\n",
            modifierFlags: [],
            action: #selector(handleReturnKey)
        ))

        return commands
    }

    @objc private func handleCharacterInput(_ command: UIKeyCommand) {
        guard let input = command.input else { return }

        let currentTime = Date()

        // Start timing on first character
        if inputBuffer.isEmpty {
            firstCharTime = currentTime
            print("🔤 Input sequence started...")
        }

        // Add character to buffer
        inputBuffer += input

        // Reset completion timer
        inputTimer?.invalidate()
        inputTimer = Timer.scheduledTimer(withTimeInterval: barcodeTimeout, repeats: false) { [weak self] _ in
            self?.analyzeAndProcessInput()
        }
    }

    @objc private func handleReturnKey() {
        print("🔚 Return key detected - processing input immediately")
        analyzeAndProcessInput()
    }

    private func analyzeAndProcessInput() {
        guard !inputBuffer.isEmpty else { return }

        let finalInput = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputLength = finalInput.count

        // Calculate input speed if we have timing data
        var inputSpeed: Double = 0
        if let startTime = firstCharTime {
            let totalTime = Date().timeIntervalSince(startTime)
            inputSpeed = totalTime / Double(inputLength) // seconds per character
        }

        // INTELLIGENT DETECTION LOGIC
        let isBarcodePattern = detectBarcodePattern(input: finalInput, speed: inputSpeed, length: inputLength)

        if isBarcodePattern {
            print("🎯 BARCODE DETECTED: '\(finalInput)' (speed: \(String(format: "%.3f", inputSpeed))s/char)")

            // Send to barcode callback
            DispatchQueue.main.async {
                self.onBarcodeScanned?(finalInput)
            }
        } else {
            print("⌨️ KEYBOARD INPUT IGNORED: '\(finalInput)' (speed: \(String(format: "%.3f", inputSpeed))s/char) - Let text field handle this")
            // Do nothing - let the text field handle normal typing
        }

        // Clear state
        inputBuffer = ""
        firstCharTime = nil
        inputTimer?.invalidate()
    }

    private func detectBarcodePattern(input: String, speed: Double, length: Int) -> Bool {
        // DETECTION CRITERIA (multiple factors for accuracy)

        // 1. Speed Detection: Barcode scanners are MUCH faster than human typing
        let isVeryFastInput = speed < maxHumanTypingSpeed && speed > 0

        // 2. Length Detection: Barcodes are typically 8-20 characters
        let isBarcodeLength = length >= 8 && length <= 20

        // 3. Pattern Detection: Barcodes are usually all numbers or alphanumeric without spaces
        let isNumericOnly = input.allSatisfy { $0.isNumber }
        let isAlphanumericNoSpaces = input.allSatisfy { $0.isLetter || $0.isNumber } && !input.contains(" ")
        let isBarcodePattern = isNumericOnly || isAlphanumericNoSpaces

        // 4. Common barcode prefixes (UPC, EAN, etc.)
        let hasCommonBarcodePrefix = input.hasPrefix("0") || input.hasPrefix("1") || input.hasPrefix("2") ||
                                    input.hasPrefix("3") || input.hasPrefix("4") || input.hasPrefix("5") ||
                                    input.hasPrefix("6") || input.hasPrefix("7") || input.hasPrefix("8") ||
                                    input.hasPrefix("9")

        // DECISION LOGIC: Must meet multiple criteria
        let speedAndLengthMatch = isVeryFastInput && isBarcodeLength
        let patternMatches = isBarcodePattern && hasCommonBarcodePrefix

        // High confidence: Fast input + right length + barcode pattern
        if speedAndLengthMatch && patternMatches {
            return true
        }

        // Medium confidence: Very fast input with reasonable length (even if pattern is unclear)
        if isVeryFastInput && length >= 6 {
            return true
        }

        // Low confidence: Assume it's keyboard input
        return false
    }
}

// MARK: - SwiftUI Wrapper for Intelligent Dual-Mode Scanner
struct IntelligentBarcodeReceiver: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> IntelligentBarcodeReceivingViewController {
        let controller = IntelligentBarcodeReceivingViewController()
        controller.onBarcodeScanned = onBarcodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: IntelligentBarcodeReceivingViewController, context: Context) {
        uiViewController.onBarcodeScanned = onBarcodeScanned
    }
}
import OSLog

struct ScanView: View {
    @State private var searchText = ""
    @State private var scanHistoryCount = 0
    @State private var isConnected = true
    @State private var showingHistory = false
    @StateObject private var searchManager: SearchManager = {
        // Use the shared database manager that's already connected in Phase 1
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SearchManager(databaseManager: databaseManager)
    }()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchDebounceTimer: Timer?
    

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with JOYLABS logo and status
                HeaderView(
                    isConnected: isConnected,
                    scanHistoryCount: scanHistoryCount,
                    onHistoryTap: handleHistoryTap
                )

                // Main content area
                if !searchManager.isDatabaseReady {
                    DatabaseInitializingView()
                } else if searchText.isEmpty {
                    EmptySearchState()
                } else {
                    SearchResultsView(searchManager: searchManager)
                }

                Spacer()

                // Bottom search bar (matching React Native layout)
                BottomSearchBar(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
            }
            .background(Color(.systemBackground))

            // CRITICAL: Intelligent dual-mode barcode receiver (invisible, handles HID scanner while preserving text field functionality)
            IntelligentBarcodeReceiver { barcode in
                print("🎯 Intelligent scanner detected barcode: '\(barcode)'")
                handleGlobalBarcodeScanned(barcode)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingHistory) {
            // TODO: Add HistoryView when it's properly added to Xcode project
            Text("History View Coming Soon")
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingHistory = false
                        }
                    }
                }
        }
        .onAppear {
            // DISABLED: Auto-focus removed for dual-mode scanning
            // Text field can be manually focused for keyboard input
            // HID scanner works globally without focus requirement
        }
        .onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { _ in
            // Refresh search results when catalog sync completes (for webhook updates)
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔄 Catalog sync completed - refreshing search results for: '\(searchText)'")
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: searchText, filters: filters)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            // Refresh search results when image is updated (for real-time image updates)
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔄 Image updated - refreshing search results for: '\(searchText)'")
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: searchText, filters: filters)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceImageRefresh)) { notification in
            // Force refresh of search results when images need to be refreshed
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔄 Force image refresh - refreshing search results for: '\(searchText)'")
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: searchText, filters: filters)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            // CRITICAL FIX: Handle extremely fast HID scanner input
            // Cancel previous timer
            searchDebounceTimer?.invalidate()

            // CRITICAL: Clear search results immediately when text is cleared
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchManager.clearSearch()
                return
            }

            // Only trigger search if field is focused and has content
            guard isSearchFieldFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            // Prevent multiple rapid onChange calls by checking if value actually changed
            guard oldValue != newValue else { return }

            // CRITICAL: Use DispatchQueue to prevent multiple updates per frame from HID scanners
            DispatchQueue.main.async {
                // Double-check the value hasn't changed again during the async dispatch
                guard searchText == newValue else { return }

                // Debounce with timer to prevent multiple rapid calls
                searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    // Triple-check the value is still current when timer fires
                    guard searchText == newValue else { return }

                    let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                    searchManager.performSearchWithDebounce(searchTerm: newValue, filters: filters)
                }
            }
        }
    }

    // MARK: - Global Barcode Handling
    private func handleGlobalBarcodeScanned(_ barcode: String) {
        print("🌍 Global barcode input received (DUAL-MODE): \(barcode)")

        // Immediately trigger search with the scanned barcode
        // This bypasses the text field and debouncing for instant barcode results
        let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)

        Task {
            // Clear any existing search state
            searchManager.clearSearch()

            // Perform immediate search for barcode
            let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)

            await MainActor.run {
                // Update search text to show what was scanned (for user feedback)
                searchText = barcode

                print("✅ Global barcode search completed: \(results.count) results found")

                // Optional: Auto-focus text field after scan for follow-up typing
                // (This allows user to modify the search or type additional terms)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // DISABLED: Auto-focus removed as requested
                    // isSearchFieldFocused = true
                }
            }
        }
    }

    // MARK: - Actions
    private func handleHistoryTap() {
        showingHistory = true
    }
}

// MARK: - Search Results View
struct SearchResultsView: View {
    @ObservedObject var searchManager: SearchManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack {
                Text("Search Results")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if searchManager.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !searchManager.searchResults.isEmpty {
                    if let totalCount = searchManager.totalResultsCount {
                        Text("\(totalCount) items")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    } else {
                        Text("\(searchManager.searchResults.count) items")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if searchManager.isSearching {
                SearchingView()
            } else if let error = searchManager.searchError {
                SearchErrorView(error: error)
            } else if searchManager.searchResults.isEmpty {
                NoResultsView(searchManager: searchManager)
            } else {
                SearchResultsList(results: searchManager.searchResults, searchManager: searchManager)
            }
        }
    }
}

// MARK: - Search State Views
struct SearchingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView("Searching...")
                .font(.subheadline)
                .foregroundColor(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchErrorView: View {
    let error: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Search Error")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoResultsView: View {
    let searchManager: SearchManager
    @State private var showingItemDetails = false
    @State private var selectedQueryType: SearchQueryType = .upc  // Default to UPC instead of SKU

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(Color.secondary)

            VStack(spacing: 8) {
                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            // Create item buttons if there's a search query
            if let searchQuery = searchManager.currentSearchTerm, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CreateItemButtons(searchQuery: searchQuery) { queryType in
                    selectedQueryType = queryType
                    showingItemDetails = true
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingItemDetails) {
            if let searchQuery = searchManager.currentSearchTerm {
                ItemDetailsModal(
                    context: .createFromSearch(
                        query: searchQuery,
                        queryType: selectedQueryType
                    ),
                    onDismiss: {
                        showingItemDetails = false
                    },
                    onSave: { itemData in
                        // TODO: Handle saved item
                        showingItemDetails = false
                    }
                )
                .fullScreenModal()
            }
        }
    }


}

// MARK: - Create Item Buttons
struct CreateItemButtons: View {
    let searchQuery: String
    let action: (SearchQueryType) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Create New Item")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                // SKU Button
                Button(action: { 
                    action(.sku) 
                }) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create with SKU")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Text("Pre-fill SKU: \(searchQuery)")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }

                // UPC Button
                Button(action: { action(.upc) }) {
                    HStack {
                        Image(systemName: "barcode")
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create with UPC")
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            Text("Pre-fill UPC: \(searchQuery)")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct SearchResultsList: View {
    let results: [SearchResultItem]
    @ObservedObject var searchManager: SearchManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        SwipeableScanResultCard(
                            result: result,
                            onAddToReorder: {
                                addItemToReorderList(result, quantity: 1)
                            },
                            onPrint: {
                                printItem(result)
                            }
                        )
                        .id(result.id)
                    }

                    // Loading indicator at the bottom
                    if searchManager.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView("Loading more...")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                            Spacer()
                        }
                        .padding()
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scrollView")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                // Trigger pagination when near bottom (industry standard pattern)
                if offset > -100 && searchManager.hasMoreResults && !searchManager.isLoadingMore && !results.isEmpty {
                    searchManager.loadMoreResults()
                }
            }
        }
    }
    
    // MARK: - Reorder and Print Functions
    
    private func addItemToReorderList(_ item: SearchResultItem, quantity: Int) {
        // Load existing reorder items
        var reorderItems: [ReorderItem] = []
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            reorderItems = items
        }
        
        // Check if item already exists
        if let existingIndex = reorderItems.firstIndex(where: { $0.itemId == item.id }) {
            // Update existing item with new quantity (replace, don't increment)
            reorderItems[existingIndex].quantity = quantity
        } else {
            // Create new reorder item
            var newItem = ReorderItem(
                id: UUID().uuidString,
                itemId: item.id,
                name: item.name ?? "Unknown Item",
                sku: item.sku,
                barcode: item.barcode,
                quantity: quantity,
                status: .added,
                addedDate: Date(),
                notes: nil
            )
            
            // Set additional properties
            newItem.price = item.price
            newItem.categoryName = item.categoryName 
            newItem.imageUrl = item.images?.first?.imageData?.url
            newItem.imageId = item.images?.first?.id
            reorderItems.append(newItem)
        }
        
        // Save back to UserDefaults
        if let data = try? JSONEncoder().encode(reorderItems) {
            UserDefaults.standard.set(data, forKey: "reorderItems")
        }
        
        // Show success toast with truncated item name
        let itemName = item.name ?? "Item"
        let truncatedName = itemName.count > 20 ? String(itemName.prefix(17)) + "..." : itemName
        ToastNotificationService.shared.showSuccess("\(truncatedName) added to reorder list")
    }
    
    private func printItem(_ item: SearchResultItem) {
        let printService = LabelLivePrintService.shared
        
        Task {
            do {
                // Create print data directly from SearchResultItem
                let printData = PrintData(
                    itemName: item.name,
                    variationName: nil, // SearchResultItem doesn't have variation name
                    price: item.price?.description,
                    originalPrice: nil,
                    upc: item.barcode,
                    sku: item.sku,
                    categoryName: item.categoryName,
                    categoryId: item.categoryId,
                    description: nil, // SearchResultItem doesn't have description
                    createdAt: nil,
                    updatedAt: nil,
                    qtyForPrice: nil,
                    qtyPrice: nil
                )
                
                try await printService.printLabel(with: printData)
                
            } catch let error as LabelLivePrintError {
                await MainActor.run {
                    if case .printSuccess = error {
                        // Success case - show success toast
                        let itemName = item.name ?? "Item"
                        let truncatedName = itemName.count > 20 ? String(itemName.prefix(17)) + "..." : itemName
                        ToastNotificationService.shared.showSuccess("\(truncatedName) label sent to printer")
                    } else {
                        // Error case - show error toast with user-friendly message
                        ToastNotificationService.shared.showError(error.errorDescription ?? "Print failed")
                    }
                }
            } catch {
                await MainActor.run {
                    ToastNotificationService.shared.showError("Failed to print label: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    ScanView()
}
