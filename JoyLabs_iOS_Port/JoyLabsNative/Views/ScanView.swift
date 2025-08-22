import SwiftUI
import UIKit


// MARK: - Legacy scanner removed - now using SharedHIDScanner
import OSLog

struct ScanView: View {
    @State private var searchText = ""
    @State private var scanHistoryCount = 0
    @State private var isConnected = true
    @State private var showingHistory = false
    @State private var lastScannedBarcode = ""  // Track HID scanned barcode
    @State private var originalSearchQuery = ""  // Track original search query for refresh
    @StateObject private var searchManager: SearchManager = {
        // Use the shared database manager that's already connected in Phase 1
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SearchManager(databaseManager: databaseManager)
    }()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchDebounceTimer: Timer?
    
    // Binding for focus state to pass up to ContentView
    let onFocusStateChanged: ((Bool) -> Void)?
    
    // Default initializer for standalone use (like previews)
    init(onFocusStateChanged: ((Bool) -> Void)? = nil) {
        self.onFocusStateChanged = onFocusStateChanged
    }

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
                } else if searchText.isEmpty && searchManager.searchResults.isEmpty && lastScannedBarcode.isEmpty {
                    EmptySearchState()
                } else if !searchManager.searchResults.isEmpty || !lastScannedBarcode.isEmpty {
                    SearchResultsView(
                        searchManager: searchManager,
                        scannedBarcode: lastScannedBarcode,
                        originalSearchQuery: originalSearchQuery
                    )
                } else {
                    EmptySearchState()
                }

                Spacer()

                // Bottom search bar (matching React Native layout)
                BottomSearchBar(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
            }
            .background(Color(.systemBackground))
            .onTapGesture {
                // Dismiss keyboard when tapping background
                isSearchFieldFocused = false
            }

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
            if let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            // Refresh search results when image is updated (for real-time image updates)
            if let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceImageRefresh)) { notification in
            // Force refresh of search results when images need to be refreshed
            if let currentTerm = searchManager.currentSearchTerm {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: currentTerm, filters: filters)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GlobalBarcodeScanned"))) { notification in
            // Handle global barcode scan from app-level HID scanner
            if let barcode = notification.object as? String {
                handleHIDBarcodeScan(barcode)
            }
        }
        .onChange(of: isSearchFieldFocused) { oldValue, newValue in
            // Notify ContentView of focus state changes for AppLevelHIDScanner
            onFocusStateChanged?(newValue)
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Clear scanned barcode when user types manually and update original query
            if !newValue.isEmpty && lastScannedBarcode != "" {
                lastScannedBarcode = ""
            }
            
            // Track original query for refresh (prioritize manual search over HID scan)
            if !newValue.isEmpty {
                originalSearchQuery = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Cancel previous timer
            searchDebounceTimer?.invalidate()

            // Clear search results immediately when text is cleared
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Don't clear search if we have HID scan results
                if lastScannedBarcode.isEmpty {
                    searchManager.clearSearch()
                }
                return
            }

            // Only trigger search if field is focused and has content
            guard isSearchFieldFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            // Prevent multiple rapid onChange calls by checking if value actually changed
            guard oldValue != newValue else { return }

            // Simplified debounce with single timer (removed triple-async layers)
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: newValue, filters: filters)
            }
        }
    }

    // MARK: - HID Barcode Handling
    private func handleHIDBarcodeScan(_ barcode: String) {
        // Dual-mode behavior based on text field focus state
        if isSearchFieldFocused {
            // Mode 1: Text field is focused - populate the text field
            // This triggers normal debounced search like manual typing
            searchText = barcode
        } else {
            // Mode 2: Text field not focused - independent search
            // Store the scanned barcode for display and refresh
            lastScannedBarcode = barcode
            originalSearchQuery = barcode  // Track for refresh logic
            
            // Clear manual search text to keep search bar clean
            searchText = ""
            
            // Perform direct search (don't populate text field)
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            
            Task {
                // Clear any existing search state
                searchManager.clearSearch()
                
                // Set currentSearchTerm AFTER clearing so NoResultsView can show create buttons
                searchManager.currentSearchTerm = barcode
                
                // Perform immediate search for barcode
                let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)
                
                await MainActor.run {
                    // Ensure currentSearchTerm is still set in case performSearch cleared it
                    if results.isEmpty {
                        searchManager.currentSearchTerm = barcode
                    }
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
    let scannedBarcode: String
    let originalSearchQuery: String  // Pass original query for refresh
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack {
                Text(scannedBarcode.isEmpty ? "Search Results" : "Search Results for \(scannedBarcode)")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

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
                NoResultsView(searchManager: searchManager, originalSearchQuery: originalSearchQuery)
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
    let originalSearchQuery: String  // Pass original query for refresh
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
                        // Dismiss the modal
                        showingItemDetails = false
                        
                        // Refresh search results using SearchRefreshService
                        // Use the best available query for refresh
                        let queryForRefresh = !originalSearchQuery.isEmpty ? originalSearchQuery : searchManager.currentSearchTerm
                        if let refreshQuery = queryForRefresh {
                            SearchRefreshService.shared.refreshSearchAfterSave(
                                with: refreshQuery,
                                searchManager: searchManager
                            )
                        }
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
                        },
                        onItemUpdated: {
                            refreshSearchResults()
                        }
                    )
                    .id(result.id)
                }
            }
        }
    }
    
    // MARK: - Search Refresh Function
    
    private func refreshSearchResults() {
        // Use SearchRefreshService for consistent refresh logic
        if let currentTerm = searchManager.currentSearchTerm {
            SearchRefreshService.shared.refreshSearchAfterSave(
                with: currentTerm,
                searchManager: searchManager
            )
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
                variationName: item.variationName,
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
                    variationName: item.variationName,
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
