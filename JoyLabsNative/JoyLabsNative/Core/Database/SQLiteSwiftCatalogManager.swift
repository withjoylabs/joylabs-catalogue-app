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
    
    // MARK: - Table Definitions (SQLite.swift style - matching React Native schema)

    // Categories table (matching React Native: id, updated_at, version, is_deleted, name, data_json)
    private let categories = Table("categories")
    private let categoryId = Expression<String>("id")
    private let categoryUpdatedAt = Expression<String>("updated_at")
    private let categoryVersion = Expression<String>("version") // Store as TEXT like React Native
    private let categoryIsDeleted = Expression<Bool>("is_deleted")
    private let categoryName = Expression<String?>("name")
    private let categoryImageUrl = Expression<String?>("image_url")
    private let categoryDataJson = Expression<String?>("data_json") // Store raw category_data JSON

    // Catalog items table (matching React Native schema)
    private let catalogItems = Table("catalog_items")
    private let itemId = Expression<String>("id")
    private let itemUpdatedAt = Expression<String>("updated_at")
    private let itemVersion = Expression<String>("version") // Store as TEXT like React Native
    private let itemIsDeleted = Expression<Bool>("is_deleted")
    private let itemPresentAtAllLocations = Expression<Bool?>("present_at_all_locations")
    private let itemName = Expression<String?>("name")
    private let itemDescription = Expression<String?>("description")
    private let itemCategoryId = Expression<String?>("category_id")
    private let itemType = Expression<String?>("type")
    private let itemLabelColor = Expression<String?>("label_color")
    private let itemAvailableOnline = Expression<Bool?>("available_online")
    private let itemAvailableForPickup = Expression<Bool?>("available_for_pickup")
    private let itemAvailableElectronically = Expression<Bool?>("available_electronically")
    private let itemDataJson = Expression<String?>("data_json") // Store raw item_data JSON
    
    // Item variations table (matching React Native schema)
    private let itemVariations = Table("item_variations")
    private let variationId = Expression<String>("id")
    private let variationUpdatedAt = Expression<String>("updated_at")
    private let variationVersion = Expression<String>("version") // Store as TEXT like React Native
    private let variationIsDeleted = Expression<Bool>("is_deleted")
    private let variationItemId = Expression<String>("item_id")
    private let variationName = Expression<String?>("name")
    private let variationSku = Expression<String?>("sku")
    private let variationUpc = Expression<String?>("upc")
    private let variationOrdinal = Expression<Int64?>("ordinal")
    private let variationPricingType = Expression<String?>("pricing_type")
    private let variationPriceMoneyAmount = Expression<Int64?>("price_money_amount")
    private let variationPriceMoneyCurrency = Expression<String?>("price_money_currency")
    private let variationBasePriceMoney = Expression<String?>("base_price_money")
    private let variationDefaultUnitCost = Expression<String?>("default_unit_cost")
    private let variationMeasurementUnitId = Expression<String?>("measurement_unit_id")
    private let variationSellable = Expression<Bool?>("sellable")
    private let variationStockable = Expression<Bool?>("stockable")
    private let variationDataJson = Expression<String?>("data_json") // Store raw variation_data JSON

    // Additional tables matching React Native schema
    private let taxes = Table("taxes")
    private let taxId = Expression<String>("id")
    private let taxUpdatedAt = Expression<String>("updated_at")
    private let taxVersion = Expression<String>("version")
    private let taxIsDeleted = Expression<Bool>("is_deleted")
    private let taxName = Expression<String?>("name")
    private let taxDataJson = Expression<String?>("data_json")

    private let discounts = Table("discounts")
    private let discountId = Expression<String>("id")
    private let discountUpdatedAt = Expression<String>("updated_at")
    private let discountVersion = Expression<String>("version")
    private let discountIsDeleted = Expression<Bool>("is_deleted")
    private let discountName = Expression<String?>("name")
    private let discountDataJson = Expression<String?>("data_json")

    private let images = Table("images")
    private let imageId = Expression<String>("id")
    private let imageUpdatedAt = Expression<String>("updated_at")
    private let imageVersion = Expression<String>("version")
    private let imageIsDeleted = Expression<Bool>("is_deleted")
    private let imageName = Expression<String?>("name")
    private let imageUrl = Expression<String?>("url")
    private let imageDataJson = Expression<String?>("data_json")

    // Team data table (matching React Native schema)
    private let teamData = Table("team_data")
    private let teamItemId = Expression<String>("item_id")
    private let teamCaseUpc = Expression<String?>("case_upc")
    private let teamCaseCost = Expression<Double?>("case_cost")
    private let teamCaseQuantity = Expression<Int64?>("case_quantity")
    private let teamVendor = Expression<String?>("vendor")
    private let teamDiscontinued = Expression<Bool>("discontinued")
    private let teamNotes = Expression<String?>("notes")
    private let teamCreatedAt = Expression<String>("created_at")
    private let teamUpdatedAt = Expression<String>("updated_at")
    private let teamOwner = Expression<String?>("owner")

    // Sync status table (matching React Native schema)
    private let syncStatus = Table("sync_status")
    private let syncId = Expression<Int>("id")
    private let syncLastSyncTime = Expression<String?>("last_sync_time")
    private let syncIsSyncing = Expression<Bool>("is_syncing")
    private let syncError = Expression<String?>("sync_error")
    private let syncProgress = Expression<Int>("sync_progress")
    private let syncTotal = Expression<Int>("sync_total")
    private let syncType = Expression<String?>("sync_type")
    private let syncLastPageCursor = Expression<String?>("last_page_cursor")
    private let syncLastSyncAttempt = Expression<String?>("last_sync_attempt")
    private let syncAttemptCount = Expression<Int>("sync_attempt_count")
    private let syncLastIncrementalSyncCursor = Expression<String?>("last_incremental_sync_cursor")
    
    // MARK: - Initialization
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbPath = documentsPath.appendingPathComponent("catalog.sqlite").path
        logger.info("SQLiteSwift database path: \(self.dbPath)")
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

    func getConnection() -> Connection? {
        return db
    }
    
    func disconnect() {
        db = nil
        logger.info("SQLiteSwift database disconnected")
    }
    
    // MARK: - Table Creation (matching React Native schema)

    func createTables() throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }

        // Create image URL mapping table first
        let imageURLManager = ImageURLManager(databaseManager: self)
        try imageURLManager.createImageMappingTable()

        // Create categories table (matching React Native schema)
        try db.run(categories.create(ifNotExists: true) { t in
            t.column(categoryId, primaryKey: true)
            t.column(categoryUpdatedAt)
            t.column(categoryVersion)
            t.column(categoryIsDeleted, defaultValue: false)
            t.column(categoryName)
            t.column(categoryImageUrl)
            t.column(categoryDataJson) // Store raw category_data JSON
        })

        // Create catalog_items table (matching React Native schema)
        try db.run(catalogItems.create(ifNotExists: true) { t in
            t.column(itemId, primaryKey: true)
            t.column(itemUpdatedAt)
            t.column(itemVersion)
            t.column(itemIsDeleted, defaultValue: false)
            t.column(itemPresentAtAllLocations, defaultValue: true)
            t.column(itemName)
            t.column(itemDescription)
            t.column(itemCategoryId)
            t.column(itemType)
            t.column(itemLabelColor)
            t.column(itemAvailableOnline)
            t.column(itemAvailableForPickup)
            t.column(itemAvailableElectronically)
            t.column(itemDataJson) // Store raw item_data JSON

            // Foreign key constraint
            t.foreignKey(itemCategoryId, references: categories, categoryId, delete: .setNull)
        })

        // Create item_variations table (matching React Native schema)
        try db.run(itemVariations.create(ifNotExists: true) { t in
            t.column(variationId, primaryKey: true)
            t.column(variationUpdatedAt)
            t.column(variationVersion)
            t.column(variationIsDeleted, defaultValue: false)
            t.column(variationItemId)
            t.column(variationName)
            t.column(variationSku)
            t.column(variationUpc)
            t.column(variationOrdinal)
            t.column(variationPricingType)
            t.column(variationPriceMoneyAmount)
            t.column(variationPriceMoneyCurrency, defaultValue: "USD")
            t.column(variationBasePriceMoney)
            t.column(variationDefaultUnitCost)
            t.column(variationMeasurementUnitId)
            t.column(variationSellable)
            t.column(variationStockable)
            t.column(variationDataJson) // Store raw variation_data JSON

            // Foreign key constraint
            t.foreignKey(variationItemId, references: catalogItems, itemId, delete: .cascade)
        })

        // Create taxes table
        try db.run(taxes.create(ifNotExists: true) { t in
            t.column(taxId, primaryKey: true)
            t.column(taxUpdatedAt)
            t.column(taxVersion)
            t.column(taxIsDeleted, defaultValue: false)
            t.column(taxName)
            t.column(taxDataJson)
        })

        // Create discounts table
        try db.run(discounts.create(ifNotExists: true) { t in
            t.column(discountId, primaryKey: true)
            t.column(discountUpdatedAt)
            t.column(discountVersion)
            t.column(discountIsDeleted, defaultValue: false)
            t.column(discountName)
            t.column(discountDataJson)
        })

        // Create images table
        try db.run(images.create(ifNotExists: true) { t in
            t.column(imageId, primaryKey: true)
            t.column(imageUpdatedAt)
            t.column(imageVersion)
            t.column(imageIsDeleted, defaultValue: false)
            t.column(imageName)
            t.column(imageUrl)
            t.column(imageDataJson)
        })

        // Create team_data table (matching React Native schema)
        try db.run(teamData.create(ifNotExists: true) { t in
            t.column(teamItemId, primaryKey: true)
            t.column(teamCaseUpc)
            t.column(teamCaseCost)
            t.column(teamCaseQuantity)
            t.column(teamVendor)
            t.column(teamDiscontinued, defaultValue: false)
            t.column(teamNotes)
            t.column(teamCreatedAt)
            t.column(teamUpdatedAt)
            t.column(teamOwner)
        })

        // Create sync_status table (matching React Native schema)
        try db.run(syncStatus.create(ifNotExists: true) { t in
            t.column(syncId, primaryKey: true)
            t.column(syncLastSyncTime)
            t.column(syncIsSyncing, defaultValue: false)
            t.column(syncError)
            t.column(syncProgress, defaultValue: 0)
            t.column(syncTotal, defaultValue: 0)
            t.column(syncType)
            t.column(syncLastPageCursor)
            t.column(syncLastSyncAttempt)
            t.column(syncAttemptCount, defaultValue: 0)
            t.column(syncLastIncrementalSyncCursor)
        })

        logger.info("SQLiteSwift tables created successfully (matching React Native schema)")
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
            try db.run(taxes.delete())
            try db.run(discounts.delete())
            try db.run(images.delete())

            // Reset sync status
            try db.run(syncStatus.delete())
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
            // Store Square categories with comprehensive data extraction
            try insertCategoryObject(object, timestamp: timestamp)
            
        case "ITEM":
            if let itemData = object.itemData {
                let insert = catalogItems.insert(or: .replace,
                    itemId <- object.id,
                    itemType <- object.type,
                    itemUpdatedAt <- timestamp,
                    itemVersion <- String(object.version ?? 1),
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
                    variationVersion <- String(object.version ?? 1)
                )
                try db.run(insert)
            }

        case "IMAGE":
            // Store Square catalog images - simplified approach
            let insert = images.insert(or: .replace,
                imageId <- object.id,
                imageName <- "Image \(object.id)",
                imageUrl <- nil, // Will be extracted from raw JSON later
                imageIsDeleted <- (object.isDeleted ?? false),
                imageUpdatedAt <- timestamp,
                imageVersion <- String(object.version ?? 1),
                imageDataJson <- nil // Store raw object JSON later if needed
            )
            try db.run(insert)

        case "TAX":
            // Store Square taxes with comprehensive data extraction
            try insertTaxObject(object, timestamp: timestamp)

        case "DISCOUNT":
            // Store Square discounts - simplified approach
            let discountInsert = discounts.insert(or: .replace,
                discountId <- object.id,
                discountName <- "Discount \(object.id)",
                discountIsDeleted <- (object.isDeleted ?? false),
                discountUpdatedAt <- timestamp,
                discountVersion <- String(object.version ?? 1),
                discountDataJson <- nil // Store raw object JSON later if needed
            )
            try db.run(discountInsert)

        case "MODIFIER":
            // Store Square modifiers with comprehensive data extraction
            try insertModifierObject(object, timestamp: timestamp)

        case "MODIFIER_LIST":
            // Store Square modifier lists with comprehensive data extraction
            try insertModifierListObject(object, timestamp: timestamp)

        default:
            logger.debug("Skipping unsupported catalog object type: \(object.type) (ID: \(object.id))")
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

    // MARK: - Categories/Taxes/Modifiers Conversion System

    /// Comprehensive category insertion with full Square API data extraction
    private func insertCategoryObject(_ object: CatalogObject, timestamp: String) throws {
        guard let categoryData = object.categoryData else {
            logger.warning("Category object \(object.id) missing categoryData - skipping")
            return
        }

        // Extract comprehensive category information
        let categoryName = categoryData.name ?? "Category \(object.id)"
        let imageUrl = categoryData.imageUrl

        // Encode full category data as JSON for future extensibility
        let categoryDataJson = try encodeJSON(categoryData)

        logger.debug("📁 Inserting category: \(categoryName) (ID: \(object.id))")

        let insert = categories.insert(or: .replace,
            categoryId <- object.id,
            categoryName <- categoryName,
            categoryImageUrl <- imageUrl,
            categoryIsDeleted <- (object.isDeleted ?? false),
            categoryUpdatedAt <- timestamp,
            categoryVersion <- String(object.version ?? 1),
            categoryDataJson <- categoryDataJson
        )
        try db.run(insert)

        logger.debug("✅ Category inserted successfully: \(categoryName)")
    }

    /// Comprehensive tax insertion with full Square API data extraction
    private func insertTaxObject(_ object: CatalogObject, timestamp: String) throws {
        guard let taxData = object.taxData else {
            logger.warning("Tax object \(object.id) missing taxData - skipping")
            return
        }

        // Extract comprehensive tax information
        let taxName = taxData.name ?? "Tax \(object.id)"
        let calculationPhase = taxData.calculationPhase
        let inclusionType = taxData.inclusionType
        let percentage = taxData.percentage
        let appliesToCustomAmounts = taxData.appliesToCustomAmounts ?? false
        let enabled = taxData.enabled ?? true

        // Encode full tax data as JSON for future extensibility
        let taxDataJson = try encodeJSON(taxData)

        logger.debug("💰 Inserting tax: \(taxName) (\(percentage ?? "0")%) (ID: \(object.id))")

        let insert = taxes.insert(or: .replace,
            taxId <- object.id,
            taxName <- taxName,
            taxCalculationPhase <- calculationPhase,
            taxInclusionType <- inclusionType,
            taxPercentage <- percentage,
            taxAppliesToCustomAmounts <- appliesToCustomAmounts,
            taxEnabled <- enabled,
            taxIsDeleted <- (object.isDeleted ?? false),
            taxUpdatedAt <- timestamp,
            taxVersion <- String(object.version ?? 1),
            taxDataJson <- taxDataJson
        )
        try db.run(insert)

        logger.debug("✅ Tax inserted successfully: \(taxName)")
    }

    /// Comprehensive modifier insertion with full Square API data extraction
    private func insertModifierObject(_ object: CatalogObject, timestamp: String) throws {
        guard let modifierData = object.modifierData else {
            logger.warning("Modifier object \(object.id) missing modifierData - skipping")
            return
        }

        // Extract comprehensive modifier information
        let modifierName = modifierData.name ?? "Modifier \(object.id)"
        let modifierListId = modifierData.modifierListId
        let priceMoney = modifierData.priceMoney
        let ordinal = modifierData.ordinal
        let onByDefault = modifierData.onByDefault ?? false

        // Encode full modifier data as JSON for future extensibility
        let modifierDataJson = try encodeJSON(modifierData)

        logger.debug("🔧 Inserting modifier: \(modifierName) (List: \(modifierListId ?? "none")) (ID: \(object.id))")

        let insert = modifiers.insert(or: .replace,
            modifierId <- object.id,
            modifierName <- modifierName,
            modifierListId <- modifierListId,
            modifierPriceAmount <- priceMoney?.amount,
            modifierPriceCurrency <- priceMoney?.currency,
            modifierOrdinal <- ordinal,
            modifierOnByDefault <- onByDefault,
            modifierIsDeleted <- (object.isDeleted ?? false),
            modifierUpdatedAt <- timestamp,
            modifierVersion <- String(object.version ?? 1),
            modifierDataJson <- modifierDataJson
        )
        try db.run(insert)

        logger.debug("✅ Modifier inserted successfully: \(modifierName)")
    }

    /// Comprehensive modifier list insertion with full Square API data extraction
    private func insertModifierListObject(_ object: CatalogObject, timestamp: String) throws {
        guard let modifierListData = object.modifierListData else {
            logger.warning("ModifierList object \(object.id) missing modifierListData - skipping")
            return
        }

        // Extract comprehensive modifier list information
        let modifierListName = modifierListData.name ?? "Modifier List \(object.id)"
        let selectionType = modifierListData.selectionType
        let ordinal = modifierListData.ordinal
        let modifierIds = modifierListData.modifiers?.map { $0.id } ?? []

        // Encode full modifier list data as JSON for future extensibility
        let modifierListDataJson = try encodeJSON(modifierListData)

        logger.debug("📋 Inserting modifier list: \(modifierListName) (\(modifierIds.count) modifiers) (ID: \(object.id))")

        let insert = modifierLists.insert(or: .replace,
            modifierListId <- object.id,
            modifierListName <- modifierListName,
            modifierListSelectionType <- selectionType,
            modifierListOrdinal <- ordinal,
            modifierListIsDeleted <- (object.isDeleted ?? false),
            modifierListUpdatedAt <- timestamp,
            modifierListVersion <- String(object.version ?? 1),
            modifierListDataJson <- modifierListDataJson
        )
        try db.run(insert)

        logger.debug("✅ Modifier list inserted successfully: \(modifierListName)")
    }
}

// MARK: - Error Types

enum SQLiteSwiftError: Error {
    case noConnection
    case clearFailed(String)
    case insertFailed(String)
}
