import SwiftUI
import OSLog

/// Industry-standard image view using native AsyncImage
/// Replaces the complex UnifiedImageView with simple, robust implementation
struct SimpleImageView: View {
    let imageURL: String?
    let size: CGFloat
    let placeholder: String
    let contentMode: ContentMode
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SimpleImageView")
    
    init(
        imageURL: String?,
        size: CGFloat,
        placeholder: String = "photo",
        contentMode: ContentMode = .fit
    ) {
        self.imageURL = imageURL
        self.size = size
        self.placeholder = placeholder
        self.contentMode = contentMode
    }
    
    var body: some View {
        AsyncImage(url: URL(string: imageURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure(_):
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundColor(.red)
            case .empty:
                Image(systemName: placeholder)
                    .foregroundColor(.gray)
            @unknown default:
                Image(systemName: placeholder)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Factory Methods (for easy migration)
extension SimpleImageView {
    static func thumbnail(imageURL: String?, size: CGFloat = 50) -> SimpleImageView {
        SimpleImageView(imageURL: imageURL, size: size, placeholder: "photo", contentMode: .fit)
    }
    
    static func catalogItem(imageURL: String?, size: CGFloat = 100) -> SimpleImageView {
        SimpleImageView(imageURL: imageURL, size: size, placeholder: "photo", contentMode: .fit)
    }
    
    static func large(imageURL: String?, size: CGFloat = 200) -> SimpleImageView {
        SimpleImageView(imageURL: imageURL, size: size, placeholder: "photo", contentMode: .fit)
    }
}