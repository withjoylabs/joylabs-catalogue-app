import Foundation
import os.log

// ⚠️ CRITICAL RULES FOR SQUARE API INTEGRATION - DO NOT IGNORE ⚠️
//
// 1. SNAKE_CASE vs CAMELCASE MAPPING:
//    - Square API returns JSON with snake_case keys: "category_data", "tax_data", "modifier_data", "image_data", "updated_at", "is_deleted"
//    - Swift models use camelCase properties: categoryData, taxData, modifierData, imageData, updatedAt, isDeleted
//    - ALL structs that decode Square API JSON MUST have CodingKeys to map snake_case → camelCase
//    - Missing CodingKeys will cause JSON decoding to fail silently, resulting in nil data fields
//
// 2. REQUIRED CODINGKEYS FOR ALL SQUARE API MODELS:
//    - CatalogObject: Maps "category_data" → categoryData, "tax_data" → taxData, etc.
//    - CategoryData: Maps "image_ids" → imageIds, "category_type" → categoryType, etc.
//    - TaxData: Maps "calculation_phase" → calculationPhase, "inclusion_type" → inclusionType, etc.
//    - ModifierData: Maps "price_money" → priceMoney, "modifier_list_id" → modifierListId, etc.
//    - ItemVariationData: Maps "item_id" → itemId, "pricing_type" → pricingType, etc.
//
// 3. TESTING REQUIREMENTS:
//    - Always test sync after modifying any CodingKeys
//    - Verify that categoryData, taxData, modifierData, imageData are NOT nil after JSON decoding
//    - Check Square API documentation for exact field names: https://developer.squareup.com/reference/square/catalog-api/list-catalog
//
// 4. DEBUGGING SYNC ISSUES:
//    - If you see "missing categoryData/taxData/modifierData" errors, check CodingKeys first
//    - Use the test button in Catalog Management to debug without full sync
//    - Never assume field names - always verify against Square API docs
//
// 5. SAFE PROPERTIES:
//    - Use safeVersion, safeIsDeleted for database operations to handle nil values gracefully
//    - These provide default values (0, false) when JSON decoding fails

// MARK: - Search Models
struct SearchFilters {
    var name: Bool = true
    var sku: Bool = true
    var barcode: Bool = true
    var category: Bool = false

    init(name: Bool = true, sku: Bool = true, barcode: Bool = true, category: Bool = false) {
        self.name = name
        self.sku = sku
        self.barcode = barcode
        self.category = category
    }
}

// MARK: - Scan History Models
struct ScanHistoryItem: Identifiable, Codable, Hashable {
    let id: String
    let itemId: String  // Catalog item ID for editing
    let scanTime: String
    let name: String?
    let sku: String?
    let price: Double?
    let barcode: String?
    let categoryId: String?
    let categoryName: String?
    let operation: ScanHistoryOperation  // Created or Updated
    let searchContext: String?  // Original search query or scan context

    init(
        id: String,
        itemId: String,
        scanTime: String,
        name: String?,
        sku: String?,
        price: Double?,
        barcode: String?,
        categoryId: String?,
        categoryName: String?,
        operation: ScanHistoryOperation = .created,
        searchContext: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.scanTime = scanTime
        self.name = name
        self.sku = sku
        self.price = price
        self.barcode = barcode
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.operation = operation
        self.searchContext = searchContext
    }
    
    // Hashable conformance for SwiftUI ForEach
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(itemId)
        hasher.combine(operation)
        hasher.combine(name)
        hasher.combine(price)
        hasher.combine(sku)
        hasher.combine(barcode)
        hasher.combine(categoryName)
        hasher.combine(scanTime)
    }
    
    static func == (lhs: ScanHistoryItem, rhs: ScanHistoryItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.itemId == rhs.itemId &&
               lhs.operation == rhs.operation &&
               lhs.name == rhs.name &&
               lhs.price == rhs.price &&
               lhs.sku == rhs.sku &&
               lhs.barcode == rhs.barcode &&
               lhs.categoryName == rhs.categoryName &&
               lhs.scanTime == rhs.scanTime
    }
}

