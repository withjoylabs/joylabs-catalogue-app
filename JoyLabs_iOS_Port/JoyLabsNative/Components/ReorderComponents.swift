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
                .foregroundColor(Color.secondary)
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
                .foregroundColor(Color.secondary)

            VStack(spacing: 8) {
                Text("No Reorder Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Add items to your reorder list by scanning products or swipe right on a search result in the Scan page.")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
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

    @State private var offset: CGFloat = 0
    @State private var showingItemDetails = false
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
                    SimpleImageView.thumbnail(
                        imageURL: item.imageUrl,
                        size: 50
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture {
                    onImageLongPress?()
                }

                // Main content section
                VStack(alignment: .leading, spacing: 6) {
                    // Item name - allow wrapping to full available width, never truncate
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)

                    // Category, UPC, SKU row - prevent overflow with SKU truncation
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
                                .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .frame(height: cardHeight)
            .offset(x: offset)
            .onTapGesture {
                if abs(offset) > 5 {
                    // Close swipe actions
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                    }
                } else {
                    // Tap anywhere on the card to open quantity modal
                    onQuantityTap?()
                }
            }
            .onLongPressGesture {
                // Long press to open item details
                showingItemDetails = true
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        
                        // Simple, smooth swipe with resistance
                        let translation = value.translation.width
                        let resistance: CGFloat = 0.7
                        
                        if translation > 0 {
                            // Swipe right - reveal received (max 100px)
                            offset = min(translation * resistance, 100)
                        } else {
                            // Swipe left - reveal delete (max 100px)
                            offset = max(translation * resistance, -100)
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        
                        let translation = value.translation.width
                        let velocity = value.velocity.width
                        
                        // Simple threshold-based completion
                        if abs(translation) > 60 || abs(velocity) > 500 {
                            if translation > 0 {
                                // Complete received action
                                onStatusChange(.received)
                            } else {
                                // Complete delete action
                                onRemove()
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

// MARK: - Category Badge (matches search results styling exactly)
struct CategoryBadge: View {
    let categoryName: String

    var body: some View {
        Text(categoryName)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray5))
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
    let onImageTap: () -> Void // Photo tap toggles bought status
    let onImageLongPress: (() -> Void)? // Long-press image to update image
    let onItemDetailsTap: () -> Void // Tap item details to show quantity modal
    let onItemDetailsLongPress: () -> Void // Long-press item details to edit item

    @State private var offset: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            // Responsive 1:1 aspect ratio image with check overlay
            Button(action: {
                // Toggle bought status: added -> purchased -> added
                let newStatus: ReorderStatus = (item.status == .added) ? .purchased : .added
                onStatusChange(newStatus)
            }) {
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
                                    let newStatus: ReorderStatus = (item.status == .added) ? .purchased : .added
                                    onStatusChange(newStatus)
                                }) {
                                    Image(systemName: item.status == .purchased ? "checkmark.circle.fill" : "circle")
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
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture {
                onImageLongPress?()
            }

            // Item details underneath (tappable for quantity modal, long-press for item details)
            Button(action: onItemDetailsTap) {
                // Layout varies by display mode
                if displayMode == .photosSmall {
                    // SMALL VIEW: 2 columns, 3 rows layout
                    HStack(alignment: .top, spacing: 8) {
                        // COLUMN 1: Item information
                        VStack(alignment: .leading, spacing: itemDetailSpacing) {
                            // Column 1, Row 1+2: Item Name (top-aligned, consistent height for 2 rows)
                            Text(item.name)
                                .font(itemNameFont)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading) // Fixed height for 2 lines + line spacing
                            
                            // Column 1, Row 3: Category only
                            HStack(spacing: 6) {
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
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // COLUMN 2: Quantity
                        VStack(alignment: .trailing, spacing: 1) {
                            // Column 2, Row 1+2: Qty # (spanning both rows, bigger font to fill the space)
                            Text("\(item.quantity)")
                                .font(.system(size: 24, weight: .semibold)) // Bigger font for 2-row span
                                .foregroundColor(.primary)
                                .frame(minWidth: 40, minHeight: 42, alignment: .topTrailing) // Match item name height with line spacing
                            
                            // Column 2, Row 3: "qty"
                            Text("qty")
                                .font(.system(size: 10))
                                .foregroundColor(Color.secondary)
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                        .frame(minWidth: 40)
                    }
                } else {
                    // MEDIUM/LARGE VIEWS: Original 2x2 layout
                    HStack(alignment: .top, spacing: 8) {
                        // COLUMN 1: Item information
                        VStack(alignment: .leading, spacing: itemDetailSpacing) {
                            // Column 1, Row 1: Item Name
                            Text(item.name)
                                .font(itemNameFont)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Column 1, Row 2: Item Details (category, UPC, SKU, price on same line)
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
                                if let price = item.price {
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
                        .frame(maxWidth: .infinity, alignment: .leading)

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
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture {
                onItemDetailsLongPress()
            }
            .padding(.horizontal, 4)
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .offset(x: offset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let horizontalTranslation = value.translation.width
                    let verticalTranslation = value.translation.height
                    
                    let isHorizontalGesture = abs(horizontalTranslation) > abs(verticalTranslation) * 2.5
                    let hasMinimumHorizontalMovement = abs(horizontalTranslation) > 30
                    
                    if isHorizontalGesture && hasMinimumHorizontalMovement {
                        if horizontalTranslation > 0 {
                            offset = min(horizontalTranslation - 30, 80)
                        } else {
                            offset = max(horizontalTranslation + 30, -80)
                        }
                    }
                }
                .onEnded { value in
                    let horizontalTranslation = value.translation.width
                    let verticalTranslation = value.translation.height
                    let velocity = value.velocity.width
                    
                    let isHorizontalGesture = abs(horizontalTranslation) > abs(verticalTranslation) * 2.5
                    let hasSignificantMovement = abs(horizontalTranslation) > 60 || abs(velocity) > 800
                    
                    if isHorizontalGesture && hasSignificantMovement {
                        if horizontalTranslation > 0 {
                            onStatusChange(.received)
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 0
                            }
                        } else {
                            onRemove()
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 0
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = 0
                        }
                    }
                }
        )
    }

    // Images now use responsive sizing based on available column width
    
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
}

// MARK: - Swipeable Reorder Card (for list display mode)
struct SwipeableReorderCard: View {
    let item: ReorderItem
    let displayMode: ReorderDisplayMode
    let onStatusChange: (ReorderStatus) -> Void
    let onQuantityChange: (Int) -> Void
    let onQuantityTap: () -> Void // Tap to show quantity modal
    let onRemove: () -> Void
    let onImageTap: () -> Void
    let onImageLongPress: (() -> Void)?
    let onItemDetailsLongPress: () -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // Image (just for display, long-press for image update)
            Button(action: onImageTap) {
                SimpleImageView(
                    imageURL: item.imageUrl,
                    size: 50,
                    contentMode: .fill
                )
                .frame(width: 50, height: 50)
                .clipped()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture {
                onImageLongPress?()
            }

            // Item details (tappable for quantity modal, long-press for item details)
            Button(action: onQuantityTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)

                    // Single line with category badge, UPC, SKU, and price
                    HStack(spacing: 8) {
                        // Category with search results badge styling
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

                        // UPC - fixed size (priority 2)
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text(barcode)
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false)
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
                                .truncationMode(.tail)
                        }

                        // Bullet separator before price
                        if let price = item.price {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture {
                onItemDetailsLongPress()
            }

            // Quantity section on the right side
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.quantity)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("qty")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .offset(x: offset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let horizontalTranslation = value.translation.width
                    let verticalTranslation = value.translation.height
                    
                    let isHorizontalGesture = abs(horizontalTranslation) > abs(verticalTranslation) * 2.5
                    let hasMinimumHorizontalMovement = abs(horizontalTranslation) > 30
                    
                    if isHorizontalGesture && hasMinimumHorizontalMovement {
                        if horizontalTranslation > 0 {
                            offset = min(horizontalTranslation - 30, 80)
                        } else {
                            offset = max(horizontalTranslation + 30, -80)
                        }
                    }
                }
                .onEnded { value in
                    let horizontalTranslation = value.translation.width
                    let verticalTranslation = value.translation.height
                    let velocity = value.velocity.width
                    
                    let isHorizontalGesture = abs(horizontalTranslation) > abs(verticalTranslation) * 2.5
                    let hasSignificantMovement = abs(horizontalTranslation) > 60 || abs(velocity) > 800
                    
                    if isHorizontalGesture && hasSignificantMovement {
                        if horizontalTranslation > 0 {
                            onStatusChange(.received)
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 0
                            }
                        } else {
                            onRemove()
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 0
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = 0
                        }
                    }
                }
        )
    }
}


