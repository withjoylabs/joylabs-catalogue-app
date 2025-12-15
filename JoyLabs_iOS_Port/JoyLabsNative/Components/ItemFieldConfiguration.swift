import Foundation

// MARK: - Settings-Driven Field Configuration System
// This system allows enabling/disabling fields and setting default values
// Note: Uses existing types from ItemDetailsViewModel.swift and CatalogModels.swift

// MARK: - Section Configuration for Drag & Drop Reordering
/// Configuration for a section in the Item Details Modal
struct SectionConfiguration: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
    var isEnabled: Bool
    var order: Int
    var isExpanded: Bool = false
    
    static let defaultSections: [SectionConfiguration] = [
        SectionConfiguration(id: "image", title: "Image", icon: "photo", isEnabled: true, order: 0, isExpanded: false),
        SectionConfiguration(id: "basicInfo", title: "Basic Information", icon: "info.circle", isEnabled: true, order: 1, isExpanded: false),
        SectionConfiguration(id: "productType", title: "Product Type", icon: "tag", isEnabled: true, order: 2, isExpanded: false),
        SectionConfiguration(id: "pricing", title: "Pricing and Variations", icon: "dollarsign.circle", isEnabled: true, order: 3, isExpanded: false),
        SectionConfiguration(id: "inventory", title: "Inventory", icon: "shippingbox", isEnabled: true, order: 4, isExpanded: false),
        SectionConfiguration(id: "categories", title: "Categories", icon: "folder", isEnabled: true, order: 5, isExpanded: false),
        SectionConfiguration(id: "taxes", title: "Tax Settings", icon: "percent", isEnabled: true, order: 6, isExpanded: false),
        SectionConfiguration(id: "modifiers", title: "Modifiers", icon: "plus.circle", isEnabled: true, order: 7, isExpanded: false),
        SectionConfiguration(id: "skipModifier", title: "Skip Details Screen at Checkout", icon: "forward.circle", isEnabled: true, order: 8, isExpanded: false),
        SectionConfiguration(id: "salesChannels", title: "Where it's Sold", icon: "storefront", isEnabled: false, order: 9, isExpanded: false),
        SectionConfiguration(id: "fulfillment", title: "Fulfillment", icon: "shippingbox", isEnabled: true, order: 10, isExpanded: false),
        SectionConfiguration(id: "locations", title: "Enabled at Locations", icon: "location", isEnabled: true, order: 11, isExpanded: false),
        SectionConfiguration(id: "customAttributes", title: "Custom Attributes", icon: "list.bullet", isEnabled: true, order: 12, isExpanded: false),
        SectionConfiguration(id: "ecommerce", title: "E-Commerce Settings", icon: "globe", isEnabled: true, order: 13, isExpanded: false),
        SectionConfiguration(id: "measurementUnit", title: "Measurement Unit", icon: "ruler", isEnabled: true, order: 14, isExpanded: false)
    ]
}

/// Configuration for item detail fields with settings-driven visibility and defaults
struct ItemFieldConfiguration: Codable {
    
    // MARK: - Basic Information Fields
    var basicFields = BasicFieldsConfig()
    
    // MARK: - Product Classification Fields
    var classificationFields = ClassificationFieldsConfig()
    
    // MARK: - Pricing and Variations Fields
    var pricingFields = PricingFieldsConfig()
    
    // MARK: - Inventory Fields
    var inventoryFields = InventoryFieldsConfig()
    
    // MARK: - Service Fields
    var serviceFields = ServiceFieldsConfig()
    
    // MARK: - Advanced Fields
    var advancedFields = AdvancedFieldsConfig()
    
    // MARK: - E-commerce Fields
    var ecommerceFields = EcommerceFieldsConfig()
    
    // MARK: - Team Data Fields
    var teamDataFields = TeamDataFieldsConfig()
    
    // MARK: - Section Ordering Configuration
    var sectionConfigurations: [String: SectionConfiguration] = Dictionary(
        uniqueKeysWithValues: SectionConfiguration.defaultSections.map { ($0.id, $0) }
    )
    
    /// Get sections ordered by their order property
    var orderedSections: [SectionConfiguration] {
        return sectionConfigurations.values.sorted { $0.order < $1.order }
    }
    
    /// Update section order
    mutating func updateSectionOrder(_ sectionId: String, newOrder: Int) {
        sectionConfigurations[sectionId]?.order = newOrder
    }
    
    /// Toggle section enabled state
    mutating func toggleSectionEnabled(_ sectionId: String) {
        sectionConfigurations[sectionId]?.isEnabled.toggle()
    }
    
