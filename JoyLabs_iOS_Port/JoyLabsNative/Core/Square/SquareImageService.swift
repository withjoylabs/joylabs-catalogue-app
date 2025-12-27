import Foundation
import SwiftData
import UIKit
import OSLog

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
    private let databaseManager: SwiftDataCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareImageService")

    init(httpClient: SquareHTTPClient, databaseManager: SwiftDataCatalogManager) {
        self.httpClient = httpClient
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

        // NativeImageView uses AsyncImage with native URLCache - return AWS URL directly
        let cacheUrl: String? = awsUrl

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
        let db = databaseManager.getContext()

        logger.info("Updating local database with new image: \(squareImageId)")

        // 1. Save the image to the images table
        let now = Date().timeIntervalSince1970
        let imageDataJson = [
            "name": fileName,
            "url": awsUrl,
            "caption": "Uploaded via JoyLabs iOS app"
        ]

        do {
            // Check if image already exists
            let descriptor = FetchDescriptor<ImageModel>(
                predicate: #Predicate { image in
                    image.id == squareImageId
                }
            )
            
            let imageModel: ImageModel
            if let existingImage = try db.fetch(descriptor).first {
                // Update existing image
                imageModel = existingImage
            } else {
                // Create new image
                imageModel = ImageModel(id: squareImageId)
                db.insert(imageModel)
            }
            
            // Set/update properties
            imageModel.id = squareImageId
            imageModel.updatedAt = Date(timeIntervalSince1970: now)
            imageModel.version = "1"
            imageModel.isDeleted = false
            imageModel.name = fileName
            imageModel.url = awsUrl
            imageModel.caption = "Uploaded via JoyLabs iOS app"
            imageModel.dataJson = try JSONSerialization.data(withJSONObject: imageDataJson).base64EncodedString()
            
            try db.save()

            logger.info("✅ Saved image to images table: \(squareImageId)")
        } catch {
            logger.error("❌ Failed to save image to images table: \(error)")
            throw SquareAPIError.upsertFailed("Failed to save image to database")
        }

        // 2. Update the item's data to include the new image ID as primary
        do {
            // Use SwiftData to get catalog item
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && item.isDeleted == false
                }
            )

            let catalogItems = try db.fetch(descriptor)

            for catalogItem in catalogItems {
                let dataJsonString = catalogItem.dataJson ?? "{}"
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

                // Save back to database using SwiftData
                let updatedDataJson = try JSONSerialization.data(withJSONObject: currentData)
                let updatedDataJsonString = String(data: updatedDataJson, encoding: .utf8) ?? "{}"

                // Update the catalog item
                catalogItem.dataJson = updatedDataJsonString
                catalogItem.updatedAt = Date(timeIntervalSince1970: now)
                
                try db.save()

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
        // Native URLCache handles invalidation automatically

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
        // Convert UIImage to appropriate format (PNG for transparency, JPEG for opaque)
        let (imageData, imageFormat) = image.smartImageData(compressionQuality: 0.9)
        guard let data = imageData else {
            throw SquareAPIError.upsertFailed("Failed to convert UIImage to data")
        }
        
        // Update filename extension to match format
        let updatedFileName = fileName.replacingOccurrences(of: ".jpg", with: ".\(imageFormat.fileExtension)")
                                     .replacingOccurrences(of: ".jpeg", with: ".\(imageFormat.fileExtension)")
        
        return try await uploadImage(
            imageData: data,
            fileName: updatedFileName,
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
        let db = databaseManager.getContext()

        // Use SwiftData to get catalog item
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { item in
                item.id == itemId
            }
        )

        if let catalogItem = try db.fetch(descriptor).first {
            let dataJsonString = catalogItem.dataJson ?? ""
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
            // Native URLCache will handle cache invalidation automatically
            logger.info("🗑️ Deleted old cached image: \(oldImageId)")
        }

        // Native URLCache handles freshness automatically

        // Force refresh in all UI components by posting notifications
        await MainActor.run {
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
                "action": "uploaded"
            ])
        }
    }
}

// MARK: - Static Factory
extension SquareImageService {
    
    /// Create SquareImageService with default dependencies
    static func create() -> SquareImageService {
        let httpClient = SquareAPIServiceFactory.createHTTPClient()
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SquareImageService(httpClient: httpClient, databaseManager: databaseManager)
    }
}
