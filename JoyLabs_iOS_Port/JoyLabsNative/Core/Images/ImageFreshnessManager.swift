import Foundation
import UIKit
import OSLog

/// Manages image freshness and intelligent cache invalidation
class ImageFreshnessManager {
    static let shared = ImageFreshnessManager()
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageFreshnessManager")
    private let userDefaults = UserDefaults.standard
    
    // Cache freshness settings
    private let imageCacheMaxAge: TimeInterval = 3600 // 1 hour
    private let lastImageCheckKey = "lastImageFreshnessCheck"
    private let imageTimestampsKey = "imageTimestamps"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if an image cache entry is fresh
    func isImageFresh(imageId: String) -> Bool {
        guard let timestamps = getImageTimestamps(),
              let lastCached = timestamps[imageId] else {
            logger.info("No timestamp found for image: \(imageId)")
            return false
        }
        
        let age = Date().timeIntervalSince(lastCached)
        let isFresh = age < imageCacheMaxAge
        
        logger.info("Image \(imageId) age: \(Int(age))s, fresh: \(isFresh)")
        return isFresh
    }
    
    /// Mark an image as freshly cached
    func markImageAsFresh(imageId: String) {
        var timestamps = getImageTimestamps() ?? [:]
        timestamps[imageId] = Date()
        setImageTimestamps(timestamps)
        
        logger.info("Marked image as fresh: \(imageId)")
    }
    
    /// Invalidate a specific image cache entry
    func invalidateImage(imageId: String) {
        var timestamps = getImageTimestamps() ?? [:]
        timestamps.removeValue(forKey: imageId)
        setImageTimestamps(timestamps)
        
        logger.info("Invalidated image cache: \(imageId)")
    }
    
    /// Check if we should perform a global freshness check
    func shouldPerformGlobalFreshnessCheck() -> Bool {
        let lastCheck = userDefaults.object(forKey: lastImageCheckKey) as? Date ?? Date.distantPast
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
        
        // Perform global check every 30 minutes
        return timeSinceLastCheck > 1800
    }
    
    /// Mark that we performed a global freshness check
    func markGlobalFreshnessCheckPerformed() {
        userDefaults.set(Date(), forKey: lastImageCheckKey)
    }
    
    /// Clean up old timestamp entries
    func cleanupOldEntries() {
        guard var timestamps = getImageTimestamps() else { return }
        
        let cutoffDate = Date().addingTimeInterval(-imageCacheMaxAge * 2) // Keep entries for 2x cache age
        let originalCount = timestamps.count
        
        timestamps = timestamps.filter { $0.value > cutoffDate }
        
        if timestamps.count != originalCount {
            setImageTimestamps(timestamps)
            logger.info("Cleaned up \(originalCount - timestamps.count) old image timestamp entries")
        }
    }
    
    // MARK: - Private Methods
    
    private func getImageTimestamps() -> [String: Date]? {
        guard let data = userDefaults.data(forKey: imageTimestampsKey) else { return nil }
        return try? JSONDecoder().decode([String: Date].self, from: data)
    }
    
    private func setImageTimestamps(_ timestamps: [String: Date]) {
        if let data = try? JSONEncoder().encode(timestamps) {
            userDefaults.set(data, forKey: imageTimestampsKey)
        }
    }
}

/// Extension to integrate with existing image loading
extension ImageFreshnessManager {
    
    /// Smart image loading that checks freshness
    func loadImageWithFreshnessCheck(imageId: String, awsUrl: String?, imageCacheService: ImageCacheService) async -> UIImage? {
        
        // If we have a fresh cache entry, use it
        if isImageFresh(imageId: imageId) {
            logger.info("Using fresh cached image: \(imageId)")
            if let cachedImage = await imageCacheService.loadImageOnDemand(imageId: imageId, awsUrl: awsUrl ?? "") {
                return cachedImage
            }
        }

        // Cache is stale or missing, download fresh image
        if let awsUrl = awsUrl {
            logger.info("Downloading fresh image: \(imageId)")
            if let freshImage = await imageCacheService.loadImageFromAWSUrl(awsUrl) {
                markImageAsFresh(imageId: imageId)
                return freshImage
            }
        }

        // Fallback to any cached version we have
        logger.warning("Falling back to any cached version for: \(imageId)")
        return await imageCacheService.loadImageOnDemand(imageId: imageId, awsUrl: awsUrl ?? "")
    }
}
