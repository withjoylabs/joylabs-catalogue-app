import Foundation
import SwiftData

// MARK: - SwiftData Model for Catalog Items
// Replaces SQLite.swift catalog_items table with native SwiftData persistence
@Model
final class CatalogItemModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Location settings (matching Square API structure)
    var presentAtAllLocations: Bool?
    var presentAtLocationIds: [String]?
    var absentAtLocationIds: [String]?
    
    // Item fields
    @Attribute(.spotlight) var name: String?
    var itemDescription: String?
    @Attribute(.spotlight) var categoryId: String?
    var categoryName: String?  // Pre-computed for search performance
    var reportingCategoryId: String?
    var reportingCategoryName: String?  // Pre-computed for search performance
    var taxNames: String?  // Comma-separated for display
    var modifierNames: String?  // Comma-separated for display
    
    // Additional fields from SQLite implementation
    var itemType: String?
    var labelColor: String?
    var availableOnline: Bool?
    var availableForPickup: Bool?
    var availableElectronically: Bool?
    
    // Store complete Square API response for complex operations
    var dataJson: String?
    
    // Relationships
    @Relationship(deleteRule: .cascade) var variations: [ItemVariationModel]?
    @Relationship var category: CategoryModel?
    @Relationship var reportingCategory: CategoryModel?
    @Relationship var taxes: [TaxModel]?
    @Relationship var modifierLists: [ModifierListModel]?
    @Relationship var images: [ImageModel]?
    @Relationship var teamData: TeamDataModel?
    
    // Computed properties for convenience
    var primaryImageUrl: String? {
        images?.first?.url
    }
    
    var lowestPrice: Double? {
        guard let variations = variations else { return nil }
        let prices = variations.compactMap { variation -> Double? in
            guard let amount = variation.priceAmount, amount > 0 else { return nil }
            return Double(amount) / 100.0
        }
        return prices.min()
    }
    
    var hasVariations: Bool {
        return (variations?.count ?? 0) > 0
    }
    
    init(
        id: String,
        updatedAt: Date = Date(),
        version: String = "0",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.version = version
        self.isDeleted = isDeleted
    }
    
    // Update from Square API CatalogObject
    func updateFromCatalogObject(_ object: CatalogObject) {
        self.updatedAt = Date()
        self.version = String(object.version ?? 0)
        self.isDeleted = object.isDeleted ?? false
        self.presentAtAllLocations = object.presentAtAllLocations
        self.presentAtLocationIds = object.presentAtLocationIds
        self.absentAtLocationIds = object.absentAtLocationIds
        
        if let itemData = object.itemData {
            self.name = itemData.name
            self.itemDescription = itemData.description
            self.categoryId = itemData.categoryId
            self.labelColor = itemData.labelColor
            self.availableOnline = itemData.availableOnline
            self.availableForPickup = itemData.availableForPickup
            self.availableElectronically = itemData.availableElectronically
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(object),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
        
        // Store type at object level
        self.itemType = object.type
    }
    
    // Convert back to CatalogObject when needed
    func toCatalogObject() -> CatalogObject? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(CatalogObject.self, from: jsonData)
    }
}

// MARK: - Search Extensions
extension CatalogItemModel {
    /// Check if item matches search term
    func matchesSearchTerm(_ searchTerm: String) -> Bool {
        let lowercasedTerm = searchTerm.lowercased()
        
        // Check item name
        if let name = name?.lowercased(), name.contains(lowercasedTerm) {
            return true
        }
        
        // Check SKUs and UPCs in variations
        if let variations = variations {
            for variation in variations {
                if let sku = variation.sku?.lowercased(), sku.contains(lowercasedTerm) {
                    return true
                }
                if let upc = variation.upc, upc == searchTerm {
                    return true
                }
            }
        }
        
        // Check category names
        if let categoryName = categoryName?.lowercased(), categoryName.contains(lowercasedTerm) {
            return true
        }
        
        return false
    }
    
    /// Get match type for search result ranking
    func getMatchType(for searchTerm: String) -> String {
        let lowercasedTerm = searchTerm.lowercased()
        
        // Exact UPC match is highest priority
        if let variations = variations {
            for variation in variations {
                if variation.upc == searchTerm {
                    return "upc"
                }
            }
        }
        
        // SKU match
        if let variations = variations {
            for variation in variations {
                if let sku = variation.sku?.lowercased(), sku.contains(lowercasedTerm) {
                    return "sku"
                }
            }
        }
        
        // Name match
        if let name = name?.lowercased(), name.contains(lowercasedTerm) {
            return "name"
        }
        
        return "other"
    }
}