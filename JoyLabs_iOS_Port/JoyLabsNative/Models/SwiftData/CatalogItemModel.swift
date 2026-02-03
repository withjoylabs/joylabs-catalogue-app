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

    // Image IDs (per Square API: first ID is primary/icon image)
    var imageIds: [String]?

    // CRITICAL: Direct access to IDs for UI without JSON parsing
    // These enable proper checkbox state for taxes, modifiers, categories
    var taxIds: [String]?  // Tax IDs for checkbox state
    var modifierListIds: [String]?  // Modifier list IDs
    var categoryIds: [String]?  // Category IDs from itemData.categories

    // Additional Square API fields for complete webhook sync
    var isTaxable: Bool?
    var isAlcoholic: Bool?
    var skipModifierScreen: Bool?
    var abbreviation: String?
    var productType: String?
    var sortName: String?

    // Store complete Square API response for complex operations
    var dataJson: String?

    // Relationships
    @Relationship(deleteRule: .cascade) var variations: [ItemVariationModel]?
    @Relationship var category: CategoryModel?
    @Relationship var reportingCategory: CategoryModel?
    @Relationship var taxes: [TaxModel]?
    @Relationship var modifierLists: [ModifierListModel]?
    @Relationship var teamData: TeamDataModel?

    // Computed properties for convenience
    var primaryImageUrl: String? {
        // Per Square API docs: first image in imageIds array is the primary/icon image
        guard let firstImageId = imageIds?.first,
              let context = modelContext else {
            return nil
        }

        // Query SwiftData for the image (SwiftData handles caching internally)
        let descriptor = FetchDescriptor<ImageModel>(
            predicate: #Predicate { $0.id == firstImageId && !$0.isDeleted }
        )

        guard let imageModel = try? context.fetch(descriptor).first else {
            return nil
        }

        return imageModel.url
    }

    var primaryImageId: String? {
        // Per Square API docs: first image in imageIds array is the primary/icon image
        return imageIds?.first
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
    // COMPREHENSIVE extraction - ensures webhook-synced items have ALL data
    func updateFromCatalogObject(_ object: CatalogObject) {
        self.updatedAt = Date()
        self.version = String(object.version ?? 0)
        self.isDeleted = object.isDeleted ?? false
        self.presentAtAllLocations = object.presentAtAllLocations
        self.presentAtLocationIds = object.presentAtLocationIds
        self.absentAtLocationIds = object.absentAtLocationIds

        if let itemData = object.itemData {
            // Basic item fields
            self.name = itemData.name
            self.itemDescription = itemData.description
            self.categoryId = itemData.categoryId
            self.labelColor = itemData.labelColor

            // Availability settings
            self.availableOnline = itemData.availableOnline
            self.availableForPickup = itemData.availableForPickup
            self.availableElectronically = itemData.availableElectronically

            // CRITICAL: Store imageIds array from Square API
            // Per Square docs: imageIds[0] is the primary/icon image
            self.imageIds = itemData.imageIds

            // CRITICAL: Extract taxIds for UI checkbox state
            // This enables taxes to display correctly without JSON parsing
            self.taxIds = itemData.taxIds

            // Extract modifier list IDs from modifierListInfo
            if let modifierListInfo = itemData.modifierListInfo {
                self.modifierListIds = modifierListInfo.compactMap { $0.modifierListId }
            } else {
                self.modifierListIds = nil
            }

            // Extract category IDs from categories array
            if let categories = itemData.categories {
                self.categoryIds = categories.map { $0.id }
            } else {
                self.categoryIds = nil
            }

            // Extract reporting category
            self.reportingCategoryId = itemData.reportingCategory?.id

            // Additional boolean flags
            self.isTaxable = itemData.isTaxable
            self.isAlcoholic = itemData.isAlcoholic
            self.skipModifierScreen = itemData.skipModifierScreen

            // String fields
            self.abbreviation = itemData.abbreviation
            self.productType = itemData.productType
            self.sortName = itemData.sortName

            // Pre-computed names for search/display (if provided by sync)
            if let taxNames = itemData.taxNames {
                self.taxNames = taxNames
            }
            if let modifierNames = itemData.modifierNames {
                self.modifierNames = modifierNames
            }

            // Store full JSON for complex operations and toCatalogObject()
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