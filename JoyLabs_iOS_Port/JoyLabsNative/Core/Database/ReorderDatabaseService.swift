import Foundation
import SQLite
import os.log

/// Database service for managing reorder items with AppSync sync capabilities
class ReorderDatabaseService: ObservableObject {
    private let db: Connection
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ReorderDatabase")
    
    // Table and column definitions
    private let reorderItems = Table("reorder_items")
    private let id = Expression<String>("id")
    private let itemId = Expression<String>("item_id")
    private let quantity = Expression<Int>("quantity")
    private let status = Expression<String>("status")
    private let addedBy = Expression<String?>("added_by")
    private let createdAt = Expression<String>("created_at")
    private let updatedAt = Expression<String>("updated_at")
    private let lastSyncAt = Expression<String?>("last_sync_at")
    private let owner = Expression<String?>("owner")
    private let pendingSync = Expression<Bool>("pending_sync")
    
    init(database: Connection) {
        self.db = database
        createTableIfNeeded()
    }
    
    // MARK: - Table Creation
    
    private func createTableIfNeeded() {
        do {
            try db.run(reorderItems.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(itemId)
                t.column(quantity, defaultValue: 1)
                t.column(status, defaultValue: "added")
                t.column(addedBy)
                t.column(createdAt, defaultValue: Date().iso8601String)
                t.column(updatedAt, defaultValue: Date().iso8601String)
                t.column(lastSyncAt)
                t.column(owner)
                t.column(pendingSync, defaultValue: true)
            })
            
            // Create indexes for performance
            try db.run("CREATE INDEX IF NOT EXISTS idx_reorder_items_item_id ON reorder_items (item_id)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_reorder_items_status ON reorder_items (status)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_reorder_items_updated_at ON reorder_items (updated_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_reorder_items_owner ON reorder_items (owner)")
            
            logger.info("Reorder items table and indexes created successfully")
        } catch {
            logger.error("Failed to create reorder items table: \(error.localizedDescription)")
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new reorder item
    func addReorderItem(_ item: ReorderItem) throws {
        let now = Date().iso8601String
        let insert = reorderItems.insert(
            id <- item.id,
            itemId <- item.itemId,
            quantity <- item.quantity,
            status <- item.status.rawValue,
            addedBy <- item.addedBy,
            createdAt <- now,
            updatedAt <- now,
            pendingSync <- true
        )
        
        try db.run(insert)
        logger.info("Added reorder item: \(item.name)")
    }
    
    /// Get all reorder items
    func getAllReorderItems() throws -> [DatabaseReorderItem] {
        let query = reorderItems.order(updatedAt.desc)
        return try db.prepare(query).map { row in
            DatabaseReorderItem(
                id: row[id],
                itemId: row[itemId],
                quantity: row[quantity],
                status: row[status],
                addedBy: row[addedBy],
                createdAt: row[createdAt],
                updatedAt: row[updatedAt],
                lastSyncAt: row[lastSyncAt],
                owner: row[owner],
                pendingSync: row[pendingSync]
            )
        }
    }
    
    /// Get reorder items by status
    func getReorderItems(status: ReorderStatus) throws -> [DatabaseReorderItem] {
        let query = reorderItems.filter(self.status == status.rawValue).order(updatedAt.desc)
        return try db.prepare(query).map { row in
            DatabaseReorderItem(
                id: row[id],
                itemId: row[itemId],
                quantity: row[quantity],
                status: row[status],
                addedBy: row[addedBy],
                createdAt: row[createdAt],
                updatedAt: row[updatedAt],
                lastSyncAt: row[lastSyncAt],
                owner: row[owner],
                pendingSync: row[pendingSync]
            )
        }
    }
    
    /// Update reorder item status
    func updateReorderItemStatus(itemId: String, newStatus: ReorderStatus) throws {
        let now = Date().iso8601String
        let item = reorderItems.filter(self.itemId == itemId)
        
        if newStatus == .received {
            // Remove received items from active list
            try db.run(item.delete())
            logger.info("Removed received item from reorder list: \(itemId)")
        } else {
            let update = item.update(
                status <- newStatus.rawValue,
                updatedAt <- now,
                pendingSync <- true
            )
            try db.run(update)
            logger.info("Updated reorder item status: \(itemId) -> \(newStatus.rawValue)")
        }
    }
    
    /// Update reorder item quantity
    func updateReorderItemQuantity(itemId: String, newQuantity: Int) throws {
        let now = Date().iso8601String
        let item = reorderItems.filter(self.itemId == itemId)
        let update = item.update(
            quantity <- max(1, newQuantity),
            updatedAt <- now,
            pendingSync <- true
        )
        try db.run(update)
        logger.info("Updated reorder item quantity: \(itemId) -> \(newQuantity)")
    }
    
    /// Remove reorder item
    func removeReorderItem(itemId: String) throws {
        let item = reorderItems.filter(self.itemId == itemId)
        try db.run(item.delete())
        logger.info("Removed reorder item: \(itemId)")
    }
    
    /// Check if item exists in reorder list (excluding received items)
    func itemExists(itemId: String) throws -> Bool {
        let query = reorderItems.filter(self.itemId == itemId && status != "received")
        return try db.scalar(query.count) > 0
    }
    
    /// Clear all reorder items
    func clearAllReorderItems() throws {
        try db.run(reorderItems.delete())
        logger.info("Cleared all reorder items")
    }
    
    /// Get unpurchased count for badge
    func getUnpurchasedCount() throws -> Int {
        let query = reorderItems.filter(status == "added")
        return try db.scalar(query.count)
    }
    
    // MARK: - AppSync Sync Support
    
    /// Get items pending sync to AppSync
    func getItemsPendingSync() throws -> [DatabaseReorderItem] {
        let query = reorderItems.filter(pendingSync == true).order(updatedAt.desc)
        return try db.prepare(query).map { row in
            DatabaseReorderItem(
                id: row[id],
                itemId: row[itemId],
                quantity: row[quantity],
                status: row[status],
                addedBy: row[addedBy],
                createdAt: row[createdAt],
                updatedAt: row[updatedAt],
                lastSyncAt: row[lastSyncAt],
                owner: row[owner],
                pendingSync: row[pendingSync]
            )
        }
    }
    
    /// Mark item as synced
    func markItemAsSynced(itemId: String) throws {
        let now = Date().iso8601String
        let item = reorderItems.filter(self.itemId == itemId)
        let update = item.update(
            pendingSync <- false,
            lastSyncAt <- now
        )
        try db.run(update)
    }
}

// MARK: - Extensions

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

extension ReorderStatus {
    var rawValue: String {
        switch self {
        case .added: return "added"
        case .purchased: return "purchased"
        case .received: return "received"
        }
    }
    
    init?(rawValue: String) {
        switch rawValue {
        case "added": self = .added
        case "purchased": self = .purchased
        case "received": self = .received
        default: return nil
        }
    }
}
