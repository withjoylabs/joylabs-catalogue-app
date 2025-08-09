import Foundation

// MARK: - Comprehensive Item Data Models
// These models capture ALL Square catalog fields for complete CRUD operations

/// Complete Square catalog item data model with all possible fields
struct ComprehensiveItemData {
    // MARK: - Core Identification
    var id: String?
    var version: Int64?
    var type: CatalogObjectType = .item
    var updatedAt: String?
    var isDeleted: Bool = false
    var presentAtAllLocations: Bool = true
    
    // MARK: - Basic Information
    var name: String = ""
    var description: String = ""
    var abbreviation: String = ""
    var labelColor: String?
    var sortName: String?
    
    // MARK: - Product Classification
    var productType: ProductType = .regular
    var categoryId: String? // Legacy single category
    var categories: [CategoryReference] = [] // Square's categories array
    var reportingCategory: ReportingCategory? // Square's reporting category
    var isAlcoholic: Bool = false
    
    // MARK: - Variations and Pricing
    var variations: [ComprehensiveVariationData] = []
    var itemOptions: [ItemOption] = []
    
    // MARK: - Tax Configuration
    var taxIds: [String] = []
    var isTaxable: Bool = true // Square API default
    
    // MARK: - Modifiers
    var modifierListInfo: [ModifierListInfo] = []
    var skipModifierScreen: Bool = false
    
    // MARK: - Images
    var imageIds: [String] = []
    var images: [CatalogImage] = []
    
    // MARK: - Availability
    var availableOnline: Bool = true
    var availableForPickup: Bool = true
    var availableElectronically: Bool = false
    var availabilityPeriodIds: [String] = []
    
    // MARK: - Service-Specific Fields (for APPOINTMENTS_SERVICE)
    var serviceDuration: ServiceDuration?
    var availableForBooking: Bool = false
    var teamMemberIds: [String] = []
    
    // MARK: - Inventory Management
    var trackInventory: Bool = false
    var inventoryAlertType: InventoryAlertType = .none
    var inventoryAlertThreshold: Int?
    
    // MARK: - Location Overrides
    var locationOverrides: [LocationOverride] = []
    
    // MARK: - Custom Attributes
    var customAttributeValues: [String: CustomAttributeValue] = [:]
    
    // MARK: - E-commerce Fields
    var ecomSeoData: EcomSeoData?
    var ecomVisibility: EcomVisibility = .unindexed
    
    // MARK: - Measurement and Units
    var measurementUnitId: String?
    var sellable: Bool = true
    var stockable: Bool = true
    
    // MARK: - Additional Metadata
    var userData: String? // Custom JSON data
    var channels: [String] = [] // Sales channels
    var onlineVisibility: OnlineVisibility = .public
    
    // MARK: - Team Data (AppSync Integration)
    var teamData: TeamItemData?
}

// MARK: - Comprehensive Variation Data
struct ComprehensiveVariationData: Identifiable {
    let id = UUID()
    
    // Core identification
    var variationId: String?
    var itemId: String?
    var version: Int64?
    var updatedAt: String?
    var isDeleted: Bool = false
    
    // Basic information
    var name: String = ""
    var sku: String = ""
    var upc: String = ""
    var ordinal: Int = 0
    
    // Pricing
    var pricingType: PricingType = .fixedPricing
    var priceMoney: Money?
    var basePriceMoney: Money?
    var defaultUnitCost: Money?
    
    // Inventory
    var trackInventory: Bool = false
    var inventoryAlertType: InventoryAlertType = .none
    var inventoryAlertThreshold: Int?
    var stockOnHand: Int = 0
    
    // Service duration (for appointments)
    var serviceDuration: ServiceDuration?
    var availableForBooking: Bool = false
    
    // Item options
    var itemOptionValues: [ItemOptionValue] = []
    
    // Location-specific overrides
    var locationOverrides: [LocationOverride] = []
    
    // Measurement
    var measurementUnitId: String?
    var sellable: Bool = true
    var stockable: Bool = true
    
    // Custom data
    var userData: String?
}

// MARK: - Supporting Data Structures
// Note: Using existing types from CatalogModels.swift to avoid conflicts

struct ServiceDuration: Codable {
    var duration: Int // in milliseconds
    var unit: ServiceDurationUnit = .milliseconds
}

enum ServiceDurationUnit: String, Codable, CaseIterable {
    case milliseconds = "MS"
    case seconds = "SEC"
    case minutes = "MIN"
    case hours = "HOUR"
    case days = "DAY"
}

// LocationOverride already exists in CatalogModels.swift

struct CustomAttributeValue: Codable {
    var stringValue: String?
    var numberValue: Double?
    var booleanValue: Bool?
    var selectionUidValues: [String]?
    var customAttributeDefinitionId: String?
}

// EcomSeoData already exists in CatalogModels.swift

struct TeamItemData: Codable {
    var caseUpc: String?
    var caseCost: Double?
    var caseQuantity: Int?
    var vendor: String?
    var discontinued: Bool = false
    var notes: [TeamNote] = []
    var owner: String?
    var lastSyncAt: String?
}

// TeamNote already exists in CatalogModels.swift

// MARK: - Enums

enum CatalogObjectType: String, Codable, CaseIterable {
    case item = "ITEM"
    case itemVariation = "ITEM_VARIATION"
    case category = "CATEGORY"
    case tax = "TAX"
    case discount = "DISCOUNT"
    case modifier = "MODIFIER"
    case modifierList = "MODIFIER_LIST"
    case image = "IMAGE"
    case quickAmountsSettings = "QUICK_AMOUNTS_SETTINGS"
    case pricingRule = "PRICING_RULE"
    case productSet = "PRODUCT_SET"
    case timePeriod = "TIME_PERIOD"
    case measurementUnit = "MEASUREMENT_UNIT"
    case subscriptionPlan = "SUBSCRIPTION_PLAN"
    case itemOption = "ITEM_OPTION"
    case itemOptionValue = "ITEM_OPTION_VALUE"
    case customAttributeDefinition = "CUSTOM_ATTRIBUTE_DEFINITION"
    case quickAmount = "QUICK_AMOUNT"
}

// Note: Using existing enums from ItemDetailsViewModel.swift to avoid conflicts
// ProductType, PricingType, and InventoryAlertType already exist

enum EcomVisibility: String, Codable, CaseIterable {
    case unindexed = "UNINDEXED"
    case unavailable = "UNAVAILABLE"
    case hidden = "HIDDEN"
    case visible = "VISIBLE"
}

enum OnlineVisibility: String, Codable, CaseIterable {
    case `public` = "PUBLIC"
    case `private` = "PRIVATE"
}

// MARK: - Money Extensions
// Note: Money struct already exists in CatalogModels.swift
// Adding convenience extensions for the existing Money type
extension Money {
    /// Convert from dollars to cents
    static func fromDollars(_ dollars: Double, currency: String = "USD") -> Money {
        let cents = Int64(dollars * 100)
        return Money(amount: cents, currency: currency)
    }

    /// Convert to dollars from cents
    var toDollars: Double {
        guard let amount = amount else { return 0.0 }
        return Double(amount) / 100.0
    }

    /// Formatted display string
    var displayString: String {
        let dollars = toDollars
        let currencySymbol = currency == "USD" ? "$" : (currency ?? "")
        return String(format: "%@%.2f", currencySymbol, dollars)
    }
}
