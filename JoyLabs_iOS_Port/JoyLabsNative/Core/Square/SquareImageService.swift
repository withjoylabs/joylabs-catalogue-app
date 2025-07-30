import Foundation
import UIKit
import OSLog
import SQLite

// MARK: - Square Image Service Result Types
struct SquareImageUploadResult {
    let squareImageId: String
    let awsUrl: String
    let localCacheUrl: String
}

/// Service for uploading images to Square API and integrating with local caching system
@MainActor
class SquareImageService: ObservableObject {

    private let httpClient: SquareHTTPClient
    private let imageCacheService: ImageCacheService
    private let databaseManager: SQLiteSwiftCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareImageService")

    init(httpClient: SquareHTTPClient, imageCacheService: ImageCacheService, databaseManager: SQLiteSwiftCatalogManager) {
        self.httpClient = httpClient
        self.imageCacheService = imageCacheService
        self.databaseManager = databaseManager
        logger.info("SquareImageService initialized")
    }
    
    /// Upload image to Square and integrate with local caching system
    func uploadImage(
        imageData: Data,
        fileName: String,
        itemId: String?
    ) async throws -> SquareImageUploadResult {
        logger.info("Starting image upload to Square: \(fileName)")
        
        // Step 1: Upload to Square API
        let idempotencyKey = UUID().uuidString
        let response = try await httpClient.uploadImageToSquare(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId,
            idempotencyKey: idempotencyKey
        )
        
        // CRITICAL: Update catalog version after successful image upload
        let catalogVersion = Date()
        try await databaseManager.saveCatalogVersion(catalogVersion)
        logger.info("📅 Updated catalog version after image upload: \(catalogVersion)")
        
        guard let imageObject = response.image,
              let imageData = imageObject.imageData,
              let awsUrl = imageData.url else {
            throw SquareAPIError.upsertFailed("Invalid response from Square image upload")
        }

        let squareImageId = imageObject.id
        
        // DEDUPLICATION: Record this local operation to prevent processing webhooks for our own changes
        PushNotificationService.shared.recordLocalOperation(itemId: squareImageId)
        if let itemId = itemId {
            PushNotificationService.shared.recordLocalOperation(itemId: itemId)
        }
        
        logger.info("Successfully uploaded image to Square: \(squareImageId)")

        // Step 2: Cache image with mapping (same as sync process)
        // Note: Square API already associated the image with the item via is_primary flag
        // This creates the proper mapping that search results expect
        let localCacheUrl = try await cacheImageWithMapping(
            squareImageId: squareImageId,
            awsUrl: awsUrl,
            itemId: itemId
        )

        // Step 3: Update local database with new image data
        if let itemId = itemId {
            // First, get the old image ID to invalidate it
            let oldImageId = try await getOldImageIdForItem(itemId: itemId)

            try await updateLocalDatabaseWithNewImage(
                squareImageId: squareImageId,
                awsUrl: awsUrl,
                itemId: itemId,
                fileName: fileName
            )

            // Step 4: Force cache invalidation and refresh
            await forceCacheRefreshForImageUpload(
                oldImageId: oldImageId,
                newImageId: squareImageId,
                itemId: itemId
            )
        }

        return SquareImageUploadResult(
            squareImageId: squareImageId,
            awsUrl: awsUrl,
            localCacheUrl: localCacheUrl
        )
    }
    
    /// Cache image with mapping (same as sync process)
    private func cacheImageWithMapping(
        squareImageId: String,
        awsUrl: String,
        itemId: String?
    ) async throws -> String {
        logger.info("Caching image with mapping (same as sync process): \(squareImageId)")

        // Use the EXACT same method as the sync process to create mappings
        let cacheUrl = await imageCacheService.cacheImageWithMapping(
            awsUrl: awsUrl,
            squareImageId: squareImageId,
            objectType: "ITEM",
            objectId: itemId ?? squareImageId, // Use imageId as objectId if no itemId
            imageType: "PRIMARY"
        )

        guard let cacheUrl = cacheUrl else {
            throw SquareAPIError.networkError(NSError(domain: "ImageCache", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cache image with mapping"]))
        }

        logger.info("Successfully cached image with mapping: \(cacheUrl)")
        return cacheUrl
    }

    /// Update local database with new image data (same as React Native version)
    private func updateLocalDatabaseWithNewImage(
        squareImageId: String,
        awsUrl: String,
        itemId: String,
        fileName: String
    ) async throws {
        guard let db = databaseManager.getConnection() else {
            throw SquareAPIError.upsertFailed("Database not connected")
        }

        logger.info("Updating local database with new image: \(squareImageId)")

        // 1. Save the image to the images table
        let now = Date().timeIntervalSince1970
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
            throw SquareAPIError.upsertFailed("Failed to save image to database")
        }

        // 2. Update the item's data to include the new image ID as primary
        do {
            // Use raw SQL for complex JSON operations
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
                return // Exit after processing the first (and only) row
            }

            logger.warning("⚠️ Item not found in database: \(itemId)")
        } catch {
            logger.error("❌ Failed to update item with new image: \(error)")
            throw SquareAPIError.upsertFailed("Failed to update item with new image")
        }
    }
    
