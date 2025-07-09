import Foundation
import SQLite
import os.log

/// Modern SQLite.swift implementation for catalog database management
/// Replaces the broken raw SQLite3 implementation with proper type safety
class SQLiteSwiftCatalogManager {
    
    // MARK: - Properties
    
    private var db: Connection?
    private let dbPath: String
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SQLiteSwiftCatalog")
    
    // MARK: - Table Definitions (SQLite.swift style)
    
    // Categories table
    private let categories = Table("categories")
    private let categoryId = Expression<String>("id")
    private let categoryName = Expression<String?>("name")
    private let categoryImageUrl = Expression<String?>("image_url")
    private let categoryIsDeleted = Expression<Bool>("is_deleted")
    private let categoryUpdatedAt = Expression<String>("updated_at")
    private let categoryVersion = Expression<Int64>("version")
    
    // Catalog items table
    private let catalogItems = Table("catalog_items")
    private let itemId = Expression<String>("id")
    private let itemType = Expression<String>("type")
    private let itemUpdatedAt = Expression<String>("updated_at")
    private let itemVersion = Expression<Int64>("version")
    private let itemIsDeleted = Expression<Bool>("is_deleted")
    private let itemPresentAtAllLocations = Expression<Bool>("present_at_all_locations")
    private let itemCategoryId = Expression<String?>("category_id")
    private let itemName = Expression<String?>("name")
    private let itemDescription = Expression<String?>("description")
    private let itemLabelColor = Expression<String?>("label_color")
    private let itemAvailableOnline = Expression<Bool?>("available_online")
    private let itemAvailableForPickup = Expression<Bool?>("available_for_pickup")
    private let itemAvailableElectronically = Expression<Bool?>("available_electronically")
    
    // Item variations table
    private let itemVariations = Table("item_variations")
    private let variationId = Expression<String>("id")
    private let variationItemId = Expression<String>("item_id")
    private let variationName = Expression<String?>("name")
    private let variationSku = Expression<String?>("sku")
    private let variationUpc = Expression<String?>("upc")
    private let variationOrdinal = Expression<Int64?>("ordinal")
    private let variationPricingType = Expression<String?>("pricing_type")
    private let variationBasePriceMoney = Expression<String?>("base_price_money")
    private let variationDefaultUnitCost = Expression<String?>("default_unit_cost")
    private let variationMeasurementUnitId = Expression<String?>("measurement_unit_id")
    private let variationSellable = Expression<Bool?>("sellable")
    private let variationStockable = Expression<Bool?>("stockable")
    private let variationUpdatedAt = Expression<String>("updated_at")
    private let variationVersion = Expression<Int64>("version")
    
    // Sync metadata table
    private let syncMetadata = Table("sync_metadata")
    private let syncType = Expression<String>("sync_type")
    private let syncStartedAt = Expression<String?>("started_at")
    private let syncCompletedAt = Expression<String?>("completed_at")
    private let syncLastCursor = Expression<String?>("last_cursor")
    private let syncTotalItems = Expression<Int64?>("total_items")
    private let syncProcessedItems = Expression<Int64?>("processed_items")
    
