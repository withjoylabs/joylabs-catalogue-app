import SwiftUI
import Combine

/// SearchViewController - Main search interface combining HID scanner and search results
/// Ports the sophisticated search UI from React Native
@MainActor
class SearchViewController: ObservableObject {
    // MARK: - Published Properties
    @Published var searchText: String = ""
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var searchFilters = SearchFilters()
    @Published var selectedItem: SearchResultItem?
    @Published var showingItemDetail: Bool = false
    
    // Scanner state
    @Published var scannerEnabled: Bool = true
    @Published var lastScannedCode: String = ""
    @Published var scannerError: String?
    
    // MARK: - Private Properties
    private let searchManager: SearchManager
    private let hidScanner: HIDScannerManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        searchManager: SearchManager = SearchManager(),
        hidScanner: HIDScannerManager = HIDScannerManager()
    ) {
        self.searchManager = searchManager
        self.hidScanner = hidScanner
        
        setupBindings()
        setupHIDScanner()
    }
    
    // MARK: - Public Methods
    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSearch()
            return
        }
        
        searchManager.performSearchWithDebounce(searchTerm: searchText, filters: searchFilters)
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        searchError = nil
        searchManager.clearSearch()
    }
    
    func selectItem(_ item: SearchResultItem) {
        selectedItem = item
        showingItemDetail = true
        
        Logger.info("Search", "Selected item: \(item.name ?? item.id)")
    }
    
    func enableScanner() {
        scannerEnabled = true
        hidScanner.enable()
        Logger.info("Search", "HID scanner enabled")
    }
    
    func disableScanner() {
        scannerEnabled = false
        hidScanner.disable()
        Logger.info("Search", "HID scanner disabled")
    }
    
    func updateSearchFilters(_ filters: SearchFilters) {
        searchFilters = filters
        
        // Re-run search if there's a current search term
        if !searchText.isEmpty {
            performSearch()
        }
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind search manager results to local state
        searchManager.$searchResults
            .receive(on: DispatchQueue.main)
            .assign(to: &$searchResults)
        
        searchManager.$isSearching
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSearching)
        
        searchManager.$searchError
            .receive(on: DispatchQueue.main)
            .assign(to: &$searchError)
        
        // Auto-search when text changes (with debouncing handled by SearchManager)
        $searchText
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }
    
    private func setupHIDScanner() {
        // Configure HID scanner callbacks
        hidScanner.onScan = { [weak self] barcode in
            Task { @MainActor in
                self?.handleBarcodeScanned(barcode)
            }
        }
        
        hidScanner.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleScannerError(error)
            }
        }
        
        // Enable scanner by default
        enableScanner()
    }
    
    private func handleBarcodeScanned(_ barcode: String) {
        Logger.info("Search", "Barcode scanned: \(barcode)")
        
        lastScannedCode = barcode
        scannerError = nil
        
        // Set search text to scanned barcode and trigger search
        searchText = barcode
        
        // Ensure barcode filter is enabled for scanned codes
        if !searchFilters.barcode {
            searchFilters.barcode = true
        }
        
        // Trigger immediate search (bypass debouncing for scanned codes)
        Task {
            let results = await searchManager.performSearch(searchTerm: barcode, filters: searchFilters)
            
            // If we get exactly one result, auto-select it
            if results.count == 1 {
                selectItem(results[0])
            }
        }
    }
    
    private func handleScannerError(_ error: String) {
        Logger.warn("Search", "Scanner error: \(error)")
        scannerError = error
        
        // Clear scanner error after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.scannerError = nil
        }
    }
}

// MARK: - Search View
struct SearchView: View {
    @StateObject private var controller = SearchViewController()
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Header
                SearchHeaderView(
                    searchText: $controller.searchText,
                    isSearching: controller.isSearching,
                    scannerEnabled: controller.scannerEnabled,
                    onToggleScanner: {
                        if controller.scannerEnabled {
                            controller.disableScanner()
                        } else {
                            controller.enableScanner()
                        }
                    },
                    onShowFilters: {
                        showingFilters = true
                    },
                    onClearSearch: {
                        controller.clearSearch()
                    }
                )
                
                // Scanner Status
                if let scannerError = controller.scannerError {
                    ScannerErrorView(error: scannerError)
                } else if !controller.lastScannedCode.isEmpty {
                    ScannerStatusView(lastCode: controller.lastScannedCode)
                }
                
                // Search Results
                SearchResultsView(
                    results: controller.searchResults,
                    isSearching: controller.isSearching,
                    searchError: controller.searchError,
                    onSelectItem: controller.selectItem
                )
                
                Spacer()
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingFilters) {
                SearchFiltersView(
                    filters: $controller.searchFilters,
                    onApply: { filters in
                        controller.updateSearchFilters(filters)
                        showingFilters = false
                    }
                )
            }
            .sheet(isPresented: $controller.showingItemDetail) {
                if let item = controller.selectedItem {
                    ItemDetailView(item: item)
                }
            }
        }
        // Add HID scanner overlay
        .hidScanner(
            enabled: controller.scannerEnabled,
            onScan: { barcode in
                // This will be handled by the controller's HID scanner
            },
            onError: { error in
                // This will be handled by the controller's HID scanner
            }
        )
    }
}

// MARK: - Supporting Views
struct SearchHeaderView: View {
    @Binding var searchText: String
    let isSearching: Bool
    let scannerEnabled: Bool
    let onToggleScanner: () -> Void
    let onShowFilters: () -> Void
    let onClearSearch: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search items, SKUs, barcodes...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: onClearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Scanner toggle
                Button(action: onToggleScanner) {
                    Image(systemName: scannerEnabled ? "barcode.viewfinder" : "barcode")
                        .foregroundColor(scannerEnabled ? .blue : .secondary)
                        .font(.title2)
                }
                
                // Filters button
                Button(action: onShowFilters) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct ScannerErrorView: View {
    let error: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
    }
}

struct ScannerStatusView: View {
    let lastCode: String
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
            Text("Last scanned: \(lastCode)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
    }
}

#Preview {
    SearchView()
}
