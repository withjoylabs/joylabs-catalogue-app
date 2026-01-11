import SwiftUI
import OSLog

// MARK: - Item Image Section
struct ItemImageSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @FocusState.Binding var focusedField: ItemField?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var isRemoving = false

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemImageSection")

    // Computed property for primary image ID (first in imageIds array)
    private var primaryImageId: String? {
        let imageIds = viewModel.staticData.imageIds

        // If imageIds array has images, use first one
        return imageIds.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()

                // Image Display/Placeholder using native iOS image system
                Button(action: {
                    focusedField = nil
                    showingImagePicker = true
                }) {
                    if let imageId = primaryImageId, !imageId.isEmpty {
                        // Use native iOS image system
                        NativeImageView.large(
                            imageId: imageId,
                            size: 200
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        ImagePlaceholder()
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }

            // Image Thumbnail Gallery (below main image)
            if let itemId = viewModel.staticData.id, !itemId.isEmpty {
                // EXISTING ITEM: Full thumbnail gallery with reorder/delete
                ImageThumbnailGallery(
                    imageIds: Binding(
                        get: { viewModel.staticData.imageIds },
                        set: { viewModel.staticData.imageIds = $0 }
                    ),
                    onReorder: { newOrder in
                        handleImageReorder(newOrder: newOrder)
                    },
                    onDelete: { imageId in
                        handleImageDeletion(imageId: imageId)
                    },
                    onUpload: {
                        focusedField = nil
                        showingImagePicker = true
                    },
                    onCameraCapture: {
                        focusedField = nil
                        showingCamera = true
                    }
                )
            } else {
                // NEW ITEM: Simple image buffer view (images upload after item creation)
                NewItemImageBufferView(
                    pendingImages: Binding(
                        get: { viewModel.staticData.pendingImages },
                        set: { viewModel.staticData.pendingImages = $0 }
                    ),
                    onUpload: {
                        focusedField = nil
                        showingImagePicker = true
                    },
                    onCameraCapture: {
                        focusedField = nil
                        showingCamera = true
                    },
                    onRemove: { imageId in
                        viewModel.staticData.pendingImages.removeAll { $0.id.uuidString == imageId }
                    }
                )
            }
        }
        .padding()
        .background(Color.itemDetailsFieldBackground)
        .cornerRadius(12)
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .itemDetails(itemId: viewModel.staticData.id),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { result in
                    if viewModel.staticData.id == nil || viewModel.staticData.id!.isEmpty {
                        // NEW ITEM: Buffer image for upload after item creation
                        if let imageData = result.pendingImageData,
                           let fileName = result.pendingFileName {
                            let pendingImage = PendingImageData(
                                imageData: imageData,
                                fileName: fileName,
                                isPrimary: viewModel.staticData.pendingImages.isEmpty  // First = primary
                            )
                            viewModel.staticData.pendingImages.append(pendingImage)
                            logger.info("[ItemModal] Buffered image for new item (total: \(viewModel.staticData.pendingImages.count))")
                        }
                    } else {
                        // EXISTING ITEM: Image already uploaded
                        logger.info("[ItemModal] Image upload completed")
                        logger.info("[ItemModal] New image ID: \(result.squareImageId)")

                        // Add to imageIds array (append to end, user can reorder to make primary)
                        viewModel.staticData.imageIds.append(result.squareImageId)

                        // Update legacy fields for compatibility
                        viewModel.imageURL = result.awsUrl
                        viewModel.imageId = result.squareImageId

                        // SimpleImageService handles all notifications automatically
                    }
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
                }
            )
        }

    }

    // MARK: - Private Methods

    /// Handle image reordering via Square API
    private func handleImageReorder(newOrder: [String]) {
        guard let itemId = viewModel.staticData.id, !itemId.isEmpty else {
            logger.warning("No item ID found for image reorder")
            return
        }

        Task {
            do {
                logger.info("Reordering images for item \(itemId)")
                let crudService = SquareAPIServiceFactory.createCRUDService()
                try await crudService.reorderItemImages(itemId: itemId, newImageOrder: newOrder)

                await MainActor.run {
                    // Update local state - already updated via binding
                    logger.info("Successfully reordered images")
                    ToastNotificationService.shared.showSuccess("Image order updated")
                }
            } catch {
                await MainActor.run {
                    logger.error("Failed to reorder images: \(error)")
                    ToastNotificationService.shared.showError("Failed to update image order")

                    // Revert local state on error
                    Task {
                        await viewModel.refreshFromSquare()
                    }
                }
            }
        }
    }

    /// Handle image deletion via Square API
    private func handleImageDeletion(imageId: String) {
        guard let itemId = viewModel.staticData.id, !itemId.isEmpty else {
            logger.warning("No item ID found for image deletion")
            return
        }

        Task {
            do {
                logger.info("Deleting image \(imageId) from item \(itemId)")
                let crudService = SquareAPIServiceFactory.createCRUDService()
                try await crudService.deleteImage(imageId: imageId, itemId: itemId)

                await MainActor.run {
                    // Remove from local imageIds array
                    viewModel.staticData.imageIds.removeAll { $0 == imageId }

                    logger.info("Successfully deleted image")
                    ToastNotificationService.shared.showSuccess("Image deleted")
                }
            } catch {
                await MainActor.run {
                    logger.error("Failed to delete image: \(error)")
                    ToastNotificationService.shared.showError("Failed to delete image")

                    // Refresh from Square on error
                    Task {
                        await viewModel.refreshFromSquare()
                    }
                }
            }
        }
    }

    /// Handle image removal with Square API integration (legacy single image support)
    private func handleImageRemoval() async {
        guard let imageId = viewModel.imageId, !imageId.isEmpty else {
            logger.warning("No image ID found for removal")
            return
        }

        isRemoving = true

        do {
            // Delete from Square API using SquareImageService
            let imageService = SquareImageService.create()
            try await imageService.deleteImage(imageId: imageId)

            // Update local data
            await MainActor.run {
                viewModel.imageURL = nil
                viewModel.imageId = nil
                isRemoving = false
            }

            // Trigger UI refresh across all views
            let itemId = viewModel.staticData.id ?? ""
            logger.info("Posting imageUpdated notification for deleted image, item: \(itemId)")
            NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
                "itemId": itemId,
                "action": "deleted"
            ])

            logger.info("Successfully removed image: \(imageId)")

        } catch {
            await MainActor.run {
                isRemoving = false
            }
            logger.error("Failed to remove image: \(error.localizedDescription)")
        }
    }

    /// Handle camera photos captured from AVCameraViewController
    private func handleCameraPhotos(_ images: [UIImage]) {
        logger.info("[ItemImageSection] Processing \(images.count) camera photos")

        let imageProcessor = ImageProcessor()
        let imageService = SimpleImageService.shared

        for image in images {
            Task {
                do {
                    // Process image (format conversion and size validation)
                    let processedResult = try await imageProcessor.processImage(image)

                    if viewModel.staticData.id == nil || viewModel.staticData.id!.isEmpty {
                        // NEW ITEM: Buffer image for upload after item creation
                        await MainActor.run {
                            let fileName = "joylabs_camera_\(UUID().uuidString).\(processedResult.format.fileExtension)"
                            let pendingImage = PendingImageData(
                                imageData: processedResult.data,
                                fileName: fileName,
                                isPrimary: viewModel.staticData.pendingImages.isEmpty
                            )
                            viewModel.staticData.pendingImages.append(pendingImage)
                            logger.info("[ItemImageSection] Buffered camera image (total: \(viewModel.staticData.pendingImages.count))")
                        }
                    } else {
                        // EXISTING ITEM: Upload directly to Square
                        logger.info("[ItemImageSection] Uploading camera image to Square")
                        let (imageId, awsURL) = try await imageService.uploadImageWithId(
                            imageData: processedResult.data,
                            fileName: "joylabs_camera_\(UUID().uuidString).\(processedResult.format.fileExtension)",
                            itemId: viewModel.staticData.id!
                        )

                        await MainActor.run {
                            // Add to imageIds array
                            viewModel.staticData.imageIds.append(imageId)

                            // Update legacy fields for compatibility
                            viewModel.imageURL = awsURL
                            viewModel.imageId = imageId

                            logger.info("[ItemImageSection] Camera image uploaded: \(imageId)")
                        }
                    }
                } catch {
                    logger.error("[ItemImageSection] Failed to process camera image: \(error)")
                    await MainActor.run {
                        ToastNotificationService.shared.showError("Failed to process camera photo")
                    }
                }
            }
        }
    }
}

// MARK: - Image Placeholder
struct ImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.itemDetailsSecondaryText.opacity(0.3))
            .frame(width: 200, height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(.gray)
                    
                    Text("Tap to add")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @FocusState private var focusedField: ItemField?

        var body: some View {
            ItemImageSection(viewModel: ItemDetailsViewModel(), focusedField: $focusedField)
                .padding()
        }
    }

    return PreviewWrapper()
}
