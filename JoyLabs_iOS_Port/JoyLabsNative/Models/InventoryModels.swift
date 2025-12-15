import Foundation

// MARK: - Inventory Adjustment Reason
/// Represents the reason for an inventory adjustment - maps to Square's adjustment types and UI display
enum InventoryAdjustmentReason: String, CaseIterable, Codable {
    case stockReceived = "STOCK_RECEIVED"
    case inventoryRecount = "INVENTORY_RECOUNT"
    case damage = "DAMAGE"
    case theft = "THEFT"
    case loss = "LOSS"
    case restockReturn = "RESTOCK_RETURN"

    var displayName: String {
        switch self {
        case .stockReceived:
            return "Stock received"
        case .inventoryRecount:
            return "Inventory re-count"
        case .damage:
            return "Damage"
        case .theft:
            return "Theft"
        case .loss:
            return "Loss"
        case .restockReturn:
            return "Restock return"
        }
    }

    var fieldLabel: String {
        switch self {
        case .stockReceived, .restockReturn:
            return "Received"
        case .inventoryRecount:
            return "In Stock"
        case .damage, .theft, .loss:
            return "Remove stock"
        }
    }

    var isAdditive: Bool {
        switch self {
        case .stockReceived, .restockReturn:
            return true
        case .damage, .theft, .loss:
            return false
        case .inventoryRecount:
            return false // Absolute, not additive/subtractive
        }
    }

    var isAbsolute: Bool {
        return self == .inventoryRecount
    }

    /// Maps to Square API change type
    var squareChangeType: String {
        switch self {
        case .inventoryRecount:
            return "PHYSICAL_COUNT"
        default:
            return "ADJUSTMENT"
        }
    }

    /// Maps to Square API states for ADJUSTMENT type
    func getSquareStates() -> (fromState: String, toState: String) {
        switch self {
        case .stockReceived, .restockReturn:
            return ("NONE", "IN_STOCK")
        case .damage, .theft, .loss:
            return ("IN_STOCK", "WASTE")
        case .inventoryRecount:
            return ("", "") // Physical counts don't use from/to states
        }
    }
}

// MARK: - Inventory State
/// Square inventory states
enum InventoryState: String, Codable {
    case inStock = "IN_STOCK"
    case sold = "SOLD"
    case returnedByCustomer = "RETURNED_BY_CUSTOMER"
    case reservedForSale = "RESERVED_FOR_SALE"
    case soldOnline = "SOLD_ONLINE"
    case orderedFromVendor = "ORDERED_FROM_VENDOR"
    case receivedFromVendor = "RECEIVED_FROM_VENDOR"
    case none = "NONE"
    case waste = "WASTE"
    case unlinkedReturn = "UNLINKED_RETURN"
    case custom = "CUSTOM"
    case composed = "COMPOSED"
    case decomposed = "DECOMPOSED"
    case inTransit = "IN_TRANSIT"

    var displayName: String {
        switch self {
        case .inStock: return "In Stock"
        case .sold: return "Sold"
        case .returnedByCustomer: return "Returned by Customer"
        case .reservedForSale: return "Reserved for Sale"
        case .soldOnline: return "Sold Online"
        case .orderedFromVendor: return "Ordered from Vendor"
        case .receivedFromVendor: return "Received from Vendor"
        case .none: return "None"
        case .waste: return "Waste"
        case .unlinkedReturn: return "Unlinked Return"
        case .custom: return "Custom"
        case .composed: return "Composed"
        case .decomposed: return "Decomposed"
        case .inTransit: return "In Transit"
        }
    }
}

// MARK: - Inventory Count Data
/// Represents current inventory count for a variation at a specific location
struct InventoryCountData: Codable, Equatable {
    let catalogObjectId: String
    let catalogObjectType: String // "ITEM_VARIATION"
    let state: String // "IN_STOCK", etc.
    let locationId: String
    let quantity: String // Square uses string for decimal precision
    let calculatedAt: String // RFC 3339 timestamp

    var quantityInt: Int {
        return Int(quantity) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case catalogObjectId = "catalog_object_id"
        case catalogObjectType = "catalog_object_type"
        case state
        case locationId = "location_id"
        case quantity
        case calculatedAt = "calculated_at"
    }
}

// MARK: - Inventory Physical Count
/// Represents a physical count operation (absolute quantity)
struct InventoryPhysicalCount: Codable {
    let referenceId: String? // Client-provided unique ID
    let catalogObjectId: String // Variation ID
    let state: String // "IN_STOCK"
    let locationId: String
    let quantity: String // Decimal string
    let teamMemberId: String? // Optional
    let occurredAt: String // RFC 3339 timestamp

    enum CodingKeys: String, CodingKey {
        case referenceId = "reference_id"
        case catalogObjectId = "catalog_object_id"
        case state
        case locationId = "location_id"
        case quantity
        case teamMemberId = "team_member_id"
        case occurredAt = "occurred_at"
    }
}

