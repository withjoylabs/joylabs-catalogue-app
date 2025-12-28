import Foundation

/// Manages shared URLSession for aggressive image caching
/// Industry-standard approach: Configure once, use everywhere
@MainActor
class ImageCacheManager {
    static let shared = ImageCacheManager()

    private(set) var urlSession: URLSession!

    private init() {
        // Will be configured during app initialization
        // Default to URLSession.shared as fallback
        self.urlSession = URLSession.shared
    }

    func configureSession(with configuration: URLSessionConfiguration) {
        self.urlSession = URLSession(configuration: configuration)
    }
}