    /// Toggle section expanded state
    mutating func toggleSectionExpanded(_ sectionId: String) {
        sectionConfigurations[sectionId]?.isExpanded.toggle()
    }
    
    /// Default configuration with commonly used fields enabled
    static func defaultConfiguration() -> ItemFieldConfiguration {
        var config = ItemFieldConfiguration()
        
        // Enable basic fields by default
        config.basicFields.nameEnabled = true
        config.basicFields.descriptionEnabled = true
        config.basicFields.abbreviationEnabled = false
        
        // Enable essential classification fields
        config.classificationFields.categoryEnabled = true
        config.classificationFields.reportingCategoryEnabled = true
        config.classificationFields.productTypeEnabled = true
        
        // Enable basic pricing
        config.pricingFields.variationsEnabled = true
        config.pricingFields.taxEnabled = true
        config.pricingFields.modifiersEnabled = true
        config.pricingFields.skipModifierScreenEnabled = true
        
        // Enable location settings
        config.advancedFields.enabledLocationsEnabled = true

        // Enable modern e-commerce sections
        config.ecommerceFields.fulfillmentMethodsEnabled = true  // Modern replacement for old availability section
        config.ecommerceFields.salesChannelsEnabled = false  // Opt-in feature (read-only display)
        
        // Enable basic inventory
        config.inventoryFields.trackInventoryEnabled = true
        config.inventoryFields.inventoryAlertsEnabled = true
        config.inventoryFields.locationOverridesEnabled = false
        
        // Disable advanced features by default
        config.serviceFields.serviceDurationEnabled = false
        config.serviceFields.teamMembersEnabled = false
        config.advancedFields.customAttributesEnabled = false
        config.ecommerceFields.seoEnabled = false
        config.teamDataFields.caseDataEnabled = true
        
        return config
    }
    
    /// Configuration for retail stores
    static func retailConfiguration() -> ItemFieldConfiguration {
        var config = defaultConfiguration()
        
        // Enable retail-specific fields
        config.inventoryFields.locationOverridesEnabled = true
        config.ecommerceFields.onlineVisibilityEnabled = true
        config.teamDataFields.vendorEnabled = true
        
        return config
    }
    
    /// Configuration for service businesses
    static func serviceConfiguration() -> ItemFieldConfiguration {
        var config = defaultConfiguration()
        
        // Enable service-specific fields
        config.serviceFields.serviceDurationEnabled = true
        config.serviceFields.teamMembersEnabled = true
        config.serviceFields.bookingEnabled = true
        config.classificationFields.productTypeEnabled = true
        
        // Set default product type to service
        config.classificationFields.defaultProductType = .appointmentsService
        
        return config
    }
}

// MARK: - Field Configuration Structures

struct BasicFieldsConfig: Codable {
    var nameEnabled: Bool = true
    var nameRequired: Bool = true
    var defaultName: String = ""
    
    var descriptionEnabled: Bool = true
    var descriptionRequired: Bool = false
    var defaultDescription: String = ""
    
    var abbreviationEnabled: Bool = false
    var abbreviationRequired: Bool = false
    var defaultAbbreviation: String = ""
    
    var labelColorEnabled: Bool = false
    var defaultLabelColor: String?
    
    var sortNameEnabled: Bool = false
    var defaultSortName: String = ""
    
    // Core Square API defaults
    var defaultPresentAtAllLocations: Bool = true
}

struct ClassificationFieldsConfig: Codable {
    var categoryEnabled: Bool = true
    var categoryRequired: Bool = false
    var defaultCategoryId: String?
    
    var reportingCategoryEnabled: Bool = true
    var reportingCategoryRequired: Bool = false
    var defaultReportingCategoryId: String?
    
    var productTypeEnabled: Bool = false
    var productTypeRequired: Bool = false
    var defaultProductType: ProductType = .regular
    
    var isAlcoholicEnabled: Bool = false
    var isAlcoholicRequired: Bool = false
    var defaultIsAlcoholic: Bool = false
    
    var multiCategoriesEnabled: Bool = false
}

struct PricingFieldsConfig: Codable {
    var variationsEnabled: Bool = true
    var variationsRequired: Bool = true
    var defaultVariationCount: Int = 1
    var defaultVariationName: String = ""  // Empty string allows blank variation names
    
    var taxEnabled: Bool = true
    var taxRequired: Bool = false
    var defaultTaxIds: [String] = []
    
    var isTaxableEnabled: Bool = true
    var isTaxableRequired: Bool = false
    var defaultIsTaxable: Bool = true
    
