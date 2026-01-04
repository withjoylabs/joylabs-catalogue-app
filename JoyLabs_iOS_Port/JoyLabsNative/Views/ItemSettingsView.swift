import SwiftUI

// MARK: - Item Settings View
/// Comprehensive settings page for customizing item defaults and field visibility
struct ItemSettingsView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    @StateObject private var imageSaveService = ImageSaveService.shared
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
            imageOptionsSection
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
                            .foregroundColor(Color.secondary)
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
            NavigationLink(destination: FieldVisibilityAndReorderingView()) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Field Visibility & Reordering")
                            .font(.headline)
                        Text("Control field visibility and reorder sections")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
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
                            .foregroundColor(Color.secondary)
                    }

                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Image Options Section
    private var imageOptionsSection: some View {
        Section("Image Options") {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Processed Images")
                        .font(.headline)
                    Text("Automatically save cropped images to camera roll")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }

                Spacer()

                Toggle("", isOn: $imageSaveService.saveProcessedImages)
                    .labelsHidden()
                    .onChange(of: imageSaveService.saveProcessedImages) { _, _ in
                        imageSaveService.saveSettings()
                    }
            }
            .padding(.vertical, 4)
            
            if imageSaveService.saveProcessedImages {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("Processed images will be saved to your camera roll with crop details and processing metadata.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(.top, 4)
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
                            .foregroundColor(Color.secondary)
                    }
                }
                
                Text("• Item name is required for all items\n• At least one variation is always required (cannot be disabled)\n• Pricing type must be FIXED_PRICING or VARIABLE_PRICING\n• Tax settings and modifier lists are optional\n• SKU and UPC are optional but recommended")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
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
        if configManager.currentConfiguration.classificationFields.isAlcoholicEnabled { count += 1 }
        // Note: Variations are always enabled (required by Square API)
        if configManager.currentConfiguration.pricingFields.taxEnabled { count += 1 }
        if configManager.currentConfiguration.pricingFields.isTaxableEnabled { count += 1 }
        if configManager.currentConfiguration.pricingFields.modifiersEnabled { count += 1 }
        if configManager.currentConfiguration.inventoryFields.trackInventoryEnabled { count += 1 }
        if configManager.currentConfiguration.inventoryFields.inventoryAlertsEnabled { count += 1 }
        if configManager.currentConfiguration.serviceFields.serviceDurationEnabled { count += 1 }
        if configManager.currentConfiguration.serviceFields.teamMembersEnabled { count += 1 }
        if configManager.currentConfiguration.advancedFields.customAttributesEnabled { count += 1 }
        if configManager.currentConfiguration.advancedFields.measurementUnitEnabled { count += 1 }
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
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(Color.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - Default Values Detail View
struct DefaultValuesDetailView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        Form {
            Section("Square API Defaults") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set default values that are automatically applied when creating new items. Fields are only included in Square API requests if they have a value.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    
                    Text("Required Fields:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• Item name: User input required\n• At least one variation: Auto-created with default values\n• Pricing type: FIXED_PRICING (default)")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(.vertical, 4)
            }
            
            basicDefaultsSection
            pricingDefaultsSection
            classificationDefaultsSection
            variationDefaultsSection
            complianceNotesSection
        }
        .navigationTitle("Default Values")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Basic Defaults Section
    private var basicDefaultsSection: some View {
        Section(header: HStack {
            Text("Basic Item Defaults")
            Spacer()
            Button("Reset") {
                resetBasicDefaults()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }) {
            DefaultValueToggleRow(
                title: "Available Online",
                binding: Binding(
                    get: { configManager.currentConfiguration.ecommerceFields.defaultAvailableOnline },
                    set: { configManager.updateFieldConfiguration(\.ecommerceFields.defaultAvailableOnline, value: $0) }
                ),
                isEnabled: true
            )
            
            DefaultValueToggleRow(
                title: "Available for Pickup", 
                binding: Binding(
                    get: { configManager.currentConfiguration.ecommerceFields.defaultAvailableForPickup },
                    set: { configManager.updateFieldConfiguration(\.ecommerceFields.defaultAvailableForPickup, value: $0) }
                ),
                isEnabled: true
            )
            
            DefaultValueToggleRow(
                title: "Present at All Locations",
                binding: Binding(
                    get: { configManager.currentConfiguration.basicFields.defaultPresentAtAllLocations },
                    set: { configManager.updateFieldConfiguration(\.basicFields.defaultPresentAtAllLocations, value: $0) }
                ),
                isEnabled: true
            )
        }
    }
    
    // MARK: - Pricing Defaults Section
    private var pricingDefaultsSection: some View {
        Section(header: HStack {
            Text("Pricing & Modifier Defaults")
            Spacer()
            Button("Reset") {
                resetPricingDefaults()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }) {
            if configManager.currentConfiguration.pricingFields.isTaxableEnabled {
                DefaultValueToggleRow(
                    title: "Item is Taxable",
                    binding: Binding(
                        get: { configManager.currentConfiguration.pricingFields.defaultIsTaxable },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.defaultIsTaxable, value: $0) }
                    ),
                    isEnabled: true
                )
            }
            
            if configManager.currentConfiguration.pricingFields.skipModifierScreenEnabled {
                DefaultValueToggleRow(
                    title: "Skip Details Screen at Checkout",
                    binding: Binding(
                        get: { configManager.currentConfiguration.pricingFields.defaultSkipModifierScreen },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.defaultSkipModifierScreen, value: $0) }
                    ),
                    isEnabled: true
                )
            }
        }
    }
    
    // MARK: - Classification Defaults Section  
    private var classificationDefaultsSection: some View {
        Section(header: HStack {
            Text("Classification Defaults")
            Spacer()
            Button("Reset") {
                resetClassificationDefaults()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }) {
            if configManager.currentConfiguration.classificationFields.isAlcoholicEnabled {
                DefaultValueToggleRow(
                    title: "Contains Alcohol",
                    binding: Binding(
                        get: { configManager.currentConfiguration.classificationFields.defaultIsAlcoholic },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.defaultIsAlcoholic, value: $0) }
                    ),
                    isEnabled: true
                )
            }
        }
    }
    
    // MARK: - Variation Defaults Section
    private var variationDefaultsSection: some View {
        Section(header: HStack {
            Text("Variation Defaults")
            Spacer()
            Button("Reset") {
                resetVariationDefaults()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Inventory Tracking Mode")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Tracking Mode", selection: Binding(
                    get: { configManager.currentConfiguration.inventoryFields.defaultInventoryTrackingMode },
                    set: { configManager.updateFieldConfiguration(\.inventoryFields.defaultInventoryTrackingMode, value: $0) }
                )) {
                    ForEach(InventoryTrackingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 8)
            
            DefaultValueToggleRow(
                title: "Sellable",
                binding: Binding(
                    get: { configManager.currentConfiguration.advancedFields.defaultSellable },
                    set: { configManager.updateFieldConfiguration(\.advancedFields.defaultSellable, value: $0) }
                ),
                isEnabled: true
            )
            
            DefaultValueToggleRow(
                title: "Stockable",
                binding: Binding(
                    get: { configManager.currentConfiguration.advancedFields.defaultStockable },
                    set: { configManager.updateFieldConfiguration(\.advancedFields.defaultStockable, value: $0) }
                ),
                isEnabled: true
            )
        }
    }
    
    // MARK: - Compliance Notes Section
    private var complianceNotesSection: some View {
        Section("API Compliance Notes") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default values ensure Square API compliance:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("• Hidden fields are excluded from API requests\n• Default values apply only to enabled fields\n• Boolean fields use these defaults when creating items\n• Required fields must still be filled by user")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Reset Methods
    private func resetBasicDefaults() {
        configManager.updateFieldConfiguration(\.ecommerceFields.defaultAvailableOnline, value: true)
        configManager.updateFieldConfiguration(\.ecommerceFields.defaultAvailableForPickup, value: true) 
        configManager.updateFieldConfiguration(\.basicFields.defaultPresentAtAllLocations, value: true)
    }
    
    private func resetPricingDefaults() {
        configManager.updateFieldConfiguration(\.pricingFields.defaultIsTaxable, value: true)
        configManager.updateFieldConfiguration(\.pricingFields.defaultSkipModifierScreen, value: false)
    }
    
    private func resetClassificationDefaults() {
        configManager.updateFieldConfiguration(\.classificationFields.defaultIsAlcoholic, value: false)
    }
    
    private func resetVariationDefaults() {
        configManager.updateFieldConfiguration(\.inventoryFields.defaultInventoryTrackingMode, value: .unavailable)
        configManager.updateFieldConfiguration(\.advancedFields.defaultSellable, value: true)
        configManager.updateFieldConfiguration(\.advancedFields.defaultStockable, value: true)
    }
}

// MARK: - Default Value Toggle Row Component
struct DefaultValueToggleRow: View {
    let title: String
    @Binding var binding: Bool
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(isEnabled ? .primary : .secondary)
            
            Spacer()
            
            Toggle("", isOn: $binding)
                .labelsHidden()
                .disabled(!isEnabled)
        }
    }
}

// MARK: - Preview
#Preview {
    ItemSettingsView()
}
