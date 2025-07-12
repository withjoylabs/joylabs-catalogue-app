import Foundation
import SQLite

/// LabelTemplateManager - Manages label template storage and retrieval
/// Handles custom template persistence and cloud synchronization
class LabelTemplateManager {
    
    // MARK: - Properties
    private let databaseManager: DatabaseManager
    private let cloudSyncService: CloudSyncService
    
    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager = DatabaseManager(),
        cloudSyncService: CloudSyncService = CloudSyncService()
    ) {
        self.databaseManager = databaseManager
        self.cloudSyncService = cloudSyncService
    }
    
    // MARK: - Public Methods
    
    /// Load all custom templates from database
    func loadCustomTemplates() async throws -> [LabelTemplate] {
        Logger.info("TemplateManager", "Loading custom templates from database")
        
        let db = try await databaseManager.getDatabase()
        
        let query = """
            SELECT id, name, category, size_data, elements_data, created_at, updated_at
            FROM label_templates
            WHERE is_built_in = 0
            ORDER BY updated_at DESC
        """
        
        let templates = try db.prepare(query).compactMap { row -> LabelTemplate? in
            do {
                return try parseTemplateFromRow(row)
            } catch {
                Logger.error("TemplateManager", "Failed to parse template: \(error)")
                return nil
            }
        }
        
        Logger.info("TemplateManager", "Loaded \(templates.count) custom templates")
        return templates
    }
    
    /// Save a template to database
    func saveTemplate(_ template: LabelTemplate) async throws {
        Logger.info("TemplateManager", "Saving template: \(template.name)")
        
        let db = try await databaseManager.getDatabase()
        
        // Serialize template data
        let sizeData = try JSONEncoder().encode(template.size)
        let elementsData = try JSONEncoder().encode(template.elements)
        
        let query = """
            INSERT OR REPLACE INTO label_templates 
            (id, name, category, size_data, elements_data, is_built_in, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        try db.run(query,
                  template.id,
                  template.name,
                  template.category.rawValue,
                  sizeData,
                  elementsData,
                  template.isBuiltIn ? 1 : 0,
                  template.createdAt,
                  template.updatedAt)
        
        // Sync to cloud if not built-in
        if !template.isBuiltIn {
            try await cloudSyncService.syncTemplate(template)
        }
        
        Logger.info("TemplateManager", "Template saved successfully")
    }
    
    /// Delete a template from database
    func deleteTemplate(_ templateId: String) async throws {
        Logger.info("TemplateManager", "Deleting template: \(templateId)")
        
        let db = try await databaseManager.getDatabase()
        
        let query = "DELETE FROM label_templates WHERE id = ? AND is_built_in = 0"
        try db.run(query, templateId)
        
        // Remove from cloud
        try await cloudSyncService.deleteTemplate(templateId)
        
        Logger.info("TemplateManager", "Template deleted successfully")
    }
    
    /// Get template by ID
    func getTemplate(_ templateId: String) async throws -> LabelTemplate? {
        let db = try await databaseManager.getDatabase()
        
        let query = """
            SELECT id, name, category, size_data, elements_data, is_built_in, created_at, updated_at
            FROM label_templates
            WHERE id = ?
        """
        
        let results = try db.prepare(query).bind(templateId).compactMap { row -> LabelTemplate? in
            try? parseTemplateFromRow(row)
        }
        
        return results.first
    }
    
    /// Search templates by name or category
    func searchTemplates(query: String, category: LabelCategory? = nil) async throws -> [LabelTemplate] {
        let db = try await databaseManager.getDatabase()
        
        var sqlQuery = """
            SELECT id, name, category, size_data, elements_data, is_built_in, created_at, updated_at
            FROM label_templates
            WHERE name LIKE ?
        """
        
        var params: [Any] = ["%\(query)%"]
        
        if let category = category {
            sqlQuery += " AND category = ?"
            params.append(category.rawValue)
        }
        
        sqlQuery += " ORDER BY name ASC"
        
        let statement = try db.prepare(sqlQuery)
        
        // Bind parameters
        for (index, param) in params.enumerated() {
            try statement.bind(param, at: index + 1)
        }
        
        let templates = try statement.compactMap { row -> LabelTemplate? in
            try? parseTemplateFromRow(row)
        }
        
        Logger.debug("TemplateManager", "Search '\(query)' returned \(templates.count) templates")
        return templates
    }
    
    /// Export template to JSON
    func exportTemplate(_ template: LabelTemplate) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(template)
    }
    
    /// Import template from JSON
    func importTemplate(from data: Data) throws -> LabelTemplate {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var template = try decoder.decode(LabelTemplate.self, from: data)
        
        // Generate new ID to avoid conflicts
        template = LabelTemplate(
            id: UUID().uuidString,
            name: template.name + " (Imported)",
            category: .custom,
            size: template.size,
            elements: template.elements,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        return template
    }
    
    /// Get template usage statistics
    func getTemplateUsageStats() async throws -> [TemplateUsageStats] {
        let db = try await databaseManager.getDatabase()
        
        let query = """
            SELECT 
                lt.id,
                lt.name,
                lt.category,
                COUNT(lp.id) as usage_count,
                MAX(lp.created_at) as last_used
            FROM label_templates lt
            LEFT JOIN label_prints lp ON lt.id = lp.template_id
            GROUP BY lt.id, lt.name, lt.category
            ORDER BY usage_count DESC, last_used DESC
        """
        
        let stats = try db.prepare(query).map { row in
            TemplateUsageStats(
                templateId: row[0] as! String,
                templateName: row[1] as! String,
                category: LabelCategory(rawValue: row[2] as! String) ?? .custom,
                usageCount: row[3] as! Int64,
                lastUsed: row[4] as? String
            )
        }
        
        return stats
    }
    
    // MARK: - Private Methods
    
    private func parseTemplateFromRow(_ row: Element) throws -> LabelTemplate {
        let id = row[0] as! String
        let name = row[1] as! String
        let categoryString = row[2] as! String
        let sizeData = row[3] as! Data
        let elementsData = row[4] as! Data
        let isBuiltIn = (row[5] as! Int64) == 1
        let createdAt = row[6] as! Date
        let updatedAt = row[7] as! Date
        
        let category = LabelCategory(rawValue: categoryString) ?? .custom
        let size = try JSONDecoder().decode(LabelSize.self, from: sizeData)
        let elements = try JSONDecoder().decode([LabelElement].self, from: elementsData)
        
        return LabelTemplate(
            id: id,
            name: name,
            category: category,
            size: size,
            elements: elements,
            isBuiltIn: isBuiltIn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Cloud Sync Service
class CloudSyncService {
    
    /// Sync template to cloud storage
    func syncTemplate(_ template: LabelTemplate) async throws {
        // This would sync to AWS S3, iCloud, or other cloud storage
        Logger.debug("CloudSync", "Syncing template to cloud: \(template.name)")
        
        // Placeholder implementation
        // In a real app, this would upload to cloud storage
    }
    
    /// Delete template from cloud storage
    func deleteTemplate(_ templateId: String) async throws {
        // This would delete from cloud storage
        Logger.debug("CloudSync", "Deleting template from cloud: \(templateId)")
        
        // Placeholder implementation
    }
    
    /// Download templates from cloud
    func downloadTemplates() async throws -> [LabelTemplate] {
        // This would download templates from cloud storage
        Logger.debug("CloudSync", "Downloading templates from cloud")
        
        // Placeholder implementation
        return []
    }
}

// MARK: - Supporting Types
struct TemplateUsageStats {
    let templateId: String
    let templateName: String
    let category: LabelCategory
    let usageCount: Int64
    let lastUsed: String?
    
    var lastUsedDate: Date? {
        guard let lastUsed = lastUsed else { return nil }
        return ISO8601DateFormatter().date(from: lastUsed)
    }
}

// MARK: - Database Schema Extension
extension DatabaseManager {
    
    /// Create label templates table
    func createLabelTemplatesTable() async throws {
        let db = try await getDatabase()
        
        try db.run("""
            CREATE TABLE IF NOT EXISTS label_templates (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                size_data BLOB NOT NULL,
                elements_data BLOB NOT NULL,
                is_built_in INTEGER NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )
        """)
        
        // Create indexes
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_templates_category ON label_templates(category)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_templates_name ON label_templates(name)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_templates_updated ON label_templates(updated_at)")
        
        Logger.info("Database", "Label templates table created")
    }
    
    /// Create label prints table for usage tracking
    func createLabelPrintsTable() async throws {
        let db = try await getDatabase()
        
        try db.run("""
            CREATE TABLE IF NOT EXISTS label_prints (
                id TEXT PRIMARY KEY,
                template_id TEXT NOT NULL,
                item_id TEXT,
                printer_name TEXT,
                print_settings BLOB,
                status TEXT NOT NULL,
                created_at DATETIME NOT NULL,
                completed_at DATETIME,
                error_message TEXT,
                FOREIGN KEY (template_id) REFERENCES label_templates(id)
            )
        """)
        
        // Create indexes
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_prints_template ON label_prints(template_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_prints_item ON label_prints(item_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_label_prints_created ON label_prints(created_at)")
        
        Logger.info("Database", "Label prints table created")
    }
}
