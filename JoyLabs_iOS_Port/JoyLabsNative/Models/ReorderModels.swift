import Foundation
import SwiftUI

// MARK: - Reorder Item Model
struct ReorderItem: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let itemId: String // Reference to Square catalog item
    var name: String // Made mutable to allow updates from database
    var sku: String? // Made mutable to allow updates from database
    var barcode: String? // Made mutable to allow updates from database
    var variationName: String? // Made mutable to allow updates from database
    var quantity: Int
    var status: ReorderItemStatus
    var addedDate: Date
    var purchasedDate: Date?
    var receivedDate: Date?
    var notes: String?
    var priority: ReorderItemPriority = .normal

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
    var hasTax: Bool = false

    init(id: String, itemId: String, name: String, sku: String? = nil, barcode: String? = nil, variationName: String? = nil, quantity: Int, status: ReorderItemStatus = .added, addedDate: Date = Date(), notes: String? = nil) {
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
    }
    
    // MARK: - SwiftUI Reactivity (Critical for UI Updates)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(price)        // Detect price changes from catalog updates
        hasher.combine(name)         // Detect name changes from catalog updates  
        hasher.combine(sku)          // Detect SKU changes from catalog updates
        hasher.combine(barcode)      // Detect barcode changes from catalog updates
        hasher.combine(categoryName) // Detect category changes from catalog updates
        hasher.combine(imageUrl)     // Detect image changes from catalog updates
        hasher.combine(vendor)       // Detect vendor changes from catalog updates
        hasher.combine(quantity)     // Detect quantity changes from user actions
        hasher.combine(status)       // Detect status changes from user actions
        hasher.combine(variationName)// Detect variation changes from catalog updates
        hasher.combine(hasTax)       // Detect tax changes from catalog updates
        hasher.combine(caseCost)     // Detect case cost changes from catalog updates
        hasher.combine(caseQuantity) // Detect case quantity changes from catalog updates
        hasher.combine(caseUpc)      // Detect case UPC changes from catalog updates
    }
    
    static func == (lhs: ReorderItem, rhs: ReorderItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.price == rhs.price &&
        lhs.name == rhs.name &&
        lhs.sku == rhs.sku &&
        lhs.barcode == rhs.barcode &&
        lhs.categoryName == rhs.categoryName &&
        lhs.imageUrl == rhs.imageUrl &&
        lhs.vendor == rhs.vendor &&
        lhs.quantity == rhs.quantity &&
        lhs.status == rhs.status &&
        lhs.variationName == rhs.variationName &&
        lhs.hasTax == rhs.hasTax &&
        lhs.caseCost == rhs.caseCost &&
        lhs.caseQuantity == rhs.caseQuantity &&
        lhs.caseUpc == rhs.caseUpc
    }
}

// MARK: - Reorder Status (3-stage workflow)
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

// MARK: - Reorder Priority
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

// MARK: - Reorder Sort Options
enum ReorderSortOption: String, CaseIterable {
    case timeNewest = "time_newest"
    case timeOldest = "time_oldest"
    case alphabeticalAZ = "alphabetical_az"
    case alphabeticalZA = "alphabetical_za"

    var displayName: String {
        switch self {
        case .timeNewest: return "Most Recent"
        case .timeOldest: return "Oldest First"
        case .alphabeticalAZ: return "A to Z"
        case .alphabeticalZA: return "Z to A"
        }
    }

    var systemImageName: String {
        switch self {
        case .timeNewest, .timeOldest: return "clock"
        case .alphabeticalAZ, .alphabeticalZA: return "textformat"
        }
    }
}

// MARK: - Reorder Filter Options
enum ReorderFilterOption: String, CaseIterable {
    case all = "all"
    case unpurchased = "unpurchased"
    case purchased = "purchased"
    case received = "received"

    var displayName: String {
        switch self {
        case .all: return "All Items"
        case .unpurchased: return "Unpurchased"
        case .purchased: return "Purchased"
        case .received: return "Received"
        }
    }
}

// MARK: - Reorder Organization Options
enum ReorderOrganizationOption: String, CaseIterable {
    case none = "none"
    case category = "category"
    case vendor = "vendor"
    case vendorThenCategory = "vendor_then_category"

    var displayName: String {
        switch self {
        case .none: return "No Grouping"
        case .category: return "By Category"
        case .vendor: return "By Vendor"
        case .vendorThenCategory: return "By Vendor, then Category"
        }
    }

    var systemImageName: String {
        switch self {
        case .none: return "list.bullet"
        case .category: return "folder"
        case .vendor: return "building.2"
        case .vendorThenCategory: return "building.2.crop.circle"
        }
    }
}

// MARK: - Reorder Display Mode Options
enum ReorderDisplayMode: String, CaseIterable {
    case list = "list"
    case photosLarge = "photos_large"
    case photosMedium = "photos_medium"
    case photosSmall = "photos_small"

    var displayName: String {
        switch self {
        case .list: return "List View"
        case .photosLarge: return "Large Photos"
        case .photosMedium: return "Medium Photos"
        case .photosSmall: return "Small Photos"
        }
    }

    var systemImageName: String {
        switch self {
        case .list: return "list.bullet"
        case .photosLarge: return "rectangle.grid.1x2"
        case .photosMedium: return "rectangle.grid.2x2"
        case .photosSmall: return "rectangle.grid.3x2"
        }
    }

    var columnsPerRow: Int {
        switch self {
        case .list: return 1
        case .photosLarge: return 1
        case .photosMedium: return 2
        case .photosSmall: return 3
        }
    }

    var showDetails: Bool {
        switch self {
        case .list: return true
        case .photosLarge: return true
        case .photosMedium: return true
        case .photosSmall: return false
        }
    }
}

#Preview("Reorder Item") {
    let item = ReorderItem(id: "1", itemId: "square-item-1", name: "Coffee Beans", sku: "COF001", variationName: "Dark Roast", quantity: 5, status: .added)
    Text("Item: \(item.name) - Qty: \(item.quantity) - Status: \(item.status.displayName)")
}