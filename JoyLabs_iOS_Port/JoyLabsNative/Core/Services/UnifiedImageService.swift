import SwiftUI
import Foundation
import OSLog
import CropViewController

/// Unified Image Service - Single source of truth for all image operations
/// Handles upload, caching, database mapping, and real-time UI refresh
@MainActor
class UnifiedImageService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = UnifiedImageService()
    
    // MARK: - Dependencies
    private let squareImageService: SquareImageService
    private let imageCacheService: ImageCacheService
    private let imageURLManager: ImageURLManager
    private let databaseManager: SQLiteSwiftCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImageService")
    
    // MARK: - Published Properties for UI Binding
    @Published private var imageRefreshTriggers: [String: UUID] = [:]
    
    // MARK: - Initialization
    private init() {
        self.squareImageService = SquareImageService.create()
        self.imageCacheService = ImageCacheService.shared
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        self.imageURLManager = ImageURLManager(databaseManager: databaseManager)

        logger.info("🖼️ UnifiedImageService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Get refresh trigger for a specific item (used by UI components)
    func getRefreshTrigger(for itemId: String) -> UUID {
        return imageRefreshTriggers[itemId] ?? UUID()
    }
    
    /// Upload image with complete lifecycle management
    func uploadImage(
        imageData: Data,
        fileName: String,
        itemId: String,
        context: ImageUploadContext
    ) async throws -> ImageUploadResult {
        logger.info("🚀 Starting unified image upload for item: \(itemId)")
        
        // Step 1: Validate image data
        try validateImageData(imageData)
        
        // Step 2: Get old image info for cleanup
        let oldImageInfo = try await getOldImageInfo(for: itemId)
        
        // Step 3: Upload to Square API
        let squareResult = try await squareImageService.uploadImage(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId
        )
        
        // Step 4: Clean up old cached image
        if let oldImageInfo = oldImageInfo {
            await cleanupOldImage(oldImageInfo)
        }
        
        // Step 5: Cache new image and update database
        let cacheResult = try await cacheAndMapNewImage(
            squareImageId: squareResult.squareImageId,
            awsUrl: squareResult.awsUrl,
            itemId: itemId
        )
        
        // Step 6: Trigger real-time UI refresh
        await triggerGlobalImageRefresh(
            itemId: itemId,
            newImageId: squareResult.squareImageId,
            oldImageId: oldImageInfo?.imageId
        )
        
        logger.info("✅ Unified image upload completed for item: \(itemId)")
        
        return ImageUploadResult(
            squareImageId: squareResult.squareImageId,
            awsUrl: squareResult.awsUrl,
            localCacheUrl: cacheResult.cacheUrl,
            context: context
        )
    }
    
    /// Load image with unified caching strategy
    func loadImage(
        imageURL: String?,
        imageId: String?,
        itemId: String
    ) async -> UIImage? {
        guard let imageURL = imageURL, !imageURL.isEmpty else {
            logger.debug("No image URL provided for item: \(itemId)")
            return nil
        }
        
        // UNIFIED APPROACH: Only use AWS URL for caching (no deprecated Square image ID fallback)
        if imageURL.hasPrefix("cache://") {
            return await imageCacheService.loadImage(from: imageURL)
        } else if imageURL.hasPrefix("https://") {
            // ALWAYS use ImageFreshnessManager with AWS URL - no deprecated cache key lookup
            let resolvedImageId = imageId ?? extractImageId(from: imageURL)
            return await ImageFreshnessManager.shared.loadImageWithFreshnessCheck(
                imageId: resolvedImageId,
                awsUrl: imageURL,
                imageCacheService: imageCacheService
            )
        }

        return await imageCacheService.loadImage(from: imageURL)
    }
    
    /// Get primary image info for an item
    func getPrimaryImageInfo(for itemId: String) async throws -> ImageInfo? {
        guard let db = databaseManager.getConnection() else {
            throw UnifiedImageError.databaseNotConnected
        }
        
        // Get item's image_ids array
        let selectQuery = """
            SELECT data_json FROM catalog_items
            WHERE id = ? AND is_deleted = 0
        """
        
        let statement = try db.prepare(selectQuery)
        for row in try statement.run([itemId]) {
            let dataJsonString = row[0] as? String ?? "{}"
            let dataJsonData = dataJsonString.data(using: String.Encoding.utf8) ?? Data()
            
            if let currentData = try JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any],
               let imageIds = currentData["image_ids"] as? [String],
               let primaryImageId = imageIds.first {
                
                // Get image mapping
                let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
                if let mapping = imageMappings.first(where: { $0.squareImageId == primaryImageId }) {
                    return ImageInfo(
                        imageId: primaryImageId,
                        awsUrl: mapping.originalAwsUrl,
                        cacheUrl: "cache://\(mapping.localCacheKey)",
                        itemId: itemId
                    )
                }
            }
        }
        
        return nil
    }
}

// MARK: - Supporting Types

