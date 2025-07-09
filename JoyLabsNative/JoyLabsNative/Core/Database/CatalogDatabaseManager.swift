import Foundation
import SQLite3
import os.log

/// Database manager for catalog data with full Square API field coverage
/// Handles SQLite operations for 18,000+ item catalogs with optimized performance
class CatalogDatabaseManager {
    
    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String
    private var isTransactionActive = false
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogDatabase")
    
    // MARK: - Initialization
    
    init() {
        // Create database in Documents directory
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        dbPath = "\(documentsPath)/catalog.sqlite"
        
        print("Database path: \(dbPath)")
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Lifecycle
    
    func initializeDatabase() async throws {
        try openDatabase()
        try createTables()
        try createIndexes()
        try createSearchTables()
    }
    
    private func openDatabase() throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw DatabaseError.cannotOpenDatabase
        }

        // Configure SQLite for better performance and corruption resistance
        var statement: OpaquePointer?

        // Enable WAL mode for better concurrency and corruption resistance
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode = WAL;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Enable foreign keys
        if sqlite3_prepare_v2(db, "PRAGMA foreign_keys = ON;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Set synchronous mode to NORMAL for better performance while maintaining safety
        if sqlite3_prepare_v2(db, "PRAGMA synchronous = NORMAL;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Increase cache size for better performance
        if sqlite3_prepare_v2(db, "PRAGMA cache_size = 10000;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        // Set WAL mode for better performance
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode = WAL;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    private func createTables() throws {
        for tableSQL in CatalogDatabaseSchema.allTableCreationStatements {
            try executeSQL(tableSQL)
        }
    }
    
    private func createIndexes() throws {
        for indexSQL in CatalogDatabaseSchema.createIndexes {
            try executeSQL(indexSQL)
        }
    }
    
    private func createSearchTables() throws {
        try executeSQL(CatalogDatabaseSchema.createSearchTable)
        
        for triggerSQL in CatalogDatabaseSchema.createSearchTriggers {
            try executeSQL(triggerSQL)
        }
    }
    
    private func executeSQL(_ sql: String) throws {
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Transaction Management
    
    func beginTransaction() async throws {
        guard !isTransactionActive else { return }
        
        try executeSQL("BEGIN TRANSACTION;")
        isTransactionActive = true
    }
    
    func commitTransaction() async throws {
        guard isTransactionActive else { return }
        
        try executeSQL("COMMIT;")
        isTransactionActive = false
    }
    
    func rollbackTransaction() async throws {
        guard isTransactionActive else { return }
        
        try executeSQL("ROLLBACK;")
        isTransactionActive = false
    }
    
    // MARK: - Sync Session Management
    
    func startSyncSession(type: String) async throws -> Int {
        let sql = """
            INSERT INTO sync_metadata (sync_type, started_at, status)
            VALUES (?, ?, 'in_progress');
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            
            sqlite3_bind_text(statement, 1, type, -1, nil)
            sqlite3_bind_text(statement, 2, timestamp, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                let syncId = Int(sqlite3_last_insert_rowid(db))
                sqlite3_finalize(statement)
                return syncId
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }
    }
    
    func completeSyncSession(syncId: Int) async throws {
        let sql = """
            UPDATE sync_metadata 
            SET completed_at = ?, status = 'completed'
            WHERE id = ?;
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            
            sqlite3_bind_text(statement, 1, timestamp, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(syncId))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Database Recovery

    /// Recreate the database if it's corrupted
    func recreateDatabase() async throws {
        logger.info("Recreating corrupted database")

        // Close current connection
        if sqlite3_close(db) != SQLITE_OK {
            logger.warning("Failed to close corrupted database")
        }

        // Delete the corrupted database file
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dbPath) {
            try fileManager.removeItem(atPath: dbPath)
            logger.info("Deleted corrupted database file")
        }

        // Reinitialize with fresh database
        try await initializeDatabase()
        logger.info("Database recreated successfully")
    }

    /// Clear all catalog-related tables for fresh sync (matching React Native implementation)
    func clearCatalogData() async throws {
        logger.info("Clearing all catalog data...")

        do {
            try await beginTransaction()

            // Clear all catalog tables (only tables that exist in our schema)
            let clearStatements = [
                "DELETE FROM categories",
                "DELETE FROM catalog_items",
                "DELETE FROM item_variations",
                "DELETE FROM modifier_lists",
                "DELETE FROM modifiers",
                "DELETE FROM taxes",
                "DELETE FROM discounts",
                "DELETE FROM images",
                // Reset sync status related to catalog (using sync_metadata table)
                "UPDATE sync_metadata SET completed_at = NULL, last_cursor = NULL WHERE sync_type = 'catalog'"
            ]

            for statement in clearStatements {
                try executeSQL(statement)
            }

            try await commitTransaction()
            logger.info("Catalog data cleared successfully")
        } catch {
            if isTransactionActive {
                try? await rollbackTransaction()
            }
            throw error
        }
    }

    /// Get the last sync time (used for corruption detection)
    func getLastSyncTime() async throws -> Date? {
        // First perform a basic integrity check
        try await performIntegrityCheck()

        let sql = "SELECT MAX(completed_at) FROM sync_metadata WHERE status = 'completed';"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.preparationFailed(errorMessage)
        }

        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed(errorMessage)
        }

        if stepResult == SQLITE_ROW {
            if let timestampCString = sqlite3_column_text(statement, 0) {
                let timestampString = String(cString: timestampCString)
                return ISO8601DateFormatter().date(from: timestampString)
            }
        }

        return nil
    }

    /// Perform basic database integrity check
    private func performIntegrityCheck() async throws {
        let sql = "PRAGMA integrity_check(1);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.preparationFailed(errorMessage)
        }

        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw DatabaseError.executionFailed("Integrity check failed")
        }

        if let resultCString = sqlite3_column_text(statement, 0) {
            let result = String(cString: resultCString)
            if result != "ok" {
                throw DatabaseError.executionFailed("Database integrity check failed: \(result)")
            }
        }
    }

