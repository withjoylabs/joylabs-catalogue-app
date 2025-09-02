import Foundation
import SwiftData
import CryptoKit
import os.log

/// SwiftData-based replacement for ImageURLManager
/// Manages mapping between Square AWS URLs and local cached image references
/// This ensures robust CRUD operations without URL confusion
class SwiftDataImageURLManager {
    
    // MARK: - Dependencies
    
    private let databaseManager: SwiftDataCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataImageURLManager")
    
    // MARK: - Initialization
    
    init(databaseManager: SwiftDataCatalogManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Public Methods
    
    /// Create image URL mapping table (SwiftData handles table creation automatically)
    @MainActor
    func createImageMappingTable() throws {
        // SwiftData automatically creates tables based on @Model classes
        // No explicit table creation needed, but we can verify the schema is loaded
        let db = databaseManager.getContext()
        
        // Test query to ensure model is properly registered
        let testDescriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { _ in false }
        )
        let _ = try db.fetch(testDescriptor)
        
        logger.info("✅ Image URL mapping schema verified (SwiftData auto-managed)")
    }
    
    /// Store image URL mapping when processing Square catalog objects
    @MainActor
    func storeImageMapping(
        squareImageId: String,
        awsUrl: String,
        objectType: String,
        objectId: String,
        imageType: String = "PRIMARY"
    ) throws -> String {
        
        let db = databaseManager.getContext()
        
        // Generate local cache key (safe filename)
        let cacheKey = generateCacheKey(from: awsUrl, squareImageId: squareImageId)
        let now = Date()
        
        // Check if mapping already exists
        let existingDescriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId
            }
        )
        
        if let existingMapping = try db.fetch(existingDescriptor).first {
            // Update existing mapping
            existingMapping.originalAwsUrl = awsUrl
            existingMapping.localCacheKey = cacheKey
            existingMapping.objectType = objectType
            existingMapping.objectId = objectId
            existingMapping.imageType = imageType
            existingMapping.lastAccessedAt = now
            existingMapping.isDeleted = false
        } else {
            // Insert new mapping
            let newMapping = ImageURLMappingModel(
                squareImageId: squareImageId,
                originalAwsUrl: awsUrl,
                localCacheKey: cacheKey,
                objectType: objectType,
                objectId: objectId,
                imageType: imageType,
                createdAt: now,
                lastAccessedAt: now
            )
            db.insert(newMapping)
        }
        
        try db.save()
        
        logger.debug("📝 Stored image mapping: \(squareImageId) -> \(cacheKey)")
        return cacheKey
    }
    
    /// Get local cache key for Square image ID
    @MainActor
    func getLocalCacheKey(for squareImageId: String) throws -> String? {
        let db = databaseManager.getContext()
        
        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId && !mapping.isDeleted
            }
        )
        
        if let mapping = try db.fetch(descriptor).first {
            // Update last accessed time
            try updateLastAccessedTime(squareImageId: squareImageId)
            return mapping.localCacheKey
        }
        
        return nil
    }
    
    /// Get original AWS URL for Square image ID
    @MainActor
    func getOriginalAwsUrl(for squareImageId: String) throws -> String? {
        let db = databaseManager.getContext()
        
        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId && !mapping.isDeleted
            }
        )
        
        if let mapping = try db.fetch(descriptor).first {
            return mapping.originalAwsUrl
        }
        
        return nil
    }
    
    /// Get all image mappings for a specific object
    @MainActor
    func getImageMappings(for objectId: String, objectType: String) throws -> [ImageMapping] {
        let db = databaseManager.getContext()
        
        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.objectId == objectId && mapping.objectType == objectType && !mapping.isDeleted
            },
            sortBy: [
                SortDescriptor(\.imageType, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        
        let mappingModels = try db.fetch(descriptor)
        
        return mappingModels.map { model in
            ImageMapping(
                id: model.id,
                squareImageId: model.squareImageId,
                originalAwsUrl: model.originalAwsUrl,
                localCacheKey: model.localCacheKey,
                objectType: model.objectType,
                objectId: model.objectId,
                imageType: model.imageType,
                createdAt: model.createdAt,
                lastAccessedAt: model.lastAccessedAt
            )
        }
    }
    
    /// Mark image mappings as deleted (soft delete for CRUD operations)
    @MainActor
    func markImageAsDeleted(squareImageId: String) throws {
        let db = databaseManager.getContext()
        
        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId
            }
        )
        
        let mappings = try db.fetch(descriptor)
        for mapping in mappings {
            mapping.markAsDeleted()
        }
        
        try db.save()
        logger.debug("🗑️ Marked image as deleted: \(squareImageId)")
    }
    
    /// Clear all image mappings (for full sync)
    @MainActor
    func clearAllImageMappings() throws {
        let db = databaseManager.getContext()
        
        // Delete all ImageURLMappingModel instances
        try db.delete(model: ImageURLMappingModel.self)
        try db.save()
        
        logger.info("🧹 Cleared all image URL mappings")
    }
    
    /// Clean up orphaned image mappings
    @MainActor
    func cleanupOrphanedMappings() throws {
        let db = databaseManager.getContext()
        
        // Get all image mappings for items
        let imageMappingDescriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.objectType == "ITEM"
            }
        )
        
        let imageMappings = try db.fetch(imageMappingDescriptor)
        
        // Get all valid catalog items
        let catalogItemDescriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { item in
                !item.isDeleted
            }
        )
        
        let validItems = try db.fetch(catalogItemDescriptor)
        let validItemIds = Set(validItems.map { $0.id })
        
        // Delete orphaned mappings
        var deletedCount = 0
        for mapping in imageMappings {
            if !validItemIds.contains(mapping.objectId) {
                db.delete(mapping)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            try db.save()
        }
        
        logger.info("🧹 Cleaned up \(deletedCount) orphaned image mappings")
    }

    /// Remove image mapping for a specific image ID
    @MainActor
    func removeImageMapping(imageId: String) async {
        do {
            let db = databaseManager.getContext()
            
            let descriptor = FetchDescriptor<ImageURLMappingModel>(
                predicate: #Predicate { mapping in
                    mapping.squareImageId == imageId
                }
            )
            
            let mappings = try db.fetch(descriptor)
            for mapping in mappings {
                db.delete(mapping)
            }
            
            if !mappings.isEmpty {
                try db.save()
                logger.info("🗑️ Removed image mapping for: \(imageId)")
            }
        } catch {
            logger.error("❌ Failed to remove image mapping for \(imageId): \(error)")
        }
    }

    // MARK: - Private Methods
    
    private func generateCacheKey(from awsUrl: String, squareImageId: String) -> String {
        // Always use Square image ID as primary key for consistency
        let baseKey: String
        if !squareImageId.isEmpty {
            baseKey = squareImageId
        } else {
            // Fallback: create meaningful key from URL
            let urlHash = awsUrl.sha256.prefix(12)
            if let url = URL(string: awsUrl) {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2 {
                    let meaningfulPart = pathComponents.suffix(2).joined(separator: "_")
                    baseKey = "\(meaningfulPart)_\(urlHash)"
                } else {
                    baseKey = "img_\(urlHash)"
                }
            } else {
                baseKey = "img_\(urlHash)"
            }
        }

        // Ensure safe filename
        let safeKey = baseKey.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)

        // Add file extension if we can detect it from URL
        if let url = URL(string: awsUrl), !url.pathExtension.isEmpty {
            return "\(safeKey).\(url.pathExtension)"
        }

        return "\(safeKey).jpg" // Default extension
    }
    
    @MainActor
    private func updateLastAccessedTime(squareImageId: String) throws {
        let db = databaseManager.getContext()

        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId
            }
        )
        
        if let mapping = try db.fetch(descriptor).first {
            mapping.updateLastAccessed()
            try db.save()
        }
    }

    // MARK: - Webhook Support Methods

    /// Invalidate image mappings for a specific object (for webhook processing)
    @MainActor
    func invalidateImagesForObject(objectId: String, objectType: String) throws {
        let db = databaseManager.getContext()

        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.objectId == objectId && mapping.objectType == objectType
            }
        )
        
        let mappings = try db.fetch(descriptor)
        for mapping in mappings {
            mapping.markAsDeleted()
        }
        
        if !mappings.isEmpty {
            try db.save()
        }

        logger.info("🔄 Invalidated images for \(objectType) object: \(objectId)")
    }

    /// Invalidate a specific image by Square image ID (for webhook processing)
    @MainActor
    func invalidateImageById(squareImageId: String) throws {
        let db = databaseManager.getContext()

        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.squareImageId == squareImageId
            }
        )
        
        let mappings = try db.fetch(descriptor)
        for mapping in mappings {
            mapping.markAsDeleted()
        }
        
        if !mappings.isEmpty {
            try db.save()
        }

        logger.info("🔄 Invalidated image: \(squareImageId)")
    }

    /// Get all cache keys that need cleanup (marked as deleted)
    @MainActor
    func getStaleImageCacheKeys() throws -> [String] {
        let db = databaseManager.getContext()

        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.isDeleted
            }
        )

        let staleMappings = try db.fetch(descriptor)
        return staleMappings.map { $0.localCacheKey }
    }

    /// Remove stale image mappings from database (cleanup after cache files are deleted)
    @MainActor
    func cleanupStaleImageMappings() throws {
        let db = databaseManager.getContext()

        let descriptor = FetchDescriptor<ImageURLMappingModel>(
            predicate: #Predicate { mapping in
                mapping.isDeleted
            }
        )
        
        let staleMappings = try db.fetch(descriptor)
        let deletedCount = staleMappings.count
        
        for mapping in staleMappings {
            db.delete(mapping)
        }
        
        if deletedCount > 0 {
            try db.save()
        }
        
        logger.info("🧹 Cleaned up \(deletedCount) stale image mappings")
    }
}

// MARK: - String Extension for SHA256 (needed for generateCacheKey)
extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Supporting Types (keep existing ImageMapping and ImageURLError)

struct ImageMapping {
    let id: String
    let squareImageId: String
    let originalAwsUrl: String
    let localCacheKey: String
    let objectType: String
    let objectId: String
    let imageType: String
    let createdAt: Date
    let lastAccessedAt: Date
    
    /// Get the AWS URL for AsyncImage (URLCache handles caching automatically)
    var displayUrl: String {
        return originalAwsUrl
    }
    
    /// Check if this is the primary image
    var isPrimary: Bool {
        return imageType.uppercased() == "PRIMARY"
    }
}

enum ImageURLError: Error, LocalizedError {
    case databaseNotConnected
    case invalidUrl
    case mappingNotFound
    
    var errorDescription: String? {
        switch self {
        case .databaseNotConnected:
            return "Database connection not available"
        case .invalidUrl:
            return "Invalid image URL provided"
        case .mappingNotFound:
            return "Image mapping not found"
        }
    }
}