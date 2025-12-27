import Foundation
import SwiftData

// MARK: - SwiftData Model for Item Variations
// Replaces SQLite.swift item_variations table with native SwiftData persistence
@Model
final class ItemVariationModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var itemId: String  // Keep for reference even with relationship
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Variation fields
    var name: String?
    @Attribute(.spotlight) var sku: String?
    @Attribute(.spotlight) var upc: String?
    var ordinal: Int?
    var pricingType: String?
    
    // Price information
    var priceAmount: Int64?  // In cents
    var priceCurrency: String?
    
    // Location settings (variations inherit from parent item but can have overrides)
    var presentAtAllLocations: Bool?
    var presentAtLocationIds: [String]?
    var absentAtLocationIds: [String]?
    
    // Inventory and stock
    var sellable: Bool?
    var stockable: Bool?
    var measurementUnitId: String?
    
    // Additional fields from SQLite implementation
    var basePriceMoney: String?  // JSON string
    var defaultUnitCost: String?  // JSON string
    
    // Store complete variation data as JSON for complex operations
    var dataJson: String?

    // Inverse relationship to parent item
    @Relationship(inverse: \CatalogItemModel.variations) var item: CatalogItemModel?

    // Relationship to inventory counts (one-to-many: one variation can have counts at multiple locations)
    @Relationship(deleteRule: .cascade) var inventoryCounts: [InventoryCountModel]?

    // Computed properties
    var formattedPrice: String? {
        guard let amount = priceAmount, amount > 0 else { return nil }
        let price = Double(amount) / 100.0
        return String(format: "$%.2f", price)
    }
    
    var priceInDollars: Double? {
        guard let amount = priceAmount, amount > 0 else { return nil }
        return Double(amount) / 100.0
    }
    
    init(
        id: String,
        itemId: String,
        updatedAt: Date = Date(),
        version: String = "0",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.itemId = itemId
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
        
        if let variationData = object.itemVariationData {
            self.itemId = variationData.itemId
            self.name = variationData.name
            self.sku = variationData.sku
            self.upc = variationData.upc
            self.ordinal = variationData.ordinal
            self.pricingType = variationData.pricingType
            
            // Price information
            if let priceMoney = variationData.priceMoney {
                self.priceAmount = priceMoney.amount
                self.priceCurrency = priceMoney.currency
            }
            
            // Stock settings
            self.sellable = variationData.sellable
            self.stockable = variationData.stockable
            self.measurementUnitId = variationData.measurementUnitId
            
            // Store full JSON for complex operations (store complete object, not just variationData)
            if let jsonData = try? JSONEncoder().encode(object),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to ItemVariationData when needed
    func toItemVariationData() -> ItemVariationData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        // Decode as CatalogObject (what's actually stored), then extract itemVariationData
        guard let catalogObject = try? JSONDecoder().decode(CatalogObject.self, from: jsonData) else {
            return nil
        }

        return catalogObject.itemVariationData
    }
}