    // MARK: - Catalog Object Storage

    func storeCatalogObject(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        switch object.type {
        case "ITEM":
            try await storeCatalogItem(object)
        case "ITEM_VARIATION":
            try await storeItemVariation(object)
        case "CATEGORY":
            try await storeCategory(object)
        case "IMAGE":
            try await storeImage(object)
        case "TAX":
            try await storeTax(object)
        case "DISCOUNT":
            try await storeDiscount(object)
        case "MODIFIER_LIST":
            try await storeModifierList(object)
        case "MODIFIER":
            try await storeModifier(object)
        default:
            print("Unknown object type: \(object.type)")
        }
    }
    
    func deleteCatalogObject(_ objectId: String) async throws {
        // Mark object as deleted in all relevant tables
        let tables = ["catalog_items", "item_variations", "categories", "images", "taxes", "discounts", "modifier_lists", "modifiers"]
        
        for table in tables {
            let sql = "UPDATE \(table) SET is_deleted = 1 WHERE id = ?;"
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, objectId, -1, nil)
                sqlite3_step(statement)
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Individual Object Storage Methods
    
    private func storeCatalogItem(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let itemData = object.itemData else { return }
        
        let sql = """
            INSERT OR REPLACE INTO catalog_items (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, description, description_html, description_plaintext,
                abbreviation, label_color, is_taxable, category_id, tax_ids,
                product_type, skip_modifier_screen, image_ids, sort_name,
                categories, channels, is_archived, is_alcoholic,
                food_and_beverage_details, ecom_seo_data, reporting_category,
                modifier_list_info, item_options, custom_attributes,
                last_synced_at, sync_version, search_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            
            // Bind core fields
            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)
            
            // Bind item-specific fields
            bindOptionalText(statement, 10, itemData.name)
            bindOptionalText(statement, 11, itemData.description)
            bindOptionalText(statement, 12, itemData.descriptionHtml)
            bindOptionalText(statement, 13, itemData.descriptionPlaintext)
            bindOptionalText(statement, 14, itemData.abbreviation)
            bindOptionalText(statement, 15, itemData.labelColor)
            sqlite3_bind_int(statement, 16, (itemData.isTaxable ?? true) ? 1 : 0)
            bindOptionalText(statement, 17, itemData.categoryId)
            bindOptionalJSONArray(statement, 18, itemData.taxIds)
            bindOptionalText(statement, 19, itemData.productType)
            sqlite3_bind_int(statement, 20, (itemData.skipModifierScreen ?? false) ? 1 : 0)
            bindOptionalJSONArray(statement, 21, itemData.imageIds)
            bindOptionalText(statement, 22, itemData.sortName)
            bindOptionalJSON(statement, 23, itemData.categories)
            bindOptionalJSONArray(statement, 24, itemData.channels)
            sqlite3_bind_int(statement, 25, (itemData.isArchived ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 26, (itemData.isAlcoholic ?? false) ? 1 : 0)
            bindOptionalJSON(statement, 27, itemData.foodAndBeverageDetails)
            bindOptionalJSON(statement, 28, itemData.ecomSeoData)
            bindOptionalJSON(statement, 29, itemData.reportingCategory)
            bindOptionalJSON(statement, 30, itemData.modifierListInfo)
            bindOptionalJSON(statement, 31, itemData.itemOptions)
            bindOptionalJSON(statement, 32, object.customAttributeValues)
            sqlite3_bind_text(statement, 33, timestamp, -1, nil)
            sqlite3_bind_int(statement, 34, 1)
            
            // Create search text
            let searchText = createSearchText(name: itemData.name, description: itemData.description)
            bindOptionalText(statement, 35, searchText)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }
        
        sqlite3_finalize(statement)
    }

    private func storeItemVariation(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let variationData = object.itemVariationData else { return }

        let sql = """
            INSERT OR REPLACE INTO item_variations (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                item_id, name, sku, upc, ordinal, pricing_type,
                price_money_amount, price_money_currency, location_overrides,
                track_inventory, inventory_alert_type, inventory_alert_threshold,
                user_data, service_duration, available_for_booking,
                item_option_values, measurement_unit_id, sellable, stockable,
                image_ids, team_member_ids, stockable_conversion,
                custom_attributes, last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            // Bind core fields
            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)

            // Bind variation-specific fields
            bindOptionalText(statement, 10, variationData.itemId)
            bindOptionalText(statement, 11, variationData.name)
            bindOptionalText(statement, 12, variationData.sku)
            bindOptionalText(statement, 13, variationData.upc)
            bindOptionalInt(statement, 14, variationData.ordinal)
            bindOptionalText(statement, 15, variationData.pricingType)
            bindOptionalInt(statement, 16, variationData.priceMoney?.amount)
            bindOptionalText(statement, 17, variationData.priceMoney?.currency)
            bindOptionalJSON(statement, 18, variationData.locationOverrides)
            sqlite3_bind_int(statement, 19, (variationData.trackInventory ?? false) ? 1 : 0)
            bindOptionalText(statement, 20, variationData.inventoryAlertType)
            bindOptionalInt(statement, 21, variationData.inventoryAlertThreshold)
            bindOptionalText(statement, 22, variationData.userData)
            bindOptionalInt(statement, 23, variationData.serviceDuration)
            sqlite3_bind_int(statement, 24, (variationData.availableForBooking ?? false) ? 1 : 0)
            bindOptionalJSON(statement, 25, variationData.itemOptionValues)
            bindOptionalText(statement, 26, variationData.measurementUnitId)
            sqlite3_bind_int(statement, 27, (variationData.sellable ?? true) ? 1 : 0)
            sqlite3_bind_int(statement, 28, (variationData.stockable ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 29, variationData.imageIds)
            bindOptionalJSONArray(statement, 30, variationData.teamMemberIds)
            bindOptionalJSON(statement, 31, variationData.stockableConversion)
            bindOptionalJSON(statement, 32, object.customAttributeValues)
            sqlite3_bind_text(statement, 33, timestamp, -1, nil)
            sqlite3_bind_int(statement, 34, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeCategory(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let categoryData = object.categoryData else { return }

        let sql = """
            INSERT OR REPLACE INTO categories (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, image_ids, category_type, parent_category, is_top_level,
                channels, availability_period_ids, online_visibility, root_category,
                ecom_seo_data, path_to_root, custom_attributes,
                last_synced_at, sync_version, search_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            // Bind core fields
            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)

            // Bind category-specific fields
            bindOptionalText(statement, 10, categoryData.name)
            bindOptionalJSONArray(statement, 11, categoryData.imageIds)
            bindOptionalText(statement, 12, categoryData.categoryType)
            bindOptionalJSON(statement, 13, categoryData.parentCategory)
            sqlite3_bind_int(statement, 14, (categoryData.isTopLevel ?? false) ? 1 : 0)
            bindOptionalJSONArray(statement, 15, categoryData.channels)
            bindOptionalJSONArray(statement, 16, categoryData.availabilityPeriodIds)
            sqlite3_bind_int(statement, 17, (categoryData.onlineVisibility ?? true) ? 1 : 0)
            bindOptionalText(statement, 18, categoryData.rootCategory)
            bindOptionalJSON(statement, 19, categoryData.ecomSeoData)
            bindOptionalJSON(statement, 20, categoryData.pathToRoot)
            bindOptionalJSON(statement, 21, object.customAttributeValues)
            sqlite3_bind_text(statement, 22, timestamp, -1, nil)
            sqlite3_bind_int(statement, 23, 1)

            // Create search text
            let searchText = createSearchText(name: categoryData.name, description: nil)
            bindOptionalText(statement, 24, searchText)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeImage(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let imageData = object.imageData else { return }

        let sql = """
            INSERT OR REPLACE INTO images (
                id, type, updated_at, created_at, version, is_deleted,
                name, url, caption, photo_studio_order_id,
                custom_attributes, last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            bindOptionalText(statement, 7, imageData.name)
            bindOptionalText(statement, 8, imageData.url)
            bindOptionalText(statement, 9, imageData.caption)
            bindOptionalText(statement, 10, imageData.photoStudioOrderId)
            bindOptionalJSON(statement, 11, object.customAttributeValues)
            sqlite3_bind_text(statement, 12, timestamp, -1, nil)
            sqlite3_bind_int(statement, 13, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeTax(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let taxData = object.taxData else { return }

        let sql = """
            INSERT OR REPLACE INTO taxes (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, calculation_phase, inclusion_type, percentage,
                applies_to_custom_amounts, enabled, custom_attributes,
                last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)
            bindOptionalText(statement, 10, taxData.name)
            bindOptionalText(statement, 11, taxData.calculationPhase)
            bindOptionalText(statement, 12, taxData.inclusionType)
            bindOptionalText(statement, 13, taxData.percentage)
            sqlite3_bind_int(statement, 14, (taxData.appliesToCustomAmounts ?? true) ? 1 : 0)
            sqlite3_bind_int(statement, 15, (taxData.enabled ?? true) ? 1 : 0)
            bindOptionalJSON(statement, 16, object.customAttributeValues)
            sqlite3_bind_text(statement, 17, timestamp, -1, nil)
            sqlite3_bind_int(statement, 18, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeDiscount(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let discountData = object.discountData else { return }

        let sql = """
            INSERT OR REPLACE INTO discounts (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, discount_type, percentage, amount_money_amount, amount_money_currency,
                pin_required, label_color, modify_tax_basis,
                maximum_amount_money_amount, maximum_amount_money_currency,
                custom_attributes, last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)
            bindOptionalText(statement, 10, discountData.name)
            bindOptionalText(statement, 11, discountData.discountType)
            bindOptionalText(statement, 12, discountData.percentage)
            bindOptionalInt(statement, 13, discountData.amountMoney?.amount)
            bindOptionalText(statement, 14, discountData.amountMoney?.currency)
            sqlite3_bind_int(statement, 15, (discountData.pinRequired ?? false) ? 1 : 0)
            bindOptionalText(statement, 16, discountData.labelColor)
            bindOptionalText(statement, 17, discountData.modifyTaxBasis)
            bindOptionalInt(statement, 18, discountData.maximumAmountMoney?.amount)
            bindOptionalText(statement, 19, discountData.maximumAmountMoney?.currency)
            bindOptionalJSON(statement, 20, object.customAttributeValues)
            sqlite3_bind_text(statement, 21, timestamp, -1, nil)
            sqlite3_bind_int(statement, 22, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeModifierList(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let modifierListData = object.modifierListData else { return }

        let sql = """
            INSERT OR REPLACE INTO modifier_lists (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, ordinal, selection_type, modifiers, image_ids,
                custom_attributes, last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)
            bindOptionalText(statement, 10, modifierListData.name)
            bindOptionalInt(statement, 11, modifierListData.ordinal)
            bindOptionalText(statement, 12, modifierListData.selectionType)
            bindOptionalJSON(statement, 13, modifierListData.modifiers)
            bindOptionalJSONArray(statement, 14, modifierListData.imageIds)
            bindOptionalJSON(statement, 15, object.customAttributeValues)
            sqlite3_bind_text(statement, 16, timestamp, -1, nil)
            sqlite3_bind_int(statement, 17, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    private func storeModifier(_ object: SquareCatalogAPIClient.CatalogObject) async throws {
        guard let modifierData = object.modifierData else { return }

        let sql = """
            INSERT OR REPLACE INTO modifiers (
                id, type, updated_at, created_at, version, is_deleted,
                present_at_all_locations, present_at_location_ids, absent_at_location_ids,
                name, price_money_amount, price_money_currency, ordinal,
                modifier_list_id, location_overrides, image_ids,
                custom_attributes, last_synced_at, sync_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(statement, 1, object.id, -1, nil)
            sqlite3_bind_text(statement, 2, object.type, -1, nil)
            bindOptionalText(statement, 3, object.updatedAt)
            bindOptionalText(statement, 4, object.createdAt)
            bindOptionalInt64(statement, 5, object.version)
            sqlite3_bind_int(statement, 6, (object.isDeleted ?? false) ? 1 : 0)
            sqlite3_bind_int(statement, 7, (object.presentAtAllLocations ?? true) ? 1 : 0)
            bindOptionalJSONArray(statement, 8, object.presentAtLocationIds)
            bindOptionalJSONArray(statement, 9, object.absentAtLocationIds)
            bindOptionalText(statement, 10, modifierData.name)
            bindOptionalInt(statement, 11, modifierData.priceMoney?.amount)
            bindOptionalText(statement, 12, modifierData.priceMoney?.currency)
            bindOptionalInt(statement, 13, modifierData.ordinal)
            bindOptionalText(statement, 14, modifierData.modifierListId)
            bindOptionalJSON(statement, 15, modifierData.locationOverrides)
            bindOptionalJSONArray(statement, 16, modifierData.imageIds)
            bindOptionalJSON(statement, 17, object.customAttributeValues)
            sqlite3_bind_text(statement, 18, timestamp, -1, nil)
            sqlite3_bind_int(statement, 19, 1)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(statement)
                throw DatabaseError.executionFailed(errorMessage)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw DatabaseError.preparationFailed(errorMessage)
        }

        sqlite3_finalize(statement)
    }

    // MARK: - Helper Methods

    private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(statement, index, value, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalInt(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalInt64(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64?) {
        if let value = value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalJSON<T: Codable>(_ statement: OpaquePointer?, _ index: Int32, _ value: T?) {
        if let value = value {
            do {
                let jsonData = try JSONEncoder().encode(value)
                let jsonString = String(data: jsonData, encoding: .utf8)
                sqlite3_bind_text(statement, index, jsonString, -1, nil)
            } catch {
                sqlite3_bind_null(statement, index)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalJSONArray<T: Codable>(_ statement: OpaquePointer?, _ index: Int32, _ value: [T]?) {
        if let value = value {
            do {
                let jsonData = try JSONEncoder().encode(value)
                let jsonString = String(data: jsonData, encoding: .utf8)
                sqlite3_bind_text(statement, index, jsonString, -1, nil)
            } catch {
                sqlite3_bind_null(statement, index)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func createSearchText(name: String?, description: String?) -> String {
        var searchComponents: [String] = []

        if let name = name {
            searchComponents.append(name)
        }

        if let description = description {
            searchComponents.append(description)
        }

        return searchComponents.joined(separator: " ").lowercased()
    }
}