/// Context for image upload operations
enum ImageUploadContext {
    case itemDetails(itemId: String?)
    case scanViewLongPress(itemId: String, imageId: String?)
    case reordersViewLongPress(itemId: String, imageId: String?)

    var title: String {
        switch self {
        case .itemDetails:
            return "Add Photo"
        case .scanViewLongPress, .reordersViewLongPress:
            return "Update Photo"
        }
    }

    var isUpdate: Bool {
        switch self {
        case .itemDetails:
            return false
        case .scanViewLongPress, .reordersViewLongPress:
            return true
        }
    }
}

/// Result of image upload operation
struct ImageUploadResult {
    let squareImageId: String
    let awsUrl: String
    let localCacheUrl: String
    let context: ImageUploadContext
}

/// Information about an image
struct ImageInfo {
    let imageId: String
    let awsUrl: String
    let cacheUrl: String
    let itemId: String
}

/// Cache operation result
struct CacheResult {
    let cacheUrl: String
    let cacheKey: String
}

/// Unified image service errors
enum UnifiedImageError: LocalizedError {
    case databaseNotConnected
    case invalidImageData(String)
    case uploadFailed(String)
    case cacheOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotConnected:
            return "Database connection not available"
        case .invalidImageData(let message):
            return "Invalid image data: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .cacheOperationFailed(let message):
            return "Cache operation failed: \(message)"
        }
    }
}

// MARK: - Private Implementation
extension UnifiedImageService {

    /// Validate image data meets requirements
    private func validateImageData(_ imageData: Data) throws {
        let sizeMB = Double(imageData.count) / (1024 * 1024)

        // Square API limit: 15MB
        guard sizeMB <= 15.0 else {
            throw UnifiedImageError.invalidImageData("Image size (\(String(format: "%.2f", sizeMB))MB) exceeds Square API limit of 15MB")
        }

        // Minimum size check (1KB)
        guard imageData.count >= 1024 else {
            throw UnifiedImageError.invalidImageData("Image size too small (minimum 1KB required)")
        }
    }

    /// Get old image information for cleanup
    private func getOldImageInfo(for itemId: String) async throws -> ImageInfo? {
        return try await getPrimaryImageInfo(for: itemId)
    }

    /// Clean up old cached image
    private func cleanupOldImage(_ imageInfo: ImageInfo) async {
        logger.info("🧹 Cleaning up old image: \(imageInfo.imageId)")

        // Remove from memory cache
        imageCacheService.removeFromMemoryCache(imageId: imageInfo.imageId)

        // Mark as stale in freshness manager
        ImageFreshnessManager.shared.markImageAsStale(imageId: imageInfo.imageId)

        // Note: We don't delete the physical cache file immediately as other views might still be using it
        // The cache cleanup process will handle this during regular maintenance
    }

    /// Cache new image and update database mappings
    private func cacheAndMapNewImage(
        squareImageId: String,
        awsUrl: String,
        itemId: String
    ) async throws -> CacheResult {
        logger.info("💾 Caching and mapping new image: \(squareImageId)")

        // Cache image with proper mapping
        guard let cacheUrl = await imageCacheService.cacheImageWithMapping(
            awsUrl: awsUrl,
            squareImageId: squareImageId,
            objectType: "ITEM",
            objectId: itemId,
            imageType: "PRIMARY"
        ) else {
            throw UnifiedImageError.cacheOperationFailed("Failed to cache image with mapping")
        }

        // Extract cache key from URL
        let cacheKey = String(cacheUrl.dropFirst(8)) // Remove "cache://"

        // Mark as fresh
        ImageFreshnessManager.shared.markImageAsFresh(imageId: squareImageId)

        return CacheResult(cacheUrl: cacheUrl, cacheKey: cacheKey)
    }

    /// Trigger global image refresh across all UI components
    private func triggerGlobalImageRefresh(
        itemId: String,
        newImageId: String,
        oldImageId: String?
    ) async {
        logger.info("🔄 Triggering global image refresh for item: \(itemId)")

        // Update local refresh trigger
        imageRefreshTriggers[itemId] = UUID()

        // Post notifications for all UI components
        let cacheURL = "cache://\(newImageId).jpeg"

        // Post forceImageRefresh for image-level updates
        NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
            "itemId": itemId,
            "oldImageId": oldImageId ?? "",
            "newImageId": newImageId
        ])

        // Post imageUpdated for item-level updates
        NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
            "itemId": itemId,
            "imageId": newImageId,
            "imageURL": cacheURL,
            "action": "uploaded"
        ])

        logger.info("✅ Global image refresh notifications sent for item: \(itemId)")
    }

    /// Extract image ID from AWS URL (fallback method)
    private func extractImageId(from url: String) -> String {
        // Try to extract a meaningful ID from the URL
        if let urlComponents = URLComponents(string: url),
           let lastPathComponent = urlComponents.path.split(separator: "/").last {
            return String(lastPathComponent.split(separator: ".").first ?? lastPathComponent)
        }

        // Fallback to hash of URL
        return String(url.hashValue)
    }
}
