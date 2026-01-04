import Foundation
import OSLog

// MARK: - Field Configuration Manager
// Manages persistence, loading, and runtime access to field configuration settings

/// Centralized manager for field configuration settings with persistence
@MainActor
class FieldConfigurationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentConfiguration: ItemFieldConfiguration
    @Published var isLoading = false
    @Published var hasUnsavedChanges = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.joylabs.native", category: "FieldConfigurationManager")
    private let configurationKey = "ItemFieldConfiguration"
    private let configurationVersionKey = "ItemFieldConfigurationVersion"
    private let currentVersion = 2  // Bumped from 1 to force migration (remove availability, add salesChannels/fulfillment)
    
    // MARK: - Singleton
    static let shared = FieldConfigurationManager()
    
    // MARK: - Initialization
    private init() {
        self.currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
        loadConfiguration()
        logger.info("[FieldConfig] FieldConfigurationManager initialized with persistence support")
    }
    
    // MARK: - Public Methods
    
    /// Load configuration from persistent storage
    func loadConfiguration() {
        logger.info("[FieldConfig] Loading field configuration from UserDefaults")
        isLoading = true
        defer { isLoading = false }
        
        // Check if we need to migrate configuration
        let savedVersion = userDefaults.integer(forKey: configurationVersionKey)
        if savedVersion < self.currentVersion {
            logger.info("[FieldConfig] Configuration version mismatch. Migrating from \(savedVersion) to \(self.currentVersion)")
            migrateConfiguration(from: savedVersion)
            return
        }
        
        // Load saved configuration
        if let configData = userDefaults.data(forKey: configurationKey) {
            do {
                let decoder = JSONDecoder()
                let savedConfig = try decoder.decode(ItemFieldConfiguration.self, from: configData)
                currentConfiguration = savedConfig
                logger.info("[FieldConfig] Successfully loaded saved field configuration from UserDefaults")
                logger.info("[FieldConfig] Loaded config - Categories enabled: \(savedConfig.classificationFields.categoryEnabled), Tax enabled: \(savedConfig.pricingFields.taxEnabled)")
            } catch {
                logger.error("Failed to decode field configuration: \(error.localizedDescription)")
                // Fall back to default configuration
                currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
                saveConfiguration() // Save the default to fix corruption
            }
        } else {
            logger.info("[FieldConfig] No saved configuration found, creating and saving default configuration")
            currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
            saveConfiguration() // Save the default for future use
        }
        
        hasUnsavedChanges = false
    }
    
    /// Save current configuration to persistent storage
    func saveConfiguration() {
        logger.info("[FieldConfig] Saving field configuration to UserDefaults")

        do {
            let encoder = JSONEncoder()
            let configData = try encoder.encode(currentConfiguration)
            userDefaults.set(configData, forKey: configurationKey)
            userDefaults.set(currentVersion, forKey: configurationVersionKey)

            // Force immediate synchronization to disk
            userDefaults.synchronize()

            hasUnsavedChanges = false
            logger.info("Successfully saved field configuration")
        } catch {
            logger.error("Failed to encode field configuration: \(error.localizedDescription)")
        }
    }
    
    /// Reset configuration to default values
    func resetToDefault() {
        logger.info("Resetting field configuration to default")
        currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
        hasUnsavedChanges = true
        saveConfiguration() // Auto-save the reset configuration
    }
    
    /// Apply a predefined configuration preset
    func applyPreset(_ preset: ConfigurationPreset) {
        logger.info("Applying configuration preset: \(preset.rawValue)")
        
        switch preset {
        case .default:
            currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
        case .retail:
            currentConfiguration = ItemFieldConfiguration.retailConfiguration()
        case .service:
            currentConfiguration = ItemFieldConfiguration.serviceConfiguration()
        case .minimal:
            currentConfiguration = ItemFieldConfiguration.minimalConfiguration()
        case .advanced:
            currentConfiguration = ItemFieldConfiguration.advancedConfiguration()
        }
        
        hasUnsavedChanges = true
    }
    
    /// Update a specific field configuration
    func updateFieldConfiguration<T>(_ keyPath: WritableKeyPath<ItemFieldConfiguration, T>, value: T) {
        currentConfiguration[keyPath: keyPath] = value
        hasUnsavedChanges = true

        // Auto-save field configuration changes for better UX
        saveConfiguration()
    }
    
    /// Update section configuration
    func updateSectionConfiguration(_ sectionId: String, _ update: (inout SectionConfiguration) -> Void) {
        if var section = currentConfiguration.sectionConfigurations[sectionId] {
            update(&section)
            currentConfiguration.sectionConfigurations[sectionId] = section
            hasUnsavedChanges = true
            saveConfiguration()
        }
    }
    
    /// Update all section configurations
    func updateAllSectionConfigurations(_ configurations: [String: SectionConfiguration]) {
        currentConfiguration.sectionConfigurations = configurations
        hasUnsavedChanges = true
        saveConfiguration()
    }
    
    /// Validate current configuration
    func validateConfiguration() -> [ConfigurationValidationError] {
        var errors: [ConfigurationValidationError] = []
        
        // Validate basic fields
        if currentConfiguration.basicFields.nameRequired && !currentConfiguration.basicFields.nameEnabled {
            errors.append(ConfigurationValidationError(
                field: "basicFields.name",
                message: "Name field is required but disabled"
            ))
        }
        
        // Validate pricing fields
        if currentConfiguration.pricingFields.variationsRequired && !currentConfiguration.pricingFields.variationsEnabled {
            errors.append(ConfigurationValidationError(
                field: "pricingFields.variations",
                message: "Variations field is required but disabled"
            ))
        }
        
        // Validate inventory fields
        if currentConfiguration.inventoryFields.inventoryAlertsRequired && !currentConfiguration.inventoryFields.inventoryAlertsEnabled {
            errors.append(ConfigurationValidationError(
                field: "inventoryFields.inventoryAlerts",
                message: "Inventory alerts field is required but disabled"
            ))
        }
        
        return errors
    }
    
    /// Check if a specific field is enabled
    func isFieldEnabled(_ fieldPath: FieldPath) -> Bool {
        switch fieldPath {
        case .basicName:
            return currentConfiguration.basicFields.nameEnabled
        case .basicDescription:
            return currentConfiguration.basicFields.descriptionEnabled
        case .basicAbbreviation:
            return currentConfiguration.basicFields.abbreviationEnabled
        case .classificationCategory:
            return currentConfiguration.classificationFields.categoryEnabled
        case .classificationReportingCategory:
            return currentConfiguration.classificationFields.reportingCategoryEnabled
        case .pricingVariations:
            return currentConfiguration.pricingFields.variationsEnabled
        case .pricingTax:
            return currentConfiguration.pricingFields.taxEnabled
        case .pricingIsTaxable:
            return currentConfiguration.pricingFields.isTaxableEnabled
        case .pricingSkipModifierScreen:
            return currentConfiguration.pricingFields.skipModifierScreenEnabled
        case .classificationIsAlcoholic:
            return currentConfiguration.classificationFields.isAlcoholicEnabled
        case .inventoryTracking:
            return currentConfiguration.inventoryFields.trackInventoryEnabled
        case .inventoryTrackingMode:
            return currentConfiguration.inventoryFields.inventoryTrackingModeEnabled
        case .inventoryAlerts:
            return currentConfiguration.inventoryFields.inventoryAlertsEnabled
        case .servicesDuration:
            return currentConfiguration.serviceFields.serviceDurationEnabled
        case .servicesTeamMembers:
            return currentConfiguration.serviceFields.teamMembersEnabled
        case .advancedCustomAttributes:
            return currentConfiguration.advancedFields.customAttributesEnabled
        case .ecommerceSalesChannels:
            return currentConfiguration.ecommerceFields.salesChannelsEnabled
        case .ecommerceFulfillmentMethods:
            return currentConfiguration.ecommerceFields.fulfillmentMethodsEnabled
        case .teamDataCaseInfo:
            return currentConfiguration.teamDataFields.caseDataEnabled
        }
    }
    
    /// Check if a specific field is required
    func isFieldRequired(_ fieldPath: FieldPath) -> Bool {
        switch fieldPath {
        case .basicName:
            return currentConfiguration.basicFields.nameRequired
        case .basicDescription:
            return currentConfiguration.basicFields.descriptionRequired
        case .basicAbbreviation:
            return currentConfiguration.basicFields.abbreviationRequired
        case .classificationCategory:
            return currentConfiguration.classificationFields.categoryRequired
        case .classificationReportingCategory:
            return currentConfiguration.classificationFields.reportingCategoryRequired
        case .pricingVariations:
            return currentConfiguration.pricingFields.variationsRequired
        case .pricingTax:
            return currentConfiguration.pricingFields.taxRequired
        case .pricingIsTaxable:
            return currentConfiguration.pricingFields.isTaxableRequired
        case .pricingSkipModifierScreen:
            return currentConfiguration.pricingFields.skipModifierScreenRequired
        case .classificationIsAlcoholic:
            return currentConfiguration.classificationFields.isAlcoholicRequired
        case .inventoryTracking:
            return currentConfiguration.inventoryFields.trackInventoryRequired
        case .inventoryTrackingMode:
            return currentConfiguration.inventoryFields.inventoryTrackingModeRequired
        case .inventoryAlerts:
            return currentConfiguration.inventoryFields.inventoryAlertsRequired
        case .servicesDuration:
            return currentConfiguration.serviceFields.serviceDurationRequired
        case .servicesTeamMembers:
            return currentConfiguration.serviceFields.teamMembersRequired
        case .advancedCustomAttributes:
            return currentConfiguration.advancedFields.customAttributesRequired
        case .ecommerceSalesChannels:
            return currentConfiguration.ecommerceFields.salesChannelsRequired
        case .ecommerceFulfillmentMethods:
            return currentConfiguration.ecommerceFields.fulfillmentMethodsRequired
        case .teamDataCaseInfo:
            return currentConfiguration.teamDataFields.caseDataRequired
        }
    }
    
    // MARK: - Private Methods
    
    private func migrateConfiguration(from version: Int) {
        logger.info("[FieldConfig] Migrating configuration from version \(version) to \(self.currentVersion)")

        if version < 2 {
            // MIGRATION 1→2: Remove deprecated "availability" section, add "salesChannels" and "fulfillment"
            logger.info("[FieldConfig] Migration 1→2: Removing availability section, adding salesChannels/fulfillment")

            var newConfig = ItemFieldConfiguration.defaultConfiguration()

            // If user has saved config, preserve their customizations where possible
            if let savedData = userDefaults.data(forKey: configurationKey),
               let savedConfig = try? JSONDecoder().decode(ItemFieldConfiguration.self, from: savedData) {

                logger.info("[FieldConfig] Preserving user's customized field settings during migration")

                // Preserve user's field settings (don't reset their customizations)
                newConfig.basicFields = savedConfig.basicFields
                newConfig.classificationFields = savedConfig.classificationFields
                newConfig.pricingFields = savedConfig.pricingFields
                newConfig.inventoryFields = savedConfig.inventoryFields
                newConfig.serviceFields = savedConfig.serviceFields
                newConfig.advancedFields = savedConfig.advancedFields
                newConfig.teamDataFields = savedConfig.teamDataFields

                // Migrate ecommerce fields
                newConfig.ecommerceFields = savedConfig.ecommerceFields
                newConfig.ecommerceFields.fulfillmentMethodsEnabled = true  // ENABLE new fulfillment
                newConfig.ecommerceFields.salesChannelsEnabled = false  // Keep salesChannels opt-in

                // Migrate section configurations, removing "availability"
                var migratedSections = savedConfig.sectionConfigurations

                if migratedSections.removeValue(forKey: "availability") != nil {
                    logger.info("[FieldConfig] Removed deprecated 'availability' section from configuration")
                }

                // Add new sections if missing
                if migratedSections["salesChannels"] == nil {
                    migratedSections["salesChannels"] = SectionConfiguration(
                        id: "salesChannels",
                        title: "Where it's Sold",
                        icon: "storefront",
                        isEnabled: false,
                        order: 8,
                        isExpanded: false
                    )
                    logger.info("[FieldConfig] Added 'salesChannels' section")
                }

                if migratedSections["fulfillment"] == nil {
                    migratedSections["fulfillment"] = SectionConfiguration(
                        id: "fulfillment",
                        title: "Fulfillment",
                        icon: "shippingbox",
                        isEnabled: true,
                        order: 9,
                        isExpanded: false
                    )
                    logger.info("[FieldConfig] Added 'fulfillment' section")
                }

                // Reorder sections to account for removed availability
                var reorderedSections = migratedSections
                for (id, var section) in migratedSections {
                    if section.order >= 10 {  // Sections after availability (old order 10)
                        section.order -= 1  // Shift down by 1
                        reorderedSections[id] = section
                    }
                }

                newConfig.sectionConfigurations = reorderedSections
            } else {
                logger.info("[FieldConfig] No saved configuration found, using fresh defaults")
            }

            currentConfiguration = newConfig
        }

        saveConfiguration()
        logger.info("[FieldConfig] Configuration migration completed successfully")
    }
}

