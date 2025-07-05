import SwiftUI

/// SearchResultsView - Displays search results with sophisticated filtering and sorting
/// Ports the search results UI from React Native
struct SearchResultsView: View {
    let results: [SearchResultItem]
    let isSearching: Bool
    let searchError: String?
    let onSelectItem: (SearchResultItem) -> Void
    
    var body: some View {
        Group {
            if isSearching {
                SearchLoadingView()
            } else if let error = searchError {
                SearchErrorView(error: error)
            } else if results.isEmpty {
                SearchEmptyView()
            } else {
                SearchResultsList(results: results, onSelectItem: onSelectItem)
            }
        }
    }
}

// MARK: - Search Loading View
struct SearchLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Search Error View
struct SearchErrorView: View {
    let error: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Search Error")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Search Empty View
struct SearchEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Results")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Try adjusting your search terms or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Search Results List
struct SearchResultsList: View {
    let results: [SearchResultItem]
    let onSelectItem: (SearchResultItem) -> Void
    
    var body: some View {
        List {
            // Results header
            Section {
                HStack {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Sort indicator (could be expanded)
                    Text("Relevance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            // Search results
            ForEach(results) { item in
                SearchResultRow(item: item) {
                    onSelectItem(item)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let item: SearchResultItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Item image placeholder
                AsyncImage(url: item.images?.first?.imageData?.url.flatMap(URL.init)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
                
                // Item details
                VStack(alignment: .leading, spacing: 4) {
                    // Item name
                    Text(item.name ?? "Unnamed Item")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Match context and type
                    HStack {
                        MatchTypeBadge(matchType: item.matchType)
                        
                        if let context = item.matchContext, !context.isEmpty {
                            Text(context)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                    
                    // Price and additional info
                    HStack {
                        if let price = item.price {
                            Text("$\(price, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        if let sku = item.sku, !sku.isEmpty {
                            Text("SKU: \(sku)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if item.isFromCaseUpc {
                            CaseUpcBadge()
                        }
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(Color(.systemBackground))
    }
}

// MARK: - Match Type Badge
struct MatchTypeBadge: View {
    let matchType: String
    
    var badgeColor: Color {
        switch matchType {
        case "barcode":
            return .green
        case "sku":
            return .blue
        case "name":
            return .purple
        case "category":
            return .orange
        case "case_upc":
            return .red
        default:
            return .gray
        }
    }
    
    var badgeText: String {
        switch matchType {
        case "barcode":
            return "Barcode"
        case "sku":
            return "SKU"
        case "name":
            return "Name"
        case "category":
            return "Category"
        case "case_upc":
            return "Case UPC"
        default:
            return matchType.capitalized
        }
    }
    
    var body: some View {
        Text(badgeText)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .cornerRadius(4)
    }
}

// MARK: - Case UPC Badge
struct CaseUpcBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "cube.box")
                .font(.caption2)
            Text("Team Data")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.red)
        .cornerRadius(4)
    }
}

// MARK: - Search Filters View
struct SearchFiltersView: View {
    @Binding var filters: SearchFilters
    let onApply: (SearchFilters) -> Void
    
    @State private var localFilters: SearchFilters
    
    init(filters: Binding<SearchFilters>, onApply: @escaping (SearchFilters) -> Void) {
        self._filters = filters
        self.onApply = onApply
        self._localFilters = State(initialValue: filters.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Search In") {
                    FilterToggleRow(
                        title: "Item Names",
                        subtitle: "Search in product names and descriptions",
                        isOn: $localFilters.name,
                        icon: "textformat"
                    )
                    
                    FilterToggleRow(
                        title: "SKUs",
                        subtitle: "Search in product SKUs",
                        isOn: $localFilters.sku,
                        icon: "number"
                    )
                    
                    FilterToggleRow(
                        title: "Barcodes",
                        subtitle: "Search in UPC/EAN barcodes",
                        isOn: $localFilters.barcode,
                        icon: "barcode"
                    )
                    
                    FilterToggleRow(
                        title: "Categories",
                        subtitle: "Search in category names",
                        isOn: $localFilters.category,
                        icon: "folder"
                    )
                }
                
                Section("Search Tips") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Enable 'Barcodes' for HID scanner input")
                        Text("• Use exact SKU or barcode for best results")
                        Text("• Category search finds items in matching categories")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Reset to original filters
                        localFilters = filters
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply(localFilters)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Filter Toggle Row
struct FilterToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchResultsView(
        results: [
            SearchResultItem(
                id: "1",
                name: "Sample Product",
                sku: "SKU123",
                price: 9.99,
                barcode: "123456789012",
                categoryId: "cat1",
                categoryName: "Electronics",
                images: nil,
                matchType: "name",
                matchContext: "Sample Product",
                isFromCaseUpc: false,
                caseUpcData: nil
            )
        ],
        isSearching: false,
        searchError: nil,
        onSelectItem: { _ in }
    )
}
