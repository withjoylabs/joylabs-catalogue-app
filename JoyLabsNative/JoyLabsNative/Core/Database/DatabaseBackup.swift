import Foundation
import SQLite3
import os.log

/// Database backup utility to save current database before recreation
class DatabaseBackup {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DatabaseBackup")
    
    /// Backup current database files before recreation
    func backupCurrentDatabase() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("catalog.sqlite").path
        
        let timestamp = DateFormatter().string(from: Date())
        let backupDir = documentsPath.appendingPathComponent("database_backups")
        
        // Create backup directory
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Backup main database file
        let mainBackupPath = backupDir.appendingPathComponent("catalog_backup_\(timestamp).sqlite")
        if FileManager.default.fileExists(atPath: dbPath) {
            try FileManager.default.copyItem(atPath: dbPath, toPath: mainBackupPath.path)
            logger.info("Backed up main database to: \(mainBackupPath.path)")
        }
        
        // Backup WAL file
        let walPath = dbPath + "-wal"
        let walBackupPath = backupDir.appendingPathComponent("catalog_backup_\(timestamp).sqlite-wal")
        if FileManager.default.fileExists(atPath: walPath) {
            try FileManager.default.copyItem(atPath: walPath, toPath: walBackupPath.path)
            logger.info("Backed up WAL file to: \(walBackupPath.path)")
        }
        
        // Backup SHM file
        let shmPath = dbPath + "-shm"
        let shmBackupPath = backupDir.appendingPathComponent("catalog_backup_\(timestamp).sqlite-shm")
        if FileManager.default.fileExists(atPath: shmPath) {
            try FileManager.default.copyItem(atPath: shmPath, toPath: shmBackupPath.path)
            logger.info("Backed up SHM file to: \(shmBackupPath.path)")
        }
        
        logger.info("Database backup completed successfully")
    }
    
    /// Export current database data to SQL dump before recreation
    func exportDatabaseToSQL() throws -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("catalog.sqlite").path
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            logger.warning("No database file found to export")
            return "-- No database file found"
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.cannotOpenDatabase
        }
        defer { sqlite3_close(db) }
        
        var sqlDump = "-- Database export from \(Date())\n\n"
        
        // Get all table names
        let tableQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, tableQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let tableName = sqlite3_column_text(statement, 0) {
                    let name = String(cString: tableName)
                    sqlDump += exportTableData(db: db, tableName: name)
                }
            }
        }
        sqlite3_finalize(statement)
        
        return sqlDump
    }
    
    private func exportTableData(db: OpaquePointer?, tableName: String) -> String {
        var result = "-- Table: \(tableName)\n"
        
        let query = "SELECT * FROM \(tableName)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let columnCount = sqlite3_column_count(statement)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                var values: [String] = []
                for i in 0..<columnCount {
                    if let text = sqlite3_column_text(statement, i) {
                        values.append("'\(String(cString: text))'")
                    } else {
                        values.append("NULL")
                    }
                }
                result += "INSERT INTO \(tableName) VALUES (\(values.joined(separator: ", ")));\n"
            }
        }
        sqlite3_finalize(statement)
        
        return result + "\n"
    }
}

enum DatabaseError: Error {
    case cannotOpenDatabase
    case executionFailed(String)
    case preparationFailed(String)
}