// MARK: - Supporting Types

enum ConfigurationPreset: String, CaseIterable {
    case `default` = "default"
    case retail = "retail"
    case service = "service"
    case minimal = "minimal"
    case advanced = "advanced"
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .retail: return "Retail Store"
        case .service: return "Service Business"
        case .minimal: return "Minimal Fields"
        case .advanced: return "All Fields"
        }
    }
    
    var description: String {
        switch self {
        case .default: return "Standard configuration for most businesses"
        case .retail: return "Optimized for retail stores with inventory management"
        case .service: return "Configured for service-based businesses"
        case .minimal: return "Only essential fields enabled"
        case .advanced: return "All available fields enabled"
        }
    }
}

enum FieldPath: String, CaseIterable {
    case basicName = "basic.name"
    case basicDescription = "basic.description"
    case basicAbbreviation = "basic.abbreviation"
    case classificationCategory = "classification.category"
    case classificationReportingCategory = "classification.reportingCategory"
    case pricingVariations = "pricing.variations"
    case pricingTax = "pricing.tax"
    case pricingIsTaxable = "pricing.isTaxable"
    case pricingSkipModifierScreen = "pricing.skipModifierScreen"
    case classificationIsAlcoholic = "classification.isAlcoholic"
    case inventoryTracking = "inventory.tracking"
    case inventoryTrackingMode = "inventory.trackingMode"
    case inventoryAlerts = "inventory.alerts"
    case servicesDuration = "services.duration"
    case servicesTeamMembers = "services.teamMembers"
    case advancedCustomAttributes = "advanced.customAttributes"
    case ecommerceSalesChannels = "ecommerce.salesChannels"
    case ecommerceFulfillmentMethods = "ecommerce.fulfillmentMethods"
    case teamDataCaseInfo = "teamData.caseInfo"