// MARK: - Scan History Operation Type
enum ScanHistoryOperation: String, Codable, CaseIterable {
    case created = "created"
    case updated = "updated"
    
    var displayName: String {
        switch self {
        case .created:
            return "Created"
        case .updated:
            return "Updated"
        }
    }
    
    var systemImage: String {
        switch self {
        case .created:
            return "plus.circle.fill"
        case .updated:
            return "pencil.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .created:
            return "green"
        case .updated:
            return "blue"
        }
    }
}

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let name: String?
    let sku: String?
    let price: Double?
    let barcode: String?
    let reportingCategoryId: String?  // Square's primary category for reporting purposes
    let categoryName: String?
    let variationName: String?
    let images: [CatalogImage]?
    let matchType: String
    let matchContext: String?
    let isFromCaseUpc: Bool
    let caseUpcData: CaseUpcData?
    let hasTax: Bool

    // Hashable conformance - includes ALL mutable fields so SwiftUI detects changes
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(matchType)
        hasher.combine(isFromCaseUpc)
        hasher.combine(price)        // ✅ Now detects price changes
        hasher.combine(name)         // ✅ Now detects name changes
        hasher.combine(sku)          // ✅ Now detects SKU changes
        hasher.combine(barcode)      // ✅ Now detects barcode changes
        hasher.combine(categoryName) // ✅ Now detects category changes
        hasher.combine(variationName) // ✅ Now detects variation name changes
        hasher.combine(hasTax)       // ✅ Now detects tax status changes
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        return lhs.id == rhs.id && 
               lhs.matchType == rhs.matchType && 
               lhs.isFromCaseUpc == rhs.isFromCaseUpc &&
               lhs.price == rhs.price &&        // ✅ Now compares price
               lhs.name == rhs.name &&          // ✅ Now compares name  
               lhs.sku == rhs.sku &&            // ✅ Now compares SKU
               lhs.barcode == rhs.barcode &&    // ✅ Now compares barcode
               lhs.categoryName == rhs.categoryName && // ✅ Now compares category
               lhs.variationName == rhs.variationName && // ✅ Now compares variation name
               lhs.hasTax == rhs.hasTax         // ✅ Now compares tax status
    }
}

// MARK: - Catalog Object Models
struct CatalogObject: Codable {
    let id: String
    let type: String
    let updatedAt: String?  // Make optional since it might be missing
    let version: Int64?     // Make optional since it might be missing
    let isDeleted: Bool?    // Make optional with default
    let presentAtAllLocations: Bool?
    let presentAtLocationIds: [String]?
    let absentAtLocationIds: [String]?
    let itemData: ItemData?
    let categoryData: CategoryData?
    let itemVariationData: ItemVariationData?
    let modifierData: ModifierData?
    let modifierListData: ModifierListData?
    let taxData: TaxData?
    let discountData: DiscountData?
    let imageData: ImageData?

    // Provide default values for missing fields
    var safeUpdatedAt: String {
        return updatedAt ?? ""
    }

    var safeVersion: Int64 {
        return version ?? 0
    }

    var safeIsDeleted: Bool {
        return isDeleted ?? false
    }
    
    /// Calculate if this catalog object is available at a specific location
    /// Based on Square's location availability logic
    func isAvailableAtLocation(_ locationId: String) -> Bool {
        if presentAtAllLocations == true {
            // Available everywhere except explicitly excluded locations
            return !(absentAtLocationIds?.contains(locationId) ?? false)
        } else {
            // Only available at explicitly included locations
            return presentAtLocationIds?.contains(locationId) ?? false
        }
    }
    
    /// Check if item is truly available at ALL current and future locations
    /// (Square Dashboard "Present at all locations" + "Available at future locations" both checked)
    var isAvailableEverywhereIncludingFuture: Bool {
        return presentAtAllLocations == true && (absentAtLocationIds?.isEmpty ?? true)
    }
    
