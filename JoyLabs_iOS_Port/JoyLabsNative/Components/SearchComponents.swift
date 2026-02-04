import SwiftUI

// MARK: - Glass Effect Modifier with Backwards Compatibility
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect()
        } else {
            // Fallback for iOS < 26: Use Material background
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

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

    var id: String {
        switch self {
        case .itemDetails(let item):
            return "itemDetails_\(item.id)"
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
                .keyboardType(.default)
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
        .modifier(GlassEffectModifier())  // Apply liquid glass morphism with backwards compatibility
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
/// Target for image upload (item vs variation)
enum ImageUploadTarget: Equatable {
    case item(id: String, name: String)
    case variation(variationId: String, variationName: String)

    var contextTitle: String {
        switch self {
        case .item(_, let name): return name
        case .variation(_, let name): return name
        }
    }

    var targetId: String {
        switch self {
        case .item(let id, _): return id
        case .variation(let variationId, _): return variationId
        }
    }
}

struct SwipeableScanResultCard: View {
    let result: SearchResultItem
    let onAddToReorder: () -> Void
    let onPrint: () -> Void
    let onItemUpdated: (() -> Void)?
    @State private var activeSheet: SearchSheet?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var currentImageId: String?  // Local state for dynamic image updates
    @State private var uploadTarget: ImageUploadTarget?  // Target for camera/picker uploads

    // Standard card height to ensure buttons match exactly
    private let cardHeight: CGFloat = 76

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
        .onAppear {
            // For hierarchical parent cards (multi-variation items), query parent item's image
            // This ensures we show the parent's image, not the scanned variation's (which may be empty)
            if result.variationCount > 1 {
                if let item = CatalogLookupService.shared.getItem(id: result.id) {
                    currentImageId = item.imageIds?.first
                }
            } else {
                // Single variation - use result's images directly
                currentImageId = result.images?.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            // Update local imageId when this item's image changes
            if let userInfo = notification.userInfo,
               let itemId = userInfo["itemId"] as? String,
               itemId == result.id,
               let newImageId = userInfo["imageId"] as? String {
                currentImageId = newImageId
            }
        }
    }

    private var scanResultContent: some View {
        return HStack(spacing: 12) {
            // Thumbnail image (left side) - using native iOS image system
            // Long press behavior depends on variation count:
            // - Single variation: Go directly to camera/picker for item
            // - Multiple variations: Show context menu to choose item or variation
            thumbnailView

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
                    context: .editExisting(itemId: item.id, scrollToVariation: item.variationName),
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
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: imagePickerContext,
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { uploadResult in
                    // SimpleImageService handles all refresh notifications
                    showingImagePicker = false
                }
            )
            .imagePickerFormSheet()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AVCameraViewControllerWrapper(
                onPhotosCaptured: { images in
                    handleCameraPhotos(images)
                    showingCamera = false
                },
                onCancel: {
                    showingCamera = false
                },
                contextTitle: uploadTarget?.contextTitle ?? result.name ?? "Item"
            )
        }
    }

    /// Trigger camera or image picker based on user setting
    private func triggerUploadAction() {
        switch ImageSaveService.shared.longPressImageAction {
        case .camera:
            showingCamera = true
        case .imagePicker:
            showingImagePicker = true
        }
    }

    /// Generate image picker context based on upload target
    private var imagePickerContext: ImageUploadContext {
        guard let target = uploadTarget else {
            return .scanViewLongPress(itemId: result.id, imageId: result.images?.first?.id)
        }

        switch target {
        case .variation(let variationId, let variationName):
            return .scanViewVariationLongPress(itemId: variationId, variationName: variationName)
        case .item(let id, _):
            return .scanViewLongPress(itemId: id, imageId: result.images?.first?.id)
        }
    }

    /// Thumbnail view - long-press always uploads to main item
    /// Variation-specific uploads happen from VariationResultRow
    private var thumbnailView: some View {
        NativeImageView.thumbnail(imageId: currentImageId, size: 50)
            .onLongPressGesture {
                uploadTarget = .item(id: result.id, name: result.name ?? "Item")
                triggerUploadAction()
            }
    }

    private func handleCameraPhotos(_ images: [UIImage]) {
        guard let firstImage = images.first,
              let imageData = firstImage.jpegData(compressionQuality: 0.9) else { return }

        // Save to camera roll if enabled
        ImageSaveService.shared.saveProcessedImage(firstImage)

        let target = uploadTarget ?? .item(id: result.id, name: result.name ?? "Item")

        Task {
            let imageService = SimpleImageService.shared
            let fileName = "camera_\(UUID().uuidString).jpg"

            switch target {
            case .item(let id, _):
                // Upload to item's main images
                _ = try? await imageService.uploadImage(imageData: imageData, fileName: fileName, itemId: id)

            case .variation(let variationId, _):
                // Upload directly to variation by ID
                _ = try? await imageService.uploadImage(
                    imageData: imageData,
                    fileName: fileName,
                    itemId: variationId
                )
            }

            // Trigger search refresh to show updated thumbnail
            await MainActor.run {
                onItemUpdated?()
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
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .frame(width: width, height: cardHeight)
        .background(color)
        .contentShape(Rectangle())
        .clipped()
    }
}

// MARK: - Grouped Search Result Card (Parent/Variation Hierarchy)
struct GroupedSearchResultCard: View {
    let group: GroupedSearchResult
    let onAddToReorder: (SearchResultItem) -> Void
    let onPrint: (SearchResultItem) -> Void
    let onItemUpdated: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Parent card - reuse existing SwipeableScanResultCard
            SwipeableScanResultCard(
                result: group.parentResult,
                onAddToReorder: { onAddToReorder(group.parentResult) },
                onPrint: { onPrint(group.parentResult) },
                onItemUpdated: onItemUpdated
            )

            // Matching variations - only shown for multi-variation items
            if group.shouldShowGrouped {
                ForEach(group.matchingVariations) { variation in
                    VariationResultRow(
                        variation: variation,
                        onAddToReorder: { onAddToReorder(variation) },
                        onPrint: { onPrint(variation) },
                        onItemUpdated: onItemUpdated
                    )
                }
            }
        }
    }
}

// MARK: - Variation Result Row (Indented child of parent item)
struct VariationResultRow: View {
    let variation: SearchResultItem
    let onAddToReorder: () -> Void
    let onPrint: () -> Void
    let onItemUpdated: (() -> Void)?

    @State private var activeSheet: SearchSheet?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var currentImageId: String?
    @State private var uploadTarget: ImageUploadTarget?

    private let cardHeight: CGFloat = 64  // Slightly shorter than parent card
    private let indentWidth: CGFloat = 50  // Match parent thumbnail area (16px padding + ~34px to center arrow)

    var body: some View {
        ZStack {
            // Background layer - action buttons
            HStack(spacing: 0) {
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

            // Foreground - indented variation content
            HStack(spacing: 0) {
                // Indent with corner arrow - right-aligned to sit closer to variation thumbnail
                HStack {
                    Spacer()
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(width: indentWidth, alignment: .trailing)
                .padding(.trailing, 3)

                // Variation card content
                variationContent
            }
            .frame(height: cardHeight)
            .background(Color(.systemBackground))
            .offset(x: offset)
            .onTapGesture {
                if abs(offset) > 5 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                    }
                } else {
                    activeSheet = .itemDetails(variation)
                }
            }
            .gesture(swipeGesture)
        }
        .clipped()
        .overlay(
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
            }
        )
        .onAppear {
            // Query SwiftData for fresh variation image (no fallback to parent)
            if let variationId = variation.variationId {
                currentImageId = CatalogLookupService.shared.getVariationPrimaryImageId(variationId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            // Listen for image uploads to this specific variation
            if let userInfo = notification.userInfo,
               let targetId = userInfo["itemId"] as? String,
               let variationId = variation.variationId,
               targetId == variationId,
               let newImageId = userInfo["imageId"] as? String {
                currentImageId = newImageId
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .itemDetails(let item):
                ItemDetailsModal(
                    context: .editExisting(
                        itemId: item.id,
                        scrollToVariation: item.variationName
                    ),
                    hideScrollButton: true,  // User tapped variation directly
                    onDismiss: { activeSheet = nil },
                    onSave: { _ in
                        activeSheet = nil
                        onItemUpdated?()
                    }
                )
                .fullScreenModal()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .scanViewVariationLongPress(
                    itemId: variation.variationId ?? variation.id,
                    variationName: variation.variationName ?? "Variation"
                ),
                onDismiss: { showingImagePicker = false },
                onImageUploaded: { _ in showingImagePicker = false }
            )
            .imagePickerFormSheet()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AVCameraViewControllerWrapper(
                onPhotosCaptured: { images in
                    handleCameraPhotos(images)
                    showingCamera = false
                },
                onCancel: { showingCamera = false },
                contextTitle: variation.variationName ?? "Variation"
            )
        }
    }

    private var variationContent: some View {
        HStack(spacing: 10) {
            // Thumbnail with long-press for upload
            NativeImageView.thumbnail(imageId: currentImageId, size: 44)
                .onLongPressGesture {
                    uploadTarget = .variation(
                        variationId: variation.variationId ?? variation.id,
                        variationName: variation.variationName ?? "Variation"
                    )
                    triggerUploadAction()
                }

            // Variation info - NO category badge (inherited from parent)
            VStack(alignment: .leading, spacing: 4) {
                Text(variation.variationName ?? "Variation")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let barcode = variation.barcode, !barcode.isEmpty {
                        Text(barcode)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let barcode = variation.barcode, !barcode.isEmpty,
                       let sku = variation.sku, !sku.isEmpty {
                        Text("*")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if let sku = variation.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()
                }
            }

            Spacer()

            // Price
            if let price = variation.price, price.isFinite && !price.isNaN {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if variation.hasTax {
                        Text("+tax")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                let translation = value.translation
                let horizontalThreshold: CGFloat = 30
                let angle = atan2(abs(translation.height), abs(translation.width))
                let isHorizontalDrag = angle < 0.5

                guard isHorizontalDrag && abs(translation.width) > horizontalThreshold else { return }

                isDragging = true
                let adjustedTranslation = translation.width > 0 ?
                    translation.width - horizontalThreshold :
                    translation.width + horizontalThreshold
                let resistance: CGFloat = 0.5

                if translation.width > 0 {
                    offset = min(adjustedTranslation * resistance, 100)
                } else {
                    offset = max(adjustedTranslation * resistance, -100)
                }
            }
            .onEnded { value in
                let translation = value.translation
                let horizontalThreshold: CGFloat = 30
                let angle = atan2(abs(translation.height), abs(translation.width))
                let isHorizontalDrag = angle < 0.5

                guard isHorizontalDrag && abs(translation.width) > horizontalThreshold else {
                    isDragging = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                    }
                    return
                }

                isDragging = false
                let adjustedTranslation = abs(translation.width) - horizontalThreshold

                if adjustedTranslation > 120 {
                    if translation.width > 0 {
                        onPrint()
                    } else {
                        onAddToReorder()
                    }
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                }
            }
    }

    private func triggerUploadAction() {
        switch ImageSaveService.shared.longPressImageAction {
        case .camera:
            showingCamera = true
        case .imagePicker:
            showingImagePicker = true
        }
    }

    private func handleCameraPhotos(_ images: [UIImage]) {
        guard let firstImage = images.first,
              let imageData = firstImage.jpegData(compressionQuality: 0.9) else { return }

        ImageSaveService.shared.saveProcessedImage(firstImage)

        let variationId = variation.variationId ?? variation.id

        Task {
            let imageService = SimpleImageService.shared
            let fileName = "camera_\(UUID().uuidString).jpg"
            _ = try? await imageService.uploadImage(
                imageData: imageData,
                fileName: fileName,
                itemId: variationId
            )

            await MainActor.run {
                onItemUpdated?()
            }
        }
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