    var displayName: String {
        switch self {
        case .basicName: return "Item Name"
        case .basicDescription: return "Description"
        case .basicAbbreviation: return "Abbreviation"
        case .classificationCategory: return "Category"
        case .classificationReportingCategory: return "Reporting Category"
        case .pricingVariations: return "Variations"
        case .pricingTax: return "Tax Settings"
        case .pricingIsTaxable: return "Item Taxable"
        case .pricingSkipModifierScreen: return "Skip Modifier Screen"
        case .classificationIsAlcoholic: return "Alcoholic Item"
        case .inventoryTracking: return "Inventory Tracking"
        case .inventoryTrackingMode: return "Inventory Tracking Mode"
        case .inventoryAlerts: return "Inventory Alerts"
        case .servicesDuration: return "Service Duration"
        case .servicesTeamMembers: return "Team Members"
        case .advancedCustomAttributes: return "Custom Attributes"
        case .ecommerceSalesChannels: return "Sales Channels"
        case .ecommerceFulfillmentMethods: return "Fulfillment Methods"
        case .teamDataCaseInfo: return "Case Information"
        }
    }
}

struct ConfigurationValidationError {
    let field: String
    let message: String
}

// MARK: - Configuration Extensions
// Note: Codable conformance is now in ItemFieldConfiguration.swift