    /// Check if item is available at future locations (Square's "Available at future locations" toggle)
    var isAvailableAtFutureLocations: Bool {
        return presentAtAllLocations == true
    }

    enum CodingKeys: String, CodingKey {
        case id, type
        case updatedAt = "updated_at"
        case version
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case presentAtLocationIds = "present_at_location_ids"
        case absentAtLocationIds = "absent_at_location_ids"
        case itemData = "item_data"
        case categoryData = "category_data"
        case itemVariationData = "item_variation_data"
        case modifierData = "modifier_data"
        case modifierListData = "modifier_list_data"
        case taxData = "tax_data"
        case discountData = "discount_data"
        case imageData = "image_data"
    }

    func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        do {
            let data = try encoder.encode(self)
            let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return dictionary ?? [:]
        } catch {
            let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogModels")
            logger.error("Failed to convert CatalogObject to dictionary: \(error)")
            return [:]
        }
    }
}

// MARK: - Item Data
struct ItemData: Codable {
    let name: String?
    let description: String?
    let categoryId: String?
    let taxIds: [String]?
    let variations: [ItemVariation]?
    let productType: String?
    let skipModifierScreen: Bool?
    let itemOptions: [ItemOption]?
    let modifierListInfo: [ModifierListInfo]?
    let images: [CatalogImage]?
    let labelColor: String?
    let availableOnline: Bool?
    let availableForPickup: Bool?
    let availableElectronically: Bool?
    let abbreviation: String?
    let categories: [CategoryReference]?
    let reportingCategory: ReportingCategory?
    let imageIds: [String]?
    
    // CRITICAL SQUARE API FIELDS - Previously missing
    let isTaxable: Bool?
    let isAlcoholic: Bool?
    let sortName: String?

    // PERFORMANCE OPTIMIZATION: Pre-resolved names stored during sync
    let taxNames: String? // Comma-separated tax names for display
    let modifierNames: String? // Comma-separated modifier names for display

    enum CodingKeys: String, CodingKey {
        case name, description, variations, images, abbreviation
        case categoryId = "category_id"
        case taxIds = "tax_ids"
        case productType = "product_type"
        case skipModifierScreen = "skip_modifier_screen"
        case itemOptions = "item_options"
        case modifierListInfo = "modifier_list_info"
        case labelColor = "label_color"
        case availableOnline = "available_online"
        case availableForPickup = "available_for_pickup"
        case availableElectronically = "available_electronically"
        case categories
        case reportingCategory = "reporting_category"
        case imageIds = "image_ids"
        case isTaxable = "is_taxable"
        case isAlcoholic = "is_alcoholic"
        case sortName = "sort_name"
        case taxNames = "tax_names"
        case modifierNames = "modifier_names"
    }
    
    // CRITICAL: Custom encoding to completely omit imageIds field when nil
    // This prevents Square API from receiving "image_ids": null which would overwrite existing images
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(taxIds, forKey: .taxIds)
        try container.encodeIfPresent(variations, forKey: .variations)
        try container.encodeIfPresent(productType, forKey: .productType)
        try container.encodeIfPresent(skipModifierScreen, forKey: .skipModifierScreen)
        try container.encodeIfPresent(itemOptions, forKey: .itemOptions)
        try container.encodeIfPresent(modifierListInfo, forKey: .modifierListInfo)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(labelColor, forKey: .labelColor)
        try container.encodeIfPresent(availableOnline, forKey: .availableOnline)
        try container.encodeIfPresent(availableForPickup, forKey: .availableForPickup)
        try container.encodeIfPresent(availableElectronically, forKey: .availableElectronically)
        try container.encodeIfPresent(abbreviation, forKey: .abbreviation)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(reportingCategory, forKey: .reportingCategory)
        
