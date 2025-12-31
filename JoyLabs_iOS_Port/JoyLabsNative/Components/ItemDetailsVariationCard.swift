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

            // Price section with location overrides
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
                        showingImagePicker = true
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
                        showingImagePicker = true
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
}