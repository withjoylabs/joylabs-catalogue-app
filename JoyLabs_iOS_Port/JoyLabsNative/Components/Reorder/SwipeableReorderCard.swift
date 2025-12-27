import SwiftUI

// MARK: - Display Name Formatting
private func formatDisplayName(itemName: String?, variationName: String?) -> String {
    let name = itemName ?? "Unknown Item"
    if let variation = variationName, !variation.isEmpty {
        return "\(name) • \(variation)"
    }
    return name
}

struct SwipeableReorderCard: View {
    let item: ReorderItem
    let displayMode: ReorderDisplayMode
    let onStatusChange: (ReorderItemStatus) -> Void
    let onQuantityChange: (Int) -> Void
    let onQuantityTap: () -> Void // Tap to show quantity modal
    let onRemove: () -> Void
    let onImageTap: () -> Void
    let onImageLongPress: ((ReorderItem) -> Void)?
    let onItemDetailsLongPress: (ReorderItem) -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    
    // Standard card height to ensure buttons match exactly
    private let cardHeight: CGFloat = 66

    var body: some View {
        ZStack {
            // Background layer - action buttons (behind main content)
            HStack(spacing: 0) {
                // Left action - Mark as Received (revealed by swiping right)
                if offset > 0 {
                    SwipeActionButton(
                        icon: "checkmark.circle.fill",
                        title: "Received",
                        color: .green,
                        width: offset,
                        cardHeight: cardHeight,
                        action: {
                            onStatusChange(.received)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                    )
                }
                
                Spacer()
                
                // Right action - Delete (revealed by swiping left)
                if offset < 0 {
                    SwipeActionButton(
                        icon: "trash.fill",
                        title: "Delete",
                        color: .red,
                        width: abs(offset),
                        cardHeight: cardHeight,
                        action: {
                            onRemove()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                    )
                }
            }
            .frame(height: cardHeight)
            
            // Foreground layer - main content (on top)
            HStack(spacing: 11) {
                // Radio button (left side) - only 2 states: empty/filled
                Button(action: {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0)) {
                        toggleStatus()
                    }
                }) {
                    Image(systemName: getRadioButtonSystemImage())
                        .font(.system(size: 22))
                        .foregroundColor(item.status == .added ? Color(.systemGray3) : .blue)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PlainButtonStyle())

                // Thumbnail image - exact same size as scan page (50px) - tappable for enlargement, long-press for update
                NativeImageView.thumbnail(
                    imageId: item.imageId,
                    size: 50
                )
                .contentShape(Rectangle())
                .highPriorityGesture(
                    // High priority: Long press for image update
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            print("[ReorderCard] IMAGE long press detected - calling onImageLongPress")
                            onImageLongPress?(item)
                        }
                )
                .onTapGesture {
                    // Tap to toggle checkbox (same as radio button)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0)) {
                        toggleStatus()
                    }
                }

                // Main content section - with isolated touch target for item details long press
                VStack(alignment: .leading, spacing: 6) {
                    // Item name with variation - allow wrapping to full available width
                    Text(formatDisplayName(itemName: item.name, variationName: item.variationName))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true) // Force proper wrapping on iPhone

                    // Category, UPC, SKU, price row - prevent overflow with SKU truncation
                    HStack(spacing: 8) {
                        // Category with background - fixed size (priority 1)
                        if let categoryName = item.categoryName, !categoryName.isEmpty {
                            Text(categoryName)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false) // Never truncate category
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }

                        // UPC - fixed size (priority 2)
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text(barcode)
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false) // Never truncate UPC
                                .lineLimit(1)
                        }

                        // Bullet point separator (only if both UPC and SKU are present)
                        if let barcode = item.barcode, !barcode.isEmpty,
                           let sku = item.sku, !sku.isEmpty {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        // SKU - flexible width, can truncate (priority 3)
                        if let sku = item.sku, !sku.isEmpty {
                            Text(sku)
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail) // Show ... at end if too long
                                // NO fixedSize - allows truncation
                        }

                        // Bullet separator before price
                        if item.price != nil {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        // Price - LEFT ALIGNED WITH OTHER DETAILS
                        if let price = item.price {
                            Text(String(format: "$%.2f", price))
                                .font(.system(size: 11))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tap on item details opens quantity modal
                    print("[ReorderCard] Item details tapped - calling onQuantityTap")
                    onQuantityTap()
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            print("[ReorderCard] Long press detected - calling onItemDetailsLongPress")
                            onItemDetailsLongPress(item)
                        }
                )

                Spacer()

                // Quantity section (right side) - TAPPABLE for editing
                Button(action: onQuantityTap) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(item.quantity)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("qty")
                            .font(.system(size: 10))
                            .foregroundColor(Color.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .frame(height: cardHeight)
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        isDragging = true
                        
                        let translation = value.translation.width
                        let initialThreshold: CGFloat = 20  // Must drag at least 20px horizontally before gesture starts
                        
                        // Only start responding after initial threshold is met
                        guard abs(translation) > initialThreshold else {
                            return
                        }
                        
                        // Apply resistance after initial threshold is overcome
                        let adjustedTranslation = translation > 0 ? 
                            translation - initialThreshold : 
                            translation + initialThreshold
                        let resistance: CGFloat = 0.5  // Moderate resistance after initiation
                        
                        if translation > 0 {
                            offset = min(adjustedTranslation * resistance, 100)
                        } else {
                            offset = max(adjustedTranslation * resistance, -100)
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        let translation = value.translation.width
                        let initialThreshold: CGFloat = 20
                        
                        // Only consider action if we've overcome the initial threshold
                        guard abs(translation) > initialThreshold else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                            return
                        }
                        
                        // Use adjusted translation (minus initial threshold) for action completion
                        let adjustedTranslation = abs(translation) - initialThreshold
                        
                        // Higher thresholds to require very intentional gestures (150px beyond initial threshold)
                        if adjustedTranslation > 150 {
                            if translation > 0 {
                                onStatusChange(.received)
                            } else {
                                onRemove()
                            }
                        }
                        
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

    private func toggleStatus() {
        // Only toggle between added and purchased
        // Received items should be swiped away, not toggled
        switch item.status {
        case .added:
            onStatusChange(.purchased)
        case .purchased:
            onStatusChange(.added)
        case .received:
            // Received items shouldn't be in the list, but if they are, reset to added
            onStatusChange(.added)
        }
    }
    
    private func getRadioButtonSystemImage() -> String {
        switch item.status {
        case .added:
            return "circle"
        case .purchased, .received:
            return "checkmark.circle.fill"
        }
    }
}