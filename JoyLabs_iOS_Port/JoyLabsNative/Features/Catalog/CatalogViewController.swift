import SwiftUI
import Combine

/// CatalogViewController - Manages catalog browsing and filtering
/// Provides comprehensive catalog management functionality
@MainActor
class CatalogViewController: ObservableObject {
    // MARK: - Published Properties
    @Published var items: [SearchResultItem] = []
    @Published var categories: [CategoryItem] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: String?
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // Filtering and sorting
    @Published var sortOption: SortOption = .name
    @Published var filterOptions = FilterOptions()
    
    // MARK: - Private Properties
    private let databaseManager = DatabaseManager()
    private let searchManager = SearchManager()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    // MARK: - Public Methods
    func loadCatalog() async {
        isLoading = true
        error = nil
        
        do {
            // Load categories
            let categoryRows = try await databaseManager.getAllCategories()
            categories = categoryRows.map { row in
                CategoryItem(
                    id: row.id,
                    name: row.name ?? "Unnamed Category",
                    itemCount: 0 // TODO: Calculate item count
                )
            }
            
            // Load all items initially
            await loadAllItems()
            
            isLoading = false
            
        } catch {
            Logger.error("Catalog", "Failed to load catalog: \(error)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task {
                await loadAllItems()
            }
            return
        }
        
        Task {
            let filters = SearchFilters(
                name: true,
                sku: true,
                barcode: true,
                category: true
            )
            
            let results = await searchManager.performSearch(
                searchTerm: searchText,
                filters: filters
            )
            
            await MainActor.run {
                self.items = results
            }
        }
    }
    
    func filterByCategory(_ categoryId: String?) {
        selectedCategory = categoryId
        
        Task {
            if let categoryId = categoryId {
                await loadItemsForCategory(categoryId)
            } else {
                await loadAllItems()
            }
        }
    }
    
    func sortItems(by option: SortOption) {
        sortOption = option
        applySorting()
    }
    
    func refreshCatalog() async {
        await loadCatalog()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Auto-search when text changes (with debouncing)
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
        
        // Auto-sort when sort option changes
        $sortOption
            .sink { [weak self] _ in
                self?.applySorting()
            }
            .store(in: &cancellables)
    }
    
    private func loadAllItems() async {
        // This would typically load from database with pagination
        // For now, we'll use search with empty term to get all items
        let filters = SearchFilters(name: true, sku: true, barcode: true, category: true)
        let results = await searchManager.performSearch(searchTerm: "", filters: filters)
        
        await MainActor.run {
            self.items = results
            self.applySorting()
        }
    }
    
    private func loadItemsForCategory(_ categoryId: String) async {
        // This would load items filtered by category
        // For now, we'll filter the existing items
        let allItems = items
        let filteredItems = allItems.filter { $0.categoryId == categoryId }
        
        await MainActor.run {
            self.items = filteredItems
            self.applySorting()
        }
    }
    
    private func applySorting() {
        switch sortOption {
        case .name:
            items.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        case .price:
            items.sort { ($0.price ?? 0) < ($1.price ?? 0) }
        case .category:
            items.sort { ($0.categoryName ?? "").localizedCaseInsensitiveCompare($1.categoryName ?? "") == .orderedAscending }
        case .dateAdded:
            // Would sort by creation date if available
            break
        }
    }
}

// MARK: - Supporting Types
struct CategoryItem: Identifiable {
    let id: String
    let name: String
    let itemCount: Int
}

enum SortOption: String, CaseIterable {
    case name = "Name"
    case price = "Price"
    case category = "Category"
    case dateAdded = "Date Added"
    
    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .price: return "dollarsign.circle"
        case .category: return "folder"
        case .dateAdded: return "calendar"
        }
    }
}

struct FilterOptions {
    var showDiscontinued: Bool = false
    var priceRange: ClosedRange<Double> = 0...1000
    var hasImages: Bool = false
    var inStock: Bool = false
}

// MARK: - Catalog UI Components

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    onSearchButtonClicked()
                }
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct CategoryFilterView: View {
    let categories: [CategoryItem]
    @Binding var selectedCategory: String?
    let onCategorySelected: (String?) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All categories button
                CategoryFilterButton(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    action: {
                        onCategorySelected(nil)
                    }
                )
                
                // Individual category buttons
                ForEach(categories) { category in
                    CategoryFilterButton(
                        title: category.name,
                        isSelected: selectedCategory == category.id,
                        action: {
                            onCategorySelected(category.id)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CatalogItemsList: View {
    let items: [SearchResultItem]
    let onItemSelected: (SearchResultItem) -> Void
    
    var body: some View {
        List {
            ForEach(items) { item in
                CatalogItemRow(item: item) {
                    onItemSelected(item)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct CatalogItemRow: View {
    let item: SearchResultItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Item image using SimpleImageView
                SimpleImageView.thumbnail(
                    imageURL: item.images?.first?.imageData?.url,
                    size: 50
                )
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
                
                // Item details
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unnamed Item")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let categoryName = item.categoryName {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                    
                    HStack {
                        if let price = item.price {
                            Text("$\(price, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        
                        if let sku = item.sku {
                            Text("SKU: \(sku)")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CatalogEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(Color.secondary)
            
            Text("No Items Found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