        // CRITICAL: Only encode imageIds if it has actual content (not nil or empty)
        // This completely omits the field from JSON when nil, preventing Square from overwriting images
        if let imageIds = imageIds, !imageIds.isEmpty {
            try container.encode(imageIds, forKey: .imageIds)
        }
        // If imageIds is nil or empty, the field is completely omitted from JSON
        
        try container.encodeIfPresent(isTaxable, forKey: .isTaxable)
        try container.encodeIfPresent(isAlcoholic, forKey: .isAlcoholic)
        try container.encodeIfPresent(sortName, forKey: .sortName)
        try container.encodeIfPresent(taxNames, forKey: .taxNames)
        try container.encodeIfPresent(modifierNames, forKey: .modifierNames)
    }
}

struct CategoryReference: Codable {
    let id: String
    let ordinal: Int?
}

struct ReportingCategory: Codable {
    let id: String
    let ordinal: Int64?  // Use Int64 for Square API's "integer(64-bit)"
}

struct ItemVariation: Codable {
    let id: String?
    let type: String?
    let updatedAt: String?
    let version: Int64?
    let isDeleted: Bool?
    let presentAtAllLocations: Bool?
    let presentAtLocationIds: [String]?
    let absentAtLocationIds: [String]?
    let itemVariationData: ItemVariationData?
    
    // Provide default value for missing version field
    var safeVersion: Int64 {
        return version ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, version
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case presentAtLocationIds = "present_at_location_ids"
        case absentAtLocationIds = "absent_at_location_ids"
        case itemVariationData = "item_variation_data"
    }
}

struct ItemVariationData: Codable {
    let itemId: String  // Required by Square API - variations must have parent item
    let name: String?
    let sku: String?
    let upc: String?
    let ordinal: Int?
    let pricingType: String?
    let priceMoney: Money?
    let basePriceMoney: Money?
    let defaultUnitCost: Money?
    let locationOverrides: [LocationOverride]?
    let trackInventory: Bool?
    let inventoryAlertType: String?
    let inventoryAlertThreshold: Int64?
    let userData: String?
    let serviceDuration: Int64?
    let availableForBooking: Bool?
    let itemOptionValues: [ItemOptionValue]?
    let measurementUnitId: String?
    let sellable: Bool?
    let stockable: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, sku, upc, ordinal
        case itemId = "item_id"
        case pricingType = "pricing_type"
        case priceMoney = "price_money"
        case basePriceMoney = "base_price_money"
        case defaultUnitCost = "default_unit_cost"
        case locationOverrides = "location_overrides"
        case trackInventory = "track_inventory"
        case inventoryAlertType = "inventory_alert_type"
        case inventoryAlertThreshold = "inventory_alert_threshold"
        case userData = "user_data"
        case serviceDuration = "service_duration"
        case availableForBooking = "available_for_booking"
        case itemOptionValues = "item_option_values"
        case measurementUnitId = "measurement_unit_id"
        case sellable, stockable
    }
    
    // Memberwise initializer (required when providing custom decoder)
    init(
        itemId: String,
        name: String? = nil,
        sku: String? = nil,
        upc: String? = nil,
        ordinal: Int? = nil,
        pricingType: String? = nil,
        priceMoney: Money? = nil,
        basePriceMoney: Money? = nil,
        defaultUnitCost: Money? = nil,
        locationOverrides: [LocationOverride]? = nil,
        trackInventory: Bool? = nil,
        inventoryAlertType: String? = nil,
        inventoryAlertThreshold: Int64? = nil,
        userData: String? = nil,
        serviceDuration: Int64? = nil,
        availableForBooking: Bool? = nil,
        itemOptionValues: [ItemOptionValue]? = nil,
        measurementUnitId: String? = nil,
        sellable: Bool? = nil,
        stockable: Bool? = nil
    ) {
        self.itemId = itemId
        self.name = name
        self.sku = sku
        self.upc = upc
        self.ordinal = ordinal
        self.pricingType = pricingType
        self.priceMoney = priceMoney
        self.basePriceMoney = basePriceMoney
        self.defaultUnitCost = defaultUnitCost
        self.locationOverrides = locationOverrides
        self.trackInventory = trackInventory
        self.inventoryAlertType = inventoryAlertType
        self.inventoryAlertThreshold = inventoryAlertThreshold
        self.userData = userData
        self.serviceDuration = serviceDuration
        self.availableForBooking = availableForBooking
        self.itemOptionValues = itemOptionValues
        self.measurementUnitId = measurementUnitId
        self.sellable = sellable
        self.stockable = stockable
    }
    
    // Custom decoder to handle orphaned variations (missing item_id)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Gracefully handle missing item_id for orphaned variations
        self.itemId = try container.decodeIfPresent(String.self, forKey: .itemId) ?? ""
        
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.sku = try container.decodeIfPresent(String.self, forKey: .sku)
        self.upc = try container.decodeIfPresent(String.self, forKey: .upc)
        self.ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        self.pricingType = try container.decodeIfPresent(String.self, forKey: .pricingType)
        self.priceMoney = try container.decodeIfPresent(Money.self, forKey: .priceMoney)
        self.basePriceMoney = try container.decodeIfPresent(Money.self, forKey: .basePriceMoney)
        self.defaultUnitCost = try container.decodeIfPresent(Money.self, forKey: .defaultUnitCost)
        self.locationOverrides = try container.decodeIfPresent([LocationOverride].self, forKey: .locationOverrides)
        self.trackInventory = try container.decodeIfPresent(Bool.self, forKey: .trackInventory)
        self.inventoryAlertType = try container.decodeIfPresent(String.self, forKey: .inventoryAlertType)
        self.inventoryAlertThreshold = try container.decodeIfPresent(Int64.self, forKey: .inventoryAlertThreshold)
        self.userData = try container.decodeIfPresent(String.self, forKey: .userData)
        self.serviceDuration = try container.decodeIfPresent(Int64.self, forKey: .serviceDuration)
        self.availableForBooking = try container.decodeIfPresent(Bool.self, forKey: .availableForBooking)
        self.itemOptionValues = try container.decodeIfPresent([ItemOptionValue].self, forKey: .itemOptionValues)
        self.measurementUnitId = try container.decodeIfPresent(String.self, forKey: .measurementUnitId)
        self.sellable = try container.decodeIfPresent(Bool.self, forKey: .sellable)
        self.stockable = try container.decodeIfPresent(Bool.self, forKey: .stockable)
    }
}