extension ItemFieldConfiguration {
    /// Minimal configuration with only essential fields
    static func minimalConfiguration() -> ItemFieldConfiguration {
        var config = ItemFieldConfiguration()
        
        // Enable only essential fields
        config.basicFields.nameEnabled = true
        config.basicFields.nameRequired = true
        config.basicFields.descriptionEnabled = false
        config.basicFields.abbreviationEnabled = false
        
        config.classificationFields.categoryEnabled = false
        config.classificationFields.reportingCategoryEnabled = false
        config.classificationFields.productTypeEnabled = false
        
        config.pricingFields.variationsEnabled = true
        config.pricingFields.variationsRequired = true
        config.pricingFields.taxEnabled = false
        config.pricingFields.modifiersEnabled = false
        
        config.inventoryFields.trackInventoryEnabled = false
        config.inventoryFields.inventoryAlertsEnabled = false
        config.inventoryFields.locationOverridesEnabled = false
        
        // Disable all advanced features
        config.serviceFields.serviceDurationEnabled = false
        config.serviceFields.teamMembersEnabled = false
        config.advancedFields.customAttributesEnabled = false
        config.ecommerceFields.seoEnabled = false
        config.teamDataFields.caseDataEnabled = false
        
        return config
    }
    
    /// Advanced configuration with all fields enabled
    static func advancedConfiguration() -> ItemFieldConfiguration {
        var config = ItemFieldConfiguration()
        
        // Enable all basic fields
        config.basicFields.nameEnabled = true
        config.basicFields.descriptionEnabled = true
        config.basicFields.abbreviationEnabled = true
        config.basicFields.labelColorEnabled = true
        config.basicFields.sortNameEnabled = true
        
        // Enable all classification fields
        config.classificationFields.categoryEnabled = true
        config.classificationFields.reportingCategoryEnabled = true
        config.classificationFields.productTypeEnabled = true
        config.classificationFields.multiCategoriesEnabled = true
        
        // Enable all pricing fields
        config.pricingFields.variationsEnabled = true
        config.pricingFields.taxEnabled = true
        config.pricingFields.modifiersEnabled = true
        config.pricingFields.skipModifierScreenEnabled = true
        config.pricingFields.itemOptionsEnabled = true
        
        // Enable all inventory fields
        config.inventoryFields.trackInventoryEnabled = true
        config.inventoryFields.inventoryAlertsEnabled = true
        config.inventoryFields.locationOverridesEnabled = true
        config.inventoryFields.stockOnHandEnabled = true
        
        // Enable all service fields
        config.serviceFields.serviceDurationEnabled = true
        config.serviceFields.teamMembersEnabled = true
        config.serviceFields.bookingEnabled = true
        
        // Enable all advanced fields
        config.advancedFields.customAttributesEnabled = true
        config.advancedFields.measurementUnitEnabled = true
        config.advancedFields.sellableEnabled = true
        config.advancedFields.stockableEnabled = true
        config.advancedFields.userDataEnabled = true
        config.advancedFields.channelsEnabled = true
        
        // Enable all e-commerce fields
        config.ecommerceFields.onlineVisibilityEnabled = true
        config.ecommerceFields.seoEnabled = true
        config.ecommerceFields.ecomVisibilityEnabled = true
        config.ecommerceFields.availabilityPeriodsEnabled = true
        config.ecommerceFields.fulfillmentMethodsEnabled = true
        config.ecommerceFields.salesChannelsEnabled = true
        
        // Enable all team data fields
        config.teamDataFields.caseDataEnabled = true
        config.teamDataFields.caseUpcEnabled = true
        config.teamDataFields.caseCostEnabled = true
        config.teamDataFields.caseQuantityEnabled = true
        config.teamDataFields.vendorEnabled = true
        config.teamDataFields.discontinuedEnabled = true
        config.teamDataFields.notesEnabled = true
        
        return config
    }
}
