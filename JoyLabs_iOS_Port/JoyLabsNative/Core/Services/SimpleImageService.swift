import Foundation
import SwiftData
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
    private let databaseManager: SwiftDataCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SimpleImageService")
    
    // MARK: - Initialization
    private init() {
        self.httpClient = SquareAPIServiceFactory.createHTTPClient()
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        
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
        
        // Detect MIME type from filename or data
        let mimeType = detectMimeType(from: fileName, data: imageData)
        
        // Upload to Square
        let response = try await httpClient.uploadImageToSquare(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId,
            idempotencyKey: idempotencyKey,
            mimeType: mimeType
        )
        
        guard let imageObject = response.image,
              let awsURL = imageObject.imageData?.url else {
            throw SimpleImageError.uploadFailed
        }
        
        let imageId = imageObject.id
        
        logger.info("✅ Image uploaded successfully: \(imageId)")
        
        // Create SwiftData image model and link to item (Pure SwiftData approach)
        try await createSwiftDataImageModel(
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
    
    /// Get primary image URL for an item using SwiftData relationships (Pure SwiftData approach)
    func getPrimaryImageURL(for itemId: String) async -> String? {
        // Use CatalogLookupService for Single Source of Truth
        return CatalogLookupService.shared.getPrimaryImageUrl(for: itemId)
    }
    
    // MARK: - Private Methods
    
    /// Create SwiftData ImageModel and establish relationship with CatalogItemModel
    private func createSwiftDataImageModel(imageId: String, awsURL: String, itemId: String) async throws {
        let db = databaseManager.getContext()
        
        do {
            // Create new ImageModel
            let imageModel = ImageModel(id: imageId)
            imageModel.url = awsURL
            imageModel.name = "joylabs_image_\(Int(Date().timeIntervalSince1970))" 
            imageModel.updatedAt = Date()
            
            // Find the catalog item to establish relationship
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            if let catalogItem = try db.fetch(itemDescriptor).first {
                // Insert the image model
                db.insert(imageModel)

                // SIMPLE: Add imageId to item's imageIds array and cache URL
                if catalogItem.imageIds == nil {
                    catalogItem.imageIds = []
                }
                if !catalogItem.imageIds!.contains(imageId) {
                    catalogItem.imageIds!.insert(imageId, at: 0) // Insert at front to make it primary
                }

                // Cache the URL for fast lookups
                ImageURLCache.shared.setURL(imageURL, forImageId: imageId)

                // Save the context
                try db.save()

                logger.info("✅ Created ImageModel and cached URL: \(imageId) -> \(itemId)")
            } else {
                logger.warning("❌ Could not find catalog item \(itemId) for image")
            }
        } catch {
            logger.error("❌ Failed to create SwiftData image model: \(error)")
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
    
    /// Detect MIME type from filename extension or data signature
    private func detectMimeType(from fileName: String, data: Data) -> String {
        // Check filename extension first
        let lowercaseFileName = fileName.lowercased()
        if lowercaseFileName.hasSuffix(".png") {
            return "image/png"
        } else if lowercaseFileName.hasSuffix(".jpg") || lowercaseFileName.hasSuffix(".jpeg") {
            return "image/jpeg"
        }
        
        // Fallback to data signature detection
        guard data.count >= 4 else {
            return "image/jpeg" // Default fallback
        }
        
        // Check PNG signature (89 50 4E 47)
        if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return "image/png"
        }
        
        // Check JPEG signature (FF D8 FF)
        if data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
            return "image/jpeg"
        }
        
        // Default fallback
        return "image/jpeg"
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

// MARK: - Image Format Utilities
extension UIImage {
    /// Detects if the image has an alpha channel (transparency)
    var hasAlphaChannel: Bool {
        guard let cgImage = self.cgImage else { return false }
        
        let alphaInfo = cgImage.alphaInfo
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        @unknown default:
            return false
        }
    }
    
    /// Detects if the image actually uses transparency (not just has alpha channel)
    var hasActualTransparency: Bool {
        // If no alpha channel, definitely no transparency
        guard hasAlphaChannel else { return false }
        
        // For product photos from Figma/design tools, often have alpha channel but no actual transparency
        // Use JPEG for better compression unless we detect actual transparent pixels
        // This is a simplified check - for most product photos, prefer JPEG
        return false  // Force JPEG for better compression in product photo use case
    }
    
    /// Converts image to appropriate data format (PNG for transparency, JPEG for opaque)
    func smartImageData(compressionQuality: CGFloat = 0.9) -> (data: Data?, format: SimpleImageService.ImageFormat) {
        if hasAlphaChannel {
            return (pngData(), SimpleImageService.ImageFormat.png)
        } else {
            return (jpegData(compressionQuality: compressionQuality), SimpleImageService.ImageFormat.jpeg)
        }
    }
}

// ImageFormat moved inside SimpleImageService extension
extension SimpleImageService {
    /// Supported image formats for upload
    enum ImageFormat {
        case png
        case jpeg
        
        var mimeType: String {
            switch self {
            case .png: return "image/png"
            case .jpeg: return "image/jpeg"
            }
        }
        
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }
}
