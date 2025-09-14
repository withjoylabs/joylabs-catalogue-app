import Foundation
import SwiftData

// MARK: - SwiftData Model for Reorder Items  
// Elegant computed properties eliminate data duplication
@Model
final class ReorderItemModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var catalogItemId: String  // Reference to Square catalog item (renamed for clarity)
    
    // Reorder-specific data ONLY (no catalog duplicates)
    var quantity: Int
    var status: String
    var addedDate: Date
    var purchasedDate: Date?
    var receivedDate: Date?
    var notes: String?
    var priority: String
    var lastUpdated: Date
    
    // Optional overrides (only store if different from catalog)
    var nameOverride: String?      // Custom name if different from catalog
    var notesInternal: String?     // Internal notes separate from catalog
    
    // MARK: - Computed Properties (Live Catalog Lookups)
    
    /// Get catalog item (cached lookup) - MainActor required
    @MainActor
    var catalogItem: CatalogItemModel? {
        return CatalogLookupService.shared.getItem(id: catalogItemId)
    }
    
    /// Item name (override or catalog)
    var name: String {
        if let nameOverride = nameOverride {
            return nameOverride
        }
        
        // Use MainActor.assumeIsolated for synchronous access in computed properties
        let catalogName = MainActor.assumeIsolated {
            CatalogLookupService.shared.getItem(id: catalogItemId)?.name
        }
        return catalogName ?? "Unknown Item"
    }
    
    /// Current catalog SKU
    var sku: String? {
        return MainActor.assumeIsolated {
            CatalogLookupService.shared.getSku(for: catalogItemId)
        }
    }
    
    /// Current catalog barcode/UPC
    var barcode: String? {
        return MainActor.assumeIsolated {
            CatalogLookupService.shared.getBarcode(for: catalogItemId)
        }
    }
    
    /// Current catalog variation name
    var variationName: String? {
        return MainActor.assumeIsolated {
            CatalogLookupService.shared.getVariationName(for: catalogItemId)
        }
    }
    
    /// Current catalog category name
    var categoryName: String? {
        return MainActor.assumeIsolated {
            let item = CatalogLookupService.shared.getItem(id: catalogItemId)
            return item?.reportingCategoryName ?? item?.categoryName
        }
    }
    
    /// Current catalog price (live lookup)
    var price: Double? {
        return MainActor.assumeIsolated {
            CatalogLookupService.shared.getCurrentPrice(for: catalogItemId)
        }
    }
    
    /// Current catalog image URL (live lookup from SwiftData)
    var imageUrl: String? {
        return MainActor.assumeIsolated {
            let item = CatalogLookupService.shared.getItem(id: catalogItemId)
            return item?.primaryImageUrl
        }
    }
    
    /// Tax status from catalog
    var hasTax: Bool {
        return MainActor.assumeIsolated {
            CatalogLookupService.shared.getHasTax(for: catalogItemId)
        }
    }
    
    /// Get current image URL asynchronously
    @MainActor
    func getCurrentImageUrl() async -> String? {
        return await CatalogLookupService.shared.getPrimaryImageURL(for: catalogItemId)
    }
    
    // MARK: - Enum Computed Properties
    
    var statusEnum: ReorderItemStatus {
        get { ReorderItemStatus(rawValue: status) ?? .added }
        set { status = newValue.rawValue }
    }
    
    var priorityEnum: ReorderItemPriority {
        get { ReorderItemPriority(rawValue: priority) ?? .normal }
        set { priority = newValue.rawValue }
    }
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        catalogItemId: String,
        quantity: Int = 1,
        status: ReorderItemStatus = .added,
        addedDate: Date = Date(),
        notes: String? = nil,
        priority: ReorderItemPriority = .normal,
        nameOverride: String? = nil
    ) {
        self.id = id
        self.catalogItemId = catalogItemId
        self.quantity = quantity
        self.status = status.rawValue
        self.addedDate = addedDate
        self.notes = notes
        self.priority = priority.rawValue
        self.nameOverride = nameOverride
        self.lastUpdated = Date()
    }
    
    // MARK: - Helper Methods
    
    /// Update reorder-specific fields only (catalog data updates automatically)
    func updateReorderData(
        quantity: Int? = nil,
        notes: String? = nil,
        priority: ReorderItemPriority? = nil,
        nameOverride: String? = nil
    ) {
        if let quantity = quantity { self.quantity = quantity }
        if let notes = notes { self.notes = notes }
        if let priority = priority { self.priority = priority.rawValue }
        if let nameOverride = nameOverride { self.nameOverride = nameOverride }
        self.lastUpdated = Date()
    }
    
    /// Clear any custom overrides to use pure catalog data
    func clearOverrides() {
        self.nameOverride = nil
        self.lastUpdated = Date()
    }
}

