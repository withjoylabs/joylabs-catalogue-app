import Foundation
import os.log

/// Service to migrate from broken raw SQLite3 implementation to proper SQLite.swift
class DatabaseMigrationService {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DatabaseMigration")
    private let backup = DatabaseBackup()
    private let newDatabase = SQLiteSwiftCatalogManager()
    
    /// Perform complete database migration
    func migrateToSQLiteSwift() async throws {
        logger.info("Starting database migration to SQLite.swift...")
        
        // Step 1: Backup current database
        do {
            try backup.backupCurrentDatabase()
            logger.info("✅ Database backup completed")
        } catch {
            logger.warning("Backup failed, but continuing with migration: \(error)")
        }
        
        // Step 2: Export current data to SQL dump
        do {
            let sqlDump = try backup.exportDatabaseToSQL()
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dumpPath = documentsPath.appendingPathComponent("database_export.sql")
            try sqlDump.write(to: dumpPath, atomically: true, encoding: .utf8)
            logger.info("✅ Database export completed: \(dumpPath.path)")
        } catch {
            logger.warning("Export failed, but continuing with migration: \(error)")
        }
        
        // Step 3: Remove corrupted database files
        try removeCorruptedDatabaseFiles()
        logger.info("✅ Corrupted database files removed")
        
        // Step 4: Initialize new SQLite.swift database
        try newDatabase.connect()
        logger.info("✅ New SQLite.swift database initialized")
        
        // Step 5: Verify new database is working
        try verifyNewDatabase()
        logger.info("✅ New database verification completed")
        
        logger.info("🎉 Database migration to SQLite.swift completed successfully!")
    }
    
    /// Remove all corrupted database files
    private func removeCorruptedDatabaseFiles() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("catalog.sqlite")
        let walPath = documentsPath.appendingPathComponent("catalog.sqlite-wal")
        let shmPath = documentsPath.appendingPathComponent("catalog.sqlite-shm")
        
        let filesToRemove = [dbPath, walPath, shmPath]
        
        for fileURL in filesToRemove {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                logger.info("Removed corrupted file: \(fileURL.path)")
            }
        }
    }
    
    /// Verify the new database is working properly
    private func verifyNewDatabase() throws {
        // Test basic operations
        try newDatabase.clearAllData()
        
        // Test inserting a sample catalog object
        let sampleCategory = CatalogObject(
            id: "test_category_001",
            type: "CATEGORY",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            categoryData: CategoryData(
                name: "Test Category",
                imageUrl: nil
            )
        )
        
        try newDatabase.insertCatalogObject(sampleCategory)
        logger.info("✅ Sample data insertion test passed")
        
        // Clean up test data
        try newDatabase.clearAllData()
        logger.info("✅ Data cleanup test passed")
    }
    
    /// Get the new database manager instance
    func getNewDatabaseManager() -> SQLiteSwiftCatalogManager {
        return newDatabase
    }
}

// MARK: - Sample Data Models for Testing

struct CategoryData: Codable {
    let name: String?
    let imageUrl: String?
}

struct CatalogObject: Codable {
    let id: String
    let type: String
    let updatedAt: String?
    let version: Int64?
    let isDeleted: Bool?
    let presentAtAllLocations: Bool?
    let categoryData: CategoryData?
    let itemData: ItemData?
    let itemVariationData: ItemVariationData?
    
    init(id: String, type: String, updatedAt: String?, version: Int64?, isDeleted: Bool?, presentAtAllLocations: Bool?, categoryData: CategoryData? = nil, itemData: ItemData? = nil, itemVariationData: ItemVariationData? = nil) {
        self.id = id
        self.type = type
        self.updatedAt = updatedAt
        self.version = version
        self.isDeleted = isDeleted
        self.presentAtAllLocations = presentAtAllLocations
        self.categoryData = categoryData
        self.itemData = itemData
        self.itemVariationData = itemVariationData
    }
}

struct ItemData: Codable {
    let categoryId: String?
    let name: String?
    let description: String?
    let labelColor: String?
    let availableOnline: Bool?
    let availableForPickup: Bool?
    let availableElectronically: Bool?
}

struct ItemVariationData: Codable {
    let itemId: String
    let name: String?
    let sku: String?
    let upc: String?
    let ordinal: Int64?
    let pricingType: String?
    let basePriceMoney: Money?
    let defaultUnitCost: Money?
    let measurementUnitId: String?
    let sellable: Bool?
    let stockable: Bool?
}

struct Money: Codable {
    let amount: Int64?
    let currency: String?
}
