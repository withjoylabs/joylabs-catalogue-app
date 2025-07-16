import SwiftUI
import Foundation

/// A SwiftUI view that displays images with automatic caching
struct CachedImageView: View {
    let imageURL: String?
    let placeholder: String
    let width: CGFloat?
    let height: CGFloat?
    let contentMode: ContentMode
    
    @StateObject private var imageCache = ImageCacheService.shared
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    
    init(
        imageURL: String?,
        placeholder: String = "photo",
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        contentMode: ContentMode = .fit
    ) {
        self.imageURL = imageURL
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
                    .frame(width: width, height: height)
            } else {
                Image(systemName: placeholder)
                    .foregroundColor(.gray)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: imageURL) { _, newURL in
            loadedImage = nil
            loadImageIfNeeded()
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
                // AWS URL - use on-demand loader with rate limiting
                let imageId = extractImageId(from: imageURL)
                image = await imageCache.loadImageOnDemand(imageId: imageId, awsUrl: imageURL)
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
        // Extract image ID from AWS URL for caching
        // Example: https://s3.amazonaws.com/bucket/path/imageId.jpg -> imageId
        if let lastComponent = URL(string: url)?.lastPathComponent {
            return String(lastComponent.prefix(while: { $0 != "." }))
        }
        return url.replacingOccurrences(of: "/", with: "_")
    }

}

// MARK: - Convenience Initializers

extension CachedImageView {
    /// Create a cached image view for Square catalog items
    static func catalogItem(imageURL: String?, size: CGFloat = 60) -> CachedImageView {
        CachedImageView(
            imageURL: imageURL,
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
