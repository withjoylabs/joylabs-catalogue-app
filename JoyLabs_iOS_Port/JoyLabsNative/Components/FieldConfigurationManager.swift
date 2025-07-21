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
    private let currentVersion = 1
    
    // MARK: - Singleton
    static let shared = FieldConfigurationManager()
    
    // MARK: - Initialization
    private init() {
        self.currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
        loadConfiguration()
        logger.info("FieldConfigurationManager initialized with persistence support")
    }
    
    // MARK: - Public Methods
    
    /// Load configuration from persistent storage
    func loadConfiguration() {
        logger.info("Loading field configuration from UserDefaults")
        isLoading = true
        defer { isLoading = false }
        
        // Check if we need to migrate configuration
        let savedVersion = userDefaults.integer(forKey: configurationVersionKey)
        if savedVersion < self.currentVersion {
            logger.info("Configuration version mismatch. Migrating from \(savedVersion) to \(self.currentVersion)")
            migrateConfiguration(from: savedVersion)
            return
        }
        
        // Load saved configuration
        if let configData = userDefaults.data(forKey: configurationKey) {
            do {
                let decoder = JSONDecoder()
                let savedConfig = try decoder.decode(ItemFieldConfiguration.self, from: configData)
                currentConfiguration = savedConfig
                logger.info("Successfully loaded saved field configuration from UserDefaults")
                logger.debug("Loaded config - Categories enabled: \(savedConfig.classificationFields.categoryEnabled), Tax enabled: \(savedConfig.pricingFields.taxEnabled)")
            } catch {
                logger.error("Failed to decode field configuration: \(error.localizedDescription)")
                // Fall back to default configuration
                currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
                saveConfiguration() // Save the default to fix corruption
            }
        } else {
            logger.info("No saved configuration found, creating and saving default configuration")
            currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
            saveConfiguration() // Save the default for future use
        }
        
        hasUnsavedChanges = false
    }
    
    /// Save current configuration to persistent storage
    func saveConfiguration() {
        logger.info("Saving field configuration to UserDefaults")

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
        case .inventoryTracking:
            return currentConfiguration.inventoryFields.trackInventoryEnabled
        case .inventoryAlerts:
            return currentConfiguration.inventoryFields.inventoryAlertsEnabled
        case .servicesDuration:
            return currentConfiguration.serviceFields.serviceDurationEnabled
        case .servicesTeamMembers:
            return currentConfiguration.serviceFields.teamMembersEnabled
        case .advancedCustomAttributes:
            return currentConfiguration.advancedFields.customAttributesEnabled
        case .ecommerceAvailability:
            return currentConfiguration.ecommerceFields.availabilityEnabled
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
        case .inventoryTracking:
            return currentConfiguration.inventoryFields.trackInventoryRequired
        case .inventoryAlerts:
            return currentConfiguration.inventoryFields.inventoryAlertsRequired
        case .servicesDuration:
            return currentConfiguration.serviceFields.serviceDurationRequired
        case .servicesTeamMembers:
            return currentConfiguration.serviceFields.teamMembersRequired
        case .advancedCustomAttributes:
            return currentConfiguration.advancedFields.customAttributesRequired
        case .ecommerceAvailability:
            return currentConfiguration.ecommerceFields.availabilityRequired
        case .teamDataCaseInfo:
            return currentConfiguration.teamDataFields.caseDataRequired
        }
    }
    
    // MARK: - Private Methods
    
    private func migrateConfiguration(from version: Int) {
        logger.info("Migrating configuration from version \(version)")
        
        // For now, just reset to default on any version change
        // In the future, implement specific migration logic
        currentConfiguration = ItemFieldConfiguration.defaultConfiguration()
        saveConfiguration()
        
        logger.info("Configuration migration completed")
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
    case inventoryTracking = "inventory.tracking"
    case inventoryAlerts = "inventory.alerts"
    case servicesDuration = "services.duration"
    case servicesTeamMembers = "services.teamMembers"
    case advancedCustomAttributes = "advanced.customAttributes"
    case ecommerceAvailability = "ecommerce.availability"
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
        case .inventoryTracking: return "Inventory Tracking"
        case .inventoryAlerts: return "Inventory Alerts"
        case .servicesDuration: return "Service Duration"
        case .servicesTeamMembers: return "Team Members"
        case .advancedCustomAttributes: return "Custom Attributes"
        case .ecommerceAvailability: return "Availability Settings"
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
        config.ecommerceFields.availabilityEnabled = true
        config.ecommerceFields.seoEnabled = true
        config.ecommerceFields.ecomVisibilityEnabled = true
        config.ecommerceFields.availabilityPeriodsEnabled = true
        
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
