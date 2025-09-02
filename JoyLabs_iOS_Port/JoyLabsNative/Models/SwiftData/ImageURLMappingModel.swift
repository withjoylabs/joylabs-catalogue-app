import Foundation
import SwiftData

/// SwiftData model for image URL mappings
/// Replaces SQLite.swift image_url_mappings table
@Model
final class ImageURLMappingModel {
    // Core identifiers  
    @Attribute(.unique) var id: String
    @Attribute(.unique) var squareImageId: String
    var originalAwsUrl: String
    var localCacheKey: String
    
    // Object association
    var objectType: String  // ITEM, CATEGORY, etc.
    var objectId: String    // The Square object ID this image belongs to
    var imageType: String   // PRIMARY, THUMBNAIL, etc.
    
    // Timestamps
    var createdAt: Date
    var lastAccessedAt: Date
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        squareImageId: String,
        originalAwsUrl: String,
        localCacheKey: String,
        objectType: String,
        objectId: String,
        imageType: String = "",
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.squareImageId = squareImageId
        self.originalAwsUrl = originalAwsUrl
        self.localCacheKey = localCacheKey
        self.objectType = objectType
        self.objectId = objectId
        self.imageType = imageType
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isDeleted = isDeleted
    }
    
    /// Update last accessed timestamp
    func updateLastAccessed() {
        self.lastAccessedAt = Date()
    }
    
    /// Mark as deleted
    func markAsDeleted() {
        self.isDeleted = true
    }
}

/// Result type for image URL operations
struct ImageURLMappingResult {
    let id: String
    let squareImageId: String
    let originalAwsUrl: String
    let localCacheKey: String
    let objectType: String
    let objectId: String
    let imageType: String
    let createdAt: Date
    let lastAccessedAt: Date
    let isDeleted: Bool
    
    init(from model: ImageURLMappingModel) {
        self.id = model.id
        self.squareImageId = model.squareImageId
        self.originalAwsUrl = model.originalAwsUrl
        self.localCacheKey = model.localCacheKey
        self.objectType = model.objectType
        self.objectId = model.objectId
        self.imageType = model.imageType
        self.createdAt = model.createdAt
        self.lastAccessedAt = model.lastAccessedAt
        self.isDeleted = model.isDeleted
    }
}