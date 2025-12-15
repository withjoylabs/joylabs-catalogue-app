import Foundation
import SwiftData

// MARK: - SwiftData Model for Inventory Counts
/// Stores current inventory counts for item variations at specific locations
/// Maps to Square's InventoryCount object from inventory.count.updated webhooks
@Model
final class InventoryCountModel {
    // Core identifiers
    @Attribute(.unique) var id: String // Composite: "variationId_locationId_state"
    var catalogObjectId: String // Variation ID
    var catalogObjectType: String // "ITEM_VARIATION"
    var locationId: String
    var state: String // "IN_STOCK", "SOLD", etc.

    // Count data
    var quantity: String // Square uses string for decimal precision
    var calculatedAt: Date // When Square calculated this count
    var updatedAt: Date // When we last updated this record

    // Inverse relationship to variation
    @Relationship(inverse: \ItemVariationModel.inventoryCounts) var variation: ItemVariationModel?

    // Computed properties
    var quantityInt: Int {
        return Int(quantity) ?? 0
    }

    var displayQuantity: String {
        let qty = quantityInt
        return qty >= 0 ? "\(qty)" : "N/A"
    }

    init(
        catalogObjectId: String,
        catalogObjectType: String = "ITEM_VARIATION",
        locationId: String,
        state: String = "IN_STOCK",
        quantity: String = "0",
        calculatedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        // Create composite ID for uniqueness
        self.id = "\(catalogObjectId)_\(locationId)_\(state)"
        self.catalogObjectId = catalogObjectId
        self.catalogObjectType = catalogObjectType
        self.locationId = locationId
        self.state = state
        self.quantity = quantity
        self.calculatedAt = calculatedAt
        self.updatedAt = updatedAt
    }

    /// Update from Square API InventoryCountData
    func updateFromInventoryCount(_ countData: InventoryCountData) {
        self.quantity = countData.quantity

        // Parse RFC 3339 timestamp from Square
        if let calculatedDate = ISO8601DateFormatter().date(from: countData.calculatedAt) {
            self.calculatedAt = calculatedDate
        }

        self.updatedAt = Date()
    }

    /// Create or update from Square API response
    static func createOrUpdate(
        from countData: InventoryCountData,
        in context: ModelContext
    ) -> InventoryCountModel {
        let compositeId = "\(countData.catalogObjectId)_\(countData.locationId)_\(countData.state)"

        // Try to find existing record
        let predicate = #Predicate<InventoryCountModel> { model in
            model.id == compositeId
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let existing = try? context.fetch(descriptor).first {
            // Update existing
            existing.updateFromInventoryCount(countData)
            return existing
        } else {
            // Create new
            let calculatedDate = ISO8601DateFormatter().date(from: countData.calculatedAt) ?? Date()
            let newCount = InventoryCountModel(
                catalogObjectId: countData.catalogObjectId,
                catalogObjectType: countData.catalogObjectType,
                locationId: countData.locationId,
                state: countData.state,
                quantity: countData.quantity,
                calculatedAt: calculatedDate,
                updatedAt: Date()
            )
            context.insert(newCount)
            return newCount
        }
    }

    /// Fetch inventory count for specific variation and location
    static func fetchCount(
        variationId: String,
        locationId: String,
        state: String = "IN_STOCK",
        in context: ModelContext
    ) -> InventoryCountModel? {
        let compositeId = "\(variationId)_\(locationId)_\(state)"

        let predicate = #Predicate<InventoryCountModel> { model in
            model.id == compositeId
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        return try? context.fetch(descriptor).first
    }

    /// Fetch all inventory counts for a variation across all locations
    static func fetchCountsForVariation(
        variationId: String,
        state: String = "IN_STOCK",
        in context: ModelContext
    ) -> [InventoryCountModel] {
        let predicate = #Predicate<InventoryCountModel> { model in
            model.catalogObjectId == variationId && model.state == state
        }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.locationId)])

        return (try? context.fetch(descriptor)) ?? []
    }
}
