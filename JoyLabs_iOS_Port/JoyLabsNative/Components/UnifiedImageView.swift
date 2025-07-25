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
        .onReceive(NotificationCenter.default.publisher(for: .forceImageRefresh)) { notification in
            handleForceRefreshNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            handleImageUpdatedNotification(notification)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadImageIfNeeded() {
        guard let imageURL = imageURL, !imageURL.isEmpty else {
            logger.debug("No image URL provided for item: \(itemId)")
            return
        }
        
        isLoading = true
        
        Task {
            let image = await imageService.loadImage(
                imageURL: imageURL,
                imageId: imageId,
                itemId: itemId
            )
            
            await MainActor.run {
                self.loadedImage = image
                self.isLoading = false
            }
        }
    }
    
    private func handleForceRefreshNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let affectedItemId = userInfo["itemId"] as? String
        let affectedImageId = userInfo["newImageId"] as? String
        let oldImageId = userInfo["oldImageId"] as? String
        let currentImageId = imageId
        
        // Refresh if this notification is for our item or image
        let shouldRefresh = (affectedItemId == itemId) ||
                           (affectedImageId != nil && affectedImageId == currentImageId) ||
                           (oldImageId != nil && !oldImageId!.isEmpty && oldImageId == currentImageId)
        
        if shouldRefresh {
            logger.debug("🔄 Force refreshing image for item: \(itemId)")
            refreshTrigger = UUID()
            loadedImage = nil
            loadImageIfNeeded()
        }
    }
    
    private func handleImageUpdatedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let notificationItemId = userInfo["itemId"] as? String,
              notificationItemId == itemId else {
            return
        }
        
        if let action = userInfo["action"] as? String, action == "uploaded" {
            logger.debug("🔄 Refreshing image for uploaded item: \(itemId)")
            refreshTrigger = UUID()
            loadedImage = nil
            loadImageIfNeeded()
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
