import SwiftUI

/// Image buffer view for new items (before item ID exists)
/// Shows thumbnails of buffered images awaiting upload after item creation
struct NewItemImageBufferView: View {
    @Binding var pendingImages: [PendingImageData]
    let onUpload: () -> Void
    let onRemove: (String) -> Void

    private let thumbnailSize: CGFloat = 80

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
                // Thumbnail grid
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingImages.enumerated()), id: \.element.id) { index, image in
                            BufferedImageThumbnail(
                                image: image,
                                index: index,
                                isPrimary: index == 0,
                                size: thumbnailSize,
                                onRemove: { onRemove(image.id.uuidString) }
                            )
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
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Image preview from Data
            if let uiImage = UIImage(data: image.imageData) {
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
                // Fallback placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            // Primary badge
            if isPrimary {
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
        .frame(width: size, height: size)
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
