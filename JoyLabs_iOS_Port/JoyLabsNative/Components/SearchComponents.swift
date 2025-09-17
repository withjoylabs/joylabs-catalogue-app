import SwiftUI

// MARK: - Display Name Formatting
private func formatDisplayName(itemName: String?, variationName: String?) -> String {
    let name = itemName ?? "Unknown Item"
    if let variation = variationName, !variation.isEmpty {
        return "\(name) • \(variation)"
    }
    return name
}

// MARK: - Search Sheet Management
enum SearchSheet: Identifiable {
    case itemDetails(SearchResultItem)
    case imagePicker(SearchResultItem)
    
    var id: String {
        switch self {
        case .itemDetails(let item):
            return "itemDetails_\(item.id)"
        case .imagePicker(let item):
            return "imagePicker_\(item.id)"
        }
    }
}

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
                .foregroundColor(Color.primary.opacity(0.6))
                .fontWeight(.medium)

            TextField("Search products, SKUs, barcodes...", text: $searchText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
                .foregroundColor(.primary)
                .textFieldStyle(.plain)  // Remove default TextField styling

            // Clear button - only show when there's text
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    // Don't auto-focus after clearing to prevent keyboard conflicts
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.primary.opacity(0.5))
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.clear)  // Clear underlying backgrounds
        .glassEffect()  // Apply liquid glass morphism
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
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
    let onItemUpdated: (() -> Void)?
    @State private var activeSheet: SearchSheet?
    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    
    // Standard card height to ensure buttons match exactly
    private let cardHeight: CGFloat = 66

    var body: some View {
        ZStack {
            // Background layer - action buttons (behind main content)
            HStack(spacing: 0) {
                // Left action - Print (revealed by swiping right)
                if offset > 0 {
                    SwipeActionButton(
                        icon: "printer.fill",
                        title: "Print",
                        color: .blue,
                        width: offset,
                        cardHeight: cardHeight,
                        action: {
                            onPrint()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                    )
                }
                
                Spacer()
                
                // Right action - Add to Reorder (revealed by swiping left)
                if offset < 0 {
                    SwipeActionButton(
                        icon: "plus.circle.fill",
                        title: "Add",
                        color: .green,
                        width: abs(offset),
                        cardHeight: cardHeight,
                        action: {
                            onAddToReorder()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                    )
                }
            }
            .frame(height: cardHeight)
            
            // Foreground layer - main content (on top)
            scanResultContent
                .frame(height: cardHeight)
                .background(Color(.systemBackground))
                .offset(x: offset)
                .onTapGesture {
                    if abs(offset) > 5 {
                        // Close swipe actions
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = 0
                        }
                    } else {
                        handleItemSelection()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 30)  // iOS 26 industry standard for swipeable cards
                        .onChanged { value in
                            let translation = value.translation
                            let horizontalThreshold: CGFloat = 30  // Increased threshold for horizontal movement

                            // Calculate drag angle to determine if it's primarily horizontal
                            let angle = atan2(abs(translation.height), abs(translation.width))
                            let isHorizontalDrag = angle < 0.5  // Less than ~30 degrees = horizontal

                            // Only respond to horizontal drags that exceed threshold
                            guard isHorizontalDrag && abs(translation.width) > horizontalThreshold else {
                                return  // Let vertical drags pass through to ScrollView
                            }

                            isDragging = true

                            // Apply resistance after threshold is overcome
                            let adjustedTranslation = translation.width > 0 ?
                                translation.width - horizontalThreshold :
                                translation.width + horizontalThreshold
                            let resistance: CGFloat = 0.5

                            if translation.width > 0 {
                                // Swipe right - reveal print (max 100px)
                                offset = min(adjustedTranslation * resistance, 100)
                            } else {
                                // Swipe left - reveal add to reorder (max 100px)
                                offset = max(adjustedTranslation * resistance, -100)
                            }
                        }
                        .onEnded { value in
                            let translation = value.translation
                            let horizontalThreshold: CGFloat = 30

                            // Calculate drag angle
                            let angle = atan2(abs(translation.height), abs(translation.width))
                            let isHorizontalDrag = angle < 0.5

                            // Only process end action for horizontal drags
                            guard isHorizontalDrag && abs(translation.width) > horizontalThreshold else {
                                isDragging = false
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    offset = 0
                                }
                                return
                            }

                            isDragging = false

                            // Use adjusted translation for action completion
                            let adjustedTranslation = abs(translation.width) - horizontalThreshold

                            // Higher threshold to require intentional gestures (120px beyond initial threshold)
                            if adjustedTranslation > 120 {
                                if translation.width > 0 {
                                    // Complete print action
                                    onPrint()
                                } else {
                                    // Complete add to reorder action
                                    onAddToReorder()
                                }
                            }

                            // Always snap back
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                )
        }
        .clipped()
        .overlay(
            // Stationary bottom border (full width, doesn't move with swipe)
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
            }
        )
    }

    private var imageURL: String? {
        return result.images?.first?.imageData?.url
    }
    
    private var scanResultContent: some View {
        // Extract image data for search results
        let _ = result.images?.first?.id

        return HStack(spacing: 12) {
            // Thumbnail image (left side) - using simple image system
            // Long press to update image
            SimpleImageView.thumbnail(
                imageURL: imageURL,
                size: 50
            )
            .onLongPressGesture {
                activeSheet = .imagePicker(result)
            }

            // Main content section
            VStack(alignment: .leading, spacing: 6) {
                // Item name with variation - allow wrapping to full available width
                Text(formatDisplayName(itemName: result.name, variationName: result.variationName))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true) // Force proper wrapping on iPhone

                // Category, UPC, SKU row - prevent overflow with SKU truncation
                HStack(spacing: 8) {
                    // Category with background - fixed size (priority 1)
                    if let categoryName = result.categoryName, !categoryName.isEmpty {
                        Text(categoryName)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.secondary)
                            .fixedSize(horizontal: true, vertical: false) // Never truncate category
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    } else {
                        // Debug: Show when category is missing - essential for debugging
                        Text("NO CAT")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: true, vertical: false) // Never truncate debug info
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(2)
                    }

                    // UPC - fixed size (priority 2)
                    if let barcode = result.barcode, !barcode.isEmpty {
                        Text(barcode)
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
                            .fixedSize(horizontal: true, vertical: false) // Never truncate UPC
                            .lineLimit(1)
                    }

                    // Bullet point separator (only if both UPC and SKU are present)
                    if let barcode = result.barcode, !barcode.isEmpty,
                       let sku = result.sku, !sku.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // SKU - flexible width, can truncate (priority 3)
                    if let sku = result.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail) // Show ... at end if too long
                            // NO fixedSize - allows truncation
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
        // Tap gesture handled by swipe gesture above (line 146)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(itemId: item.id),
                    onDismiss: {
                        activeSheet = nil
                    },
                    onSave: { itemData in
                        // Dismiss the modal
                        activeSheet = nil
                        
                        // Trigger search refresh to show updated item data
                        onItemUpdated?()
                    }
                )
                .fullScreenModal()
            case .imagePicker(let item):
                UnifiedImagePickerModal(
                    context: .scanViewLongPress(
                        itemId: item.id,
                        imageId: item.images?.first?.id
                    ),
                    onDismiss: {
                        activeSheet = nil
                    },
                    onImageUploaded: { uploadResult in
                        // SimpleImageService handles all refresh notifications
                        activeSheet = nil
                    }
                )
                .imagePickerModal()
            }
        }
    }

    
    private func handleItemSelection() {
        print("Selected item: \(result.name ?? result.id)")
        activeSheet = .itemDetails(result)
    }
}

// MARK: - Swipe Action Button Component
struct SwipeActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let width: CGFloat
    let cardHeight: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: true, vertical: false) // Prevent word wrapping
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .frame(width: width, height: cardHeight) // Match exact card height
        .background(color)
        .contentShape(Rectangle())
        .clipped() // Prevent overflow
    }
}


// MARK: - Product Info View
struct ProductInfoView: View {
    let result: SearchResultItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDisplayName(itemName: result.name, variationName: result.variationName))
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
        reportingCategoryId: "coffee",
        categoryName: "Coffee & Tea",
        variationName: "Dark Roast",
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
        },
        onItemUpdated: {
            print("Item updated!")
        }
    )
    .padding()
}

#Preview("Original Scan Result Card") {
    // Legacy preview removed - use SwipeableScanResultCard instead
    Text("Use SwipeableScanResultCard preview instead")
        .foregroundColor(.secondary)
}
