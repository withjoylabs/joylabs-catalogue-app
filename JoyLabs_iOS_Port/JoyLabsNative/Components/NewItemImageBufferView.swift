import SwiftUI

/// Image buffer view for new items (before item ID exists)
/// Shows thumbnails of buffered images awaiting upload after item creation
/// Supports drag-and-drop reordering
struct NewItemImageBufferView: View {
    @Binding var pendingImages: [PendingImageData]
    let onUpload: () -> Void
    let onRemove: (String) -> Void

    private let thumbnailSize: CGFloat = 80

    // Drag and drop state tracking
    @State private var draggedImageId: String?
    @State private var dropTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            HStack {
                Text("Images")
                    .font(.itemDetailsSectionTitle)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onUpload) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Image")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }

            if pendingImages.isEmpty {
                // Empty state
                Text("No images added yet. Tap 'Add Image' to upload after item creation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Thumbnail grid with drag-to-reorder
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(pendingImages.enumerated()), id: \.element.id) { index, image in
                            BufferedImageThumbnail(
                                image: image,
                                index: index,
                                isPrimary: index == 0,
                                size: thumbnailSize,
                                isDragging: draggedImageId == image.id.uuidString,
                                onRemove: { onRemove(image.id.uuidString) }
                            )
                            .opacity(draggedImageId == image.id.uuidString ? 0.5 : 1.0)
                            .onDrag {
                                draggedImageId = image.id.uuidString
                                return NSItemProvider(object: image.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: PendingImageDropDelegate(
                                draggedItem: $draggedImageId,
                                dropTargetItem: $dropTargetId,
                                items: $pendingImages,
                                currentItemId: image.id.uuidString
                            ))

                            // Gap AFTER this thumbnail (shows line when THIS thumbnail is hovered)
                            DropGapView(
                                showLine: dropTargetId == image.id.uuidString && draggedImageId != image.id.uuidString,
                                height: thumbnailSize
                            )
                        }

                        // Final gap for end position
                        ZStack {
                            DropGapView(
                                showLine: draggedImageId != nil && dropTargetId == "END_POSITION",
                                height: thumbnailSize
                            )

                            // Drop target overlaps gap (2x width for easier targeting)
                            Color.clear
                                .frame(width: thumbnailSize * 2, height: thumbnailSize)
                                .onDrop(of: [.text], delegate: PendingImageEndDropDelegate(
                                    draggedItem: $draggedImageId,
                                    dropTargetItem: $dropTargetId,
                                    items: $pendingImages
                                ))
                        }
                    }
                    .padding(.vertical, 8)
                    .onChange(of: draggedImageId) { oldValue, newValue in
                        // Clear state when drag ends
                        if newValue == nil && oldValue != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                dropTargetId = nil
                            }
                        }
                    }
                }

                Text("\(pendingImages.count) image\(pendingImages.count == 1 ? "" : "s") ready for upload")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Buffered Image Thumbnail
struct BufferedImageThumbnail: View {
    let image: PendingImageData
    let index: Int
    let isPrimary: Bool
    let size: CGFloat
    let isDragging: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Image preview from Data with error handling for corrupt data
            Group {
                if let uiImage = createUIImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isPrimary ? Color.blue : Color.gray.opacity(0.3), lineWidth: isPrimary ? 2 : 1)
                        )
                } else {
                    // Fallback placeholder for corrupt or invalid image data
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
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

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.red))
                    .frame(width: 20, height: 20)
            }
            .offset(x: 8, y: -8)
        }
        .frame(width: size + 16, height: size + 16)  // Extra space for offset button to prevent clipping
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // Helper function to safely create UIImage with error logging
    private func createUIImage() -> UIImage? {
        guard image.imageData.count > 0 else {
            print("[BufferedImageThumbnail] Error: Empty image data for buffered image")
            return nil
        }

        guard let uiImage = UIImage(data: image.imageData) else {
            print("[BufferedImageThumbnail] Error: Failed to decode image data (possibly corrupt JPEG/PNG)")
            return nil
        }

        // Validate image has valid dimensions
        guard uiImage.size.width > 0 && uiImage.size.height > 0 else {
            print("[BufferedImageThumbnail] Error: Invalid image dimensions: \(uiImage.size)")
            return nil
        }

        return uiImage
    }
}

// MARK: - Pending Image Drop Delegate
/// Drop delegate for reordering buffered images (no API call, just local array update)
struct PendingImageDropDelegate: DropDelegate {
    @Binding var draggedItem: String?
    @Binding var dropTargetItem: String?
    @Binding var items: [PendingImageData]
    let currentItemId: String

    func dropEntered(info: DropInfo) {
        // Show drop indicator at this position
        dropTargetItem = currentItemId
    }

    func dropExited(info: DropInfo) {
        // Hide drop indicator when leaving
        if dropTargetItem == currentItemId {
            dropTargetItem = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = draggedItem,
              let fromIndex = items.firstIndex(where: { $0.id.uuidString == draggedId }),
              let toIndex = items.firstIndex(where: { $0.id.uuidString == currentItemId }),
              fromIndex != toIndex else {
            // Clear state even if drop failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedItem = nil
                dropTargetItem = nil
            }
            return false
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Reorder the array (local only - no API call)
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: fromIndex < toIndex ? toIndex + 1 : toIndex)
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

// MARK: - Pending Image End Drop Delegate
/// Handles dropping at the end position (after last buffered image)
struct PendingImageEndDropDelegate: DropDelegate {
    @Binding var draggedItem: String?
    @Binding var dropTargetItem: String?
    @Binding var items: [PendingImageData]

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
              let fromIndex = items.firstIndex(where: { $0.id.uuidString == draggedId }) else {
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
            // Move to end position (local only - no API call)
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: items.count)
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

// MARK: - Drop Gap View
/// Renders a gap with optional centered blue drop indicator line (reused from ImageThumbnailGallery)
private struct DropGapView: View {
    let showLine: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 4.5)
            if showLine {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3, height: height)
                    .transition(.opacity)
            } else {
                Spacer().frame(width: 3)
            }
            Spacer().frame(width: 4.5)
        }
    }
}

#Preview {
    @Previewable @State var pendingImages: [PendingImageData] = []

    NewItemImageBufferView(
        pendingImages: $pendingImages,
        onUpload: { print("Upload tapped") },
        onRemove: { id in print("Remove: \(id)") }
    )
    .padding()
}
