import SwiftUI
import Foundation

/// A SwiftUI view that displays images with automatic caching
struct CachedImageView: View {
    let imageURL: String?
    let imageId: String? // Real Square image ID for proper cache lookup
    let placeholder: String
    let width: CGFloat?
    let height: CGFloat?
    let contentMode: ContentMode
    
    @StateObject private var imageCache = ImageCacheService.shared
    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    // Safe dimensions to prevent NaN values in CoreGraphics
    private var safeWidth: CGFloat? {
        guard let width = width, width > 0, width.isFinite else { return nil }
        return width
    }

    private var safeHeight: CGFloat? {
        guard let height = height, height > 0, height.isFinite else { return nil }
        return height
    }
    
    init(
        imageURL: String?,
        imageId: String? = nil,
        placeholder: String = "photo",
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        contentMode: ContentMode = .fit
    ) {
        self.imageURL = imageURL
        self.imageId = imageId
        self.placeholder = placeholder
        self.width = width
        self.height = height
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
                    .frame(width: safeWidth, height: safeHeight)
            } else {
                Image(systemName: placeholder.isEmpty ? "photo" : placeholder)
                    .foregroundColor(.gray)
                    .frame(width: safeWidth, height: safeHeight)
            }
        }
        .frame(width: safeWidth, height: safeHeight)
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: imageURL) { _, newURL in
            loadedImage = nil
            loadImageIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceImageRefresh)) { notification in
            // Force refresh if this image is affected
            if let userInfo = notification.userInfo {
                let affectedImageId = userInfo["newImageId"] as? String
                let oldImageId = userInfo["oldImageId"] as? String
                let currentImageId = imageId

                // Refresh if the new image ID matches, OR if the old image ID matches (for replacements)
                if (affectedImageId != nil && affectedImageId == currentImageId) ||
                   (oldImageId != nil && !oldImageId!.isEmpty && oldImageId == currentImageId) {
                    loadedImage = nil
                    loadImageIfNeeded()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageUpdated)) { notification in
            // Also refresh on imageUpdated notifications - this handles item-level updates
            if let userInfo = notification.userInfo,
               let action = userInfo["action"] as? String,
               action == "uploaded",
               let newImageId = userInfo["imageId"] as? String {

                // Check if this notification is for the current image
                if let currentImageId = imageId, currentImageId == newImageId {
                    print("🔄 [CachedImageView] Refreshing for uploaded image: \(newImageId)")
                    // Force refresh for this specific image
                    loadedImage = nil
                    loadImageIfNeeded()
                } else {
                    print("🔄 [CachedImageView] Ignoring notification for different image: \(newImageId) vs current: \(imageId ?? "nil")")
                }
            }
        }
    }
    
    private func loadImageIfNeeded() {
        guard let imageURL = imageURL, !imageURL.isEmpty else {
            return
        }

        isLoading = true

        Task {
            var image: UIImage?

            // UNIFIED IMAGE LOADING SYSTEM - ALL PATHS USE SAME LOGIC
            if imageURL.hasPrefix("cache://") {
                // Already cached, load directly from cache
                image = await imageCache.loadImage(from: imageURL)
            } else if imageURL.hasPrefix("https://") {
                // AWS URL - ALWAYS use the unified cache system
                let resolvedImageId = imageId ?? extractImageId(from: imageURL)

                // Try to get cache key first (for consistency with upload system)
                do {
                    if let cacheKey = try imageCache.getLocalCacheKey(for: resolvedImageId) {
                        // Use cache:// format for consistency
                        let cacheURL = "cache://\(cacheKey)"
                        image = await imageCache.loadImage(from: cacheURL)
                    }
                } catch {
                    // Fallback to freshness manager if no cache key found
                    image = await ImageFreshnessManager.shared.loadImageWithFreshnessCheck(
                        imageId: resolvedImageId,
                        awsUrl: imageURL,
                        imageCacheService: imageCache
                    )
                }
            } else {
                // Fallback to cache service
                image = await imageCache.loadImage(from: imageURL)
            }

            await MainActor.run {
                self.loadedImage = image
                self.isLoading = false
            }
        }
    }

    private func extractImageId(from url: String) -> String {
        // Create a unique, meaningful image ID from AWS URL
        // Use URL hash to ensure uniqueness while being deterministic
        let urlHash = url.sha256

        // Try to extract meaningful parts from URL path
        if let urlObj = URL(string: url) {
            let pathComponents = urlObj.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 {
                // Use last two path components for more meaningful ID
                let meaningfulPart = pathComponents.suffix(2).joined(separator: "_")
                return "\(meaningfulPart)_\(urlHash.prefix(8))"
            }
        }

        // Fallback to hash-based ID
        return "img_\(urlHash.prefix(12))"
    }

}

// MARK: - Convenience Initializers

extension CachedImageView {
    /// Create a cached image view for Square catalog items
    static func catalogItem(imageURL: String?, imageId: String? = nil, size: CGFloat = 60) -> CachedImageView {
        CachedImageView(
            imageURL: imageURL,
            imageId: imageId,
            placeholder: "cube.box",
            width: size,
            height: size,
            contentMode: .fill
        )
    }
    
    /// Create a cached image view for category images
    static func category(imageURL: String?, size: CGFloat = 40) -> CachedImageView {
        CachedImageView(
            imageURL: imageURL,
            placeholder: "folder",
            width: size,
            height: size,
            contentMode: .fill
        )
    }
    
    /// Create a cached image view for location/business images
    static func location(imageURL: String?, width: CGFloat = 100, height: CGFloat = 60) -> CachedImageView {
        CachedImageView(
            imageURL: imageURL,
            placeholder: "building.2",
            width: width,
            height: height,
            contentMode: .fill
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        CachedImageView.catalogItem(imageURL: "https://example.com/image.jpg")
        CachedImageView.category(imageURL: nil)
        CachedImageView.location(imageURL: "https://example.com/location.jpg")
    }
    .padding()
}
