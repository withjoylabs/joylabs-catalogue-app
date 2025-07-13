import Foundation
import os.log

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

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let name: String?
    let sku: String?
    let price: Double?
    let barcode: String?
    let categoryId: String?
    let categoryName: String?
    let images: [CatalogImage]?
    let matchType: String
    let matchContext: String?
    let isFromCaseUpc: Bool
    let caseUpcData: CaseUpcData?
    let hasTax: Bool

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(matchType)
        hasher.combine(isFromCaseUpc)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        return lhs.id == rhs.id && lhs.matchType == rhs.matchType && lhs.isFromCaseUpc == rhs.isFromCaseUpc
    }
}

// MARK: - Catalog Object Models
struct CatalogObject: Codable {
    let id: String
    let type: String
    let updatedAt: String
    let version: Int64
    let isDeleted: Bool
    let presentAtAllLocations: Bool?
    let itemData: ItemData?
    let categoryData: CategoryData?
    let itemVariationData: ItemVariationData?
    let modifierData: ModifierData?
    let modifierListData: ModifierListData?
    let taxData: TaxData?
    let discountData: DiscountData?
    
    enum CodingKeys: String, CodingKey {
        case id, type, version
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case itemData = "item_data"
        case categoryData = "category_data"
        case itemVariationData = "item_variation_data"
        case modifierData = "modifier_data"
        case modifierListData = "modifier_list_data"
        case taxData = "tax_data"
        case discountData = "discount_data"
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
    }
}

struct CategoryReference: Codable {
    let id: String
    let ordinal: Int?
}

struct ReportingCategory: Codable {
    let id: String
}

struct ItemVariation: Codable {
    let id: String?
    let type: String?
    let updatedAt: String?
    let version: Int64?
    let isDeleted: Bool?
    let presentAtAllLocations: Bool?
    let itemVariationData: ItemVariationData?
    
    enum CodingKeys: String, CodingKey {
        case id, type, version
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case presentAtAllLocations = "present_at_all_locations"
        case itemVariationData = "item_variation_data"
    }
}

struct ItemVariationData: Codable {
    let itemId: String
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
}

// MARK: - Category Data
struct CategoryData: Codable {
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
        case name
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
    let name: String?
    let ordinal: Int?
    let selectionType: String?
    let modifiers: [CatalogObject]?
    let imageIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, ordinal, modifiers
        case selectionType = "selection_type"
        case imageIds = "image_ids"
    }
}

// MARK: - Tax Data
struct TaxData: Codable {
    let name: String?
    let calculationPhase: String?
    let inclusionType: String?
    let percentage: String?
    let appliesToCustomAmounts: Bool?
    let enabled: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, percentage, enabled
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

struct TeamNote: Codable {
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
