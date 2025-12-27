import SwiftUI
import SwiftData

// MARK: - Item Details Variation Card
struct ItemDetailsVariationCard: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
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
                viewModel: viewModel,
                modelContext: modelContext
            )

            // Price section with location overrides
            VariationCardPriceSection(
                variation: $variation,
                viewModel: viewModel
            )

            // Image gallery (only show for existing variations with IDs)
            if let variationId = variation.id, !variationId.isEmpty {
                Divider()
                    .padding(.horizontal, ItemDetailsSpacing.compactSpacing)

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
            }
        }
        .background(Color.itemDetailsSectionBackground)
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
        .sheet(isPresented: $showingImagePicker) {
            if let variationId = variation.id {
                UnifiedImagePickerModal(
                    context: .variationDetails(variationId: variationId),
                    onDismiss: {
                        showingImagePicker = false
                    },
                    onImageUploaded: { result in
                        // Add to variation's imageIds array
                        variation.imageIds.append(result.squareImageId)
                        showingImagePicker = false
                    }
                )
                .nestedComponentModal()
            }
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