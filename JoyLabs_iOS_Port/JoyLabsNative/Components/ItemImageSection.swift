import SwiftUI
import OSLog

// MARK: - Item Image Section
struct ItemImageSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingImagePicker = false
    @State private var isRemoving = false

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemImageSection")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                
                // Image Display/Placeholder using unified image system
                Button(action: {
                    showingImagePicker = true
                }) {
                    if let imageURL = viewModel.itemData.imageURL, !imageURL.isEmpty {
                        // Use simple image system
                        SimpleImageView.large(
                            imageURL: imageURL,
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
            
            // Image Actions
            HStack {
                Spacer()
                
                Button(action: {
                    showingImagePicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera")
                        Text("Add Photo")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                
                if viewModel.itemData.imageURL != nil && !viewModel.itemData.imageURL!.isEmpty {
                    Button(action: {
                        Task {
                            await handleImageRemoval()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Remove")
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                    .padding(.leading, 20)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showingImagePicker) {
            UnifiedImagePickerModal(
                context: .itemDetails(itemId: viewModel.itemData.id),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { result in
                    print("🔄 [ItemModal] Image upload completed, updating view model")
                    print("🔄 [ItemModal] New image ID: \(result.squareImageId)")
                    print("🔄 [ItemModal] New AWS URL: \(result.awsUrl)")

                    // Update the view model with the new image (use AWS URL for proper URLCache)
                    viewModel.itemData.imageURL = result.awsUrl
                    viewModel.itemData.imageId = result.squareImageId
                    showingImagePicker = false

                    // SimpleImageService handles all notifications automatically
                }
            )
            .nestedComponentModal()
        }

    }

    // MARK: - Private Methods

    /// Handle image removal with Square API integration
    private func handleImageRemoval() async {
        guard let imageId = viewModel.itemData.imageId, !imageId.isEmpty else {
            logger.warning("No image ID found for removal")
            return
        }

        isRemoving = true

        do {
            // Delete from Square API
            let imageService = SquareImageService.create()
            try await imageService.deleteImage(imageId: imageId)

            // Update local data
            await MainActor.run {
                viewModel.itemData.imageURL = nil
                viewModel.itemData.imageId = nil
                isRemoving = false
            }

            // Trigger UI refresh across all views
            let itemId = viewModel.itemData.id ?? ""
            print("📢 Posting imageUpdated notification for deleted image, item: \(itemId)")
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
}

// MARK: - Image Placeholder
struct ImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
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
    ItemImageSection(viewModel: ItemDetailsViewModel())
        .padding()
}
