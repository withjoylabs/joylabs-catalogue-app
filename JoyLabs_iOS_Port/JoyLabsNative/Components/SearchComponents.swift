import SwiftUI

// MARK: - Bottom Search Bar
struct BottomSearchBar: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                SearchTextField(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
                
                ScanButton()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Search Text Field
struct SearchTextField: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search products, SKUs, barcodes...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.default)
                .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Scan Button
struct ScanButton: View {
    var body: some View {
        Button(action: {
            // TODO: Implement barcode scanning
        }) {
            Image(systemName: "barcode.viewfinder")
                .font(.title2)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Search Result Card
struct SearchResultCard: View {
    let result: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProductInfoView(result: result)
                
                Spacer()
                
                PriceInfoView(result: result)
            }

            if result.isFromCaseUpc, let caseData = result.caseUpcData {
                CaseInfoView(caseData: caseData)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .onTapGesture {
            handleItemSelection()
        }
    }
    
    private func handleItemSelection() {
        // Handle item selection
        print("Selected item: \(result.name ?? result.id)")
    }
}

// MARK: - Product Info View
struct ProductInfoView: View {
    let result: SearchResultItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.name ?? "Unknown Item")
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            if let sku = result.sku {
                Text("SKU: \(sku)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let barcode = result.barcode {
                Text("UPC: \(barcode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Price Info View
struct PriceInfoView: View {
    let result: SearchResultItem
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let price = result.price, price.isFinite && !price.isNaN {
                Text("$\(price, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            MatchTypeBadge(matchType: result.matchType)
        }
    }
}

// MARK: - Match Type Badge
struct MatchTypeBadge: View {
    let matchType: String
    
    var body: some View {
        Text(matchType.uppercased())
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
    }
}

// MARK: - Case Info View
struct CaseInfoView: View {
    let caseData: CaseUpcData
    
    var body: some View {
        HStack {
            Image(systemName: "cube.box")
                .foregroundColor(.orange)

            Text("Case: \(caseData.caseQuantity ?? 0) units")
                .font(.caption)
                .foregroundColor(.orange)

            Spacer()

            if let caseCost = caseData.caseCost, caseCost.isFinite && !caseCost.isNaN {
                Text("$\(caseCost, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Search Bar with Clear Button
struct SearchBarWithClear: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    let placeholder: String
    
    init(searchText: Binding<String>, isSearchFieldFocused: FocusState<Bool>.Binding, placeholder: String = "Search...") {
        self._searchText = searchText
        self._isSearchFieldFocused = isSearchFieldFocused
        self.placeholder = placeholder
    }
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview("Bottom Search Bar") {
    @Previewable @State var searchText = ""
    @Previewable @FocusState var isSearchFieldFocused: Bool

    BottomSearchBar(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
}

#Preview("Search Result Card") {
    let sampleResult = SearchResultItem(
        id: "1",
        name: "Sample Product",
        sku: "SKU123",
        price: 19.99,
        barcode: "1234567890",
        categoryId: nil,
        categoryName: nil,
        images: [],
        matchType: "name",
        matchContext: "",
        isFromCaseUpc: false,
        caseUpcData: nil,
        hasTax: true
    )

    SearchResultCard(result: sampleResult)
        .padding()
}
