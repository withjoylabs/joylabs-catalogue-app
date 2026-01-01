import SwiftUI
import SwiftData
import Kingfisher

// MARK: - Image Thumbnail Gallery
/// Displays a horizontal scrolling row of image thumbnails with drag-to-reorder functionality
/// First image is marked as PRIMARY and shown in header
/// Tapping a thumbnail shows full-screen preview with delete option
struct ImageThumbnailGallery: View {
    @Binding var imageIds: [String]
    let onReorder: ([String]) -> Void
    let onDelete: (String) -> Void
    let onUpload: () -> Void

    @State private var selectedImageId: String?
    @State private var showingPreview = false

    // Drag and drop state tracking
    @State private var draggedImageId: String?
    @State private var dropTargetId: String?

    // SwiftData context for resolving image URLs
    @Environment(\.modelContext) private var modelContext
    @Query private var images: [ImageModel]

    private let thumbnailSize: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Images")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onUpload) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Image")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }

            if imageIds.isEmpty {
                // Empty state (simple message, user clicks "Add Image" button in header)
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("No images added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                // Thumbnail grid with drag-to-reorder
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Half-width start gap (6px for visual balance)
                        DropGapView(
                            showLine: draggedImageId != nil && dropTargetId == "START_POSITION",
                            height: thumbnailSize,
                            isHalfWidth: true
                        )
                        .onDrop(of: [.text], delegate: StartDropDelegate(
                            draggedItem: $draggedImageId,
                            dropTargetItem: $dropTargetId,
                            items: $imageIds,
                            onReorder: onReorder
                        ))

                        ForEach(Array(imageIds.enumerated()), id: \.element) { index, imageId in
                            ThumbnailView(
                                imageId: imageId,
                                isPrimary: index == 0,
                                size: thumbnailSize,
                                isDragging: draggedImageId == imageId,
                                onTap: {
                                    selectedImageId = imageId
                                    showingPreview = true
                                }
                            )
                            .opacity(draggedImageId == imageId ? 0.5 : 1.0)
                            .onDrag {
                                draggedImageId = imageId
                                return NSItemProvider(object: imageId as NSString)
                            }
                            .onDrop(of: [.text], delegate: DropViewDelegate(
                                draggedItem: $draggedImageId,
                                dropTargetItem: $dropTargetId,
                                items: $imageIds,
                                currentItem: imageId,
                                onReorder: onReorder
                            ))

                            // Gap AFTER this thumbnail (shows line when THIS thumbnail is hovered)
                            DropGapView(
                                showLine: dropTargetId == imageId && draggedImageId != imageId,
                                height: thumbnailSize
                            )
                        }

                        // Final gap for end position (always visible)
                        ZStack {
                            DropGapView(
                                showLine: draggedImageId != nil && dropTargetId == "END_POSITION",
                                height: thumbnailSize
                            )

                            // Drop target overlaps gap (2x width for easier iPhone targeting)
                            Color.clear
                                .frame(width: thumbnailSize * 2, height: thumbnailSize)
                                .onDrop(of: [.text], delegate: EndDropDelegate(
                                    draggedItem: $draggedImageId,
                                    dropTargetItem: $dropTargetId,
                                    items: $imageIds,
                                    onReorder: onReorder
                                ))
                        }
                    }
                    .padding(.vertical, 8)
                    .onChange(of: draggedImageId) { oldValue, newValue in
                        // Ensure state is cleared when drag ends (even if dropped outside valid zone)
                        if newValue == nil && oldValue != nil {
                            // Drag ended - clear any lingering drop target state
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                dropTargetId = nil
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let imageId = selectedImageId {
                ImagePreviewModal(
                    imageId: imageId,
                    isPrimary: imageIds.first == imageId,
                    onDelete: {
                        onDelete(imageId)
                        showingPreview = false
                    },
                    onDismiss: {
                        showingPreview = false
                    }
                )
            }
        }
    }
}

// MARK: - Thumbnail View
private struct ThumbnailView: View {
    let imageId: String
    let isPrimary: Bool
    let size: CGFloat
    let isDragging: Bool
    let onTap: () -> Void

    @Query private var images: [ImageModel]

