import SwiftUI

// MARK: - Scrollable Reorders Header (collapses on scroll like Profile page)
struct ReordersScrollableHeader: View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int
    let onManagementAction: (ManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Main header area
            VStack(spacing: 16) {
                HStack {
                    Text("Reorders")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Spacer()

                    Menu {
                        Button("Mark All as Received") {
                            onManagementAction(.markAllReceived)
                        }
                        Button("Clear All Items", role: .destructive) {
                            onManagementAction(.clearAll)
                        }
                        Divider()
                        Button("Export Items") {
                            onManagementAction(.export)
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }

                // Stats row - properly aligned
                HStack(spacing: 0) {
                    StatItem(title: "Unpurchased", value: "\(unpurchasedItems)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatItem(title: "Total", value: "\(totalItems)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatItem(title: "Qty", value: "\(totalQuantity)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Management Actions
enum ManagementAction {
    case markAllReceived
    case clearAll
    case export
}

// MARK: - Stat Item
struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Filter Row
struct ReorderFilterRow: View {
    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption
    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // View Options (leftmost)
                Menu {
                    // Organization options
                    Section("Organization") {
                        ForEach(ReorderOrganizationOption.allCases, id: \.self) { option in
                            Button(action: {
                                organizationOption = option
                            }) {
                                HStack {
                                    Image(systemName: option.systemImageName)
                                    Text(option.displayName)
                                    if organizationOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Display mode options
                    Section("Display Mode") {
                        ForEach(ReorderDisplayMode.allCases, id: \.self) { option in
                            Button(action: {
                                displayMode = option
                            }) {
                                HStack {
                                    Image(systemName: option.systemImageName)
                                    Text(option.displayName)
                                    if displayMode == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group")
                            .font(.caption)
                        Text("View")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }

                // Sort options
                Menu {
                    ForEach(ReorderSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                        }) {
                            HStack {
                                Text(option.displayName)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sortOption.systemImageName)
                            .font(.caption)
                        Text(sortOption.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }

                // Filter options
                Menu {
                    ForEach(ReorderFilterOption.allCases, id: \.self) { option in
                        Button(action: {
                            filterOption = option
                        }) {
                            HStack {
                                Text(option.displayName)
                                if filterOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        Text(filterOption.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(filterOption == .all ? Color(.systemGray5) : Color.blue.opacity(0.1))
                    .foregroundColor(filterOption == .all ? .primary : .blue)
                    .cornerRadius(16)
                }


            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Reorders Empty State
struct ReordersEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Reorder Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Add items to your reorder list by scanning products or swipe right on a search result in the Scan page.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



// MARK: - Reorder Item Card (iOS Reminders Style with Swipe Actions)
struct ReorderItemCard: View {
    let item: ReorderItem
    let displayMode: ReorderDisplayMode
    let onStatusChange: (ReorderStatus) -> Void
    let onQuantityChange: (Int) -> Void
    let onQuantityTap: (() -> Void)? // NEW: Callback for tapping quantity to edit
    let onRemove: () -> Void
    let onImageTap: () -> Void
    let onImageLongPress: (() -> Void)? // NEW: Callback for long-pressing image to update

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showingItemDetails = false

    private let deleteThreshold: CGFloat = -120
    private let receivedThreshold: CGFloat = 120
    private let actionButtonWidth: CGFloat = 80

    var body: some View {
        ZStack {
            // Background colors that fill the space like iOS Reminders
            HStack(spacing: 0) {
                // Left side - Green background for received (swipe right)
                if dragOffset > 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: min(dragOffset, UIScreen.main.bounds.width))
                        .overlay(
                            HStack {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        onStatusChange(.received)
                                        dragOffset = 0
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                        Text("Received")
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

                // Right side - Red background for delete (swipe left)
                if dragOffset < 0 {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: min(abs(dragOffset), UIScreen.main.bounds.width))
                        .overlay(
                            HStack {
                                Spacer()

                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        onRemove()
                                        dragOffset = 0
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "trash.fill")
                                            .font(.title2)
                                        Text("Delete")
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

            // Main content card
            HStack(spacing: 11) {
                // Radio button (left side) - only 2 states: empty/filled
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        toggleStatus()
                    }
                }) {
                    Image(systemName: item.status == .added ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(item.status == .added ? Color(.systemGray3) : .blue)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PlainButtonStyle())

                // Thumbnail image - exact same size as scan page (50px) - tappable for enlargement, long-press for update
                Button(action: onImageTap) {
                    UnifiedImageView.thumbnail(
                        imageURL: nil, // Always fetch current primary image
                        imageId: nil,  // Always fetch current primary image
                        itemId: item.itemId,
                        size: 50
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture {
                    onImageLongPress?()
                }

                // Main content section - exact same as scan page
                VStack(alignment: .leading, spacing: 6) {
                    // Item name - exact same styling as scan page
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Category, UPC, SKU row - exact same as scan page
                    HStack(spacing: 8) {
                        // Category with background - exact same styling as scan page
                        if let categoryName = item.categoryName, !categoryName.isEmpty {
                            Text(categoryName)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }

                        // UPC - exact same as scan page
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text(barcode)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        // Bullet point separator (only if both UPC and SKU are present)
                        if let barcode = item.barcode, !barcode.isEmpty,
                           let sku = item.sku, !sku.isEmpty {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        // SKU - exact same as scan page
                        if let sku = item.sku, !sku.isEmpty {
                            Text(sku)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }

                Spacer()

                // Quantity section (right side) - TAPPABLE for editing
                if let onQuantityTap = onQuantityTap {
                    Button(action: onQuantityTap) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.quantity)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("qty")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Fallback to non-tappable display
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(item.quantity)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("qty")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(
                // Subtle divider line like scan page - fixed positioning that moves with content
                VStack {
                    Spacer()
                    HStack {
                        // Start divider after thumbnail (22px + 11px + 50px = 83px from left)
                        Spacer()
                            .frame(width: 83)
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                    }
                }
                .offset(x: dragOffset) // Move divider with content
            )
            .offset(x: dragOffset)
            .onTapGesture {
                // Tap anywhere on the card to open quantity modal
                onQuantityTap?()
            }
            .onLongPressGesture {
                // Long press to open item details
                showingItemDetails = true
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        isDragging = false

                        // Auto-complete actions based on threshold
                        if dragOffset < deleteThreshold {
                            // Full swipe left - auto delete
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                onRemove()
                                dragOffset = 0
                            }
                        } else if dragOffset > receivedThreshold {
                            // Full swipe right - auto mark as received
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                onStatusChange(.received)
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
        .sheet(isPresented: $showingItemDetails) {
            ItemDetailsModal(
                context: .editExisting(itemId: item.itemId),
                onDismiss: {
                    showingItemDetails = false
                },
                onSave: { itemData in
                    // TODO: Handle saved item
                    showingItemDetails = false
                }
            )
        }

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
}

// MARK: - Category Badge (reused from search components)
struct CategoryBadge: View {
    let categoryName: String

    var body: some View {
        Text(categoryName)
            .font(.caption2)
            .fontWeight(.light) // Reduced visual intensity
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
    }
}



#Preview("Reorders Header") {
    ReordersScrollableHeader(
        totalItems: 5,
        unpurchasedItems: 3,
        purchasedItems: 2,
        totalQuantity: 15,
        onManagementAction: { _ in }
    )
}

#Preview("Reorders Empty State") {
    ReordersEmptyState()
}

#Preview("Reorder Item Card") {
    let sampleItem = ReorderItem(
        id: "1",
        itemId: "square-item-1",
        name: "Premium Coffee Beans",
        sku: "COF001",
        barcode: "1234567890",
        quantity: 3,
        status: .added
    )

    ReorderItemCard(
        item: sampleItem,
        displayMode: .list,
        onStatusChange: { _ in },
        onQuantityChange: { _ in },
        onQuantityTap: nil, // No tap action in preview
        onRemove: {},
        onImageTap: {},
        onImageLongPress: nil // No long press action in preview
    )
    .padding()
}

// MARK: - Reorder Photo Card (for photo display modes)
struct ReorderPhotoCard: View {
    let item: ReorderItem
    let displayMode: ReorderDisplayMode
    let onStatusChange: (ReorderStatus) -> Void
    let onQuantityChange: (Int) -> Void
    let onRemove: () -> Void
    let onImageTap: () -> Void
    let onImageLongPress: (() -> Void)? // NEW: Callback for long-pressing image to update

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let deleteThreshold: CGFloat = -120
    private let receivedThreshold: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            // Image (tappable for enlargement, long-press for update)
            Button(action: onImageTap) {
                UnifiedImageView(
                    imageURL: nil, // Always fetch current primary image
                    imageId: nil,  // Always fetch current primary image
                    itemId: item.itemId,
                    size: imageSize,
                    contentMode: .fill
                )
                .frame(width: imageSize, height: imageSize)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture {
                onImageLongPress?()
            }

            // Details (if enabled for this display mode)
            if displayMode.showDetails {
                VStack(spacing: 4) {
                    // Item name
                    Text(item.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    // Category and price
                    HStack {
                        if let category = item.categoryName {
                            Text(category)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let price = item.price {
                            Text(String(format: "$%.2f", price))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                    }

                    // Status and quantity
                    HStack {
                        // Radio button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                toggleStatus()
                            }
                        }) {
                            Image(systemName: item.status == .added ? "circle" : "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(item.status == .added ? Color(.systemGray3) : .blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        // Quantity
                        Text("Qty: \(item.quantity)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    isDragging = false

                    // Auto-complete actions based on threshold
                    if dragOffset < deleteThreshold {
                        // Full swipe left - auto delete
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onRemove()
                            dragOffset = 0
                        }
                    } else if dragOffset > receivedThreshold {
                        // Full swipe right - auto mark as received
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onStatusChange(.received)
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

    private var imageSize: CGFloat {
        switch displayMode {
        case .list:
            return 50
        case .photosLarge:
            return 120
        case .photosMedium:
            return 100
        case .photosSmall:
            return 80
        }
    }

    private func toggleStatus() {
        // Only toggle between added and purchased
        switch item.status {
        case .added:
            onStatusChange(.purchased)
        case .purchased:
            onStatusChange(.added)
        case .received:
            onStatusChange(.added) // Fallback
        }
    }
}