    // MARK: - Initialization
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbPath = documentsPath.appendingPathComponent("catalog.sqlite").path
        logger.info("SQLiteSwift database path: \(dbPath)")
    }
    
    // MARK: - Database Connection
    
    func connect() throws {
        do {
            db = try Connection(dbPath)
            
            // Configure SQLite for optimal performance
            try db?.execute("PRAGMA journal_mode = WAL")
            try db?.execute("PRAGMA synchronous = NORMAL")
            try db?.execute("PRAGMA cache_size = 10000")
            try db?.execute("PRAGMA foreign_keys = ON")
            try db?.execute("PRAGMA busy_timeout = 30000")
            
            logger.info("SQLiteSwift database connected successfully")
            
            // Create tables if they don't exist
            try createTables()
            
        } catch {
            logger.error("Failed to connect to SQLiteSwift database: \(error)")
            throw error
        }
    }
    
    func disconnect() {
        db = nil
        logger.info("SQLiteSwift database disconnected")
    }
    
    // MARK: - Table Creation
    
    private func createTables() throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }
        
        // Create categories table
        try db.run(categories.create(ifNotExists: true) { t in
            t.column(categoryId, primaryKey: true)
            t.column(categoryName)
            t.column(categoryImageUrl)
            t.column(categoryIsDeleted, defaultValue: false)
            t.column(categoryUpdatedAt)
            t.column(categoryVersion, defaultValue: 1)
        })
        
        // Create catalog_items table
        try db.run(catalogItems.create(ifNotExists: true) { t in
            t.column(itemId, primaryKey: true)
            t.column(itemType)
            t.column(itemUpdatedAt)
            t.column(itemVersion, defaultValue: 1)
            t.column(itemIsDeleted, defaultValue: false)
            t.column(itemPresentAtAllLocations, defaultValue: true)
            t.column(itemCategoryId)
            t.column(itemName)
            t.column(itemDescription)
            t.column(itemLabelColor)
            t.column(itemAvailableOnline)
            t.column(itemAvailableForPickup)
            t.column(itemAvailableElectronically)
            
            // Foreign key constraint
            t.foreignKey(itemCategoryId, references: categories, categoryId, delete: .setNull)
        })
        
        // Create item_variations table
        try db.run(itemVariations.create(ifNotExists: true) { t in
            t.column(variationId, primaryKey: true)
            t.column(variationItemId)
            t.column(variationName)
            t.column(variationSku)
            t.column(variationUpc)
            t.column(variationOrdinal)
            t.column(variationPricingType)
            t.column(variationBasePriceMoney)
            t.column(variationDefaultUnitCost)
            t.column(variationMeasurementUnitId)
            t.column(variationSellable)
            t.column(variationStockable)
            t.column(variationUpdatedAt)
            t.column(variationVersion, defaultValue: 1)
            
            // Foreign key constraint
            t.foreignKey(variationItemId, references: catalogItems, itemId, delete: .cascade)
        })
        
        // Create sync_metadata table
        try db.run(syncMetadata.create(ifNotExists: true) { t in
            t.column(syncType, primaryKey: true)
            t.column(syncStartedAt)
            t.column(syncCompletedAt)
            t.column(syncLastCursor)
            t.column(syncTotalItems)
            t.column(syncProcessedItems)
        })
        
        logger.info("SQLiteSwift tables created successfully")
    }
    
    // MARK: - Data Operations
    
    func clearAllData() throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }
        
        logger.info("Clearing all catalog data using SQLiteSwift...")
        
        try db.transaction {
            // Clear in reverse dependency order
            try db.run(itemVariations.delete())
            try db.run(catalogItems.delete())
            try db.run(categories.delete())
            
            // Reset sync metadata
            try db.run(syncMetadata.delete())
        }
        
        // Verify clear operation
        let itemCount = try db.scalar(catalogItems.count)
        logger.info("Data cleared successfully. Remaining items: \(itemCount)")
        
        if itemCount > 0 {
            throw SQLiteSwiftError.clearFailed("Items still remain after clear operation")
        }
    }
    
    func insertCatalogObject(_ object: CatalogObject) throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        switch object.type {
        case "CATEGORY":
            if let categoryData = object.categoryData {
                let insert = categories.insert(or: .replace,
                    categoryId <- object.id,
                    categoryName <- categoryData.name,
                    categoryImageUrl <- categoryData.imageUrl,
                    categoryIsDeleted <- (object.isDeleted ?? false),
                    categoryUpdatedAt <- timestamp,
                    categoryVersion <- (object.version ?? 1)
                )
                try db.run(insert)
            }
            
        case "ITEM":
            if let itemData = object.itemData {
                let insert = catalogItems.insert(or: .replace,
                    itemId <- object.id,
                    itemType <- object.type,
                    itemUpdatedAt <- timestamp,
                    itemVersion <- (object.version ?? 1),
                    itemIsDeleted <- (object.isDeleted ?? false),
                    itemPresentAtAllLocations <- (object.presentAtAllLocations ?? true),
                    itemCategoryId <- itemData.categoryId,
                    itemName <- itemData.name,
                    itemDescription <- itemData.description,
                    itemLabelColor <- itemData.labelColor,
                    itemAvailableOnline <- itemData.availableOnline,
                    itemAvailableForPickup <- itemData.availableForPickup,
                    itemAvailableElectronically <- itemData.availableElectronically
                )
                try db.run(insert)
            }
            
        case "ITEM_VARIATION":
            if let variationData = object.itemVariationData {
                let insert = itemVariations.insert(or: .replace,
                    variationId <- object.id,
                    variationItemId <- variationData.itemId,
                    variationName <- variationData.name,
                    variationSku <- variationData.sku,
                    variationUpc <- variationData.upc,
                    variationOrdinal <- variationData.ordinal,
                    variationPricingType <- variationData.pricingType,
                    variationBasePriceMoney <- encodeJSON(variationData.basePriceMoney),
                    variationDefaultUnitCost <- encodeJSON(variationData.defaultUnitCost),
                    variationMeasurementUnitId <- variationData.measurementUnitId,
                    variationSellable <- variationData.sellable,
                    variationStockable <- variationData.stockable,
                    variationUpdatedAt <- timestamp,
                    variationVersion <- (object.version ?? 1)
                )
                try db.run(insert)
            }
            
        default:
            logger.warning("Unsupported catalog object type: \(object.type)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func encodeJSON<T: Codable>(_ object: T?) -> String? {
        guard let object = object else { return nil }
        do {
            let data = try JSONEncoder().encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            logger.error("Failed to encode JSON: \(error)")
            return nil
        }
    }
}

// MARK: - Error Types

enum SQLiteSwiftError: Error {
    case noConnection
    case clearFailed(String)
    case insertFailed(String)
}