    init(imageId: String, isPrimary: Bool, size: CGFloat, isDragging: Bool, onTap: @escaping () -> Void) {
        self.imageId = imageId
        self.isPrimary = isPrimary
        self.size = size
        self.isDragging = isDragging
        self.onTap = onTap

        // Query for this specific image
        let predicate = #Predicate<ImageModel> { model in
            model.id == imageId
        }
        _images = Query(filter: predicate)
    }

    private var imageURL: String? {
        images.first?.url
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Image with Kingfisher caching
                if let url = imageURL, !url.isEmpty, let validURL = URL(string: url) {
                    KFImage(validURL)
                        .placeholder {
                            ProgressView()
                                .frame(width: size, height: size)
                        }
                        .onFailure { error in
                            // Silently handle image load failures
                        }
                        .resizable()
                        .aspectRatio(contentMode: SwiftUI.ContentMode.fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                        .background(Color(.systemGray5))
                }

                // Primary badge (hidden during drag to reduce visual noise)
                if isPrimary && !isDragging {
                    Text("PRIMARY")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                        .padding(4)
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPrimary ? Color.blue : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Modern Drop Delegate (State-Based)
/// Modern iOS drag and drop delegate using state tracking for reliable reordering
struct DropViewDelegate: DropDelegate {
    @Binding var draggedItem: String?
    @Binding var dropTargetItem: String?
    @Binding var items: [String]
    let currentItem: String
    let onReorder: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        // Show drop indicator at this position
        dropTargetItem = currentItem
    }

    func dropExited(info: DropInfo) {
        // Hide drop indicator when leaving
        if dropTargetItem == currentItem {
            dropTargetItem = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = draggedItem,
              let fromIndex = items.firstIndex(of: draggedId),
              let toIndex = items.firstIndex(of: currentItem),
              fromIndex != toIndex else {
            // Clear state even if drop failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Reorder the array
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: fromIndex < toIndex ? toIndex + 1 : toIndex)

            // Call the callback to sync with Square
            onReorder(items)
        }

        // Reset state after animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            draggedItem = nil
            dropTargetItem = nil
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Start Drop Delegate
/// Handles dropping at the start position (before first item)
struct StartDropDelegate: DropDelegate {
    @Binding var draggedItem: String?
    @Binding var dropTargetItem: String?
    @Binding var items: [String]
    let onReorder: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        // Show drop indicator at start position
        dropTargetItem = "START_POSITION"
    }

    func dropExited(info: DropInfo) {
        // Hide drop indicator when leaving
        if dropTargetItem == "START_POSITION" {
            dropTargetItem = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = draggedItem,
              let fromIndex = items.firstIndex(of: draggedId) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        // Don't move if already at start
        if fromIndex == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Move to start position (index 0)
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: 0)

            // Call the callback to sync with Square
            onReorder(items)
        }

        // Reset state after animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            draggedItem = nil
            dropTargetItem = nil
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - End Drop Delegate
/// Handles dropping at the end position (after last item)
struct EndDropDelegate: DropDelegate {
    @Binding var draggedItem: String?
    @Binding var dropTargetItem: String?
    @Binding var items: [String]
    let onReorder: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        // Show drop indicator at end position
        dropTargetItem = "END_POSITION"
    }

    func dropExited(info: DropInfo) {
        // Hide drop indicator when leaving
        if dropTargetItem == "END_POSITION" {
            dropTargetItem = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = draggedItem,
              let fromIndex = items.firstIndex(of: draggedId) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        // Don't move if already at end
        if fromIndex == items.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Move to end position
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: items.count)

            // Call the callback to sync with Square
            onReorder(items)
        }

        // Reset state after animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            draggedItem = nil
            dropTargetItem = nil
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Legacy Drop Delegate (For Variations - Backward Compatibility)
/// Legacy drop delegate used by variation image galleries
/// TODO: Update VariationCardComponents to use modern DropViewDelegate pattern
struct ImageDropDelegate: DropDelegate {
    let item: String
    @Binding var items: [String]
    let onReorder: ([String]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromIndex = items.firstIndex(of: item) else { return }

        // Find the item being dragged
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return }

        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, error in
            DispatchQueue.main.async {
                guard let data = data as? Data,
                      let draggedId = String(data: data, encoding: .utf8),
                      let toIndex = items.firstIndex(of: draggedId) else { return }

                if fromIndex != toIndex {
                    withAnimation {
                        items.move(fromOffsets: IndexSet(integer: toIndex), toOffset: fromIndex > toIndex ? fromIndex + 1 : fromIndex)
                        onReorder(items)
                    }
                }
            }
        }
    }
}

// MARK: - Image Preview Modal
struct ImagePreviewModal: View {
    let imageId: String
    let isPrimary: Bool
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Query private var images: [ImageModel]
    @State private var showingDeleteConfirmation = false

    init(imageId: String, isPrimary: Bool, onDelete: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.imageId = imageId
        self.isPrimary = isPrimary
        self.onDelete = onDelete
        self.onDismiss = onDismiss

        let predicate = #Predicate<ImageModel> { model in
            model.id == imageId
        }
        _images = Query(filter: predicate)
    }

    private var imageURL: String? {
        images.first?.url
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = imageURL, !url.isEmpty, let validURL = URL(string: url) {
                    KFImage(validURL)
                        .placeholder {
                            ProgressView()
                                .tint(.white)
                        }
                        .onFailure { error in
                            // Silently handle image load failures
                        }
                        .resizable()
                        .aspectRatio(contentMode: SwiftUI.ContentMode.fit)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(isPrimary && images.count > 1)
                }
            }
            .alert("Delete Image?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            } message: {
                if isPrimary {
                    Text("This is the primary image. Deleting it will make the next image primary.")
                } else {
                    Text("This action cannot be undone.")
                }
            }
        }
    }
}

// MARK: - Drop Gap View
/// Renders a gap with optional centered blue drop indicator line
private struct DropGapView: View {
    let showLine: Bool
    let height: CGFloat
    var isHalfWidth: Bool = false  // Half-width for start gap (6px vs 12px)

    var body: some View {
        HStack(spacing: 0) {
            if !isHalfWidth {
                Spacer().frame(width: 4.5)  // Left padding (only for full-width gaps)
            }
            if showLine {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3, height: height)
                    .transition(.opacity)
            } else {
                Spacer().frame(width: 3)
            }
            Spacer().frame(width: 4.5)  // Right padding (always present)
        }
    }
}
