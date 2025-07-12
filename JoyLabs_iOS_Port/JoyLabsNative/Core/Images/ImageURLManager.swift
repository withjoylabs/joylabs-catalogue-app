import Foundation
import SQLite
import os.log

/// Manages mapping between Square AWS URLs and local cached image references
/// This ensures robust CRUD operations without URL confusion
class ImageURLManager {
    
    // MARK: - Dependencies
    
    private let databaseManager: SQLiteSwiftCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageURLManager")
    
    // MARK: - Database Tables
    
    private let imageUrlMappings = Table("image_url_mappings")
    private let id = Expression<String>("id")
    private let squareImageId = Expression<String>("square_image_id")
    private let originalAwsUrl = Expression<String>("original_aws_url")
    private let localCacheKey = Expression<String>("local_cache_key")
    private let objectType = Expression<String>("object_type") // ITEM, CATEGORY, etc.
    private let objectId = Expression<String>("object_id") // The Square object ID this image belongs to
    private let imageType = Expression<String>("image_type") // PRIMARY, THUMBNAIL, etc.
    private let createdAt = Expression<Date>("created_at")
    private let lastAccessedAt = Expression<Date>("last_accessed_at")
    private let isDeleted = Expression<Bool>("is_deleted")
    
    // MARK: - Initialization
    
    init(databaseManager: SQLiteSwiftCatalogManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Public Methods
    
    /// Create image URL mapping table
    func createImageMappingTable() throws {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        try db.run(imageUrlMappings.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(squareImageId, unique: true)
            t.column(originalAwsUrl)
            t.column(localCacheKey)
            t.column(objectType)
            t.column(objectId)
            t.column(imageType)
            t.column(createdAt)
            t.column(lastAccessedAt)
            t.column(isDeleted, defaultValue: false)
        })
        
        // Create indexes for efficient lookups
        try db.run("CREATE INDEX IF NOT EXISTS idx_image_object_id ON image_url_mappings(object_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_image_square_id ON image_url_mappings(square_image_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_image_cache_key ON image_url_mappings(local_cache_key)")
        
        logger.info("✅ Image URL mapping table created with indexes")
    }
    
    /// Store image URL mapping when processing Square catalog objects
    func storeImageMapping(
        squareImageId: String,
        awsUrl: String,
        objectType: String,
        objectId: String,
        imageType: String = "PRIMARY"
    ) throws -> String {
        
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        // Generate local cache key (safe filename)
        let cacheKey = generateCacheKey(from: awsUrl, squareImageId: squareImageId)
        let mappingId = UUID().uuidString
        let now = Date()
        
        // Insert or update mapping
        try db.run(imageUrlMappings.insert(or: .replace,
            self.id <- mappingId,
            self.squareImageId <- squareImageId,
            self.originalAwsUrl <- awsUrl,
            self.localCacheKey <- cacheKey,
            self.objectType <- objectType,
            self.objectId <- objectId,
            self.imageType <- imageType,
            self.createdAt <- now,
            self.lastAccessedAt <- now,
            self.isDeleted <- false
        ))
        
        logger.debug("📝 Stored image mapping: \(squareImageId) -> \(cacheKey)")
        return cacheKey
    }
    
    /// Get local cache key for Square image ID
    func getLocalCacheKey(for squareImageId: String) throws -> String? {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        let query = imageUrlMappings
            .select(localCacheKey)
            .where(self.squareImageId == squareImageId && isDeleted == false)
        
        if let row = try db.pluck(query) {
            // Update last accessed time
            try updateLastAccessedTime(squareImageId: squareImageId)
            return try row.get(localCacheKey)
        }
        
        return nil
    }
    
    /// Get original AWS URL for Square image ID
    func getOriginalAwsUrl(for squareImageId: String) throws -> String? {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        let query = imageUrlMappings
            .select(originalAwsUrl)
            .where(self.squareImageId == squareImageId && isDeleted == false)
        
        if let row = try db.pluck(query) {
            return try row.get(originalAwsUrl)
        }
        
        return nil
    }
    
    /// Get all image mappings for a specific object
    func getImageMappings(for objectId: String, objectType: String) throws -> [ImageMapping] {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        let query = imageUrlMappings
            .where(self.objectId == objectId && self.objectType == objectType && isDeleted == false)
            .order(imageType.asc, createdAt.asc)
        
        var mappings: [ImageMapping] = []
        
        for row in try db.prepare(query) {
            let mapping = ImageMapping(
                id: try row.get(id),
                squareImageId: try row.get(squareImageId),
                originalAwsUrl: try row.get(originalAwsUrl),
                localCacheKey: try row.get(localCacheKey),
                objectType: try row.get(self.objectType),
                objectId: try row.get(self.objectId),
                imageType: try row.get(imageType),
                createdAt: try row.get(createdAt),
                lastAccessedAt: try row.get(lastAccessedAt)
            )
            mappings.append(mapping)
        }
        
        return mappings
    }
    
    /// Mark image mappings as deleted (soft delete for CRUD operations)
    func markImageAsDeleted(squareImageId: String) throws {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        let query = imageUrlMappings.where(self.squareImageId == squareImageId)
        try db.run(query.update(isDeleted <- true))
        
        logger.debug("🗑️ Marked image as deleted: \(squareImageId)")
    }
    
    /// Clear all image mappings (for full sync)
    func clearAllImageMappings() throws {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        try db.run(imageUrlMappings.delete())
        logger.info("🧹 Cleared all image URL mappings")
    }
    
    /// Clean up orphaned image mappings
    func cleanupOrphanedMappings() throws {
        guard let db = databaseManager.getConnection() else {
            throw ImageURLError.databaseNotConnected
        }
        
        // Delete mappings where the parent object no longer exists
        let deleteQuery = """
        DELETE FROM image_url_mappings 
        WHERE object_type = 'ITEM' 
        AND object_id NOT IN (SELECT id FROM catalog_items WHERE is_deleted = 0)
        """
        
        try db.execute(deleteQuery)
        
        logger.info("🧹 Cleaned up orphaned image mappings")
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(from awsUrl: String, squareImageId: String) -> String {
        // Use Square image ID as primary key, fallback to URL hash
        let baseKey = squareImageId.isEmpty ? awsUrl.sha256 : squareImageId
        
        // Ensure safe filename
        let safeKey = baseKey.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        
        // Add file extension if we can detect it from URL
        if let url = URL(string: awsUrl), !url.pathExtension.isEmpty {
            return "\(safeKey).\(url.pathExtension)"
        }
        
        return safeKey
    }
    
    private func updateLastAccessedTime(squareImageId: String) throws {
        guard let db = databaseManager.getConnection() else { return }
        
        let query = imageUrlMappings.where(self.squareImageId == squareImageId)
        try db.run(query.update(lastAccessedAt <- Date()))
    }
}

// MARK: - Supporting Types

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
    
    /// Get the local cache URL for this mapping
    var localCacheUrl: String {
        return "cache://\(localCacheKey)"
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

// MARK: - String Extension for SHA256

extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { bytes in
            return bytes.bindMemory(to: UInt8.self)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
