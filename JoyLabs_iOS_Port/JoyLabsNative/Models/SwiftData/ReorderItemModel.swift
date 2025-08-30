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
    var status: ReorderItemStatus
    var addedDate: Date
    var purchasedDate: Date?
    var receivedDate: Date?
    var notes: String?
    var priority: ReorderItemPriority
    
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
        self.status = status
        self.addedDate = addedDate
        self.notes = notes
        self.priority = priority
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

// MARK: - Status Enum (Stored as String in SwiftData)
enum ReorderItemStatus: String, CaseIterable, Codable {
    case added = "added"
    case purchased = "purchased"
    case received = "received"
    
    var displayName: String {
        switch self {
        case .added: return "Added"
        case .purchased: return "Purchased"
        case .received: return "Received"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .added: return "circle"
        case .purchased: return "checkmark.circle.fill"
        case .received: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Priority Enum (Stored as String in SwiftData)
enum ReorderItemPriority: String, CaseIterable, Codable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"
    
    var color: String {
        switch self {
        case .low: return "gray"
        case .normal: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}