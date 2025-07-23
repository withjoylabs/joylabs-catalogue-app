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

    // MARK: - Helper Components
    private let tableCreator = CatalogTableCreator()
    private let objectInserters = CatalogObjectInserters()
    
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
    private let taxCalculationPhase = Expression<String?>("calculation_phase")
    private let taxInclusionType = Expression<String?>("inclusion_type")
    private let taxPercentage = Expression<String?>("percentage")
    private let taxAppliesToCustomAmounts = Expression<Bool?>("applies_to_custom_amounts")
    private let taxEnabled = Expression<Bool?>("enabled")
    private let taxDataJson = Expression<String?>("data_json")

    private let modifiers = Table("modifiers")
    private let modifierId = Expression<String>("id")
    private let modifierUpdatedAt = Expression<String>("updated_at")
    private let modifierVersion = Expression<String>("version")
    private let modifierIsDeleted = Expression<Bool>("is_deleted")
    private let modifierName = Expression<String?>("name")
    private let modifierListId = Expression<String?>("modifier_list_id")
    private let modifierPriceAmount = Expression<Int64?>("price_amount")
    private let modifierPriceCurrency = Expression<String?>("price_currency")
    private let modifierOrdinal = Expression<Int64?>("ordinal")
    private let modifierOnByDefault = Expression<Bool?>("on_by_default")
    private let modifierDataJson = Expression<String?>("data_json")

    private let modifierLists = Table("modifier_lists")
    private let modifierListPrimaryId = Expression<String>("id")
    private let modifierListUpdatedAt = Expression<String>("updated_at")
    private let modifierListVersion = Expression<String>("version")
    private let modifierListIsDeleted = Expression<Bool>("is_deleted")
    private let modifierListName = Expression<String?>("name")
    private let modifierListSelectionType = Expression<String?>("selection_type")
    private let modifierListOrdinal = Expression<Int64?>("ordinal")
    private let modifierListDataJson = Expression<String?>("data_json")

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

        } catch {
            logger.error("Failed to connect to SQLiteSwift database: \(error)")
            throw error
        }
    }

    func getConnection() -> Connection? {
        return db
    }

    func getDatabasePath() -> String {
        return dbPath
    }



    func getItemCount() async throws -> Int {
        guard let db = db else {
            throw SQLiteSwiftError.noConnection
        }

        let countInt64 = try db.scalar(CatalogTableDefinitions.catalogItems.filter(Expression<Bool>("is_deleted") == false).count)
        return Int(countInt64)
    }

    /// Get the current version of an item from the database
    func getItemVersion(itemId: String) async throws -> Int64 {
        guard let db = db else {
            throw SQLiteSwiftError.noConnection
        }

        let query = CatalogTableDefinitions.catalogItems
            .select(CatalogTableDefinitions.itemVersion)
            .where(CatalogTableDefinitions.itemId == itemId)

        if let row = try db.pluck(query) {
            let versionString = row[CatalogTableDefinitions.itemVersion]
            let version = Int64(versionString) ?? 0
            return version
        } else {
            // Item not found, return 0 (will be treated as new item)
            return 0
        }
    }

    // MARK: - Item Fetching Methods

    /// Fetch a complete catalog item by ID with all related data
    func fetchItemById(_ itemId: String) throws -> CatalogObject? {
        guard let db = db else {
            throw SQLiteSwiftError.noConnection
        }

        logger.info("Fetching item by ID: \(itemId)")

        // Query the catalog_items table for the item
        let query = CatalogTableDefinitions.catalogItems
            .filter(CatalogTableDefinitions.itemId == itemId)
            .filter(CatalogTableDefinitions.itemIsDeleted == false)

        guard let row = try db.pluck(query) else {
            logger.warning("Item not found: \(itemId)")
            return nil
        }

        // Extract data from the row
        let dataJson = try row.get(CatalogTableDefinitions.itemDataJson)

        // Parse the stored JSON back to CatalogObject
        guard let jsonData = dataJson?.data(using: .utf8) else {
            logger.error("Failed to convert data_json to Data for item: \(itemId)")
            return nil
        }

        do {
            // CRITICAL DEBUG: Log the raw JSON to see what's actually stored
            logger.info("🔍 RAW JSON for item \(itemId): \(dataJson ?? "nil")")

            let decoder = JSONDecoder()
            // DON'T use convertFromSnakeCase - the JSON is already in snake_case format and our CodingKeys handle the mapping
            // decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalogObject = try decoder.decode(CatalogObject.self, from: jsonData)

            // CRITICAL DEBUG: Log the decoded item data structure
            if let itemData = catalogObject.itemData {
                logger.info("🔍 DECODED itemData - taxIds: \(itemData.taxIds ?? []), modifierListInfo: \(itemData.modifierListInfo?.count ?? 0)")
            }

            logger.info("Successfully fetched item: \(itemId)")
            return catalogObject

        } catch {
            logger.error("Failed to decode CatalogObject from JSON for item \(itemId): \(error)")
            return nil
        }
    }



    func disconnect() {
        db = nil
        logger.info("SQLiteSwift database disconnected")
    }
    
    // MARK: - Table Creation (matching React Native schema)

    func createTables() throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }

        // Create image URL mapping table first (only if not already created)
        let imageURLManager = ImageURLManager(databaseManager: self)
        try imageURLManager.createImageMappingTable()

        // Use table creator component
        try tableCreator.createTables(in: db)
    }

    func createTablesAsync() async throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }

        logger.info("Ensuring catalog database tables exist...")

        // Create image URL mapping table first (only if not already created)
        let imageURLManager = ImageURLManager(databaseManager: self)
        try imageURLManager.createImageMappingTable()

        // Use table creator component
        try tableCreator.createTables(in: db)

        logger.info("Catalog database tables verified/created successfully")
    }

    // MARK: - Data Operations
    
    func clearAllData() throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }

        logger.info("Clearing all catalog data and recreating tables with current schema...")

        try db.transaction {
            // Drop tables in reverse dependency order to avoid foreign key constraints
            try db.run("DROP TABLE IF EXISTS item_variations")
            try db.run("DROP TABLE IF EXISTS catalog_items")
            try db.run("DROP TABLE IF EXISTS categories")
            try db.run("DROP TABLE IF EXISTS taxes")
            try db.run("DROP TABLE IF EXISTS discounts")
            try db.run("DROP TABLE IF EXISTS images")
            try db.run("DROP TABLE IF EXISTS team_data")
            try db.run("DROP TABLE IF EXISTS sync_status")
            try db.run("DROP TABLE IF EXISTS image_url_mappings")

            logger.info("All tables dropped successfully")
        }

        // Recreate tables with current schema
        try tableCreator.createTables(in: db)
        logger.info("Tables recreated with current schema")

        // Create image URL mapping table
        let imageURLManager = ImageURLManager(databaseManager: self)
        try imageURLManager.createImageMappingTable()
        logger.info("Image mapping table recreated")
    }
    
    func insertCatalogObject(_ object: CatalogObject) throws {
        guard let db = db else { throw SQLiteSwiftError.noConnection }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        switch object.type {
        case "CATEGORY":
            // Use object inserters component
            try objectInserters.insertCategoryObject(object, timestamp: timestamp, in: db)
            
        case "ITEM":
            if let itemData = object.itemData {
                // Debug: Log what category data we have for this item
                logger.debug("🔍 Processing item \(object.id): reportingCategory=\(itemData.reportingCategory?.id ?? "nil"), categoryId=\(itemData.categoryId ?? "nil"), categories=\(itemData.categories?.map { $0.id } ?? [])")

                // Extract both category types during sync for fast retrieval
                let reportingCategoryName = extractReportingCategoryName(from: itemData, in: db)
                let primaryCategoryName = extractPrimaryCategoryName(from: itemData, in: db)

                // PERFORMANCE OPTIMIZATION: Extract tax and modifier names during sync for fast retrieval
                let taxNames = extractTaxNames(from: itemData, in: db)
                let modifierNames = extractModifierNames(from: itemData, in: db)

                // Debug: Log what names we resolved
                logger.debug("🔍 Item \(object.id) resolved names: reporting='\(reportingCategoryName ?? "nil")', primary='\(primaryCategoryName ?? "nil")', taxes='\(taxNames ?? "nil")', modifiers='\(modifierNames ?? "nil")'")

                // SAFE INSERT: Try with new columns first, fallback to old structure if needed
                do {
                    let insert = CatalogTableDefinitions.catalogItems.insert(or: .replace,
                        CatalogTableDefinitions.itemId <- object.id,
                        CatalogTableDefinitions.itemUpdatedAt <- timestamp,
                        CatalogTableDefinitions.itemVersion <- String(object.safeVersion),
                        CatalogTableDefinitions.itemIsDeleted <- object.safeIsDeleted,
                        CatalogTableDefinitions.itemCategoryId <- itemData.categoryId,
                        CatalogTableDefinitions.itemCategoryName <- primaryCategoryName,
                        CatalogTableDefinitions.itemReportingCategoryName <- reportingCategoryName,
                        CatalogTableDefinitions.itemTaxNames <- taxNames, // Pre-resolved tax names for performance
                        CatalogTableDefinitions.itemModifierNames <- modifierNames, // Pre-resolved modifier names for performance
                        CatalogTableDefinitions.itemName <- itemData.name,
                        CatalogTableDefinitions.itemDescription <- itemData.description,
                        CatalogTableDefinitions.itemDataJson <- encodeJSON(object)  // Store FULL CatalogObject, not just itemData
                    )
                    try db.run(insert)
                } catch {
                    // FALLBACK: If new columns don't exist, insert without them
                    logger.warning("Failed to insert with new columns, falling back to old structure: \(error)")
                    let fallbackInsert = CatalogTableDefinitions.catalogItems.insert(or: .replace,
                        CatalogTableDefinitions.itemId <- object.id,
                        CatalogTableDefinitions.itemUpdatedAt <- timestamp,
                        CatalogTableDefinitions.itemVersion <- String(object.safeVersion),
                        CatalogTableDefinitions.itemIsDeleted <- object.safeIsDeleted,
                        CatalogTableDefinitions.itemCategoryId <- itemData.categoryId,
                        CatalogTableDefinitions.itemCategoryName <- primaryCategoryName,
                        CatalogTableDefinitions.itemReportingCategoryName <- reportingCategoryName,
                        CatalogTableDefinitions.itemName <- itemData.name,
                        CatalogTableDefinitions.itemDescription <- itemData.description,
                        CatalogTableDefinitions.itemDataJson <- encodeJSON(object)  // Store FULL CatalogObject, not just itemData
                    )
                    try db.run(fallbackInsert)
                }
            }
            
        case "ITEM_VARIATION":
            if let variationData = object.itemVariationData {
                let insert = CatalogTableDefinitions.itemVariations.insert(or: .replace,
                    CatalogTableDefinitions.variationId <- object.id,
                    CatalogTableDefinitions.variationItemId <- variationData.itemId,
                    CatalogTableDefinitions.variationName <- variationData.name,
                    CatalogTableDefinitions.variationSku <- variationData.sku,
                    CatalogTableDefinitions.variationUpc <- variationData.upc,
                    CatalogTableDefinitions.variationOrdinal <- variationData.ordinal.map { Int64($0) },
                    CatalogTableDefinitions.variationPricingType <- variationData.pricingType,
                    CatalogTableDefinitions.variationPriceAmount <- variationData.priceMoney?.amount,
                    CatalogTableDefinitions.variationPriceCurrency <- variationData.priceMoney?.currency,
                    CatalogTableDefinitions.variationIsDeleted <- object.safeIsDeleted,
                    CatalogTableDefinitions.variationUpdatedAt <- timestamp,
                    CatalogTableDefinitions.variationVersion <- String(object.safeVersion),
                    CatalogTableDefinitions.variationDataJson <- encodeJSON(variationData)
                )
                try db.run(insert)
            }

        case "IMAGE":
            // Store Square catalog images with proper AWS URL and data
            if let imageData = object.imageData {
                let imageName = imageData.name ?? "Image \(object.id)"
                let imageUrl = imageData.url // Store the actual AWS URL
                let imageCaption = imageData.caption
                let imageDataJson = encodeJSON(imageData) // Store full image data

                let insert = CatalogTableDefinitions.images.insert(or: .replace,
                    CatalogTableDefinitions.imageId <- object.id,
                    CatalogTableDefinitions.imageName <- imageName,
                    CatalogTableDefinitions.imageUrl <- imageUrl,
                    CatalogTableDefinitions.imageCaption <- imageCaption,
                    CatalogTableDefinitions.imageIsDeleted <- object.safeIsDeleted,
                    CatalogTableDefinitions.imageUpdatedAt <- timestamp,
                    CatalogTableDefinitions.imageVersion <- String(object.safeVersion),
                    CatalogTableDefinitions.imageDataJson <- imageDataJson
                )
                try db.run(insert)

                logger.debug("✅ Stored IMAGE object: \(object.id) with URL: \(imageUrl ?? "nil")")
            } else {
                logger.warning("⚠️ IMAGE object \(object.id) missing imageData - skipping")
            }

        case "TAX":
            // Use object inserters component
            try objectInserters.insertTaxObject(object, timestamp: timestamp, in: db)

        case "DISCOUNT":
            // Store Square discounts - simplified approach
            let discountInsert = CatalogTableDefinitions.discounts.insert(or: .replace,
                CatalogTableDefinitions.discountId <- object.id,
                CatalogTableDefinitions.discountName <- "Discount \(object.id)",
                CatalogTableDefinitions.discountIsDeleted <- object.safeIsDeleted,
                CatalogTableDefinitions.discountUpdatedAt <- timestamp,
                CatalogTableDefinitions.discountVersion <- String(object.safeVersion),
                CatalogTableDefinitions.discountDataJson <- nil
            )
            try db.run(discountInsert)

        case "MODIFIER":
            // Use object inserters component
            try objectInserters.insertModifierObject(object, timestamp: timestamp, in: db)

        case "MODIFIER_LIST":
            // Use object inserters component
            try objectInserters.insertModifierListObject(object, timestamp: timestamp, in: db)

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

    // MARK: - Reporting Category Extraction (for fast search performance)

    /// Extract reporting category name during sync for fast retrieval
    private func extractReportingCategoryName(from itemData: ItemData, in db: Connection) -> String? {
        // Check if item has a reporting category
        guard let reportingCategory = itemData.reportingCategory else {
            return nil
        }

        logger.debug("🔍 Looking up reporting category ID: \(reportingCategory.id)")

        // Look up the reporting category name from the categories table
        do {
            let query = CatalogTableDefinitions.categories
                .select(CatalogTableDefinitions.categoryName)
                .filter(CatalogTableDefinitions.categoryId == reportingCategory.id)

            if let row = try db.pluck(query) {
                let categoryName = try row.get(CatalogTableDefinitions.categoryName)
                logger.debug("🔍 Found reporting category name: '\(categoryName ?? "nil")' for ID: \(reportingCategory.id)")
                return categoryName
            } else {
                logger.warning("🔍 No category found in database for reporting category ID: \(reportingCategory.id)")
            }
        } catch {
            logger.error("🔍 Failed to get reporting category name for \(reportingCategory.id): \(error)")
        }

        return nil
    }

    /// Extract primary category name from categories array during sync for fast retrieval
    private func extractPrimaryCategoryName(from itemData: ItemData, in db: Connection) -> String? {
        // Check if item has categories array
        guard let categories = itemData.categories, !categories.isEmpty else {
            // Fall back to legacy categoryId if no categories array
            if let categoryId = itemData.categoryId {
                logger.debug("🔍 Using legacy categoryId: \(categoryId)")
                return getCategoryNameById(categoryId: categoryId, in: db)
            }
            logger.debug("🔍 No categories array or legacy categoryId found")
            return nil
        }

        // Get the first category from the categories array (primary category)
        let primaryCategory = categories.first!
        logger.debug("🔍 Looking up primary category ID: \(primaryCategory.id) from categories array")
        return getCategoryNameById(categoryId: primaryCategory.id, in: db)
    }

    /// Helper method to get category name by ID
    private func getCategoryNameById(categoryId: String, in db: Connection) -> String? {
        do {
            let query = CatalogTableDefinitions.categories
                .select(CatalogTableDefinitions.categoryName)
                .filter(CatalogTableDefinitions.categoryId == categoryId)

            if let row = try db.pluck(query) {
                let categoryName = try row.get(CatalogTableDefinitions.categoryName)
                logger.debug("🔍 Found category name: '\(categoryName ?? "nil")' for ID: \(categoryId)")
                return categoryName
            } else {
                logger.warning("🔍 No category found in database for ID: \(categoryId)")
            }
        } catch {
            logger.error("🔍 Failed to get category name for \(categoryId): \(error)")
        }

        return nil
    }

    // MARK: - Tax and Modifier Name Extraction (for performance optimization)

    /// Extract tax names during sync for fast retrieval - returns comma-separated string
    private func extractTaxNames(from itemData: ItemData, in db: Connection) -> String? {
        guard let taxIds = itemData.taxIds, !taxIds.isEmpty else {
            return nil
        }

        logger.debug("🔍 Looking up tax names for IDs: \(taxIds)")

        var taxNames: [String] = []

        for taxId in taxIds {
            do {
                let query = CatalogTableDefinitions.taxes
                    .select(CatalogTableDefinitions.taxName)
                    .filter(CatalogTableDefinitions.taxId == taxId && CatalogTableDefinitions.taxIsDeleted == false)

                if let row = try db.pluck(query) {
                    if let taxName = try row.get(CatalogTableDefinitions.taxName) {
                        taxNames.append(taxName)
                        logger.debug("🔍 Found tax name: '\(taxName)' for ID: \(taxId)")
                    }
                } else {
                    logger.warning("🔍 No tax found in database for ID: \(taxId)")
                }
            } catch {
                logger.error("🔍 Failed to get tax name for \(taxId): \(error)")
            }
        }

        return taxNames.isEmpty ? nil : taxNames.joined(separator: ", ")
    }

    /// Extract modifier names during sync for fast retrieval - returns comma-separated string
    private func extractModifierNames(from itemData: ItemData, in db: Connection) -> String? {
        guard let modifierListInfo = itemData.modifierListInfo, !modifierListInfo.isEmpty else {
            return nil
        }

        logger.debug("🔍 Looking up modifier list names for \(modifierListInfo.count) modifier lists")

        var modifierNames: [String] = []

        for modifierInfo in modifierListInfo {
            guard let modifierListId = modifierInfo.modifierListId else { continue }

            do {
                let query = CatalogTableDefinitions.modifierLists
                    .select(CatalogTableDefinitions.modifierListName)
                    .filter(CatalogTableDefinitions.modifierListPrimaryId == modifierListId && CatalogTableDefinitions.modifierListIsDeleted == false)

                if let row = try db.pluck(query) {
                    if let modifierName = try row.get(CatalogTableDefinitions.modifierListName) {
                        modifierNames.append(modifierName)
                        logger.debug("🔍 Found modifier list name: '\(modifierName)' for ID: \(modifierListId)")
                    }
                } else {
                    logger.warning("🔍 No modifier list found in database for ID: \(modifierListId)")
                }
            } catch {
                logger.error("🔍 Failed to get modifier list name for \(modifierListId): \(error)")
            }
        }

        return modifierNames.isEmpty ? nil : modifierNames.joined(separator: ", ")
    }

}

// MARK: - Error Types

enum SQLiteSwiftError: Error {
    case noConnection
    case clearFailed(String)
    case insertFailed(String)
}