    /// Update existing image in Square
    func updateImage(
        imageId: String,
        imageData: Data,
        fileName: String
    ) async throws -> SquareImageUploadResult {
        logger.info("Updating existing image in Square: \(imageId)")
        
        // For updates, we need to use the PUT endpoint
        // This is a simplified implementation - full implementation would use PUT /v2/catalog/images/{image_id}
        // For now, we'll create a new image and return that
        return try await uploadImage(imageData: imageData, fileName: fileName, itemId: nil)
    }
    
    /// Delete image from Square
    func deleteImage(imageId: String) async throws {
        logger.info("Deleting image from Square: \(imageId)")
        
        // Use existing HTTP client to delete the catalog object
        _ = try await httpClient.deleteCatalogObject(imageId)
        
        // Clean up local cache
        try await cleanupLocalCache(imageId: imageId)
        
        logger.info("Successfully deleted image: \(imageId)")
    }
    




    /// Clean up local cache for deleted image
    private func cleanupLocalCache(imageId: String) async throws {
        logger.info("Cleaning up local cache for image: \(imageId)")

        // Use the existing invalidateImageById method which handles cleanup
        await imageCacheService.invalidateImageById(squareImageId: imageId)

        logger.info("Successfully cleaned up local cache for image: \(imageId)")
    }
}

// MARK: - Convenience Extensions
extension SquareImageService {
    
    /// Upload UIImage with automatic format conversion
    func uploadUIImage(
        _ image: UIImage,
        fileName: String,
        itemId: String?
    ) async throws -> SquareImageUploadResult {
        // Convert UIImage to JPEG data with high quality
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw SquareAPIError.upsertFailed("Failed to convert UIImage to JPEG data")
        }
        
        return try await uploadImage(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId
        )
    }
    
    /// Get file size in MB for validation
    func getImageSizeInMB(_ imageData: Data) -> Double {
        return Double(imageData.count) / (1024 * 1024)
    }
    
    /// Validate image data meets Square API requirements
    func validateImageData(_ imageData: Data) throws {
        let sizeMB = getImageSizeInMB(imageData)
        
        // Square API limit: 15MB
        guard sizeMB <= 15.0 else {
            throw SquareAPIError.upsertFailed("Image size (\(String(format: "%.2f", sizeMB))MB) exceeds Square API limit of 15MB")
        }
        
        // Minimum size check (1KB)
        guard imageData.count >= 1024 else {
            throw SquareAPIError.upsertFailed("Image size too small (minimum 1KB required)")
        }
    }

    /// Get the current image ID for an item before uploading new one
    private func getOldImageIdForItem(itemId: String) async throws -> String? {
        guard let db = databaseManager.getConnection() else {
            throw SquareAPIError.upsertFailed("No database connection")
        }

        // Use SQLite.swift table syntax
        let catalogItems = Table("catalog_items")
        let id = Expression<String>("id")
        let dataJson = Expression<String?>("data_json")

        let query = catalogItems.select(dataJson).where(id == itemId)

        if let row = try db.pluck(query) {
            let dataJsonString = row[dataJson] ?? ""
            if let data = dataJsonString.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let imageIds = json["image_ids"] as? [String],
               let firstImageId = imageIds.first {
                return firstImageId
            }
        }

        return nil
    }

    /// Clean up old image and notify UI components of new image
    private func forceCacheRefreshForImageUpload(
        oldImageId: String?,
        newImageId: String,
        itemId: String
    ) async {
        // CRITICAL: Invalidate freshness for old image to force refresh
        if let oldImageId = oldImageId, oldImageId != newImageId {
            ImageFreshnessManager.shared.invalidateImage(imageId: oldImageId)
            await imageCacheService.deleteCachedImage(imageId: oldImageId)
            logger.info("🗑️ Deleted old cached image: \(oldImageId)")
        }

        // Mark new image as fresh
        ImageFreshnessManager.shared.markImageAsFresh(imageId: newImageId)

        // Force refresh in all UI components by posting notifications
        await MainActor.run {
            let cacheURL = "cache://\(newImageId).jpeg"

            logger.info("📡 Posting forceImageRefresh notification for item: \(itemId)")
            // Post forceImageRefresh for image-level updates
            NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
                "itemId": itemId,
                "oldImageId": oldImageId ?? "",
                "newImageId": newImageId
            ])

            logger.info("📡 Posting imageUpdated notification for item: \(itemId)")
            // Also post imageUpdated for item-level updates
            NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
                "itemId": itemId,
                "imageId": newImageId,
                "imageURL": cacheURL,
                "action": "uploaded"
            ])
        }
    }
}

// MARK: - Static Factory
extension SquareImageService {
    
    /// Create SquareImageService with default dependencies
    static func create() -> SquareImageService {
        let tokenService = SquareAPIServiceFactory.createTokenService()
        let httpClient = SquareHTTPClient(tokenService: tokenService, resilienceService: BasicResilienceService())
        let imageCacheService = ImageCacheService.shared
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SquareImageService(httpClient: httpClient, imageCacheService: imageCacheService, databaseManager: databaseManager)
    }
}
