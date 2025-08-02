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
              let url = URL(string: urlString),
              image == nil, !isLoading else { return }
        
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