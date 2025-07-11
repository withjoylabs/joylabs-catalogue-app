import Foundation
import os.log

/// Service to migrate from broken raw SQLite3 implementation to proper SQLite.swift
class DatabaseMigrationService {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DatabaseMigration")
    private let backup = DatabaseBackup()
    private let newDatabase = SQLiteSwiftCatalogManager()
    
    /// Check if migration is actually needed
    func isMigrationNeeded() -> Bool {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("catalog.sqlite")
        let migrationMarkerPath = documentsPath.appendingPathComponent(".sqlite_swift_migration_completed")

        // If migration marker exists, migration is already done
        if FileManager.default.fileExists(atPath: migrationMarkerPath.path) {
            logger.info("Migration marker found - SQLite.swift migration already completed")
            return false
        }

        // If no database exists at all, no migration needed (fresh install)
        if !FileManager.default.fileExists(atPath: dbPath.path) {
            logger.info("No existing database found - fresh install, no migration needed")
            return false
        }

        logger.info("Existing database found without migration marker - migration needed")
        return true
    }

    /// Perform complete database migration ONLY if needed
    func migrateToSQLiteSwift() async throws {
        // Check if migration is actually needed
        guard isMigrationNeeded() else {
            logger.info("Database migration not needed - skipping")
            try newDatabase.connect()
            return
        }

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

        // Step 3: Remove old database files (only if actually migrating)
        try removeOldDatabaseFiles()
        logger.info("✅ Old database files removed")

        // Step 4: Initialize new SQLite.swift database
        try newDatabase.connect()
        logger.info("✅ New SQLite.swift database initialized")

        // Step 5: Verify new database is working
        try verifyNewDatabase()
        logger.info("✅ New database verification completed")

        // Step 6: Create migration marker
        try createMigrationMarker()
        logger.info("✅ Migration marker created")

        logger.info("🎉 Database migration to SQLite.swift completed successfully!")
    }
    
    /// Remove old database files during migration
    private func removeOldDatabaseFiles() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("catalog.sqlite")
        let walPath = documentsPath.appendingPathComponent("catalog.sqlite-wal")
        let shmPath = documentsPath.appendingPathComponent("catalog.sqlite-shm")

        let filesToRemove = [dbPath, walPath, shmPath]

        for fileURL in filesToRemove {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                logger.info("Removed old database file: \(fileURL.path)")
            }
        }
    }

    /// Create migration marker to prevent repeated migrations
    private func createMigrationMarker() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let markerPath = documentsPath.appendingPathComponent(".sqlite_swift_migration_completed")
        let markerContent = "Migration completed on \(Date())"
        try markerContent.write(to: markerPath, atomically: true, encoding: .utf8)
    }
    
    /// Verify the new database is working properly
    private func verifyNewDatabase() throws {
        // Test basic database functionality without clearing data
        guard let db = newDatabase.getConnection() else {
            throw DatabaseMigrationError.verificationFailed("No database connection")
        }

        // Simple verification - check if tables exist
        let tableCount = try db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table'") as! Int64
        logger.info("✅ Database verification completed - \(tableCount) tables found")
    }
    
    /// Get the new database manager instance
    func getNewDatabaseManager() -> SQLiteSwiftCatalogManager {
        return newDatabase
    }
}

// MARK: - Migration Errors

enum DatabaseMigrationError: Error {
    case verificationFailed(String)
    case migrationFailed(String)
    case backupFailed(String)
}

// MARK: - Sample Data Models for Testing
// All model definitions moved to CatalogModels.swift for consistency
