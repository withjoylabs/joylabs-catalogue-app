import Foundation
import SwiftData

/// Type aliases and compatibility layer for SwiftData migration
/// Allows existing code to work with SwiftData without changes

// MARK: - Database Manager Aliases
typealias SQLiteSwiftCatalogManager = SwiftDataCatalogManager
typealias CatalogStatsService = SwiftDataCatalogStatsService
// SearchManager typealias moved to SearchManager.swift to avoid redeclaration
// ImageURLManager removed - using pure SwiftData for images

// MARK: - Connection Type Aliases
// SQLite.swift used Connection, SwiftData uses ModelContext
typealias Connection = ModelContext

// MARK: - TeamData Compatibility
// The old TeamData struct is now replaced by TeamDataModel
// This typealias allows existing code to continue working
typealias TeamData = TeamDataModel

// MARK: - Extensions for Compatibility

extension SwiftDataCatalogManager {
    /// Compatibility method that returns the context as a "connection"
    func getConnection() -> ModelContext? {
        return getContext()
    }
}

extension ModelContext {
    /// Compatibility method for SQLite.swift's prepare() method
    /// SwiftData uses fetch() with FetchDescriptor instead
    func prepare<T>(_ fetchDescriptor: FetchDescriptor<T>) throws -> [T] {
        return try fetch(fetchDescriptor)
    }
    
    /// Compatibility method for SQLite.swift's scalar() method
    /// SwiftData uses fetchCount() for count queries
    func scalar<T>(_ fetchDescriptor: FetchDescriptor<T>) throws -> Int64 {
        let count = try fetchCount(fetchDescriptor)
        return Int64(count)
    }
    
    /// Compatibility method for SQLite.swift's pluck() method
    /// SwiftData uses fetch() to get first result
    func pluck<T>(_ fetchDescriptor: FetchDescriptor<T>) throws -> T? {
        return try fetch(fetchDescriptor).first
    }
    
    /// Compatibility method for SQLite.swift's run() method
    /// SwiftData uses save() for persistence
    func run(_ statement: Any) throws {
        try save()
    }
    
    /// Compatibility method for SQLite.swift's execute() method
    /// SwiftData uses save() for persistence
    func execute(_ statement: String) async throws {
        try save()
    }
}

// MARK: - Mock CatalogTableDefinitions for Compatibility
// This provides empty implementations for code that still references these
struct CatalogTableDefinitions {
    // These are no longer used in SwiftData but kept for compilation compatibility
    static let catalogItems = "catalog_items"
    static let itemVariations = "item_variations"
    static let categories = "categories"
    static let teamData = "team_data"
    static let taxes = "taxes"
    static let modifierLists = "modifier_lists"
    static let modifiers = "modifiers"
    static let images = "images"
    static let locations = "locations"
    
    // Column names (these are now handled by SwiftData properties)
    static let itemId = "id"
    static let itemName = "name"
    static let itemCategoryName = "category_name"
    static let itemReportingCategoryName = "reporting_category_name"
    static let itemDataJson = "data_json"
    static let itemIsDeleted = "is_deleted"
    
    static let categoryId = "id"
    static let categoryName = "name"
    static let categoryIsDeleted = "is_deleted"
    static let categoryUpdatedAt = "updated_at"
    static let categoryVersion = "version"
    
    static let variationId = "id"
    static let variationItemId = "item_id"
    static let variationSku = "sku"
    static let variationUpc = "upc"
    static let variationPriceAmount = "price_amount"
    static let variationName = "name"
    static let variationIsDeleted = "is_deleted"
    
    static let teamDataItemId = "item_id"
    static let teamCaseUpc = "case_upc"
    static let teamCaseCost = "case_cost"
    static let teamCaseQuantity = "case_quantity"
    static let teamVendor = "vendor"
    static let teamDiscontinued = "discontinued"
    static let teamNotes = "notes"
    
    static let taxId = "id"
    static let taxName = "name"
    static let taxIsDeleted = "is_deleted"
    static let taxUpdatedAt = "updated_at"
    static let taxVersion = "version"
    static let taxCalculationPhase = "calculation_phase"
    static let taxPercentage = "percentage"
    static let taxEnabled = "enabled"
    
    static let modifierListPrimaryId = "id"
    static let modifierListName = "name"
    
    static let modifierId = "id"
    static let modifierName = "name"
    static let modifierIsDeleted = "is_deleted"
    static let modifierUpdatedAt = "updated_at"
    static let modifierVersion = "version"
    static let modifierPriceAmount = "price_amount"
    static let modifierPriceCurrency = "price_currency"
    static let modifierOnByDefault = "on_by_default"
}

// MARK: - Extensions for Compatibility