import Foundation
import SQLite

/// Database Models - Type-safe representations of database tables
/// Ported from React Native with iOS native enhancements using 2025 industry standards

// MARK: - Core Square Catalog Models

/// Represents a Square catalog item (exact port from React Native schema)
struct CatalogItem: Codable, Identifiable {
    let id: String
    let updatedAt: String
    let version: String  // Store as TEXT since it can be large number string
    let isDeleted: Bool
    let presentAtAllLocations: Bool
    let name: String?
    let description: String?
    let categoryId: String?
    let dataJson: String  // Store the raw Square API JSON
    
    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case version
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case name
        case description
        case categoryId = "category_id"
        case dataJson = "data_json"
    }
}

/// Represents a Square item variation (exact port from React Native schema)
struct ItemVariation: Codable, Identifiable {
    let id: String
    let updatedAt: String
    let version: String
    let isDeleted: Bool
    let itemId: String
    let name: String?
    let sku: String?
    let pricingType: String?
    let priceAmount: Int?  // Store amount in cents/smallest unit
    let priceCurrency: String?
    let dataJson: String  // Store the raw Square API JSON
    
    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case version
        case isDeleted = "is_deleted"
        case itemId = "item_id"
        case name
        case sku
        case pricingType = "pricing_type"
        case priceAmount = "price_amount"
        case priceCurrency = "price_currency"
        case dataJson = "data_json"
    }
}

/// Represents a Square category (exact port from React Native schema)
struct Category: Codable, Identifiable {
    let id: String
    let updatedAt: String
    let version: String
    let isDeleted: Bool
    let name: String?
    let dataJson: String  // Store the raw Square API JSON
    
    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
        case version
        case isDeleted = "is_deleted"
        case name
        case dataJson = "data_json"
    }
}

// MARK: - Team Data Models (AppSync Integration)

/// Team data for items (syncs with AWS AppSync)
struct TeamData: Codable, Identifiable {
    let itemId: String
    let caseUpc: String?
    let caseCost: Double?
    let caseQuantity: Int?
    let vendor: String?
    let discontinued: Bool
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let lastSyncAt: String?
    let owner: String?
    
    var id: String { itemId }
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case caseUpc = "case_upc"
        case caseCost = "case_cost"
        case caseQuantity = "case_quantity"
        case vendor
        case discontinued
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSyncAt = "last_sync_at"
        case owner
    }
}

/// Database reorder items (minimal data that cross-references Square catalog)
struct DatabaseReorderItem: Codable, Identifiable {
    let id: String
    let itemId: String  // Reference to Square catalog
    let quantity: Int
    let status: String  // 'incomplete' | 'complete'
    let addedBy: String?
    let createdAt: String
    let updatedAt: String
    let lastSyncAt: String?
    let owner: String?
    let pendingSync: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
        case quantity
        case status
        case addedBy = "added_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSyncAt = "last_sync_at"
        case owner
        case pendingSync = "pending_sync"
    }
}

// MARK: - Sync Management Models

/// Sync status tracking (exact port from React Native schema)
struct SyncStatus: Codable {
    let id: Int
    let lastSyncTime: String?
    let isSyncing: Bool
    let syncError: String?
    let syncProgress: Int
    let syncTotal: Int
    let syncType: String?  // 'full', 'delta'
    let lastPageCursor: String?
    let lastSyncAttempt: String?
    let syncAttemptCount: Int
    let lastIncrementalSyncCursor: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case lastSyncTime = "last_sync_time"
        case isSyncing = "is_syncing"
        case syncError = "sync_error"
        case syncProgress = "sync_progress"
        case syncTotal = "sync_total"
        case syncType = "sync_type"
        case lastPageCursor = "last_page_cursor"
        case lastSyncAttempt = "last_sync_attempt"
        case syncAttemptCount = "sync_attempt_count"
        case lastIncrementalSyncCursor = "last_incremental_sync_cursor"
    }
}

// MARK: - Database Table Definitions (SQLite.swift)

/// Type-safe table definitions using SQLite.swift
enum DatabaseTables {
    // Core Square tables
    static let catalogItems = Table("catalog_items")
    static let itemVariations = Table("item_variations")
    static let categories = Table("categories")
    static let modifierLists = Table("modifier_lists")
    static let modifiers = Table("modifiers")
    static let taxes = Table("taxes")
    static let discounts = Table("discounts")
    static let images = Table("images")
    
    // Team data tables
    static let teamData = Table("team_data")
    static let reorderItems = Table("reorder_items")
    static let itemChangeLogs = Table("item_change_logs")
    
    // Sync management tables
    static let syncStatus = Table("sync_status")
    static let catalogObjects = Table("catalog_objects")
    static let syncLogs = Table("sync_logs")
    static let dbVersion = Table("db_version")
    
    // Square merchant data
    static let merchantInfo = Table("merchant_info")
    static let locations = Table("locations")
}

// MARK: - Column Definitions (Type-safe)

/// Type-safe column definitions for catalog_items table
enum CatalogItemColumns {
    static let id = Expression<String>("id")
    static let updatedAt = Expression<String>("updated_at")
    static let version = Expression<String>("version")
    static let isDeleted = Expression<Bool>("is_deleted")
    static let presentAtAllLocations = Expression<Bool>("present_at_all_locations")
    static let name = Expression<String?>("name")
    static let description = Expression<String?>("description")
    static let categoryId = Expression<String?>("category_id")
    static let dataJson = Expression<String>("data_json")
}

/// Type-safe column definitions for item_variations table
enum ItemVariationColumns {
    static let id = Expression<String>("id")
    static let updatedAt = Expression<String>("updated_at")
    static let version = Expression<String>("version")
    static let isDeleted = Expression<Bool>("is_deleted")
    static let itemId = Expression<String>("item_id")
    static let name = Expression<String?>("name")
    static let sku = Expression<String?>("sku")
    static let pricingType = Expression<String?>("pricing_type")
    static let priceAmount = Expression<Int?>("price_amount")
    static let priceCurrency = Expression<String?>("price_currency")
    static let dataJson = Expression<String>("data_json")
}

/// Type-safe column definitions for categories table
enum CategoryColumns {
    static let id = Expression<String>("id")
    static let updatedAt = Expression<String>("updated_at")
    static let version = Expression<String>("version")
    static let isDeleted = Expression<Bool>("is_deleted")
    static let name = Expression<String?>("name")
    static let dataJson = Expression<String>("data_json")
}

/// Type-safe column definitions for team_data table
enum TeamDataColumns {
    static let itemId = Expression<String>("item_id")
    static let caseUpc = Expression<String?>("case_upc")
    static let caseCost = Expression<Double?>("case_cost")
    static let caseQuantity = Expression<Int?>("case_quantity")
    static let vendor = Expression<String?>("vendor")
    static let discontinued = Expression<Bool>("discontinued")
    static let notes = Expression<String?>("notes")
    static let createdAt = Expression<String>("created_at")
    static let updatedAt = Expression<String>("updated_at")
    static let lastSyncAt = Expression<String?>("last_sync_at")
    static let owner = Expression<String?>("owner")
}
