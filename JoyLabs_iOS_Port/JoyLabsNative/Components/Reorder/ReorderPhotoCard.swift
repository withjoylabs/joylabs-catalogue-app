import SwiftUI

// MARK: - Display Name Formatting
private func formatDisplayName(itemName: String?, variationName: String?) -> String {
    let name = itemName ?? "Unknown Item"
    if let variation = variationName, !variation.isEmpty {
        return "\(name) • \(variation)"
    }
    return name
}

struct ReorderPhotoCard: View {
    let item: ReorderItem
    let displayMode: ReorderDisplayMode
    let onStatusChange: (ReorderStatus) -> Void
    let onQuantityChange: (Int) -> Void
    let onRemove: () -> Void
    let onImageTap: () -> Void // Photo tap toggles bought status
    let onImageLongPress: ((ReorderItem) -> Void)? // Long-press image to update image
    let onItemDetailsTap: () -> Void // Tap item details to show quantity modal
    let onItemDetailsLongPress: (ReorderItem) -> Void // Long press item details to edit item
    @State private var offset: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            // Responsive 1:1 aspect ratio image with check overlay
            GeometryReader { geometry in
                let imageSize = geometry.size.width
                ZStack {
                    // Background image
                    SimpleImageView(
                        imageURL: item.imageUrl,
                        size: imageSize,
                        contentMode: .fill
                    )
                    .frame(width: imageSize, height: imageSize) // Perfect 1:1 square
                    .clipped()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    // Check radio button overlay (top-left corner)
                    VStack {
                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0)) {
                                    let newStatus: ReorderStatus = (item.status == .added) ? .purchased : .added
                                    onStatusChange(newStatus)
                                }
                            }) {
                                Image(systemName: getPhotoCardSystemImage())
                                    .font(.system(size: min(imageSize * 0.15, 24))) // Responsive size
                                    .foregroundColor(item.status == .purchased ? .green : Color(.systemGray3))
                                    .background(Color(.systemBackground).opacity(0.8))
                                    .clipShape(Circle())
                            }
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit) // Maintain 1:1 aspect ratio at container level
            .contentShape(Rectangle())
            .onLongPressGesture {
                print("[ReorderPhotoCard] Image long press detected - calling onImageLongPress")
                onImageLongPress?(item)
            }
            .onTapGesture {
                print("[ReorderPhotoCard] Image tap detected - toggling status")
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0)) {
                    let newStatus: ReorderStatus = (item.status == .added) ? .purchased : .added
                    onStatusChange(newStatus)
                }
            }

            // Item details underneath (tappable for quantity modal, long-press for item details)
            VStack {
                // Layout varies by display mode
                if displayMode == .photosSmall {
                    // SMALL VIEW: Item name only, all 4 rows
                    HStack(alignment: .top, spacing: 6) {
                        // COLUMN 1: Item name only (rows 1-4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(formatDisplayName(itemName: item.name, variationName: item.variationName))
                                .font(.system(size: 11, weight: .medium)) // 2 steps smaller than medium
                                .multilineTextAlignment(.leading)
                                .lineLimit(4) // Use all 4 rows for item name
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading) // Fixed height for 4 lines + spacing
                        }
                        .frame(maxWidth: nil, alignment: .leading)

                        // COLUMN 2: Quantity
                        VStack(alignment: .trailing, spacing: 1) {
                            // Qty # (2 steps smaller)
                            Text("\(item.quantity)")
                                .font(.system(size: 12, weight: .semibold)) // 2 steps smaller than medium (16->12)
                                .foregroundColor(.primary)
                            
                            // "qty"
                            Text("qty")
                                .font(.system(size: 8)) // 2 steps smaller than medium (10->8)
                                .foregroundColor(Color.secondary)
                        }
                        .frame(minWidth: 30) // Smaller minimum width for small view
                    }
                } else {
                    // MEDIUM/LARGE VIEWS: Original 2x2 layout
                    HStack(alignment: .top, spacing: 8) {
                        // COLUMN 1: Item information
                        VStack(alignment: .leading, spacing: itemDetailSpacing) {
                            // Column 1, Rows 1-3: Item Name (for medium photos)
                            if displayMode == .photosMedium {
                                Text(formatDisplayName(itemName: item.name, variationName: item.variationName))
                                    .font(itemNameFont)
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading) // Fixed height for 3 lines + spacing
                            } else {
                                Text(formatDisplayName(itemName: item.name, variationName: item.variationName))
                                    .font(itemNameFont)
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Column 1, Row 4: Category, UPC, Price (for medium photos)
                            // For medium photos, show category, UPC, and price on row 4
                            if displayMode == .photosMedium {
                                HStack(spacing: 4) {
                                    // Category badge
                                    if let category = item.categoryName, !category.isEmpty {
                                        Text(category)
                                            .font(.system(size: 9, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                            .lineLimit(1)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(3)
                                    }
                                    
                                    // UPC
                                    if let barcode = item.barcode, !barcode.isEmpty {
                                        Text(barcode)
                                            .font(.system(size: 9))
                                            .foregroundColor(Color.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    // Price
                                    if let price = item.price {
                                        Text(String(format: "$%.2f", price))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                }
                            } else {
                                // Full details for large photos view
                                HStack(spacing: 6) {
                                    // Category badge
                                    if let category = item.categoryName, !category.isEmpty {
                                        Text(category)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .lineLimit(1)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(4)
                                    }

                                    // UPC/Barcode
                                    if let barcode = item.barcode, !barcode.isEmpty {
                                        Text(barcode)
                                            .font(detailFont)
                                            .foregroundColor(Color.secondary)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .lineLimit(1)
                                    }

                                    // Bullet separator
                                    if let barcode = item.barcode, !barcode.isEmpty,
                                       let sku = item.sku, !sku.isEmpty {
                                        Text("•")
                                            .font(detailFont)
                                            .foregroundColor(Color.secondary)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }

                                    // SKU
                                    if let sku = item.sku, !sku.isEmpty {
                                        Text(sku)
                                            .font(detailFont)
                                            .foregroundColor(Color.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }

                                    // Bullet separator before price
                                    if item.price != nil {
                                        Text("•")
                                            .font(detailFont)
                                            .foregroundColor(Color.secondary)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }

                                    // Price - LEFT ALIGNED WITH OTHER DETAILS
                                    if let price = item.price {
                                        Text(String(format: "$%.2f", price))
                                            .font(detailFont)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }

                                    Spacer()
                                }
                            }
                        }
                        .frame(maxWidth: displayMode == .photosMedium ? nil : .infinity, alignment: .leading)

                        // COLUMN 2: Quantity
                        VStack(alignment: .trailing, spacing: 1) {
                            // Column 2, Row 1: Qty #
                            Text("\(item.quantity)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            // Column 2, Row 2: "qty"
                            Text("qty")
                                .font(.system(size: 10))
                                .foregroundColor(Color.secondary)
                        }
                        .frame(minWidth: 40)
                    }
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture {
                print("[ReorderPhotoCard] Item details long press detected - calling onItemDetailsLongPress")
                onItemDetailsLongPress(item)
            }
            .onTapGesture {
                print("[ReorderPhotoCard] Item details tap detected - calling onItemDetailsTap")
                onItemDetailsTap()
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .offset(x: offset)
    }

    // MARK: - Computed Properties for Responsive Design
    
    private var itemNameFont: Font {
        switch displayMode {
        case .list:
            return .caption
        case .photosLarge:
            return .body
        case .photosMedium:
            return .callout
        case .photosSmall:
            return .callout  // Increased from .caption
        }
    }
    
    private var categoryFont: Font {
        switch displayMode {
        case .list:
            return .caption2
        case .photosLarge:
            return .callout
        case .photosMedium:
            return .caption
        case .photosSmall:
            return .caption  // Increased from .caption2
        }
    }
    
    private var detailFont: Font {
        switch displayMode {
        case .list:
            return .caption2
        case .photosLarge:
            return .caption
        case .photosMedium:
            return .caption2
        case .photosSmall:
            return .caption  // Increased from .caption2
        }
    }
    
    private var itemDetailSpacing: CGFloat {
        switch displayMode {
        case .list:
            return 2
        case .photosLarge:
            return 6
        case .photosMedium:
            return 4
        case .photosSmall:
            return 3
        }
    }
    
    private var itemNameLineLimit: Int {
        switch displayMode {
        case .list:
            return 2
        case .photosLarge:
            return 3
        case .photosMedium:
            return 2
        case .photosSmall:
            return 2
        }
    }
    
    private var showAllDetails: Bool {
        displayMode == .photosLarge
    }

    // MARK: - Helper Methods
    
    private func toggleStatus() {
        switch item.status {
        case .added:
            onStatusChange(.purchased)
        case .purchased:
            onStatusChange(.added)
        case .received:
            onStatusChange(.added)
        }
    }
    
    private func getPhotoCardSystemImage() -> String {
        switch item.status {
        case .added:
            return "circle"
        case .purchased, .received:
            return "checkmark.circle.fill"
        }
    }
}