    var modifiersEnabled: Bool = false
    var modifiersRequired: Bool = false
    var defaultModifierListIds: [String] = []
    
    var skipModifierScreenEnabled: Bool = true
    var skipModifierScreenRequired: Bool = false
    var defaultSkipModifierScreen: Bool = false
    
    var itemOptionsEnabled: Bool = false
    var itemOptionsRequired: Bool = false
}

struct InventoryFieldsConfig: Codable {
    var showInventorySection: Bool = true // Show inventory management section in item details

    var trackInventoryEnabled: Bool = true
    var trackInventoryRequired: Bool = false
    var defaultTrackInventory: Bool = false

    var inventoryAlertsEnabled: Bool = true
    var inventoryAlertsRequired: Bool = false
    var defaultInventoryAlertType: InventoryAlertType = .none
    var defaultInventoryAlertThreshold: Int?

    var locationOverridesEnabled: Bool = false
    var locationOverridesRequired: Bool = false

    var stockOnHandEnabled: Bool = true
    var stockOnHandRequired: Bool = false
    var defaultStockOnHand: Int = 0
}

struct ServiceFieldsConfig: Codable {
    var serviceDurationEnabled: Bool = false
    var serviceDurationRequired: Bool = false
    var defaultServiceDuration: Int? // in minutes
    
    var teamMembersEnabled: Bool = false
    var teamMembersRequired: Bool = false
    var defaultTeamMemberIds: [String] = []
    
    var bookingEnabled: Bool = false
    var bookingRequired: Bool = false
    var defaultAvailableForBooking: Bool = false
}

struct AdvancedFieldsConfig: Codable {
    var customAttributesEnabled: Bool = false
    var customAttributesRequired: Bool = false
    
    var measurementUnitEnabled: Bool = false
    var measurementUnitRequired: Bool = false
    var defaultMeasurementUnitId: String?
    
    var sellableEnabled: Bool = false
    var sellableRequired: Bool = false
    var defaultSellable: Bool = true
    
    var stockableEnabled: Bool = false
    var stockableRequired: Bool = false
    var defaultStockable: Bool = true
    
    var userDataEnabled: Bool = false
    var userDataRequired: Bool = false
    var defaultUserData: String?
    
    var channelsEnabled: Bool = false
    var channelsRequired: Bool = false
    var defaultChannels: [String] = []

    var enabledLocationsEnabled: Bool = true
    var enabledLocationsRequired: Bool = false
    var defaultEnabledAtAllLocations: Bool = true
}

struct EcommerceFieldsConfig: Codable {
    var onlineVisibilityEnabled: Bool = false
    var onlineVisibilityRequired: Bool = false
    var defaultOnlineVisibility: OnlineVisibility = .public

    // Sales Channels Section (read-only display of where item is sold)
    var salesChannelsEnabled: Bool = false
    var salesChannelsRequired: Bool = false

    // Fulfillment Methods Section (replaces old availability section)
    var fulfillmentMethodsEnabled: Bool = true
    var fulfillmentMethodsRequired: Bool = false
    var defaultAvailableOnline: Bool = true
    var defaultAvailableForPickup: Bool = true
    var defaultAvailableElectronically: Bool = false

    var seoEnabled: Bool = false
    var seoRequired: Bool = false

    var ecomVisibilityEnabled: Bool = false
    var ecomVisibilityRequired: Bool = false
    var defaultEcomVisibility: EcomVisibility = .unindexed

    var availabilityPeriodsEnabled: Bool = false
    var availabilityPeriodsRequired: Bool = false
}

struct TeamDataFieldsConfig: Codable {
    var caseDataEnabled: Bool = true
    var caseDataRequired: Bool = false
    
    var caseUpcEnabled: Bool = true
    var caseUpcRequired: Bool = false
    var defaultCaseUpc: String = ""
    
    var caseCostEnabled: Bool = true
    var caseCostRequired: Bool = false
    var defaultCaseCost: Double?
    
    var caseQuantityEnabled: Bool = true
    var caseQuantityRequired: Bool = false
    var defaultCaseQuantity: Int?
    
    var vendorEnabled: Bool = true
    var vendorRequired: Bool = false
    var defaultVendor: String = ""
    
    var discontinuedEnabled: Bool = true
    var discontinuedRequired: Bool = false
    var defaultDiscontinued: Bool = false
    
    var notesEnabled: Bool = true
    var notesRequired: Bool = false
    var defaultNotes: [TeamNote] = []
}

// MARK: - Field Validation

