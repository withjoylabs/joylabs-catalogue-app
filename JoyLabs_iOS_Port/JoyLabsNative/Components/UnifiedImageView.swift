import SwiftUI
import Foundation
import OSLog

/// Unified Image View - Single component for displaying images across all views
/// Replaces all instances of CachedImageView.catalogItem with consistent behavior
struct UnifiedImageView: View {
    let imageURL: String?
    let imageId: String?
    let itemId: String
    let size: CGFloat
    let placeholder: String
    let contentMode: ContentMode
    
    @StateObject private var imageService = UnifiedImageService.shared
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var refreshTrigger = UUID()
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImageView")
    
    // Safe dimensions to prevent NaN values in CoreGraphics
    private var safeSize: CGFloat {
        guard size > 0, size.isFinite else { return 50 }
        return size
    }
    
    init(
        imageURL: String?,
        imageId: String?,
        itemId: String,
        size: CGFloat,
        placeholder: String = "photo",
        contentMode: ContentMode = .fit
    ) {
        self.imageURL = imageURL
        self.imageId = imageId
        self.itemId = itemId
        self.size = size
        self.placeholder = placeholder
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .frame(width: safeSize, height: safeSize)
            } else {
                Image(systemName: placeholder.isEmpty ? "photo" : placeholder)
                    .foregroundColor(.gray)
                    .frame(width: safeSize, height: safeSize)
            }
        }
        .frame(width: safeSize, height: safeSize)
        .id(refreshTrigger) // Force refresh when trigger changes
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: imageURL) { _, newURL in
            loadedImage = nil
            loadImageIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            handleImageUpdatedNotification(notification)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadImageIfNeeded() {
        isLoading = true
        
        Task {
            var finalImageURL: String?
            var finalImageId: String?
            
            if let imageURL = imageURL, !imageURL.isEmpty {
                // Use provided URL
                finalImageURL = imageURL
                finalImageId = imageId
            } else {
                // Fetch current primary image info when no URL provided
                logger.debug("🔄 No image URL provided, fetching primary image for item: \(itemId)")
                do {
                    if let imageInfo = try await UnifiedImageService.shared.getPrimaryImageInfo(for: itemId) {
                        finalImageURL = imageInfo.cacheUrl
                        finalImageId = imageInfo.imageId
                        logger.debug("🔄 Using primary image: \(imageInfo.imageId) -> \(imageInfo.cacheUrl)")
                    } else {
                        logger.warning("⚠️ No primary image found for item: \(itemId)")
                    }
                } catch {
                    logger.error("❌ Failed to get primary image info: \(error)")
                }
            }
            
            let image: UIImage?
            if let finalURL = finalImageURL {
                image = await imageService.loadImage(
                    imageURL: finalURL,
                    imageId: finalImageId,
                    itemId: itemId
                )
            } else {
                image = nil
            }
            
            await MainActor.run {
                self.loadedImage = image
                self.isLoading = false
            }
        }
    }
    
    private func handleImageUpdatedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationItemId = userInfo["itemId"] as? String else {
            return
        }
        
        // Check if this notification is for our item or our specific image
        let affectedImageId = userInfo["imageId"] as? String
        let oldImageId = userInfo["oldImageId"] as? String
        let currentImageId = imageId
        
        let shouldRefresh = (notificationItemId == itemId) ||
                           (affectedImageId != nil && affectedImageId == currentImageId) ||
                           (oldImageId != nil && !oldImageId!.isEmpty && oldImageId == currentImageId)
        
        if shouldRefresh {
            logger.debug("🔄 Refreshing image for item: \(itemId) (reason: \(userInfo["action"] as? String ?? "unknown"))")
            refreshTrigger = UUID()
            loadedImage = nil
            
            // Use the cache URL from notification if available (most efficient)
            if let notificationImageURL = userInfo["imageURL"] as? String, !notificationImageURL.isEmpty {
                logger.debug("🔄 Using cache URL from notification: \(notificationImageURL)")
                
                Task {
                    let freshImage = await imageService.loadImage(
                        imageURL: notificationImageURL,
                        imageId: affectedImageId,
                        itemId: itemId
                    )
                    
                    await MainActor.run {
                        self.loadedImage = freshImage
                    }
                }
            } else {
                // Fallback: Re-fetch current primary image info
                Task {
                    do {
                        if let imageInfo = try await UnifiedImageService.shared.getPrimaryImageInfo(for: itemId) {
                            logger.debug("🔄 Using updated primary image info: \(imageInfo.cacheUrl)")
                            
                            let freshImage = await imageService.loadImage(
                                imageURL: imageInfo.cacheUrl, // Use cache URL instead of AWS URL
                                imageId: imageInfo.imageId,
                                itemId: itemId
                            )
                            
                            await MainActor.run {
                                self.loadedImage = freshImage
                            }
                        } else {
                            logger.warning("⚠️ No primary image found for item: \(itemId), falling back to original URL")
                            loadImageIfNeeded() // Fallback to original logic
                        }
                    } catch {
                        logger.error("❌ Failed to get updated primary image: \(error)")
                        loadImageIfNeeded() // Fallback to original logic
                    }
                }
            }
        }
    }
}

// MARK: - Convenience Initializers
extension UnifiedImageView {
    
    /// Create image view for catalog items (most common use case)
    static func catalogItem(
        imageURL: String?,
        imageId: String?,
        itemId: String,
        size: CGFloat
    ) -> UnifiedImageView {
        return UnifiedImageView(
            imageURL: imageURL,
            imageId: imageId,
            itemId: itemId,
            size: size,
            placeholder: "photo",
            contentMode: .fill
        )
    }
    
    /// Create image view for thumbnails
    static func thumbnail(
        imageURL: String?,
        imageId: String?,
        itemId: String,
        size: CGFloat = 50
    ) -> UnifiedImageView {
        return UnifiedImageView(
            imageURL: imageURL,
            imageId: imageId,
            itemId: itemId,
            size: size,
            placeholder: "photo",
            contentMode: .fill
        )
    }
    
    /// Create image view for large displays
    static func large(
        imageURL: String?,
        imageId: String?,
        itemId: String,
        size: CGFloat = 200
    ) -> UnifiedImageView {
        return UnifiedImageView(
            imageURL: imageURL,
            imageId: imageId,
            itemId: itemId,
            size: size,
            placeholder: "photo",
            contentMode: .fit
        )
    }
}

// MARK: - Preview
#Preview("Unified Image View") {
    VStack(spacing: 20) {
        UnifiedImageView.thumbnail(
            imageURL: nil,
            imageId: nil,
            itemId: "preview-item",
            size: 50
        )
        
        UnifiedImageView.catalogItem(
            imageURL: nil,
            imageId: nil,
            itemId: "preview-item",
            size: 100
        )
        
        UnifiedImageView.large(
            imageURL: nil,
            imageId: nil,
            itemId: "preview-item",
            size: 200
        )
    }
    .padding()
}
