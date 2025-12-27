import SwiftUI
import SwiftData

/// Native iOS image view using SwiftData @Query + AsyncImage
/// Zero custom caching - leverages iOS URLCache automatically
/// Reactive updates when ImageModel changes
struct NativeImageView: View {
    let imageId: String?
    let size: CGFloat
    let placeholder: String
    let contentMode: ContentMode

    @Query private var images: [ImageModel]

    init(
        imageId: String?,
        size: CGFloat,
        placeholder: String = "photo",
        contentMode: ContentMode = .fit
    ) {
        self.imageId = imageId
        self.size = size
        self.placeholder = placeholder
        self.contentMode = contentMode

        // Setup SwiftData query for this specific image ID
        if let imageId = imageId, !imageId.isEmpty {
            let predicate = #Predicate<ImageModel> { model in
                model.id == imageId
            }
            _images = Query(filter: predicate)
        } else {
            // No image ID - show placeholder only
            _images = Query(filter: #Predicate<ImageModel> { _ in false })
        }
    }

    private var imageURL: String? {
        images.first?.url
    }

    var body: some View {
        Group {
            if let url = imageURL, !url.isEmpty, let validURL = URL(string: url) {
                // Native AsyncImage with automatic URLCache
                AsyncImage(url: validURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        Image(systemName: placeholder)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                // No URL - show placeholder
                Image(systemName: placeholder)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Factory Methods (convenience sizing presets)
extension NativeImageView {
    static func thumbnail(imageId: String?, size: CGFloat = 50) -> NativeImageView {
        NativeImageView(imageId: imageId, size: size, placeholder: "photo", contentMode: .fit)
    }

    static func catalogItem(imageId: String?, size: CGFloat = 100) -> NativeImageView {
        NativeImageView(imageId: imageId, size: size, placeholder: "photo", contentMode: .fit)
    }

    static func large(imageId: String?, size: CGFloat = 200) -> NativeImageView {
        NativeImageView(imageId: imageId, size: size, placeholder: "photo", contentMode: .fit)
    }
}
