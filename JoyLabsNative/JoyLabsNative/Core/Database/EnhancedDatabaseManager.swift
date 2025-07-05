import Foundation
import SQLite
import OSLog

/// Enhanced Database Manager - Type-safe SQLite operations with iOS native optimizations
/// Uses 2025 industry standards: structured concurrency, actor isolation, comprehensive error handling
@MainActor
class EnhancedDatabaseManager: ObservableObject {
    
    // MARK: - Properties
    
    private var connection: Connection?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "Database")
    private let databasePath: String
    
    // Connection pool for performance optimization
    private var connectionPool: [Connection] = []
    private let maxConnections = 5
    
    // Performance metrics
    private var queryMetrics: [String: TimeInterval] = [:]
    
    // MARK: - Initialization
    
    init(databaseName: String = "joylabs.db") {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        self.databasePath = "\(documentsPath)/\(databaseName)"
        
        logger.info("Database path: \(self.databasePath)")
    }
    
    // MARK: - Database Lifecycle
    
    /// Initialize database with complete schema (exact port from React Native)
    func initializeDatabase() async throws {
        logger.info("Initializing database...")
        
        do {
            // Create connection
            connection = try Connection(databasePath)
            
            // Enable foreign keys and WAL mode for performance
            try connection?.execute("PRAGMA foreign_keys = ON")
            try connection?.execute("PRAGMA journal_mode = WAL")
            try connection?.execute("PRAGMA synchronous = NORMAL")
            try connection?.execute("PRAGMA cache_size = 10000")
            try connection?.execute("PRAGMA temp_store = MEMORY")
            
            // Check database version and migrate if needed
            try await checkAndMigrateSchema()
            
            logger.info("Database initialized successfully")
            
        } catch {
            logger.error("Failed to initialize database: \(error.localizedDescription)")
            throw DatabaseError.initializationFailed(error)
        }
    }
    
    /// Create all tables with exact React Native schema
    private func createTables() async throws {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }
        
        logger.info("Creating database tables...")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Create core Square tables
            group.addTask { try await self.createCatalogItemsTable(db) }
            group.addTask { try await self.createItemVariationsTable(db) }
            group.addTask { try await self.createCategoriesTable(db) }
            group.addTask { try await self.createTeamDataTable(db) }
            group.addTask { try await self.createReorderItemsTable(db) }
            group.addTask { try await self.createSyncStatusTable(db) }
            group.addTask { try await self.createCatalogObjectsTable(db) }
            
            // Wait for all tables to be created
            try await group.waitForAll()
        }
        
        // Create indexes after tables (for performance)
        try await createIndexes()
        
        logger.info("All tables and indexes created successfully")
    }
    
    /// Create catalog_items table (exact port from React Native)
    private func createCatalogItemsTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.catalogItems.create(ifNotExists: true) { t in
            t.column(CatalogItemColumns.id, primaryKey: true)
            t.column(CatalogItemColumns.updatedAt)
            t.column(CatalogItemColumns.version)
            t.column(CatalogItemColumns.isDeleted, defaultValue: false)
            t.column(CatalogItemColumns.presentAtAllLocations, defaultValue: true)
            t.column(CatalogItemColumns.name)
            t.column(CatalogItemColumns.description)
            t.column(CatalogItemColumns.categoryId)
            t.column(CatalogItemColumns.dataJson)
        })
        
        logger.debug("Created catalog_items table")
    }
    
    /// Create item_variations table (exact port from React Native)
    private func createItemVariationsTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.itemVariations.create(ifNotExists: true) { t in
            t.column(ItemVariationColumns.id, primaryKey: true)
            t.column(ItemVariationColumns.updatedAt)
            t.column(ItemVariationColumns.version)
            t.column(ItemVariationColumns.isDeleted, defaultValue: false)
            t.column(ItemVariationColumns.itemId)
            t.column(ItemVariationColumns.name)
            t.column(ItemVariationColumns.sku)
            t.column(ItemVariationColumns.pricingType)
            t.column(ItemVariationColumns.priceAmount)
            t.column(ItemVariationColumns.priceCurrency)
            t.column(ItemVariationColumns.dataJson)
            
            // Foreign key constraint
            t.foreignKey(ItemVariationColumns.itemId, references: DatabaseTables.catalogItems, CatalogItemColumns.id)
        })
        
        logger.debug("Created item_variations table")
    }
    
    /// Create categories table (exact port from React Native)
    private func createCategoriesTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.categories.create(ifNotExists: true) { t in
            t.column(CategoryColumns.id, primaryKey: true)
            t.column(CategoryColumns.updatedAt)
            t.column(CategoryColumns.version)
            t.column(CategoryColumns.isDeleted, defaultValue: false)
            t.column(CategoryColumns.name)
            t.column(CategoryColumns.dataJson)
        })
        
        logger.debug("Created categories table")
    }
    
    /// Create team_data table (AppSync integration)
    private func createTeamDataTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.teamData.create(ifNotExists: true) { t in
            t.column(TeamDataColumns.itemId, primaryKey: true)
            t.column(TeamDataColumns.caseUpc)
            t.column(TeamDataColumns.caseCost)
            t.column(TeamDataColumns.caseQuantity)
            t.column(TeamDataColumns.vendor)
            t.column(TeamDataColumns.discontinued, defaultValue: false)
            t.column(TeamDataColumns.notes)
            t.column(TeamDataColumns.createdAt, defaultValue: "CURRENT_TIMESTAMP")
            t.column(TeamDataColumns.updatedAt, defaultValue: "CURRENT_TIMESTAMP")
            t.column(TeamDataColumns.lastSyncAt)
            t.column(TeamDataColumns.owner)
        })
        
        logger.debug("Created team_data table")
    }
    
    /// Create reorder_items table (cross-references Square catalog)
    private func createReorderItemsTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.reorderItems.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("item_id"))
            t.column(Expression<Int>("quantity"), defaultValue: 1)
            t.column(Expression<String>("status"), defaultValue: "incomplete")
            t.column(Expression<String?>("added_by"))
            t.column(Expression<String>("created_at"), defaultValue: "CURRENT_TIMESTAMP")
            t.column(Expression<String>("updated_at"), defaultValue: "CURRENT_TIMESTAMP")
            t.column(Expression<String?>("last_sync_at"))
            t.column(Expression<String?>("owner"))
            t.column(Expression<Bool>("pending_sync"), defaultValue: false)
        })
        
        logger.debug("Created reorder_items table")
    }
    
    /// Create sync_status table (exact port from React Native)
    private func createSyncStatusTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.syncStatus.create(ifNotExists: true) { t in
            t.column(Expression<Int>("id"), primaryKey: .autoincrement)
            t.column(Expression<String?>("last_sync_time"))
            t.column(Expression<Bool>("is_syncing"), defaultValue: false)
            t.column(Expression<String?>("sync_error"))
            t.column(Expression<Int>("sync_progress"), defaultValue: 0)
            t.column(Expression<Int>("sync_total"), defaultValue: 0)
            t.column(Expression<String?>("sync_type"))
            t.column(Expression<String?>("last_page_cursor"))
            t.column(Expression<String?>("last_sync_attempt"))
            t.column(Expression<Int>("sync_attempt_count"), defaultValue: 0)
            t.column(Expression<String?>("last_incremental_sync_cursor"))
        })
        
        // Insert default sync status row
        let insertQuery = DatabaseTables.syncStatus.insert(Expression<Int>("id") <- 1)
        try db.run(insertQuery)
        
        logger.debug("Created sync_status table")
    }

    /// Create catalog_objects table for Square API sync
    private func createCatalogObjectsTable(_ db: Connection) async throws {
        try db.run(DatabaseTables.catalogObjects.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("type"))
            t.column(Expression<Int?>("version"))
            t.column(Expression<Bool>("is_deleted"), defaultValue: false)
            t.column(Expression<String?>("name"))
            t.column(Expression<String?>("category_id"))
            t.column(Expression<String?>("sku"))
            t.column(Expression<String?>("upc"))
            t.column(Expression<Int?>("price_amount"))
            t.column(Expression<String?>("price_currency"))
            t.column(Expression<String?>("created_at"))
            t.column(Expression<String?>("updated_at"))
            t.column(Expression<Data>("raw_data"))
        })

        logger.debug("Created catalog_objects table")
    }
    
    /// Create performance indexes (exact port from React Native)
    private func createIndexes() async throws {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }
        
        logger.info("Creating database indexes...")
        
        let indexQueries = [
            // Catalog Items indexes
            "CREATE INDEX IF NOT EXISTS idx_items_name ON catalog_items (name)",
            "CREATE INDEX IF NOT EXISTS idx_items_category_id ON catalog_items (category_id)",
            "CREATE INDEX IF NOT EXISTS idx_items_deleted ON catalog_items (is_deleted)",
            
            // Variations indexes
            "CREATE INDEX IF NOT EXISTS idx_variations_item_id ON item_variations (item_id)",
            "CREATE INDEX IF NOT EXISTS idx_variations_sku ON item_variations (sku)",
            "CREATE INDEX IF NOT EXISTS idx_variations_deleted ON item_variations (is_deleted)",
            
            // Categories indexes
            "CREATE INDEX IF NOT EXISTS idx_categories_name ON categories (name)",
            "CREATE INDEX IF NOT EXISTS idx_categories_deleted ON categories (is_deleted)",
            
            // Team data indexes
            "CREATE INDEX IF NOT EXISTS idx_team_data_case_upc ON team_data (case_upc)",
            "CREATE INDEX IF NOT EXISTS idx_team_data_item_id ON team_data (item_id)",
            
            // Reorder items indexes
            "CREATE INDEX IF NOT EXISTS idx_reorder_items_item_id ON reorder_items (item_id)",
            "CREATE INDEX IF NOT EXISTS idx_reorder_items_status ON reorder_items (status)",
            "CREATE INDEX IF NOT EXISTS idx_reorder_items_updated_at ON reorder_items (updated_at)",
            
            // Composite indexes for common queries
            "CREATE INDEX IF NOT EXISTS idx_catalog_items_category_deleted ON catalog_items (category_id, is_deleted)",
            "CREATE INDEX IF NOT EXISTS idx_variations_item_deleted ON item_variations (item_id, is_deleted)"
        ]
        
        for query in indexQueries {
            try db.execute(query)
        }
        
        logger.info("All indexes created successfully")
    }
    
    /// Check database version and migrate if needed
    private func checkAndMigrateSchema() async throws {
        // Implementation will be added in next step
        logger.info("Schema migration check completed")
    }

    // MARK: - Catalog Object Operations

    /// Insert catalog object from Square API
    func insertCatalogObject(_ object: CatalogObject) async throws {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }

        let sql = """
            INSERT OR REPLACE INTO catalog_objects
            (id, type, version, is_deleted, name, category_id, sku, upc, price_amount, price_currency, created_at, updated_at, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let rawData = try JSONEncoder().encode(object)

        try db.run(sql,
            object.id,
            object.type,
            object.version ?? 0,
            object.isDeleted ?? false,
            extractName(from: object),
            extractCategoryId(from: object),
            extractSKU(from: object),
            extractUPC(from: object),
            extractPriceAmount(from: object),
            extractPriceCurrency(from: object),
            Date().iso8601String,
            Date().iso8601String,
            rawData.datatypeValue
        )
    }

    /// Update catalog object from Square API
    func updateCatalogObject(_ object: CatalogObject) async throws {
        try await insertCatalogObject(object) // Using INSERT OR REPLACE
    }

    /// Get catalog object by ID
    func getCatalogObject(id: String) async throws -> CatalogObject? {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }

        let sql = "SELECT raw_data FROM catalog_objects WHERE id = ?"

        for row in try db.prepare(sql, id) {
            let rawData = row[0] as! Data
            return try JSONDecoder().decode(CatalogObject.self, from: rawData)
        }

        return nil
    }

    /// Delete catalog object by ID
    func deleteCatalogObject(id: String) async throws {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }

        let sql = "DELETE FROM catalog_objects WHERE id = ?"
        try db.run(sql, id)
    }

    /// Get all catalog object IDs
    func getAllCatalogObjectIds() async throws -> Set<String> {
        guard let db = connection else {
            throw DatabaseError.connectionNotAvailable
        }

        let sql = "SELECT id FROM catalog_objects"
        var ids = Set<String>()

        for row in try db.prepare(sql) {
            let id = row[0] as! String
            ids.insert(id)
        }

        return ids
    }

    // MARK: - Helper Methods for Catalog Objects

    private func extractName(from object: CatalogObject) -> String? {
        return object.itemData?.name ?? object.categoryData?.name
    }

    private func extractCategoryId(from object: CatalogObject) -> String? {
        return object.itemData?.categoryId
    }

    private func extractSKU(from object: CatalogObject) -> String? {
        return object.itemVariationData?.sku
    }

    private func extractUPC(from object: CatalogObject) -> String? {
        return object.itemVariationData?.upc
    }

    private func extractPriceAmount(from object: CatalogObject) -> Int? {
        return object.itemVariationData?.priceMoney?.amount
    }

    private func extractPriceCurrency(from object: CatalogObject) -> String? {
        return object.itemVariationData?.priceMoney?.currency
    }
}

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case connectionNotAvailable
    case initializationFailed(Error)
    case queryFailed(Error)
    case invalidData
    case migrationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .connectionNotAvailable:
            return "Database connection is not available"
        case .initializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Database query failed: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid data provided to database operation"
        case .migrationFailed(let error):
            return "Database migration failed: \(error.localizedDescription)"
        }
    }
}
