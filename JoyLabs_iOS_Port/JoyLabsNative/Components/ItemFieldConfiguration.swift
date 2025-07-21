import Foundation

// MARK: - Settings-Driven Field Configuration System
// This system allows enabling/disabling fields and setting default values
// Note: Uses existing types from ItemDetailsViewModel.swift and CatalogModels.swift

/// Configuration for item detail fields with settings-driven visibility and defaults
struct ItemFieldConfiguration {
    
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
        config.classificationFields.productTypeEnabled = false
        
        // Enable basic pricing
        config.pricingFields.variationsEnabled = true
        config.pricingFields.taxEnabled = true
        config.pricingFields.modifiersEnabled = false
        
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

struct BasicFieldsConfig {
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
}

struct ClassificationFieldsConfig {
    var categoryEnabled: Bool = true
    var categoryRequired: Bool = false
    var defaultCategoryId: String?
    
    var reportingCategoryEnabled: Bool = true
    var reportingCategoryRequired: Bool = false
    var defaultReportingCategoryId: String?
    
    var productTypeEnabled: Bool = false
    var productTypeRequired: Bool = false
    var defaultProductType: ProductType = .regular
    
    var multiCategoriesEnabled: Bool = false
}

struct PricingFieldsConfig {
    var variationsEnabled: Bool = true
    var variationsRequired: Bool = true
    var defaultVariationCount: Int = 1
    
    var taxEnabled: Bool = true
    var taxRequired: Bool = false
    var defaultTaxIds: [String] = []
    
    var modifiersEnabled: Bool = false
    var modifiersRequired: Bool = false
    var defaultModifierListIds: [String] = []
    
    var skipModifierScreenEnabled: Bool = false
    var defaultSkipModifierScreen: Bool = false
    
    var itemOptionsEnabled: Bool = false
    var itemOptionsRequired: Bool = false
}

struct InventoryFieldsConfig {
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

struct ServiceFieldsConfig {
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

struct AdvancedFieldsConfig {
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
}

struct EcommerceFieldsConfig {
    var onlineVisibilityEnabled: Bool = false
    var onlineVisibilityRequired: Bool = false
    var defaultOnlineVisibility: OnlineVisibility = .public
    
    var availabilityEnabled: Bool = true
    var availabilityRequired: Bool = false
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

struct TeamDataFieldsConfig {
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
            reportingCategory = ReportingCategory(id: config.classificationFields.defaultReportingCategoryId!)
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
