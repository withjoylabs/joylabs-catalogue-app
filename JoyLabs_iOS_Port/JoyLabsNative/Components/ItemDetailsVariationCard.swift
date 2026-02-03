import SwiftUI
import SwiftData

// MARK: - Item Details Variation Card
struct ItemDetailsVariationCard: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    let onDelete: () -> Void
    let onPrint: (ItemDetailsVariationData) -> Void
    let isPrinting: Bool
    let viewModel: ItemDetailsViewModel
    let modelContext: ModelContext

    @State private var showingImagePicker = false
    @State private var showingCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with proper theming and functionality
            VariationCardHeader(
                index: index,
                variation: variation,
                onDelete: onDelete,
                onPrint: onPrint,
                isPrinting: isPrinting
            )

            // Fields with full duplicate detection
            VariationCardFields(
                variation: $variation,
                index: index,
                focusedField: $focusedField,
                moveToNextField: moveToNextField,
                viewModel: viewModel,
                modelContext: modelContext
            )

            // Price section with location overrides AND inventory section
            VariationCardPriceSection(
                variation: $variation,
                index: index,
                focusedField: $focusedField,
                moveToNextField: moveToNextField,
                viewModel: viewModel
            )

            // Image gallery
            Divider()
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                .padding(.top, ItemDetailsSpacing.compactSpacing)

            if let variationId = variation.id, !variationId.isEmpty {
                // EXISTING VARIATION: Full image gallery with reorder/delete
                VariationImageGallery(
                    variation: $variation,
                    onReorder: { newOrder in
                        handleImageReorder(variationId: variationId, newOrder: newOrder)
                    },
                    onDelete: { imageId in
                        handleImageDeletion(variationId: variationId, imageId: imageId)
                    },
                    onUpload: {
                        focusedField = nil
                        showingImagePicker = true
                    },
                    onCameraCapture: {
                        focusedField = nil
                        showingCamera = true
                    },
                    viewModel: viewModel
                )
            } else {
                // NEW VARIATION: Simple image buffer view (images upload after item creation)
                NewItemImageBufferView(
                    pendingImages: Binding(
                        get: { variation.pendingImages },
                        set: { variation.pendingImages = $0 }
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
                        variation.pendingImages.removeAll { $0.id.uuidString == imageId }
                    }
                )
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
            }
        }
        .background(Color.itemDetailsSectionBackground)
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .variationDetails(variationId: variation.id ?? ""),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { result in
                    if variation.id == nil || variation.id!.isEmpty {
                        // NEW VARIATION: Buffer image for upload after item/variation creation
                        if let imageData = result.pendingImageData,
                           let fileName = result.pendingFileName {
                            let pendingImage = PendingImageData(
                                imageData: imageData,
                                fileName: fileName,
                                isPrimary: variation.pendingImages.isEmpty  // First = primary
                            )
                            variation.pendingImages.append(pendingImage)
                        }
                    } else {
                        // EXISTING VARIATION: Image already uploaded
                        variation.imageIds.append(result.squareImageId)
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
                },
                contextTitle: "\(viewModel.name.isEmpty ? "Item" : viewModel.name) - \(variation.name ?? "Variation")"
            )
        }
    }

    // MARK: - Private Methods

    private func handleImageReorder(variationId: String, newOrder: [String]) {
        Task {
            do {
                let crudService = SquareAPIServiceFactory.createCRUDService()
                try await crudService.reorderVariationImages(variationId: variationId, newImageOrder: newOrder)

                await MainActor.run {
                    ToastNotificationService.shared.showSuccess("Image order updated")
                }
            } catch {
                await MainActor.run {
                    ToastNotificationService.shared.showError("Failed to update image order")

                    // Revert local state on error
                    Task {
                        await viewModel.refreshFromSquare()
                    }
                }
            }
        }
    }

    private func handleImageDeletion(variationId: String, imageId: String) {
        Task {
            do {
                let crudService = SquareAPIServiceFactory.createCRUDService()
                try await crudService.deleteVariationImage(imageId: imageId, variationId: variationId)

                await MainActor.run {
                    // Remove from local imageIds array
                    variation.imageIds.removeAll { $0 == imageId }
                    ToastNotificationService.shared.showSuccess("Image deleted")
                }
            } catch {
                await MainActor.run {
                    ToastNotificationService.shared.showError("Failed to delete image")

                    // Refresh from Square on error
                    Task {
                        await viewModel.refreshFromSquare()
                    }
                }
            }
        }
    }

    /// Handle camera photos captured from AVCameraViewController
    private func handleCameraPhotos(_ images: [UIImage]) {
        print("[VariationCard] Processing \(images.count) camera photos")

        let imageProcessor = ImageProcessor()
        let imageService = SimpleImageService.shared

        for image in images {
            Task {
                do {
                    // Process image (format conversion and size validation)
                    let processedResult = try await imageProcessor.processImage(image)

                    // Save to camera roll if enabled
                    await MainActor.run {
                        ImageSaveService.shared.saveProcessedImage(processedResult.image)
                    }

                    if variation.id == nil || variation.id!.isEmpty {
                        // NEW VARIATION: Buffer image for upload after variation creation
                        await MainActor.run {
                            let fileName = "joylabs_camera_\(UUID().uuidString).\(processedResult.format.fileExtension)"
                            let pendingImage = PendingImageData(
                                imageData: processedResult.data,
                                fileName: fileName,
                                isPrimary: variation.pendingImages.isEmpty
                            )
                            variation.pendingImages.append(pendingImage)
                            print("[VariationCard] Buffered camera image (total: \(variation.pendingImages.count))")
                        }
                    } else {
                        // EXISTING VARIATION: Upload directly to Square
                        print("[VariationCard] Uploading camera image to Square")
                        let (imageId, _) = try await imageService.uploadImageWithId(
                            imageData: processedResult.data,
                            fileName: "joylabs_camera_\(UUID().uuidString).\(processedResult.format.fileExtension)",
                            itemId: variation.id!
                        )

                        await MainActor.run {
                            // Add to imageIds array
                            variation.imageIds.append(imageId)
                            print("[VariationCard] Camera image uploaded: \(imageId)")
                        }
                    }
                } catch {
                    print("[VariationCard] Failed to process camera image: \(error)")
                    await MainActor.run {
                        ToastNotificationService.shared.showError("Failed to process camera photo")
                    }
                }
            }
        }
    }
}