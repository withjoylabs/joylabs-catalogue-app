import SwiftUI
import SwiftData

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
            .padding(.horizontal, 16)

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
                .padding(.horizontal, 16)
            } else {
                // Thumbnail grid with drag-to-reorder
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(imageIds.enumerated()), id: \.element) { index, imageId in
                            ThumbnailView(
                                imageId: imageId,
                                isPrimary: index == 0,
                                size: thumbnailSize,
                                onTap: {
                                    selectedImageId = imageId
                                    showingPreview = true
                                }
                            )
                            .onDrag {
                                NSItemProvider(object: imageId as NSString)
                            }
                            .onDrop(of: [.text], delegate: ImageDropDelegate(
                                item: imageId,
                                items: $imageIds,
                                onReorder: onReorder
                            ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
    let onTap: () -> Void

    @Query private var images: [ImageModel]

    init(imageId: String, isPrimary: Bool, size: CGFloat, onTap: @escaping () -> Void) {
        self.imageId = imageId
        self.isPrimary = isPrimary
        self.size = size
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
                // Image
                if let url = imageURL {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: size, height: size)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .clipped()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                                .frame(width: size, height: size)
                                .background(Color(.systemGray5))
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                        .background(Color(.systemGray5))
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

// MARK: - Image Drop Delegate
/// Shared drop delegate for image reordering (used by both item and variation galleries)
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

                if let url = imageURL {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                                Text("Failed to load image")
                                    .foregroundColor(.white)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
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
