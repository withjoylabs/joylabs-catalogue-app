import SwiftUI
import Foundation
import OSLog

/// Unified Image Service - Single source of truth for all image operations
/// Handles upload, caching, database mapping, and real-time UI refresh
@MainActor
class UnifiedImageService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = UnifiedImageService()
    
    // MARK: - Dependencies
    private let imageCacheService: ImageCacheService
    private let imageURLManager: ImageURLManager
    private let databaseManager: SQLiteSwiftCatalogManager
    private let httpClient: SquareHTTPClient
    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImageService")
    
    // MARK: - Published Properties for UI Binding
    @Published private var imageRefreshTriggers: [String: UUID] = [:]
    
    // MARK: - Initialization
    private init() {
        self.imageCacheService = ImageCacheService.shared
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        self.imageURLManager = ImageURLManager(databaseManager: databaseManager)
        let tokenService = SquareAPIServiceFactory.createTokenService()
        self.httpClient = SquareHTTPClient(tokenService: tokenService, resilienceService: BasicResilienceService())

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
        let squareResult = try await uploadToSquareAPI(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId
        )
        
        // Step 4: Clean up old cached image
        if let oldImageInfo = oldImageInfo {
            await cleanupOldImage(oldImageInfo)
        }
        
        // Step 5: Update database with new image
        try await updateItemDatabase(
            squareImageId: squareResult.squareImageId,
            awsUrl: squareResult.awsUrl,
            itemId: itemId,
            fileName: fileName
        )
        
        // Step 6: Cache new image and update database
        let cacheResult = try await cacheAndMapNewImage(
            squareImageId: squareResult.squareImageId,
            awsUrl: squareResult.awsUrl,
            itemId: itemId
        )
        
        // Step 7: Trigger real-time UI refresh
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
            // Direct AWS URL loading without unnecessary freshness checks
            return await imageCacheService.loadImageFromAWSUrl(imageURL)
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

        // Image marked as stale in cache service

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

        // Image cached successfully

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

        // Get the actual cache URL from the mapping (don't construct it manually)
        var imageURL = ""
        do {
            if let cacheKey = try imageURLManager.getLocalCacheKey(for: newImageId) {
                imageURL = "cache://\(cacheKey)"
                logger.debug("📋 Using actual cache key for notification: \(cacheKey)")
            } else {
                // Fallback to AWS URL if cache key not found
                if let imageInfo = try await getPrimaryImageInfo(for: itemId) {
                    imageURL = imageInfo.awsUrl
                    logger.warning("⚠️ No cache key found, using AWS URL for notification")
                }
            }
        } catch {
            logger.error("❌ Failed to get cache key for notification: \(error)")
        }

        // Post SINGLE notification for UI updates (eliminate redundancy)
        NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
            "itemId": itemId,
            "imageId": newImageId,
            "imageURL": imageURL,
            "oldImageId": oldImageId ?? "",
            "action": "uploaded"
        ])

        logger.info("✅ Image refresh notification sent for item: \(itemId) (new: \(newImageId), URL: \(imageURL))")
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
    
    /// Upload image directly to Square API
    private func uploadToSquareAPI(
        imageData: Data,
        fileName: String,
        itemId: String
    ) async throws -> (squareImageId: String, awsUrl: String) {
        logger.info("🚀 Uploading image to Square API: \(fileName)")
        
        let idempotencyKey = UUID().uuidString
        let response = try await httpClient.uploadImageToSquare(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId,
            idempotencyKey: idempotencyKey
        )
        
        // CRITICAL: Update catalog version after successful image upload
        let catalogVersion = Date()
        try await SquareAPIServiceFactory.createDatabaseManager().saveCatalogVersion(catalogVersion)
        logger.info("📅 Updated catalog version after image upload: \(catalogVersion)")
        
        guard let imageObject = response.image,
              let imageData = imageObject.imageData,
              let awsUrl = imageData.url else {
            throw UnifiedImageError.uploadFailed("Invalid response from Square image upload")
        }

        let squareImageId = imageObject.id
        
        logger.info("✅ Successfully uploaded image to Square: \(squareImageId)")
        logger.info("📍 AWS URL: \(awsUrl)")

        return (squareImageId: squareImageId, awsUrl: awsUrl)
    }
    
    /// Update local database with new image
    private func updateItemDatabase(
        squareImageId: String,
        awsUrl: String,
        itemId: String,
        fileName: String
    ) async throws {
        guard let db = databaseManager.getConnection() else {
            throw UnifiedImageError.databaseNotConnected
        }

        logger.info("💾 Updating local database with new image: \(squareImageId)")

        let now = Date().timeIntervalSince1970
        
        // 1. Save the image to the images table
        let imageDataJson = [
            "name": fileName,
            "url": awsUrl,
            "caption": "Uploaded via JoyLabs iOS app"
        ]

        do {
            try db.run("""
                INSERT OR REPLACE INTO images
                (id, updated_at, version, is_deleted, name, url, caption, data_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            squareImageId,
            String(now),
            "1",
            false,
            fileName,
            awsUrl,
            "Uploaded via JoyLabs iOS app",
            try JSONSerialization.data(withJSONObject: imageDataJson).base64EncodedString()
            )

            logger.info("✅ Saved image to images table: \(squareImageId)")
        } catch {
            logger.error("❌ Failed to save image to images table: \(error)")
            throw UnifiedImageError.uploadFailed("Failed to save image to database")
        }

        // 2. Update the item's data to include the new image ID as primary
        do {
            let selectQuery = """
                SELECT id, data_json FROM catalog_items
                WHERE id = ? AND is_deleted = 0
            """

            let statement = try db.prepare(selectQuery)

            for row in try statement.run([itemId]) {
                let dataJsonString = row[1] as? String ?? "{}"
                let dataJsonData = dataJsonString.data(using: String.Encoding.utf8) ?? Data()

                var currentData = try JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any] ?? [:]

                // Get current image_ids array
                var imageIds = currentData["image_ids"] as? [String] ?? []

                // Remove the new image ID if it already exists
                imageIds.removeAll { $0 == squareImageId }

                // Add as primary image (first in array)
                imageIds.insert(squareImageId, at: 0)

                // Update the data
                currentData["image_ids"] = imageIds

                // Save back to database
                let updatedDataJson = try JSONSerialization.data(withJSONObject: currentData)
                let updatedDataJsonString = String(data: updatedDataJson, encoding: .utf8) ?? "{}"

                let updateQuery = """
                    UPDATE catalog_items
                    SET data_json = ?, updated_at = ?
                    WHERE id = ?
                """

                try db.run(updateQuery, updatedDataJsonString, String(now), itemId)

                logger.info("✅ Updated item with new primary image: \(itemId) -> \(squareImageId)")
                logger.info("📊 Updated image_ids array: \(imageIds)")
                return
            }

            logger.warning("⚠️ Item not found in database: \(itemId)")
        } catch {
            logger.error("❌ Failed to update item with new image: \(error)")
            throw UnifiedImageError.uploadFailed("Failed to update item with new image")
        }
    }
}