struct FieldValidationRules {
    static func validateBasicFields(_ data: ComprehensiveItemData, config: BasicFieldsConfig) -> [ItemFieldValidationError] {
        var errors: [ItemFieldValidationError] = []

        if config.nameRequired && data.name.isEmpty {
            errors.append(ItemFieldValidationError(field: "name", message: "Item name is required"))
        }

        if config.descriptionRequired && data.description.isEmpty {
            errors.append(ItemFieldValidationError(field: "description", message: "Item description is required"))
        }

        if config.abbreviationRequired && data.abbreviation.isEmpty {
            errors.append(ItemFieldValidationError(field: "abbreviation", message: "Item abbreviation is required"))
        }

        return errors
    }

    static func validatePricingFields(_ data: ComprehensiveItemData, config: PricingFieldsConfig) -> [ItemFieldValidationError] {
        var errors: [ItemFieldValidationError] = []

        if config.variationsRequired && data.variations.isEmpty {
            errors.append(ItemFieldValidationError(field: "variations", message: "At least one variation is required"))
        }

        if config.taxRequired && data.taxIds.isEmpty {
            errors.append(ItemFieldValidationError(field: "taxIds", message: "Tax configuration is required"))
        }

        if config.modifiersRequired && data.modifierListInfo.isEmpty {
            errors.append(ItemFieldValidationError(field: "modifierListInfo", message: "Modifier configuration is required"))
        }

        return errors
    }
}

// Note: Using existing ValidationError from DataValidation.swift
struct ItemFieldValidationError {
    let field: String
    let message: String
}

// MARK: - Default Value Application

extension ComprehensiveItemData {
    /// Apply default values from configuration
    mutating func applyDefaults(from config: ItemFieldConfiguration) {
        // Apply basic field defaults
        if name.isEmpty {
            name = config.basicFields.defaultName
        }
        if description.isEmpty {
            description = config.basicFields.defaultDescription
        }
        if abbreviation.isEmpty {
            abbreviation = config.basicFields.defaultAbbreviation
        }
        
        // Apply classification defaults
        if categoryId == nil {
            categoryId = config.classificationFields.defaultCategoryId
        }
        if reportingCategory == nil && config.classificationFields.defaultReportingCategoryId != nil {
            reportingCategory = ReportingCategory(id: config.classificationFields.defaultReportingCategoryId!, ordinal: nil)
        }
        productType = config.classificationFields.defaultProductType
        
        // Apply inventory defaults
        trackInventory = config.inventoryFields.defaultTrackInventory
        inventoryAlertType = config.inventoryFields.defaultInventoryAlertType
        inventoryAlertThreshold = config.inventoryFields.defaultInventoryAlertThreshold
        
        // Apply availability defaults
        availableOnline = config.ecommerceFields.defaultAvailableOnline
        availableForPickup = config.ecommerceFields.defaultAvailableForPickup
        availableElectronically = config.ecommerceFields.defaultAvailableElectronically
        
        // Apply service defaults
        if let defaultDuration = config.serviceFields.defaultServiceDuration {
            serviceDuration = ServiceDuration(duration: defaultDuration * 60 * 1000) // Convert minutes to milliseconds
        }
        availableForBooking = config.serviceFields.defaultAvailableForBooking
        teamMemberIds = config.serviceFields.defaultTeamMemberIds
        
        // Apply advanced defaults
        measurementUnitId = config.advancedFields.defaultMeasurementUnitId
        sellable = config.advancedFields.defaultSellable
        stockable = config.advancedFields.defaultStockable
        userData = config.advancedFields.defaultUserData
        channels = config.advancedFields.defaultChannels
        
        // Apply e-commerce defaults
        onlineVisibility = config.ecommerceFields.defaultOnlineVisibility
        ecomVisibility = config.ecommerceFields.defaultEcomVisibility
        
        // Apply pricing defaults  
        isTaxable = config.pricingFields.defaultIsTaxable
        
        // Apply classification defaults
        isAlcoholic = config.classificationFields.defaultIsAlcoholic
        
        // Apply team data defaults if enabled
        if config.teamDataFields.caseDataEnabled && teamData == nil {
            teamData = TeamItemData()
            teamData?.caseUpc = config.teamDataFields.defaultCaseUpc
            teamData?.caseCost = config.teamDataFields.defaultCaseCost
            teamData?.caseQuantity = config.teamDataFields.defaultCaseQuantity
            teamData?.vendor = config.teamDataFields.defaultVendor
            teamData?.discontinued = config.teamDataFields.defaultDiscontinued
            teamData?.notes = config.teamDataFields.defaultNotes
        }
    }
}