// MARK: - Category Data
struct CategoryData: Codable {
    let id: String?
    let name: String?
    let imageIds: [String]?
    let imageUrl: String?
    let categoryType: String?
    let parentCategory: ParentCategory?
    let isTopLevel: Bool?
    let channels: [String]?
    let availabilityPeriodIds: [String]?
    let onlineVisibility: Bool?
    let rootCategory: String?
    let ecomSeoData: EcomSeoData?
    let pathToRoot: [PathToRootCategory]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case imageIds = "image_ids"
        case imageUrl = "image_url"
        case categoryType = "category_type"
        case parentCategory = "parent_category"
        case isTopLevel = "is_top_level"
        case channels
        case availabilityPeriodIds = "availability_period_ids"
        case onlineVisibility = "online_visibility"
        case rootCategory = "root_category"
        case ecomSeoData = "ecom_seo_data"
        case pathToRoot = "path_to_root"
    }
}

// MARK: - Supporting Types
struct Money: Codable {
    let amount: Int64?
    let currency: String?
}

struct CatalogImage: Codable {
    let id: String?
    let type: String?
    let updatedAt: String?
    let version: Int64?
    let isDeleted: Bool?
    let presentAtAllLocations: Bool?
    let imageData: ImageData?
    
    enum CodingKeys: String, CodingKey {
        case id, type, version
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case imageData = "image_data"
    }
}

struct ImageData: Codable {
    let name: String?
    let url: String?
    let caption: String?
    let photoStudioOrderId: String?
    
