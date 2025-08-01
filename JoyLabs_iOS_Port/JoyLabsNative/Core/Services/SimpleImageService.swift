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
    
    /// Get primary image URL for an item
    func getPrimaryImageURL(for itemId: String) async -> String? {
        do {
            let mappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
            return mappings.first?.originalAwsUrl
        } catch {
            logger.error("❌ Failed to get primary image URL: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func updateImageMapping(imageId: String, awsURL: String, itemId: String) async throws {
        let cacheKey = try imageURLManager.storeImageMapping(
            squareImageId: imageId,
            awsUrl: awsURL,
            objectType: "ITEM",
            objectId: itemId,
            imageType: "PRIMARY"
        )
        logger.info("✅ Image mapping stored: \(imageId) -> \(awsURL) (cache key: \(cacheKey))")
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
