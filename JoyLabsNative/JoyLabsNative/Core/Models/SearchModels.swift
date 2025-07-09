import Foundation

// MARK: - Search Filters
struct SearchFilters {
    let name: Bool
    let sku: Bool
    let barcode: Bool
    let category: Bool
    
    init(name: Bool = true, sku: Bool = true, barcode: Bool = true, category: Bool = false) {
        self.name = name
        self.sku = sku
        self.barcode = barcode
        self.category = category
    }
}

// MARK: - Search Result Item
struct SearchResultItem: Identifiable, Codable {
    let id: String
    let name: String?
    let sku: String?
    let price: Double?
    let barcode: String?
    let categoryId: String?
    let categoryName: String?
    let images: [String]?
    let matchType: String?
    let matchContext: String?
    let isFromCaseUpc: Bool
    let caseUpcData: CaseUpcData?
    
    init(
        id: String,
        name: String? = nil,
        sku: String? = nil,
        price: Double? = nil,
        barcode: String? = nil,
        categoryId: String? = nil,
        categoryName: String? = nil,
        images: [String]? = nil,
        matchType: String? = nil,
        matchContext: String? = nil,
        isFromCaseUpc: Bool = false,
        caseUpcData: CaseUpcData? = nil
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.price = price
        self.barcode = barcode
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.images = images
        self.matchType = matchType
        self.matchContext = matchContext
        self.isFromCaseUpc = isFromCaseUpc
        self.caseUpcData = caseUpcData
    }
}

// MARK: - Case UPC Data
struct CaseUpcData: Codable {
    let caseUpc: String
    let unitsPerCase: Int
    let unitUpc: String?
    let unitName: String?
}

// MARK: - Catalog Models (simplified for Phase 7)
struct CatalogObject: Codable {
    let id: String
    let type: String
    let updatedAt: String
    let version: Int?
    let isDeleted: Bool
    let presentAtAllLocations: Bool
    let itemData: ItemData?
    let categoryData: CategoryData?
    let itemVariationData: ItemVariationData?
    let modifierData: ModifierData?
    let modifierListData: ModifierListData?
    let taxData: TaxData?
    let discountData: DiscountData?
}

struct ItemData: Codable {
    let name: String?
    let description: String?
    let categoryId: String?
    let abbreviation: String?
    let labelColor: String?
    let availableOnline: Bool?
    let availableForPickup: Bool?
    let availableElectronically: Bool?
    let categoryData: CategoryData?
    let taxIds: [String]?
    let modifierListInfo: [ModifierListInfo]?
    let variations: [String]?
    let productType: String?
    let skipModifierScreen: Bool?
    let itemOptions: [ItemOption]?
    let imageIds: [String]?
    let sortName: String?
    let descriptionHtml: String?
    let descriptionPlaintext: String?
}

struct CategoryData: Codable {
    let name: String?
}

struct ItemVariationData: Codable {
    let itemId: String?
    let name: String?
    let sku: String?
    let upc: String?
    let ordinal: Int?
    let pricingType: String?
    let priceMoney: Money?
    let locationOverrides: [LocationOverride]?
    let trackInventory: Bool?
    let inventoryAlertType: String?
    let inventoryAlertThreshold: Int?
    let userData: String?
    let serviceDuration: Int?
    let availableForBooking: Bool?
    let itemOptionValues: [ItemOptionValue]?
    let measurementUnitId: String?
    let sellable: Bool?
    let stockable: Bool?
    let imageIds: [String]?
    let teamMemberIds: [String]?
    let stockableConversion: StockableConversion?
}

struct Money: Codable {
    let amount: Int?
    let currency: String?
}

struct LocationOverride: Codable {
    let locationId: String
    let priceMoney: Money?
    let pricingType: String?
    let trackInventory: Bool?
    let inventoryAlertType: String?
    let inventoryAlertThreshold: Int?
    let soldOut: Bool?
    let soldOutValidUntil: String?
}

struct ItemOptionValue: Codable {
    let itemOptionId: String
    let name: String
    let description: String?
    let color: String?
    let ordinal: Int?
}

struct StockableConversion: Codable {
    let stockableItemVariationId: String
    let stockableQuantity: String
    let nonstockableQuantity: String
}

struct ModifierListInfo: Codable {
    let modifierListId: String
    let minSelectedModifiers: Int?
    let maxSelectedModifiers: Int?
    let enabled: Bool?
}

struct ItemOption: Codable {
    let itemOptionId: String
}

struct ModifierData: Codable {
    let name: String?
    let priceMoney: Money?
    let ordinal: Int?
    let modifierListId: String?
    let onByDefault: Bool?
}

struct ModifierListData: Codable {
    let name: String?
    let ordinal: Int?
    let selectionType: String?
    let modifiers: [String]?
    let imageIds: [String]?
}

struct TaxData: Codable {
    let name: String?
    let calculationPhase: String?
    let inclusionType: String?
    let percentage: String?
    let appliesToCustomAmounts: Bool?
    let enabled: Bool?
}

struct DiscountData: Codable {
    let name: String?
    let discountType: String?
    let percentage: String?
    let amountMoney: Money?
    let pinRequired: Bool?
    let labelColor: String?
    let modifyTaxBasis: String?
    let maximumAmountMoney: Money?
}
