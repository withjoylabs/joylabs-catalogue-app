import SwiftUI
import OSLog

// MARK: - Item Image Section
struct ItemImageSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingImagePicker = false
    @State private var isRemoving = false
    @State private var imageRefreshTrigger = UUID()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemImageSection")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                
                // Image Display/Placeholder using cached image system
                Button(action: {
                    showingImagePicker = true
                }) {
                    if let imageURL = viewModel.itemData.imageURL, !imageURL.isEmpty {
                        // Use the same cached image system as search results
                        CachedImageView.catalogItem(
                            imageURL: imageURL,
                            imageId: viewModel.itemData.imageId,
                            size: 200
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .id(imageRefreshTrigger) // Force refresh when trigger changes
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
            ImagePickerModal(
                context: .itemDetails(itemId: viewModel.itemData.id),
                onDismiss: {
                    showingImagePicker = false
                },
                onImageUploaded: { result in
                    print("🔄 [ItemModal] Image upload completed, updating view model")
                    print("🔄 [ItemModal] New image ID: \(result.squareImageId)")
                    print("🔄 [ItemModal] New cache URL: \(result.localCacheUrl)")

                    // Update the view model with the new image
                    viewModel.itemData.imageURL = result.localCacheUrl
                    viewModel.itemData.imageId = result.squareImageId
                    showingImagePicker = false

                    // DO NOT post notification here - SquareImageService already posts it
                    // This was causing duplicate notifications and redundant processing
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            guard let userInfo = notification.userInfo,
                  let notificationItemId = userInfo["itemId"] as? String,
                  let currentItemId = viewModel.itemData.id,
                  notificationItemId == currentItemId else {
                return
            }

            print("🔄 [ItemModal] Received imageUpdated notification for item: \(notificationItemId)")

            if let action = userInfo["action"] as? String {
                if action == "uploaded" {
                    if let newImageId = userInfo["imageId"] as? String,
                       let newImageURL = userInfo["imageURL"] as? String {
                        print("✅ [ItemModal] Updating image ID to: \(newImageId)")
                        viewModel.itemData.imageId = newImageId
                        viewModel.itemData.imageURL = newImageURL
                        // Force image refresh by updating trigger
                        imageRefreshTrigger = UUID()
                    }
                } else if action == "deleted" {
                    print("✅ [ItemModal] Clearing image ID")
                    viewModel.itemData.imageId = nil
                    viewModel.itemData.imageURL = nil
                }
            }
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
