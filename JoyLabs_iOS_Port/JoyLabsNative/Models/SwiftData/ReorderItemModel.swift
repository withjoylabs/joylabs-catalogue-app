import Foundation
import SwiftData

// MARK: - SwiftData Model for Reorder Items
// Single source of truth - SwiftData handles all persistence automatically
@Model
final class ReorderItemModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var itemId: String  // Reference to Square catalog item
    
    // Item details (mutable, updated from catalog)
    var name: String
    var sku: String?
    var barcode: String?
    var variationName: String?
    
    // Reorder-specific data
    var quantity: Int
    var status: String
    var addedDate: Date
    var purchasedDate: Date?
    var receivedDate: Date?
    var notes: String?
    var priority: String
    
    // Team data fields (from team_data table)
    var vendor: String?
    var unitCost: Double?
    var caseUpc: String?
    var caseCost: Double?
    var caseQuantity: Int?
    
    // Catalog data fields
    var categoryName: String?
    var price: Double?
    var imageUrl: String?
    var imageId: String?
    var hasTax: Bool
    
    // Timestamp for updates
    var lastUpdated: Date
    
    
    // Computed properties for enum access
    var statusEnum: ReorderItemStatus {
        get { ReorderItemStatus(rawValue: status) ?? .added }
        set { status = newValue.rawValue }
    }
    
    var priorityEnum: ReorderItemPriority {
        get { ReorderItemPriority(rawValue: priority) ?? .normal }
        set { priority = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        itemId: String,
        name: String,
        sku: String? = nil,
        barcode: String? = nil,
        variationName: String? = nil,
        quantity: Int = 1,
        status: ReorderItemStatus = .added,
        addedDate: Date = Date(),
        notes: String? = nil,
        priority: ReorderItemPriority = .normal
    ) {
        self.id = id
        self.itemId = itemId
        self.name = name
        self.sku = sku
        self.barcode = barcode
        self.variationName = variationName
        self.quantity = quantity
        self.status = status.rawValue
        self.addedDate = addedDate
        self.notes = notes
        self.priority = priority.rawValue
        self.hasTax = false
        self.lastUpdated = Date()
    }
    
    // Update catalog fields from fresh data
    func updateFromCatalog(
        name: String? = nil,
        sku: String? = nil,
        barcode: String? = nil,
        price: Double? = nil,
        categoryName: String? = nil,
        hasTax: Bool? = nil,
        vendor: String? = nil,
        caseUpc: String? = nil,
        caseCost: Double? = nil,
        caseQuantity: Int? = nil,
        imageUrl: String? = nil
    ) {
        if let name = name { self.name = name }
        if let sku = sku { self.sku = sku }
        if let barcode = barcode { self.barcode = barcode }
        if let price = price { self.price = price }
        if let categoryName = categoryName { self.categoryName = categoryName }
        if let hasTax = hasTax { self.hasTax = hasTax }
        if let vendor = vendor { self.vendor = vendor }
        if let caseUpc = caseUpc { self.caseUpc = caseUpc }
        if let caseCost = caseCost { self.caseCost = caseCost }
        if let caseQuantity = caseQuantity { self.caseQuantity = caseQuantity }
        if let imageUrl = imageUrl { self.imageUrl = imageUrl }
        self.lastUpdated = Date()
    }
}