    enum CodingKeys: String, CodingKey {
        case name, url, caption
        case photoStudioOrderId = "photo_studio_order_id"
    }
}

struct LocationOverride: Codable {
    let locationId: String?
    let priceMoney: Money?
    let pricingType: String?
    let trackInventory: Bool?
    let inventoryAlertType: String?
    let inventoryAlertThreshold: Int64?
    let soldOut: Bool?
    let soldOutValidUntil: String?
    
    enum CodingKeys: String, CodingKey {
        case priceMoney = "price_money"
        case pricingType = "pricing_type"
        case trackInventory = "track_inventory"
        case inventoryAlertType = "inventory_alert_type"
        case inventoryAlertThreshold = "inventory_alert_threshold"
        case soldOut = "sold_out"
        case soldOutValidUntil = "sold_out_valid_until"
        case locationId = "location_id"
    }
}

struct ItemOption: Codable {
    let itemOptionId: String?
    
    enum CodingKeys: String, CodingKey {
        case itemOptionId = "item_option_id"
    }
}

struct ItemOptionValue: Codable {
    let itemOptionId: String?
    let itemOptionValueId: String?
    
    enum CodingKeys: String, CodingKey {
        case itemOptionId = "item_option_id"
        case itemOptionValueId = "item_option_value_id"
    }
}

struct ModifierListInfo: Codable {
    let modifierListId: String?
    let modifierOverrides: [ModifierOverride]?
    let minSelectedModifiers: Int?
    let maxSelectedModifiers: Int?
    let enabled: Bool?
    let ordinal: Int?
    
    enum CodingKeys: String, CodingKey {
        case modifierListId = "modifier_list_id"
        case modifierOverrides = "modifier_overrides"
        case minSelectedModifiers = "min_selected_modifiers"
        case maxSelectedModifiers = "max_selected_modifiers"
        case enabled, ordinal
    }
}

struct ModifierOverride: Codable {
    let modifierId: String?
    let onByDefault: Bool?
    
    enum CodingKeys: String, CodingKey {
        case modifierId = "modifier_id"
        case onByDefault = "on_by_default"
    }
}

struct ParentCategory: Codable {
    let ordinal: Int?
}

struct EcomSeoData: Codable {
    let pageTitle: String?
    let pageDescription: String?
    let permalink: String?
    
    enum CodingKeys: String, CodingKey {
        case pageTitle = "page_title"
        case pageDescription = "page_description"
        case permalink
    }
}

struct PathToRootCategory: Codable {
    let categoryId: String?
    let categoryName: String?
    
    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
    }
}

// MARK: - Modifier Data
struct ModifierData: Codable {
    let name: String?
    let priceMoney: Money?
    let ordinal: Int?
    let modifierListId: String?
    let onByDefault: Bool?
    let locationOverrides: [LocationOverride]?
    let imageId: String?

    enum CodingKeys: String, CodingKey {
        case name, ordinal
        case priceMoney = "price_money"
        case modifierListId = "modifier_list_id"
        case onByDefault = "on_by_default"
        case locationOverrides = "location_overrides"
        case imageId = "image_id"
    }
}

struct ModifierListData: Codable {
    let id: String?
    let name: String?
    let ordinal: Int?
    let selectionType: String?
    let modifiers: [CatalogObject]?
    let imageIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, ordinal, modifiers
        case selectionType = "selection_type"
        case imageIds = "image_ids"
    }
}

// MARK: - Tax Data
struct TaxData: Codable {
    let id: String?
    let name: String?
    let calculationPhase: String?
    let inclusionType: String?
    let percentage: String?
    let appliesToCustomAmounts: Bool?
    let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, percentage, enabled
        case calculationPhase = "calculation_phase"
        case inclusionType = "inclusion_type"
        case appliesToCustomAmounts = "applies_to_custom_amounts"
    }
}

// MARK: - Discount Data
struct DiscountData: Codable {
    let name: String?
    let discountType: String?
    let percentage: String?
    let amountMoney: Money?
    let pinRequired: Bool?
    let labelColor: String?
    let modifyTaxBasis: String?
    let maximumAmountMoney: Money?
    
