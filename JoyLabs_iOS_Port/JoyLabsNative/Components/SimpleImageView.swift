import SwiftUI
import OSLog

/// Industry-standard image view with proper URLCache utilization
/// Uses custom URLSession to ensure aggressive caching for instant repeated loads
struct SimpleImageView: View {
    let imageURL: String?
    let size: CGFloat
    let placeholder: String
    let contentMode: ContentMode
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SimpleImageView")
    
    // Custom URLSession with aggressive caching
    private static let cachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
    
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
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
            } else {
                Image(systemName: placeholder)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loadImage()
        }
        .onChange(of: imageURL) { _, _ in
            image = nil
            isLoading = false
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let urlString = imageURL,
              !urlString.isEmpty,
              image == nil, !isLoading else { return }
        
        // Handle base64 data URLs for new items with embedded image data
        if urlString.hasPrefix("data:image") {
            logger.debug("Loading base64 data URL image")
            loadBase64Image(from: urlString)
            return
        }
        
        // Regular HTTP/HTTPS URLs
        guard let url = URL(string: urlString) else { return }
        
        isLoading = true
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        
        Self.cachedSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data, let uiImage = UIImage(data: data) {
                    image = uiImage
                }
            }
        }.resume()
    }
    
    private func loadBase64Image(from dataURL: String) {
        // Extract base64 data from data URL format: data:image/jpeg;base64,<base64-data>
        guard let commaRange = dataURL.range(of: ","),
              let base64Data = Data(base64Encoded: String(dataURL[commaRange.upperBound...])),
              let uiImage = UIImage(data: base64Data) else {
            logger.error("Failed to decode base64 image data")
            return
        }
        
        image = uiImage
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