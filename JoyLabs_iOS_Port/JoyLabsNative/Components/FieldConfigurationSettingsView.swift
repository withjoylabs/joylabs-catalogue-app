import SwiftUI

// MARK: - Field Configuration Settings View
// Foundation UI for managing field visibility and default values

/// Settings view for configuring field visibility and defaults
struct FieldConfigurationSettingsView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var selectedPreset: ConfigurationPreset = .default
    @State private var showingResetAlert = false
    @State private var showingValidationErrors = false
    @State private var validationErrors: [ConfigurationValidationError] = []
    
    var body: some View {
        NavigationView {
            Form {
                presetSection
                basicFieldsSection
                classificationFieldsSection
                pricingFieldsSection
                inventoryFieldsSection
                serviceFieldsSection
                advancedFieldsSection
                ecommerceFieldsSection
                teamDataFieldsSection
                actionsSection
            }
            .navigationTitle("Field Configuration")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .disabled(!configManager.hasUnsavedChanges)
                }
            }
            .alert("Reset Configuration", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) {
                    configManager.resetToDefault()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will reset all field configurations to default values. This action cannot be undone.")
            }
            .alert("Configuration Errors", isPresented: $showingValidationErrors) {
                Button("OK") { }
            } message: {
                Text(validationErrors.map { $0.message }.joined(separator: "\n"))
            }
        }
    }
    
    // MARK: - Preset Section
    private var presetSection: some View {
        Section("Configuration Presets") {
            Picker("Preset", selection: $selectedPreset) {
                ForEach(ConfigurationPreset.allCases, id: \.self) { preset in
                    VStack(alignment: .leading) {
                        Text(preset.displayName)
                            .font(.headline)
                        Text(preset.description)
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPreset) { _, newPreset in
                configManager.applyPreset(newPreset)
            }
            
            if configManager.hasUnsavedChanges {
                Text("Configuration has unsaved changes")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Basic Fields Section
    private var basicFieldsSection: some View {
        Section("Basic Information") {
            FieldToggleRow(
                title: "Item Name",
                isEnabled: $configManager.currentConfiguration.basicFields.nameEnabled,
                isRequired: $configManager.currentConfiguration.basicFields.nameRequired,
                description: "The primary name of the item"
            )
            
            FieldToggleRow(
                title: "Description",
                isEnabled: $configManager.currentConfiguration.basicFields.descriptionEnabled,
                isRequired: $configManager.currentConfiguration.basicFields.descriptionRequired,
                description: "Detailed description of the item"
            )
            
            FieldToggleRow(
                title: "Abbreviation",
                isEnabled: $configManager.currentConfiguration.basicFields.abbreviationEnabled,
                isRequired: $configManager.currentConfiguration.basicFields.abbreviationRequired,
                description: "Short abbreviation for the item"
            )
            
            FieldToggleRow(
                title: "Label Color",
                isEnabled: $configManager.currentConfiguration.basicFields.labelColorEnabled,
                isRequired: .constant(false),
                description: "Color coding for item labels"
            )
        }
    }
    
    // MARK: - Classification Fields Section
    private var classificationFieldsSection: some View {
        Section("Product Classification") {
            FieldToggleRow(
                title: "Category",
                isEnabled: $configManager.currentConfiguration.classificationFields.categoryEnabled,
                isRequired: $configManager.currentConfiguration.classificationFields.categoryRequired,
                description: "Primary product category"
            )
            
            FieldToggleRow(
                title: "Reporting Category",
                isEnabled: $configManager.currentConfiguration.classificationFields.reportingCategoryEnabled,
                isRequired: $configManager.currentConfiguration.classificationFields.reportingCategoryRequired,
                description: "Category used for reporting purposes"
            )
            
            FieldToggleRow(
                title: "Product Type",
                isEnabled: $configManager.currentConfiguration.classificationFields.productTypeEnabled,
                isRequired: $configManager.currentConfiguration.classificationFields.productTypeRequired,
                description: "Type of product (regular, service, etc.)"
            )
        }
    }
    
    // MARK: - Pricing Fields Section
    private var pricingFieldsSection: some View {
        Section("Pricing & Variations") {
            FieldToggleRow(
                title: "Variations",
                isEnabled: $configManager.currentConfiguration.pricingFields.variationsEnabled,
                isRequired: $configManager.currentConfiguration.pricingFields.variationsRequired,
                description: "Product variations with different prices"
            )
            
            FieldToggleRow(
                title: "Tax Settings",
                isEnabled: $configManager.currentConfiguration.pricingFields.taxEnabled,
                isRequired: $configManager.currentConfiguration.pricingFields.taxRequired,
                description: "Tax configuration for the item"
            )
            
            FieldToggleRow(
                title: "Modifiers",
                isEnabled: $configManager.currentConfiguration.pricingFields.modifiersEnabled,
                isRequired: $configManager.currentConfiguration.pricingFields.modifiersRequired,
                description: "Item modifiers and add-ons"
            )
        }
    }
    
    // MARK: - Inventory Fields Section
    private var inventoryFieldsSection: some View {
        Section("Inventory Management") {
            FieldToggleRow(
                title: "Track Inventory",
                isEnabled: $configManager.currentConfiguration.inventoryFields.trackInventoryEnabled,
                isRequired: $configManager.currentConfiguration.inventoryFields.trackInventoryRequired,
                description: "Enable inventory tracking for this item"
            )
            
            FieldToggleRow(
                title: "Inventory Alerts",
                isEnabled: $configManager.currentConfiguration.inventoryFields.inventoryAlertsEnabled,
                isRequired: $configManager.currentConfiguration.inventoryFields.inventoryAlertsRequired,
                description: "Low stock alerts and thresholds"
            )
            
            FieldToggleRow(
                title: "Location Overrides",
                isEnabled: $configManager.currentConfiguration.inventoryFields.locationOverridesEnabled,
                isRequired: $configManager.currentConfiguration.inventoryFields.locationOverridesRequired,
                description: "Location-specific inventory settings"
            )
        }
    }
    
    // MARK: - Service Fields Section
    private var serviceFieldsSection: some View {
        Section("Service Configuration") {
            FieldToggleRow(
                title: "Service Duration",
                isEnabled: $configManager.currentConfiguration.serviceFields.serviceDurationEnabled,
                isRequired: $configManager.currentConfiguration.serviceFields.serviceDurationRequired,
                description: "Duration for service appointments"
            )
            
            FieldToggleRow(
                title: "Team Members",
                isEnabled: $configManager.currentConfiguration.serviceFields.teamMembersEnabled,
                isRequired: $configManager.currentConfiguration.serviceFields.teamMembersRequired,
                description: "Assign team members to services"
            )
            
            FieldToggleRow(
                title: "Booking Settings",
                isEnabled: $configManager.currentConfiguration.serviceFields.bookingEnabled,
                isRequired: $configManager.currentConfiguration.serviceFields.bookingRequired,
                description: "Online booking availability"
            )
        }
    }
    
    // MARK: - Advanced Fields Section
    private var advancedFieldsSection: some View {
        Section("Advanced Features") {
            FieldToggleRow(
                title: "Custom Attributes",
                isEnabled: $configManager.currentConfiguration.advancedFields.customAttributesEnabled,
                isRequired: $configManager.currentConfiguration.advancedFields.customAttributesRequired,
                description: "Custom data fields for items"
            )
            
            FieldToggleRow(
                title: "Measurement Units",
                isEnabled: $configManager.currentConfiguration.advancedFields.measurementUnitEnabled,
                isRequired: $configManager.currentConfiguration.advancedFields.measurementUnitRequired,
                description: "Units of measurement for items"
            )
        }
    }
    
    // MARK: - E-commerce Fields Section
    private var ecommerceFieldsSection: some View {
        Section("E-commerce Settings") {
            FieldToggleRow(
                title: "Availability Settings",
                isEnabled: $configManager.currentConfiguration.ecommerceFields.availabilityEnabled,
                isRequired: $configManager.currentConfiguration.ecommerceFields.availabilityRequired,
                description: "Online and pickup availability"
            )
            
            FieldToggleRow(
                title: "SEO Settings",
                isEnabled: $configManager.currentConfiguration.ecommerceFields.seoEnabled,
                isRequired: $configManager.currentConfiguration.ecommerceFields.seoRequired,
                description: "Search engine optimization settings"
            )
        }
    }
    
    // MARK: - Team Data Fields Section
    private var teamDataFieldsSection: some View {
        Section("Team Data") {
            FieldToggleRow(
                title: "Case Information",
                isEnabled: $configManager.currentConfiguration.teamDataFields.caseDataEnabled,
                isRequired: $configManager.currentConfiguration.teamDataFields.caseDataRequired,
                description: "Case UPC, cost, and quantity information"
            )
            
            FieldToggleRow(
                title: "Vendor Information",
                isEnabled: $configManager.currentConfiguration.teamDataFields.vendorEnabled,
                isRequired: $configManager.currentConfiguration.teamDataFields.vendorRequired,
                description: "Vendor and supplier information"
            )
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
        }
    }
    
    // MARK: - Private Methods
    private func saveConfiguration() {
        configManager.saveConfiguration()
    }
    
    private func validateConfiguration() {
        validationErrors = configManager.validateConfiguration()
        if !validationErrors.isEmpty {
            showingValidationErrors = true
        }
    }
}

// MARK: - Field Toggle Row Component
struct FieldToggleRow: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var isRequired: Bool
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.body)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            
            if isEnabled {
                HStack {
                    Text("Required")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $isRequired)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .padding(.leading, 16)
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                isRequired = false
            }
        }
    }
}

// MARK: - Preview
#Preview {
    FieldConfigurationSettingsView()
}
