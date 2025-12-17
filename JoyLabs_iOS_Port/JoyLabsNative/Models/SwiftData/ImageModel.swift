import Foundation
import SwiftData

// MARK: - SwiftData Model for Images
// Replaces SQLite.swift images table with native SwiftData persistence
@Model
final class ImageModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Image fields
    var name: String?
    var url: String?  // The AWS URL for the image
    var caption: String?
    var photoStudioOrderId: String?
    
    // Store complete image data as JSON for complex operations
    var dataJson: String?

    // NOTE: No relationships needed - ImageURLCache provides imageId->URL lookups

    // Computed properties
    var hasValidUrl: Bool {
        return url != nil && !url!.isEmpty
    }
    
    var isSquareHosted: Bool {
        guard let url = url else { return false }
        return url.contains("square.site") || url.contains("squarecdn.com")
    }
    
    init(
        id: String,
        updatedAt: Date = Date(),
        version: String = "0",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.version = version
        self.isDeleted = isDeleted
    }
    
    // Update from Square API CatalogObject
    func updateFromCatalogObject(_ object: CatalogObject) {
        self.updatedAt = Date()
        self.version = String(object.version ?? 0)
        self.isDeleted = object.isDeleted ?? false
        
        if let imageData = object.imageData {
            self.name = imageData.name
            self.url = imageData.url
            self.caption = imageData.caption
            self.photoStudioOrderId = imageData.photoStudioOrderId
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(imageData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to ImageData when needed
    func toImageData() -> ImageData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(ImageData.self, from: jsonData)
    }
    
    // Convert to CatalogImage for UI display
    func toCatalogImage() -> CatalogImage {
        return CatalogImage(
            id: id,
            type: "IMAGE",
            updatedAt: ISO8601DateFormatter().string(from: updatedAt),
            version: Int64(version) ?? 0,
            isDeleted: isDeleted,
            presentAtAllLocations: true,
            imageData: ImageData(
                name: name,
                url: url,
                caption: caption,
                photoStudioOrderId: photoStudioOrderId
            )
        )
    }
}