// MARK: - Inventory Adjustment
/// Represents an inventory adjustment (state transition)
struct InventoryAdjustment: Codable {
    let referenceId: String? // Client-provided unique ID
    let fromState: String // "IN_STOCK", "NONE", etc.
    let toState: String // "WASTE", "IN_STOCK", etc.
    let catalogObjectId: String // Variation ID
    let locationId: String
    let quantity: String // Decimal string
    let teamMemberId: String? // Optional
    let occurredAt: String // RFC 3339 timestamp

    enum CodingKeys: String, CodingKey {
        case referenceId = "reference_id"
        case fromState = "from_state"
        case toState = "to_state"
        case catalogObjectId = "catalog_object_id"
        case locationId = "location_id"
        case quantity
        case teamMemberId = "team_member_id"
        case occurredAt = "occurred_at"
    }
}

// MARK: - Inventory Change
/// Wrapper for either physical count or adjustment
struct InventoryChange: Codable {
    let type: String // "PHYSICAL_COUNT" or "ADJUSTMENT"
    let physicalCount: InventoryPhysicalCount?
    let adjustment: InventoryAdjustment?

    enum CodingKeys: String, CodingKey {
        case type
        case physicalCount = "physical_count"
        case adjustment
    }

    /// Create a physical count change
    static func physicalCount(
        catalogObjectId: String,
        locationId: String,
        quantity: String,
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> InventoryChange {
        let count = InventoryPhysicalCount(
            referenceId: UUID().uuidString,
            catalogObjectId: catalogObjectId,
            state: "IN_STOCK",
            locationId: locationId,
            quantity: quantity,
            teamMemberId: nil,
            occurredAt: occurredAt
        )
        return InventoryChange(
            type: "PHYSICAL_COUNT",
            physicalCount: count,
            adjustment: nil
        )
    }

    /// Create an adjustment change
    static func adjustment(
        catalogObjectId: String,
        locationId: String,
        fromState: String,
        toState: String,
        quantity: String,
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> InventoryChange {
        let adj = InventoryAdjustment(
            referenceId: UUID().uuidString,
            fromState: fromState,
            toState: toState,
            catalogObjectId: catalogObjectId,
            locationId: locationId,
            quantity: quantity,
            teamMemberId: nil,
            occurredAt: occurredAt
        )
        return InventoryChange(
            type: "ADJUSTMENT",
            physicalCount: nil,
            adjustment: adj
        )
    }
}

// MARK: - Batch Change Inventory Request
/// Request body for POST /v2/inventory/changes/batch-create
struct BatchChangeInventoryRequest: Codable {
    let idempotencyKey: String
    let changes: [InventoryChange]
    let ignoreUnchangedCounts: Bool?

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case changes
        case ignoreUnchangedCounts = "ignore_unchanged_counts"
    }
}

// MARK: - Batch Change Inventory Response
/// Response from POST /v2/inventory/changes/batch-create
struct BatchChangeInventoryResponse: Codable {
    let errors: [SquareError]?
    let counts: [InventoryCountData]?
    let changes: [InventoryChange]? // Beta feature
}

// MARK: - Inventory Count Updated Event (Webhook)
/// Payload for inventory.count.updated webhook
struct InventoryCountUpdatedEvent: Codable {
    let merchantId: String
    let type: String // "inventory.count.updated"
    let eventId: String
    let createdAt: String
    let data: InventoryCountUpdatedEventData

    enum CodingKeys: String, CodingKey {
        case merchantId = "merchant_id"
        case type
        case eventId = "event_id"
        case createdAt = "created_at"
        case data
    }
}

struct InventoryCountUpdatedEventData: Codable {
    let type: String // "inventory_counts"
    let id: String
    let object: InventoryCountUpdatedObject
}

struct InventoryCountUpdatedObject: Codable {
    let inventoryCounts: [InventoryCountData]

    enum CodingKeys: String, CodingKey {
        case inventoryCounts = "inventory_counts"
    }
}

// MARK: - UI Data Models

/// Represents inventory data for a variation at a specific location (for UI display)
struct VariationInventoryData: Identifiable, Equatable {
    let id = UUID()
    let variationId: String
    let locationId: String
    var stockOnHand: Int?
    var committed: Int?
    var availableToSell: Int?

    var hasInventory: Bool {
        return stockOnHand != nil
    }

    var displayStockOnHand: String {
        guard let stock = stockOnHand else { return "N/A" }
        return "\(stock)"
    }

    var displayCommitted: String {
        return "\(committed ?? 0)"
    }

    var displayAvailableToSell: String {
        guard let available = availableToSell else { return "N/A" }
        return "\(available)"
    }
}

/// Represents a pending inventory adjustment (before sending to Square)
struct PendingInventoryAdjustment {
    let variationId: String
    let locationId: String
    let reason: InventoryAdjustmentReason
    let quantity: Int
    let currentStock: Int?

    var newTotal: Int {
        guard let current = currentStock else { return quantity }

        switch reason {
        case .stockReceived, .restockReturn:
            return current + quantity
        case .damage, .theft, .loss:
            return current - quantity
        case .inventoryRecount:
            return quantity // Absolute
        }
    }

    var variance: Int {
        guard reason == .inventoryRecount, let current = currentStock else { return 0 }
        return quantity - current
    }
}