    enum CodingKeys: String, CodingKey {
        case name, percentage
        case discountType = "discount_type"
        case amountMoney = "amount_money"
        case pinRequired = "pin_required"
        case labelColor = "label_color"
        case modifyTaxBasis = "modify_tax_basis"
        case maximumAmountMoney = "maximum_amount_money"
    }
}

// MARK: - Case UPC Data (for GraphQL integration)
struct CaseUpcData: Codable {
    let caseUpc: String?
    let caseCost: Double?
    let caseQuantity: Int?
    let vendor: String?
    let discontinued: Bool?
    let notes: [TeamNote]?
    
    enum CodingKeys: String, CodingKey {
        case caseUpc = "case_upc"
        case caseCost = "case_cost"
        case caseQuantity = "case_quantity"
        case vendor, discontinued, notes
    }
}

struct TeamNote: Codable, Equatable {
    let id: String
    let content: String
    let isComplete: Bool
    let authorId: String
    let authorName: String
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, content, authorId, authorName, createdAt, updatedAt
        case isComplete = "is_complete"
    }
}

// MARK: - API Response Types
struct CatalogResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let errors: [APIError]?
}

/// Response for fetching a single catalog object
struct CatalogObjectResponse: Codable {
    let object: CatalogObject?
    let relatedObjects: [CatalogObject]?
    let errors: [APIError]?

    enum CodingKeys: String, CodingKey {
        case object
        case relatedObjects = "related_objects"
        case errors
    }
}

/// Request for upserting a catalog object
struct UpsertCatalogObjectRequest: Codable {
    let idempotencyKey: String
    let object: CatalogObject

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case object
    }
}

/// Response for upserting a catalog object
struct UpsertCatalogObjectResponse: Codable {
    let catalogObject: CatalogObject?
    let idMappings: [IdMapping]?
    let errors: [APIError]?

    enum CodingKeys: String, CodingKey {
        case catalogObject = "catalog_object"
        case idMappings = "id_mappings"
        case errors
    }
}

/// Response for deleting a catalog object
struct DeleteCatalogObjectResponse: Codable {
    let deletedObject: DeletedCatalogObject?
    let deletedObjectIds: [String]?
    let errors: [APIError]?

    enum CodingKeys: String, CodingKey {
        case deletedObject = "deleted_object"
        case deletedObjectIds = "deleted_object_ids"
        case errors
    }
}

/// Information about a deleted catalog object
struct DeletedCatalogObject: Codable {
    let objectType: String?
    let id: String?
    let version: Int64?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case objectType = "object_type"
        case id
        case version
        case deletedAt = "deleted_at"
    }
}

/// ID mapping for upsert operations
struct IdMapping: Codable {
    let clientObjectId: String?
    let objectId: String?

    enum CodingKeys: String, CodingKey {
        case clientObjectId = "client_object_id"
        case objectId = "object_id"
    }
}

struct APIError: Codable {
    let category: String?
    let code: String?
    let detail: String?
    let field: String?
}

// MARK: - Database Row Types
struct CatalogItemRow {
    let id: String
    let updatedAt: String
    let version: String
    let isDeleted: Int
    let presentAtAllLocations: Int?
    let name: String?
    let description: String?
    let categoryId: String?
    let dataJson: String
}

struct CategoryRow {
    let id: String
    let updatedAt: String
    let version: String
    let isDeleted: Int
    let name: String?
    let dataJson: String
}

struct ItemVariationRow {
    let id: String
    let updatedAt: String
    let version: String
    let isDeleted: Int
    let itemId: String
    let name: String?
    let sku: String?
    let pricingType: String?
    let priceAmount: Int64?
    let priceCurrency: String?
    let dataJson: String
}

// MARK: - Image Upload Response
struct CreateCatalogImageResponse: Codable {
    let image: CatalogObject?
    let errors: [APIError]?
}
