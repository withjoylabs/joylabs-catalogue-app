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
            if let userInfo = notification.userInfo,
               let affectedImageId = userInfo["newImageId"] as? String,
               let currentImageId = imageId,
               affectedImageId == currentImageId {
                loadedImage = nil
                loadImageIfNeeded()
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

            if imageURL.hasPrefix("cache://") {
                // Already cached, load directly
                image = await imageCache.loadImage(from: imageURL)
            } else if imageURL.hasPrefix("https://") {
                // AWS URL - use intelligent freshness checking
                let resolvedImageId = imageId ?? extractImageId(from: imageURL)

                // Use freshness manager for intelligent caching
                image = await ImageFreshnessManager.shared.loadImageWithFreshnessCheck(
                    imageId: resolvedImageId,
                    awsUrl: imageURL,
                    imageCacheService: imageCache
                )
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
