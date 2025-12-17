import Foundation
import OSLog

/// Simple, industry-standard image URL cache
/// Maps Square IMAGE object IDs to their AWS URLs
/// This is the CORRECT way to handle Square API images per official documentation
/// NOT @MainActor - needs to be accessible from computed properties
class ImageURLCache {

    static let shared = ImageURLCache()

    private var cache: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.joylabs.ImageURLCache", attributes: .concurrent)
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageURLCache")

    private init() {
        logger.info("[ImageURLCache] Initialized")
    }

    // MARK: - Public Interface (Thread-Safe)

    /// Store image URL for given image ID
    func setURL(_ url: String, forImageId imageId: String) {
        queue.async(flags: .barrier) {
            self.cache[imageId] = url
        }
        logger.debug("[ImageURLCache] Cached: \(imageId) -> \(url)")
    }

    /// Get image URL for given image ID
    func getURL(forImageId imageId: String) -> String? {
        return queue.sync {
            return cache[imageId]
        }
    }

    /// Get primary image URL from item's imageIds array
    /// Per Square docs: first image in array is the primary/icon image
    func getPrimaryURL(fromImageIds imageIds: [String]?) -> String? {
        guard let firstImageId = imageIds?.first else {
            return nil
        }
        return queue.sync {
            return cache[firstImageId]
        }
    }

    /// Batch set multiple image URLs
    func setURLs(_ urlMapping: [String: String]) {
        queue.async(flags: .barrier) {
            self.cache.merge(urlMapping) { _, new in new }
        }
        logger.info("[ImageURLCache] Batch cached \(urlMapping.count) image URLs")
    }

    /// Clear all cached URLs
    func clearCache() {
        queue.async(flags: .barrier) {
            let count = self.cache.count
            self.cache.removeAll()
            self.logger.info("[ImageURLCache] Cleared \(count) cached image URLs")
        }
    }

    /// Get cache statistics
    func getStats() -> (count: Int, sampleIds: [String]) {
        return queue.sync {
            let sampleIds = Array(cache.keys.prefix(5))
            return (cache.count, sampleIds)
        }
    }
}
