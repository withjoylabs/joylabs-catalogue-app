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
                .submitLabel(.done)
                .onSubmit {
                    // Dismiss keyboard when Done is pressed
                    isSearchFieldFocused = false
                }

            // Clear button - only show when there's text
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearchFieldFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
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
struct ScanResultCard: View {
    let result: SearchResultItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail image (left side) - using cached image system with real Square image ID
            CachedImageView.catalogItem(
                imageURL: result.images?.first?.imageData?.url,
                imageId: result.images?.first?.id,
                size: 50
            )

            // Main content section
            VStack(alignment: .leading, spacing: 6) {
                // Item name
                Text(result.name ?? "Unknown Item")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Category, UPC, SKU row
                HStack(spacing: 8) {
                    // Category with background - reduced visual intensity
                    if let categoryName = result.categoryName, !categoryName.isEmpty {
                        Text(categoryName)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    } else {
                        // Debug: Show when category is missing - essential for debugging
                        Text("NO CAT")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(2)
                    }

                    // UPC
                    if let barcode = result.barcode, !barcode.isEmpty {
                        Text(barcode)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Bullet point separator (only if both UPC and SKU are present)
                    if let barcode = result.barcode, !barcode.isEmpty,
                       let sku = result.sku, !sku.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // SKU
                    if let sku = result.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            Spacer()

            // Price section (right side)
            VStack(alignment: .trailing, spacing: 2) {
                if let price = result.price, price.isFinite && !price.isNaN {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    // Show "+tax" if item has taxes
                    if result.hasTax {
                        Text("+tax")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            // Subtle divider line like iOS Reminders
            VStack {
                Spacer()
                HStack {
                    // Start divider after thumbnail (60px + 12px spacing = 72px from left)
                    Spacer()
                        .frame(width: 62)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
            }
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
                .submitLabel(.done)
                .onSubmit {
                    // Dismiss keyboard when Done is pressed
                    isSearchFieldFocused = false
                }
            
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

#Preview("Scan Result Card") {
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

    ScanResultCard(result: sampleResult)
        .padding()
}
