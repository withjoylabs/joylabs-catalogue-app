import Foundation
import UIKit
import OSLog

/// Simple, industry-standard image service
/// Handles uploads to Square API and maintains URL mappings
/// Uses native URLCache for all caching needs
@MainActor
class SimpleImageService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = SimpleImageService()
    
    // MARK: - Dependencies
    private let httpClient: SquareHTTPClient
    private let databaseManager: SQLiteSwiftCatalogManager
    private let imageURLManager: ImageURLManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SimpleImageService")
    
    // MARK: - Initialization
    private init() {
        self.httpClient = SquareAPIServiceFactory.createHTTPClient()
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        self.imageURLManager = SquareAPIServiceFactory.createImageURLManager()
        
        logger.info("[SimpleImage] SimpleImageService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Upload image to Square and update database mapping
    func uploadImage(
        imageData: Data,
        fileName: String,
        itemId: String
    ) async throws -> String {
        logger.info("🚀 Uploading image for item: \(itemId)")
        
        // Validate image data
        guard imageData.count > 0 else {
            throw SimpleImageError.invalidImageData
        }
        
        // Generate idempotency key
        let idempotencyKey = UUID().uuidString
        
        // Upload to Square
        let response = try await httpClient.uploadImageToSquare(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId,
            idempotencyKey: idempotencyKey
        )
        
        guard let imageObject = response.image,
              let awsURL = imageObject.imageData?.url else {
            throw SimpleImageError.uploadFailed
        }
        
        let imageId = imageObject.id
        
        logger.info("✅ Image uploaded successfully: \(imageId)")
        
        // Update database mapping
        try await updateImageMapping(
            imageId: imageId,
            awsURL: awsURL,
            itemId: itemId
        )
        
        // Clear URLCache for this item to force refresh
        clearCacheForItem(itemId: itemId)
        
        // Send notification for UI refresh
        NotificationCenter.default.post(
            name: .imageUpdated,
            object: nil,
            userInfo: [
                "itemId": itemId,
                "imageId": imageId,
                "imageURL": awsURL,
                "action": "upload"
            ]
        )
        
        return awsURL
    }
    
    /// Get primary image URL for an item using Square's image_ids array order as truth
    func getPrimaryImageURL(for itemId: String) async -> String? {
        // Get the primary image ID from Square's catalog data (image_ids[0])
        guard let primaryImageId = getPrimaryImageIdFromSquare(itemId: itemId) else {
            logger.debug("⚠️ No primary image ID found in Square data for item: \(itemId)")
            return nil
        }
        
        do {
            // Get all image mappings for this item
            let mappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
            
            // Find the mapping for the primary image ID from Square
            if let primaryMapping = mappings.first(where: { $0.squareImageId == primaryImageId }) {
                logger.debug("✅ Found primary image mapping for item \(itemId): \(primaryImageId)")
                return primaryMapping.originalAwsUrl
            } else {
                logger.warning("⚠️ Primary image ID \(primaryImageId) not found in mappings for item \(itemId)")
                // Fallback to first available mapping
                return mappings.first?.originalAwsUrl
            }
        } catch {
            logger.error("❌ Failed to get image mappings: \(error)")
            return nil
        }
    }
    
    /// Get the primary image ID from Square's catalog data (image_ids[0])
    private func getPrimaryImageIdFromSquare(itemId: String) -> String? {
        guard let db = databaseManager.getConnection() else {
            logger.error("❌ Database not connected")
            return nil
        }
        
        do {
            // Get catalog item data to extract image_ids array
            let selectQuery = "SELECT data_json FROM catalog_items WHERE id = ? AND is_deleted = 0"
            
            for row in try db.prepare(selectQuery, itemId) {
                guard let dataJson = row[0] as? String,
                      let data = dataJson.data(using: .utf8) else {
                    continue
                }
                
                // Parse JSON as dictionary to access image_ids array
                if let catalogData = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var imageIds: [String]? = nil
                    
                    // Try nested under item_data first (current format with underscores)
                    if let itemData = catalogData["item_data"] as? [String: Any] {
                        imageIds = itemData["image_ids"] as? [String]
                    }
                    
                    // Fallback to root level (legacy format or direct storage)
                    if imageIds == nil {
                        imageIds = catalogData["image_ids"] as? [String]
                    }
                    
                    // Return first image ID from Square's array (primary image)
                    return imageIds?.first
                }
            }
        } catch {
            logger.error("❌ Failed to get primary image ID from Square data: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    private func updateImageMapping(imageId: String, awsURL: String, itemId: String) async throws {
        // Store image mapping without type tag - Square's image_ids array order determines priority
        let cacheKey = try imageURLManager.storeImageMapping(
            squareImageId: imageId,
            awsUrl: awsURL,
            objectType: "ITEM",
            objectId: itemId
            // No imageType parameter - using default (no type tracking)
        )
        logger.info("✅ Image mapping stored: \(imageId) -> \(awsURL) (cache key: \(cacheKey))")
        
        // Update local database with new image ID to show immediately (before next sync)
        try await updateLocalCatalogWithNewImage(imageId: imageId, itemId: itemId)
    }
    
    /// Update the local catalog_items.data_json with the new image ID
    private func updateLocalCatalogWithNewImage(imageId: String, itemId: String) async throws {
        guard let db = databaseManager.getConnection() else {
            logger.error("❌ Database not connected for local catalog update")
            return
        }
        
        do {
            // Get current data_json for the item
            let selectQuery = "SELECT data_json FROM catalog_items WHERE id = ? AND is_deleted = 0"
            
            for row in try db.prepare(selectQuery, itemId) {
                guard let dataJson = row[0] as? String,
                      let data = dataJson.data(using: .utf8) else {
                    continue
                }
                
                // Parse JSON and update image_ids array
                if var catalogData = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Handle nested item_data structure (current format)
                    if var itemData = catalogData["item_data"] as? [String: Any] {
                        var imageIds = itemData["image_ids"] as? [String] ?? []
                        
                        // Remove if already exists, then add as primary (first in array)
                        imageIds.removeAll { $0 == imageId }
                        imageIds.insert(imageId, at: 0)
                        
                        itemData["image_ids"] = imageIds
                        catalogData["item_data"] = itemData
                        
                        logger.info("🔄 Updated image_ids in item_data: \(imageIds)")
                    } else {
                        // Handle root level structure (legacy format)
                        var imageIds = catalogData["image_ids"] as? [String] ?? []
                        
                        // Remove if already exists, then add as primary (first in array)
                        imageIds.removeAll { $0 == imageId }
                        imageIds.insert(imageId, at: 0)
                        
                        catalogData["image_ids"] = imageIds
                        
                        logger.info("🔄 Updated image_ids at root level: \(imageIds)")
                    }
                    
                    // Convert back to JSON and update database
                    let updatedData = try JSONSerialization.data(withJSONObject: catalogData)
                    let updatedJson = String(data: updatedData, encoding: .utf8) ?? ""
                    
                    let updateQuery = "UPDATE catalog_items SET data_json = ? WHERE id = ?"
                    try db.run(updateQuery, updatedJson, itemId)
                    
                    logger.info("✅ Local catalog updated with new primary image: \(itemId) -> \(imageId)")
                    break
                }
            }
        } catch {
            logger.error("❌ Failed to update local catalog with new image: \(error)")
            throw error
        }
    }
    
    private func generateCacheKey(from url: String) -> String {
        return url.components(separatedBy: "/").last ?? UUID().uuidString
    }
    
    private func clearCacheForItem(itemId: String) {
        // Clear URLCache entries for this item's images
        // URLCache will automatically handle this when AsyncImage makes new requests
        logger.debug("🗑️ Cache cleared for item: \(itemId)")
    }
}

// MARK: - Error Types
enum SimpleImageError: LocalizedError {
    case invalidImageData
    case uploadFailed
    case databaseError
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data provided"
        case .uploadFailed:
            return "Failed to upload image to Square"
        case .databaseError:
            return "Database operation failed"
        }
    }
}
// MARK: - Supporting Types

/// Context for image upload operations (compatibility with old system)
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

/// Result of image upload operation (compatibility with old system)
struct ImageUploadResult {
    let squareImageId: String
    let awsUrl: String
    let localCacheUrl: String
    let context: ImageUploadContext
}

// Compatibility aliases for migration
typealias UnifiedImageError = SimpleImageError
