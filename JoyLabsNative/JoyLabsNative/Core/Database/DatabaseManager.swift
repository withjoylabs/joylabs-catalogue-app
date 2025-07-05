import Foundation
import SQLite
import Combine

/// DatabaseManager - Handles SQLite database operations
/// Ports the sophisticated database schema and operations from React Native
@MainActor
class DatabaseManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isInitialized: Bool = false
    @Published var syncStatus: SyncStatus = .idle
    
    // MARK: - Private Properties
    private var db: Connection?
    private let databaseVersion = 5 // Port from React Native DATABASE_VERSION
    
    // Database file path
    private var databasePath: String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return "\(documentsPath)/joylabs.db"
    }
    
    // MARK: - Initialization
    func initialize() async throws {
        Logger.info("Database", "Initializing SQLite database")
        
        do {
            // Open database connection
            db = try Connection(databasePath)
            
            // Enable foreign keys
            try db?.run("PRAGMA foreign_keys = ON")
            
            // Check if schema needs initialization or migration
            if try await needsSchemaUpdate() {
                try await initializeSchema()
            }
            
            isInitialized = true
            Logger.info("Database", "Database initialized successfully")
            
        } catch {
            Logger.error("Database", "Failed to initialize database: \(error)")
            throw DatabaseError.initializationFailed(error)
        }
    }
    
    // MARK: - Schema Management
    private func needsSchemaUpdate() async throws -> Bool {
        guard let db = db else { return true }
        
        // Check if db_version table exists
        let versionTableExists = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='db_version'"
        ) as! Int64 > 0
        
        if !versionTableExists {
            return true
        }
        
        // Check current version
        let currentVersion = try db.scalar("SELECT version FROM db_version WHERE id = 1") as? Int64 ?? 0
        
        return currentVersion < databaseVersion
    }
    
    private func initializeSchema() async throws {
        guard let db = db else { throw DatabaseError.noConnection }
        
        Logger.info("Database", "Initializing database schema")
        
        try db.transaction {
            // Create sync_status table (port from React Native)
            try db.run("""
                CREATE TABLE IF NOT EXISTS sync_status (
                    id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
                    last_sync_time TEXT,
                    is_syncing INTEGER NOT NULL DEFAULT 0,
                    sync_error TEXT,
                    sync_progress INTEGER NOT NULL DEFAULT 0,
                    sync_total INTEGER NOT NULL DEFAULT 0,
                    sync_type TEXT,
                    last_page_cursor TEXT,
                    last_sync_attempt TEXT,
                    sync_attempt_count INTEGER NOT NULL DEFAULT 0,
                    last_incremental_sync_cursor TEXT
                )
            """)
            
            // Insert default sync status
            try db.run("INSERT OR IGNORE INTO sync_status (id) VALUES (1)")
            
            // Create team_data table (port from React Native)
            try db.run("""
                CREATE TABLE IF NOT EXISTS team_data (
                    item_id TEXT PRIMARY KEY NOT NULL,
                    case_upc TEXT,
                    case_cost REAL,
                    case_quantity INTEGER,
                    vendor TEXT,
                    discontinued INTEGER DEFAULT 0,
                    notes TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    last_sync_at TEXT,
                    owner TEXT
                )
            """)
            
            // Create indexes for team_data
            try db.run("CREATE INDEX IF NOT EXISTS idx_team_data_case_upc ON team_data(case_upc)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_team_data_item_id ON team_data(item_id)")
            
            // Create catalog_items table (port from React Native)
            try db.run("""
                CREATE TABLE IF NOT EXISTS catalog_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    updated_at TEXT NOT NULL,
                    version TEXT NOT NULL,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    present_at_all_locations INTEGER DEFAULT 1,
                    name TEXT,
                    description TEXT,
                    category_id TEXT,
                    data_json TEXT
                )
            """)
            
            // Create categories table
            try db.run("""
                CREATE TABLE IF NOT EXISTS categories (
                    id TEXT PRIMARY KEY NOT NULL,
                    updated_at TEXT NOT NULL,
                    version TEXT NOT NULL,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    name TEXT,
                    data_json TEXT
                )
            """)
            
            // Create item_variations table
            try db.run("""
                CREATE TABLE IF NOT EXISTS item_variations (
                    id TEXT PRIMARY KEY NOT NULL,
                    updated_at TEXT NOT NULL,
                    version TEXT NOT NULL,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    item_id TEXT NOT NULL,
                    name TEXT,
                    sku TEXT,
                    pricing_type TEXT,
                    price_amount INTEGER,
                    price_currency TEXT,
                    data_json TEXT,
                    FOREIGN KEY (item_id) REFERENCES catalog_items (id)
                )
            """)
            
            // Create performance indexes (port from React Native)
            try db.run("CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items(name)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_catalog_items_category_id ON catalog_items(category_id)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_catalog_items_updated_at ON catalog_items(updated_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_item_variations_item_id ON item_variations(item_id)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_item_variations_sku ON item_variations(sku)")
            
            // Create other tables (modifiers, taxes, discounts, etc.)
            try createAdditionalTables()
            
            // Update database version
            try db.run("""
                CREATE TABLE IF NOT EXISTS db_version (
                    id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
                    version INTEGER NOT NULL,
                    updated_at TEXT
                )
            """)
            
            try db.run("""
                INSERT OR REPLACE INTO db_version (id, version, updated_at) 
                VALUES (1, ?, ?)
            """, databaseVersion, ISO8601DateFormatter().string(from: Date()))
        }
        
        Logger.info("Database", "Schema initialization completed")
    }
    
    private func createAdditionalTables() throws {
        guard let db = db else { return }
        
        // Create modifiers table
        try db.run("""
            CREATE TABLE IF NOT EXISTS modifiers (
                id TEXT PRIMARY KEY NOT NULL,
                updated_at TEXT NOT NULL,
                version TEXT NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                name TEXT,
                price_amount INTEGER,
                price_currency TEXT,
                ordinal INTEGER,
                modifier_list_id TEXT,
                data_json TEXT
            )
        """)
        
        // Create modifier_lists table
        try db.run("""
            CREATE TABLE IF NOT EXISTS modifier_lists (
                id TEXT PRIMARY KEY NOT NULL,
                updated_at TEXT NOT NULL,
                version TEXT NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                name TEXT,
                ordinal INTEGER,
                selection_type TEXT,
                data_json TEXT
            )
        """)
        
        // Create taxes table
        try db.run("""
            CREATE TABLE IF NOT EXISTS taxes (
                id TEXT PRIMARY KEY NOT NULL,
                updated_at TEXT NOT NULL,
                version TEXT NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                name TEXT,
                calculation_phase TEXT,
                inclusion_type TEXT,
                percentage TEXT,
                applies_to_custom_amounts INTEGER,
                enabled INTEGER,
                data_json TEXT
            )
        """)
        
        // Create discounts table
        try db.run("""
            CREATE TABLE IF NOT EXISTS discounts (
                id TEXT PRIMARY KEY NOT NULL,
                updated_at TEXT NOT NULL,
                version TEXT NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                name TEXT,
                discount_type TEXT,
                percentage TEXT,
                amount INTEGER,
                currency TEXT,
                pin_required INTEGER,
                label_color TEXT,
                modify_tax_basis TEXT,
                data_json TEXT
            )
        """)
        
        // Create merchant_info table
        try db.run("""
            CREATE TABLE IF NOT EXISTS merchant_info (
                id TEXT PRIMARY KEY NOT NULL,
                business_name TEXT,
                country TEXT,
                language_code TEXT,
                currency TEXT,
                status TEXT,
                main_location_id TEXT,
                created_at TEXT,
                last_updated TEXT,
                logo_url TEXT,
                data TEXT
            )
        """)
        
        // Create locations table
        try db.run("""
            CREATE TABLE IF NOT EXISTS locations (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT,
                merchant_id TEXT,
                address TEXT,
                timezone TEXT,
                phone_number TEXT,
                business_name TEXT,
                business_email TEXT,
                website_url TEXT,
                description TEXT,
                status TEXT,
                type TEXT,
                logo_url TEXT,
                created_at TEXT,
                last_updated TEXT,
                data TEXT,
                is_deleted INTEGER NOT NULL DEFAULT 0
            )
        """)
    }
    
    // MARK: - Public Methods
    func getDatabase() async throws -> Connection {
        guard let db = db else {
            throw DatabaseError.noConnection
        }
        return db
    }

    // MARK: - Catalog Operations (port from React Native)

    /// Upsert catalog objects (exact port from React Native upsertCatalogObjects)
    func upsertCatalogObjects(_ objects: [CatalogObject]) async throws {
        guard let db = db else { throw DatabaseError.noConnection }

        Logger.debug("Database", "Upserting \(objects.count) catalog objects")

        try db.transaction {
            for object in objects {
                try upsertCatalogObject(object, db: db)
            }
        }

        Logger.debug("Database", "Successfully upserted \(objects.count) objects")
    }

    /// Search local items (exact port from React Native searchLocalItems)
    func searchLocalItems(searchTerm: String, filters: SearchFilters) async throws -> [RawSearchResult] {
        guard let db = db else { throw DatabaseError.noConnection }

        var queryParts: [String] = []
        var params: [String] = []
        let searchTermLike = "%\(searchTerm)%"

        // Name search
        if filters.name {
            queryParts.append("""
                SELECT id, data_json, 'name' as match_type, name as match_context
                FROM catalog_items
                WHERE name LIKE ? AND is_deleted = 0
            """)
            params.append(searchTermLike)
        }

        // SKU search
        if filters.sku {
            queryParts.append("""
                SELECT iv.item_id as id, ci.data_json, 'sku' as match_type,
                       json_extract(iv.data_json, '$.item_variation_data.sku') as match_context
                FROM item_variations iv
                JOIN catalog_items ci ON iv.item_id = ci.id
                WHERE json_extract(iv.data_json, '$.item_variation_data.sku') LIKE ?
                  AND iv.is_deleted = 0 AND ci.is_deleted = 0
            """)
            params.append(searchTermLike)
        }

        // Barcode/UPC search
        if filters.barcode {
            queryParts.append("""
                SELECT iv.item_id as id, ci.data_json, 'barcode' as match_type,
                       json_extract(iv.data_json, '$.item_variation_data.upc') as match_context
                FROM item_variations iv
                JOIN catalog_items ci ON iv.item_id = ci.id
                WHERE json_extract(iv.data_json, '$.item_variation_data.upc') LIKE ?
                  AND iv.is_deleted = 0 AND ci.is_deleted = 0
            """)
            params.append(searchTermLike)
        }

        // Category search
        if filters.category {
            queryParts.append("""
                SELECT ci.id, ci.data_json, 'category' as match_type, c.name as match_context
                FROM catalog_items ci
                JOIN categories c ON ci.category_id = c.id
                WHERE c.name LIKE ? AND ci.is_deleted = 0 AND c.is_deleted = 0
            """)
            params.append(searchTermLike)
        }

        guard !queryParts.isEmpty else {
            return []
        }

        // Combine queries with UNION
        let finalQuery = queryParts.joined(separator: " UNION ")

        // Execute query with parameters
        var paramIndex = 0
        let statement = try db.prepare(finalQuery)

        // Bind parameters
        for param in params {
            try statement.bind(param, at: paramIndex + 1)
            paramIndex += 1
        }

        let results = try statement.map { row in
            RawSearchResult(
                id: row[0] as! String,
                dataJson: row[1] as! String,
                matchType: row[2] as! String,
                matchContext: row[3] as? String
            )
        }

        Logger.debug("Database", "Local search returned \(results.count) results")
        return results
    }

    /// Get all categories (port from React Native getAllCategories)
    func getAllCategories() async throws -> [CategoryRow] {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            SELECT id, updated_at, version, is_deleted, name, data_json
            FROM categories
            WHERE is_deleted = 0
            ORDER BY name ASC
        """

        let results = try db.prepare(query).map { row in
            CategoryRow(
                id: row[0] as! String,
                updatedAt: row[1] as! String,
                version: row[2] as! String,
                isDeleted: row[3] as! Int,
                name: row[4] as? String,
                dataJson: row[5] as! String
            )
        }

        Logger.debug("Database", "Retrieved \(results.count) categories")
        return results
    }

    /// Get catalog item by ID (port from React Native getCatalogItem)
    func getCatalogItem(id: String) async throws -> CatalogItemRow? {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            SELECT id, updated_at, version, is_deleted, present_at_all_locations, name, description, category_id, data_json
            FROM catalog_items
            WHERE id = ? AND is_deleted = 0
        """

        let results = try db.prepare(query).bind(id).map { row in
            CatalogItemRow(
                id: row[0] as! String,
                updatedAt: row[1] as! String,
                version: row[2] as! String,
                isDeleted: row[3] as! Int,
                presentAtAllLocations: row[4] as? Int,
                name: row[5] as? String,
                description: row[6] as? String,
                categoryId: row[7] as? String,
                dataJson: row[8] as! String
            )
        }

        return results.first
    }

    /// Get item variations for item (port from React Native getItemVariations)
    func getItemVariations(itemId: String) async throws -> [ItemVariationRow] {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            SELECT id, updated_at, version, is_deleted, item_id, name, sku, pricing_type, price_amount, price_currency, data_json
            FROM item_variations
            WHERE item_id = ? AND is_deleted = 0
            ORDER BY name ASC
        """

        let results = try db.prepare(query).bind(itemId).map { row in
            ItemVariationRow(
                id: row[0] as! String,
                updatedAt: row[1] as! String,
                version: row[2] as! String,
                isDeleted: row[3] as! Int,
                itemId: row[4] as! String,
                name: row[5] as? String,
                sku: row[6] as? String,
                pricingType: row[7] as? String,
                priceAmount: row[8] as? Int64,
                priceCurrency: row[9] as? String,
                dataJson: row[10] as! String
            )
        }

        Logger.debug("Database", "Retrieved \(results.count) variations for item \(itemId)")
        return results
    }

    // MARK: - Sync Operations

    /// Get last sync cursor (port from React Native getLastSyncCursor)
    func getLastSyncCursor() async -> String? {
        guard let db = db else { return nil }

        do {
            let query = "SELECT last_incremental_sync_cursor FROM sync_status WHERE id = 1"
            let result = try db.scalar(query) as? String
            return result
        } catch {
            Logger.error("Database", "Failed to get last sync cursor: \(error)")
            return nil
        }
    }

    /// Save last sync cursor (port from React Native saveLastSyncCursor)
    func saveLastSyncCursor(_ cursor: String) async throws {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            UPDATE sync_status
            SET last_incremental_sync_cursor = ?, last_sync_time = ?
            WHERE id = 1
        """

        let timestamp = ISO8601DateFormatter().string(from: Date())
        try db.run(query, cursor, timestamp)

        Logger.debug("Database", "Saved sync cursor: \(cursor)")
    }

    /// Update sync status (port from React Native updateSyncStatus)
    func updateSyncStatus(isSync: Bool, progress: Int = 0, total: Int = 0, error: String? = nil) async throws {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            UPDATE sync_status
            SET is_syncing = ?, sync_progress = ?, sync_total = ?, sync_error = ?, last_sync_attempt = ?
            WHERE id = 1
        """

        let timestamp = ISO8601DateFormatter().string(from: Date())
        try db.run(query, isSync ? 1 : 0, progress, total, error, timestamp)
    }

    // MARK: - Team Data Operations

    /// Upsert team data (port from React Native team data operations)
    func upsertTeamData(_ itemId: String, _ data: CaseUpcData) async throws {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            INSERT OR REPLACE INTO team_data
            (item_id, case_upc, case_cost, case_quantity, vendor, discontinued, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        let notesJson = try? JSONEncoder().encode(data.notes)
        let notesString = notesJson.flatMap { String(data: $0, encoding: .utf8) }
        let timestamp = ISO8601DateFormatter().string(from: Date())

        try db.run(query,
                  itemId,
                  data.caseUpc,
                  data.caseCost,
                  data.caseQuantity,
                  data.vendor,
                  data.discontinued == true ? 1 : 0,
                  notesString,
                  timestamp)

        Logger.debug("Database", "Upserted team data for item: \(itemId)")
    }

    /// Get team data for item (port from React Native getTeamData)
    func getTeamData(itemId: String) async throws -> CaseUpcData? {
        guard let db = db else { throw DatabaseError.noConnection }

        let query = """
            SELECT case_upc, case_cost, case_quantity, vendor, discontinued, notes
            FROM team_data
            WHERE item_id = ?
        """

        let results = try db.prepare(query).bind(itemId).map { row -> CaseUpcData? in
            let notesString = row[5] as? String
            let notes = notesString?.data(using: .utf8).flatMap {
                try? JSONDecoder().decode([TeamNote].self, from: $0)
            }

            return CaseUpcData(
                caseUpc: row[0] as? String,
                caseCost: row[1] as? Double,
                caseQuantity: row[2] as? Int,
                vendor: row[3] as? String,
                discontinued: (row[4] as? Int) == 1,
                notes: notes
            )
        }

        return results.compactMap { $0 }.first
    }

    // MARK: - Private Helper Methods

    private func upsertCatalogObject(_ object: CatalogObject, db: Connection) throws {
        switch object.type {
        case "ITEM":
            try upsertItem(object, db: db)
        case "CATEGORY":
            try upsertCategory(object, db: db)
        case "ITEM_VARIATION":
            try upsertItemVariation(object, db: db)
        case "MODIFIER":
            try upsertModifier(object, db: db)
        case "MODIFIER_LIST":
            try upsertModifierList(object, db: db)
        case "TAX":
            try upsertTax(object, db: db)
        case "DISCOUNT":
            try upsertDiscount(object, db: db)
        default:
            Logger.debug("Database", "Skipping unsupported object type: \(object.type)")
        }
    }

    private func upsertItem(_ object: CatalogObject, db: Connection) throws {
        let itemData = object.itemData
        let dataJson = try JSONSerialization.data(withJSONObject: object.toDictionary())

        let query = """
            INSERT OR REPLACE INTO catalog_items
            (id, updated_at, version, is_deleted, present_at_all_locations, name, description, category_id, data_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        try db.run(query,
                  object.id,
                  object.updatedAt,
                  String(object.version),
                  object.isDeleted ? 1 : 0,
                  object.presentAtAllLocations == true ? 1 : 0,
                  itemData?.name,
                  itemData?.description,
                  itemData?.categoryId,
                  dataJson)
    }

    private func upsertCategory(_ object: CatalogObject, db: Connection) throws {
        let categoryData = object.categoryData
        let dataJson = try JSONSerialization.data(withJSONObject: object.toDictionary())

        let query = """
            INSERT OR REPLACE INTO categories
            (id, updated_at, version, is_deleted, name, data_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """

        try db.run(query,
                  object.id,
                  object.updatedAt,
                  String(object.version),
                  object.isDeleted ? 1 : 0,
                  categoryData?.name,
                  dataJson)
    }

    private func upsertItemVariation(_ object: CatalogObject, db: Connection) throws {
        let variationData = object.itemVariationData
        let dataJson = try JSONSerialization.data(withJSONObject: object.toDictionary())

        let query = """
            INSERT OR REPLACE INTO item_variations
            (id, updated_at, version, is_deleted, item_id, name, sku, pricing_type, price_amount, price_currency, data_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        try db.run(query,
                  object.id,
                  object.updatedAt,
                  String(object.version),
                  object.isDeleted ? 1 : 0,
                  variationData?.itemId,
                  variationData?.name,
                  variationData?.sku,
                  variationData?.pricingType,
                  variationData?.priceMoney?.amount,
                  variationData?.priceMoney?.currency,
                  dataJson)
    }

    // Placeholder implementations for other object types
    private func upsertModifier(_ object: CatalogObject, db: Connection) throws {
        // Implementation for modifier upsert
        Logger.debug("Database", "Upserting modifier: \(object.id)")
    }

    private func upsertModifierList(_ object: CatalogObject, db: Connection) throws {
        // Implementation for modifier list upsert
        Logger.debug("Database", "Upserting modifier list: \(object.id)")
    }

    private func upsertTax(_ object: CatalogObject, db: Connection) throws {
        // Implementation for tax upsert
        Logger.debug("Database", "Upserting tax: \(object.id)")
    }

    private func upsertDiscount(_ object: CatalogObject, db: Connection) throws {
        // Implementation for discount upsert
        Logger.debug("Database", "Upserting discount: \(object.id)")
    }
}

// MARK: - Supporting Types
enum SyncStatus {
    case idle
    case syncing
    case completed
    case failed(Error)
}

enum DatabaseError: LocalizedError {
    case noConnection
    case initializationFailed(Error)
    case queryFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No database connection available"
        case .initializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Database query failed: \(error.localizedDescription)"
        }
    }
}
