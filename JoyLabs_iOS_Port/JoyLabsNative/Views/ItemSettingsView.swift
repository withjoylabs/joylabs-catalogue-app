import SwiftUI

// MARK: - Item Settings View
/// Comprehensive settings page for customizing item defaults and field visibility
struct ItemSettingsView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var showingResetAlert = false
    @State private var showingValidationErrors = false
    @State private var validationErrors: [ConfigurationValidationError] = []
    @State private var hasUnsavedChanges = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            headerSection
            // presetSection // Commented out for now - not in current scope
            fieldVisibilitySection
            defaultValuesSection
            squareAPISection
            actionsSection
        }
        .navigationTitle("Item Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    if hasUnsavedChanges {
                        showingResetAlert = true
                    } else {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveConfiguration()
                }
                .disabled(!hasUnsavedChanges)
                .fontWeight(.semibold)
            }
        }
            .alert("Unsaved Changes", isPresented: $showingResetAlert) {
                Button("Discard", role: .destructive) {
                    configManager.loadConfiguration()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .alert("Configuration Errors", isPresented: $showingValidationErrors) {
                Button("OK") { }
            } message: {
                Text(validationErrors.map { $0.message }.joined(separator: "\n"))
            }
            .onChange(of: configManager.hasUnsavedChanges) { _, newValue in
                hasUnsavedChanges = newValue
            }
        }
    
    // MARK: - Header Section
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Item Configuration")
                            .font(.headline)
                        Text("Customize which fields appear in item forms and set default values for Square API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if hasUnsavedChanges {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("You have unsaved changes")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Preset Section
    private var presetSection: some View {
        Section("Quick Setup") {
            VStack(spacing: 12) {
                ForEach(ConfigurationPreset.allCases, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: false, // We'll implement selection logic later
                        action: {
                            configManager.applyPreset(preset)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Field Visibility Section
    private var fieldVisibilitySection: some View {
        Section("Field Visibility") {
            NavigationLink(destination: FieldVisibilityDetailView()) {
                HStack {
                    Image(systemName: "eye")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Field Visibility")
                            .font(.headline)
                        Text("Control which fields appear in item forms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(enabledFieldsCount) enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Default Values Section
    private var defaultValuesSection: some View {
        Section("Default Values") {
            NavigationLink(destination: DefaultValuesDetailView()) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set Default Values")
                            .font(.headline)
                        Text("Configure default values sent to Square API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Square API Section
    private var squareAPISection: some View {
        Section("Square API Compliance") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Requirements Met")
                            .font(.headline)
                        Text("Configuration follows Square API specifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("• Item name is required for all items\n• At least one variation is always required (cannot be disabled)\n• Pricing type must be FIXED_PRICING or VARIABLE_PRICING\n• Tax settings and modifier lists are optional\n• SKU and UPC are optional but recommended")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        Section("Actions") {
            Button("Reset to Default") {
                showingResetAlert = true
            }
            .foregroundColor(.red)
            
            Button("Validate Configuration") {
                validateConfiguration()
            }
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Computed Properties
    private var enabledFieldsCount: Int {
        var count = 0

        // Count enabled fields across all sections
        if configManager.currentConfiguration.basicFields.nameEnabled { count += 1 }
        if configManager.currentConfiguration.basicFields.descriptionEnabled { count += 1 }
        if configManager.currentConfiguration.basicFields.abbreviationEnabled { count += 1 }
        if configManager.currentConfiguration.classificationFields.categoryEnabled { count += 1 }
        if configManager.currentConfiguration.classificationFields.reportingCategoryEnabled { count += 1 }
        // Note: Variations are always enabled (required by Square API)
        if configManager.currentConfiguration.pricingFields.taxEnabled { count += 1 }
        if configManager.currentConfiguration.pricingFields.modifiersEnabled { count += 1 }
        if configManager.currentConfiguration.inventoryFields.trackInventoryEnabled { count += 1 }
        if configManager.currentConfiguration.inventoryFields.inventoryAlertsEnabled { count += 1 }
        if configManager.currentConfiguration.serviceFields.serviceDurationEnabled { count += 1 }
        if configManager.currentConfiguration.serviceFields.teamMembersEnabled { count += 1 }
        if configManager.currentConfiguration.advancedFields.customAttributesEnabled { count += 1 }
        if configManager.currentConfiguration.advancedFields.measurementUnitEnabled { count += 1 }
        if configManager.currentConfiguration.ecommerceFields.availabilityEnabled { count += 1 }
        if configManager.currentConfiguration.ecommerceFields.onlineVisibilityEnabled { count += 1 }
        if configManager.currentConfiguration.ecommerceFields.seoEnabled { count += 1 }
        if configManager.currentConfiguration.advancedFields.enabledLocationsEnabled { count += 1 }
        if configManager.currentConfiguration.teamDataFields.caseDataEnabled { count += 1 }

        return count
    }
    
    // MARK: - Private Methods
    private func saveConfiguration() {
        configManager.saveConfiguration()
        dismiss()
    }
    
    private func validateConfiguration() {
        validationErrors = configManager.validateConfiguration()
        if !validationErrors.isEmpty {
            showingValidationErrors = true
        }
    }
}

// MARK: - Preset Card Component
struct PresetCard: View {
    let preset: ConfigurationPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Field Visibility Detail View
struct FieldVisibilityDetailView: View {
    @ObservedObject var configManager = FieldConfigurationManager.shared

    var body: some View {
        Form {
            Section("Basic Information") {
                FieldToggleRow(
                    title: "Item Name",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.basicFields.nameEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.nameEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.basicFields.nameRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.nameRequired, value: $0) }
                    ),
                    description: "The primary name of the item (Required by Square API)"
                )

                FieldToggleRow(
                    title: "Description",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.basicFields.descriptionEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.descriptionEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.basicFields.descriptionRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.descriptionRequired, value: $0) }
                    ),
                    description: "Detailed description of the item"
                )

                FieldToggleRow(
                    title: "Abbreviation",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.basicFields.abbreviationEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.abbreviationEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.basicFields.abbreviationRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.abbreviationRequired, value: $0) }
                    ),
                    description: "Short abbreviation for the item"
                )
            }
            
            Section("Product Classification") {
                FieldToggleRow(
                    title: "Category",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.classificationFields.categoryEnabled },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.categoryEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.classificationFields.categoryRequired },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.categoryRequired, value: $0) }
                    ),
                    description: "Primary product category"
                )

                FieldToggleRow(
                    title: "Reporting Category",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.classificationFields.reportingCategoryEnabled },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.reportingCategoryEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.classificationFields.reportingCategoryRequired },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.reportingCategoryRequired, value: $0) }
                    ),
                    description: "Category used for reporting purposes"
                )
            }
            
            Section("Taxes and Modifiers") {
                FieldToggleRow(
                    title: "Tax Settings",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.pricingFields.taxEnabled },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.taxEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.pricingFields.taxRequired },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.taxRequired, value: $0) }
                    ),
                    description: "Tax configuration for the item"
                )

                FieldToggleRow(
                    title: "Modifier Lists",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.pricingFields.modifiersEnabled },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.modifiersEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.pricingFields.modifiersRequired },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.modifiersRequired, value: $0) }
                    ),
                    description: "Modifier lists that can be applied to this item"
                )
            }
            
            Section("Inventory Management") {
                FieldToggleRow(
                    title: "Track Inventory",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.inventoryFields.trackInventoryEnabled },
                        set: { configManager.updateFieldConfiguration(\.inventoryFields.trackInventoryEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.inventoryFields.trackInventoryRequired },
                        set: { configManager.updateFieldConfiguration(\.inventoryFields.trackInventoryRequired, value: $0) }
                    ),
                    description: "Enable inventory tracking for this item"
                )

                FieldToggleRow(
                    title: "Inventory Alerts",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.inventoryFields.inventoryAlertsEnabled },
                        set: { configManager.updateFieldConfiguration(\.inventoryFields.inventoryAlertsEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.inventoryFields.inventoryAlertsRequired },
                        set: { configManager.updateFieldConfiguration(\.inventoryFields.inventoryAlertsRequired, value: $0) }
                    ),
                    description: "Low stock alerts and thresholds"
                )
            }

            Section("Availability & Locations") {
                FieldToggleRow(
                    title: "Availability Settings",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.availabilityEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.availabilityEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.availabilityRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.availabilityRequired, value: $0) }
                    ),
                    description: "Control item availability for sale, online, and pickup"
                )

                FieldToggleRow(
                    title: "Enabled Locations",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.advancedFields.enabledLocationsEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.enabledLocationsEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.advancedFields.enabledLocationsRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.enabledLocationsRequired, value: $0) }
                    ),
                    description: "Specify which locations this item is available at"
                )
            }

            Section("Advanced Features") {
                FieldToggleRow(
                    title: "Custom Attributes",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.advancedFields.customAttributesEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.customAttributesEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.advancedFields.customAttributesRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.customAttributesRequired, value: $0) }
                    ),
                    description: "Add custom key-value pairs for additional item metadata"
                )

                FieldToggleRow(
                    title: "Measurement Units",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.advancedFields.measurementUnitEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.measurementUnitEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.advancedFields.measurementUnitRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.measurementUnitRequired, value: $0) }
                    ),
                    description: "Set measurement units and sellable/stockable properties"
                )
            }

            Section("E-commerce & SEO") {
                FieldToggleRow(
                    title: "Online Visibility",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.onlineVisibilityEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.onlineVisibilityEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.onlineVisibilityRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.onlineVisibilityRequired, value: $0) }
                    ),
                    description: "Control item visibility in online channels"
                )

                FieldToggleRow(
                    title: "SEO Settings",
                    isEnabled: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.seoEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.seoEnabled, value: $0) }
                    ),
                    isRequired: Binding(
                        get: { configManager.currentConfiguration.ecommerceFields.seoRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.seoRequired, value: $0) }
                    ),
                    description: "SEO title, description, and keywords for search optimization"
                )
            }
        }
        .navigationTitle("Field Visibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Default Values Detail View
struct DefaultValuesDetailView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        Form {
            Section("Square API Defaults") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default values are automatically applied when creating new items to ensure Square API compliance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Required Fields:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• Item name: User input required\n• At least one variation: Auto-created with default values\n• Pricing type: FIXED_PRICING (default)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section("Default Item Values") {
                HStack {
                    Text("Product Type")
                    Spacer()
                    Text("REGULAR")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Available Online")
                    Spacer()
                    Text("true")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Available for Pickup")
                    Spacer()
                    Text("true")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Present at All Locations")
                    Spacer()
                    Text("true")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Default Variation Values") {
                HStack {
                    Text("Pricing Type")
                    Spacer()
                    Text("FIXED_PRICING")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Track Inventory")
                    Spacer()
                    Text("false")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Sellable")
                    Spacer()
                    Text("true")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Stockable")
                    Spacer()
                    Text("true")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("API Compliance Notes") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These defaults ensure all created items meet Square's API requirements:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• Items must have a name and at least one variation\n• Pricing type must be FIXED_PRICING or VARIABLE_PRICING\n• Boolean fields default to appropriate values\n• Optional fields are omitted if not specified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Default Values")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview
#Preview {
    ItemSettingsView()
}
