import Foundation
import OSLog

/// Simple, industry-standard image URL cache
/// Maps Square IMAGE object IDs to their AWS URLs
/// This is the CORRECT way to handle Square API images per official documentation
@MainActor
class ImageURLCache {

    static let shared = ImageURLCache()

    private var cache: [String: String] = [:]
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageURLCache")

    private init() {
        logger.info("[ImageURLCache] Initialized")
    }

    // MARK: - Public Interface

    /// Store image URL for given image ID
    func setURL(_ url: String, forImageId imageId: String) {
        cache[imageId] = url
        logger.debug("[ImageURLCache] Cached: \(imageId) -> \(url)")
    }

    /// Get image URL for given image ID
    func getURL(forImageId imageId: String) -> String? {
        return cache[imageId]
    }

    /// Get primary image URL from item's imageIds array
    /// Per Square docs: first image in array is the primary/icon image
    func getPrimaryURL(fromImageIds imageIds: [String]?) -> String? {
        guard let firstImageId = imageIds?.first else {
            return nil
        }
        return cache[firstImageId]
    }

    /// Batch set multiple image URLs
    func setURLs(_ urlMapping: [String: String]) {
        cache.merge(urlMapping) { _, new in new }
        logger.info("[ImageURLCache] Batch cached \(urlMapping.count) image URLs")
    }

    /// Clear all cached URLs
    func clearCache() {
        let count = cache.count
        cache.removeAll()
        logger.info("[ImageURLCache] Cleared \(count) cached image URLs")
    }

    /// Get cache statistics
    func getStats() -> (count: Int, sampleIds: [String]) {
        let sampleIds = Array(cache.keys.prefix(5))
        return (cache.count, sampleIds)
    }
}
