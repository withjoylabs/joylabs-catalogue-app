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
                .foregroundColor(Color.secondary)

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
                        .foregroundColor(Color.secondary)
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

// MARK: - Swipeable Search Result Card with Gestures
struct SwipeableScanResultCard: View {
    let result: SearchResultItem
    let onAddToReorder: () -> Void
    let onPrint: () -> Void
    @State private var showingItemDetails = false
    @State private var showingImagePicker = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let addToReorderThreshold: CGFloat = -120  // Swipe left threshold
    private let printThreshold: CGFloat = 120          // Swipe right threshold

    var body: some View {
        ZStack {
            // Background colors that fill the space like iOS Reminders
            HStack(spacing: 0) {
                // Left side - Blue background for print (swipe right)
                if dragOffset > 0 {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: min(dragOffset, UIScreen.main.bounds.width))
                        .overlay(
                            HStack {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        onPrint()
                                        dragOffset = 0
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "printer.fill")
                                            .font(.title2)
                                        Text("Print")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                                .opacity(dragOffset > 40 ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.2), value: dragOffset)

                                Spacer()
                            }
                            .padding(.leading, 20)
                        )
                }

                Spacer()

                // Right side - Green background for add to reorder (swipe left)
                if dragOffset < 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: min(abs(dragOffset), UIScreen.main.bounds.width))
                        .overlay(
                            HStack {
                                Spacer()

                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        onAddToReorder()
                                        dragOffset = 0
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                        Text("Add")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                                .opacity(abs(dragOffset) > 40 ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.2), value: dragOffset)
                            }
                            .padding(.trailing, 20)
                        )
                }
            }

            // Main content card (same as original ScanResultCard)
            scanResultContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            // Only update dragOffset, don't trigger additional animations
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            isDragging = false
                            let finalOffset = dragOffset

                            // Auto-complete actions based on threshold
                            if finalOffset < addToReorderThreshold {
                                // Full swipe left - auto add to reorder
                                onAddToReorder()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            } else if finalOffset > printThreshold {
                                // Full swipe right - auto print
                                onPrint()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            } else {
                                // Snap back to center
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    private var scanResultContent: some View {
        // Extract image data for search results
        let imageURL = result.images?.first?.imageData?.url
        let imageId = result.images?.first?.id

        return HStack(spacing: 12) {
            // Thumbnail image (left side) - using unified image system
            // Long press to update image
            UnifiedImageView.thumbnail(
                imageURL: imageURL,
                imageId: imageId,
                itemId: result.id,
                size: 50
            )
            .onLongPressGesture {
                showingImagePicker = true
            }

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
                            .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
                    }

                    // Bullet point separator (only if both UPC and SKU are present)
                    if let barcode = result.barcode, !barcode.isEmpty,
                       let sku = result.sku, !sku.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
                    }

                    // SKU
                    if let sku = result.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
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
        .sheet(isPresented: $showingItemDetails) {
            ItemDetailsModal(
                context: .editExisting(itemId: result.id),
                onDismiss: {
                    showingItemDetails = false
                },
                onSave: { itemData in
                    // TODO: Handle saved item
                    showingItemDetails = false
                }
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .scanViewLongPress(
                    itemId: result.id,
                    imageId: result.images?.first?.id
                ),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { uploadResult in
                    // UnifiedImageService handles all refresh notifications
                    showingImagePicker = false
                }
            )
        }
    }

    private func handleItemSelection() {
        print("Selected item: \(result.name ?? result.id)")
        showingItemDetails = true
    }
}

// MARK: - Search Result Card (Original - kept for backward compatibility)
struct ScanResultCard: View {
    let result: SearchResultItem
    @State private var showingItemDetails = false
    @State private var showingImagePicker = false

    var body: some View {
        // Extract image data for search results
        let imageURL = result.images?.first?.imageData?.url
        let imageId = result.images?.first?.id

        return HStack(spacing: 12) {
            // Thumbnail image (left side) - using unified image system
            // Long press to update image
            UnifiedImageView.thumbnail(
                imageURL: imageURL,
                imageId: imageId,
                itemId: result.id,
                size: 50
            )
            .onLongPressGesture {
                showingImagePicker = true
            }

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
                            .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
                    }

                    // Bullet point separator (only if both UPC and SKU are present)
                    if let barcode = result.barcode, !barcode.isEmpty,
                       let sku = result.sku, !sku.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
                    }

                    // SKU
                    if let sku = result.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
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
        .sheet(isPresented: $showingItemDetails) {
            ItemDetailsModal(
                context: .editExisting(itemId: result.id),
                onDismiss: {
                    showingItemDetails = false
                },
                onSave: { itemData in
                    // TODO: Handle saved item
                    showingItemDetails = false
                }
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .scanViewLongPress(
                    itemId: result.id,
                    imageId: result.images?.first?.id
                ),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { uploadResult in
                    // UnifiedImageService handles all refresh notifications
                    showingImagePicker = false
                }
            )
        }
    }

    private func handleItemSelection() {
        print("Selected item: \(result.name ?? result.id)")
        showingItemDetails = true
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
                    .foregroundColor(Color.secondary)
            }

            if let barcode = result.barcode {
                Text("UPC: \(barcode)")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
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
                .foregroundColor(Color.secondary)

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
                        .foregroundColor(Color.secondary)
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

#Preview("Swipeable Scan Result Card") {
    let sampleResult = SearchResultItem(
        id: "1",
        name: "Premium Coffee Beans",
        sku: "COF001",
        price: 19.99,
        barcode: "1234567890",
        categoryId: "coffee",
        categoryName: "Coffee & Tea",
        images: [],
        matchType: "name",
        matchContext: "",
        isFromCaseUpc: false,
        caseUpcData: nil,
        hasTax: true
    )

    SwipeableScanResultCard(
        result: sampleResult,
        onAddToReorder: {
            print("Added to reorder list!")
        },
        onPrint: {
            print("Print item!")
        }
    )
    .padding()
}

#Preview("Original Scan Result Card") {
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
