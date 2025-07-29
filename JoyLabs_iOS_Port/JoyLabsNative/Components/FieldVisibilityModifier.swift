import SwiftUI

// MARK: - Field Visibility System
// Runtime field visibility based on configuration settings

/// View modifier that conditionally shows/hides fields based on configuration
struct FieldVisibilityModifier: ViewModifier {
    let fieldPath: FieldPath
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    func body(content: Content) -> some View {
        if configManager.isFieldEnabled(fieldPath) {
            content
        } else {
            EmptyView()
        }
    }
}

/// View modifier that adds required field indicators
struct RequiredFieldModifier: ViewModifier {
    let fieldPath: FieldPath
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    func body(content: Content) -> some View {
        HStack {
            content
            
            if configManager.isFieldRequired(fieldPath) {
                Text("*")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}

/// View modifier that applies field configuration styling
struct FieldConfigurationModifier: ViewModifier {
    let fieldPath: FieldPath
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    func body(content: Content) -> some View {
        content
            .modifier(FieldVisibilityModifier(fieldPath: fieldPath))
            .modifier(RequiredFieldModifier(fieldPath: fieldPath))
    }
}

// MARK: - View Extensions
extension View {
    /// Apply field visibility based on configuration
    func fieldVisibility(_ fieldPath: FieldPath) -> some View {
        modifier(FieldVisibilityModifier(fieldPath: fieldPath))
    }
    
    /// Add required field indicator based on configuration
    func requiredField(_ fieldPath: FieldPath) -> some View {
        modifier(RequiredFieldModifier(fieldPath: fieldPath))
    }
    
    /// Apply complete field configuration (visibility + required indicator)
    func fieldConfiguration(_ fieldPath: FieldPath) -> some View {
        modifier(FieldConfigurationModifier(fieldPath: fieldPath))
    }
}

// MARK: - Conditional Field Container
/// Container that shows/hides entire sections based on field configuration
struct ConditionalFieldSection<Content: View>: View {
    let fieldPaths: [FieldPath]
    let content: Content
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    init(fieldPaths: [FieldPath], @ViewBuilder content: () -> Content) {
        self.fieldPaths = fieldPaths
        self.content = content()
    }
    
    var body: some View {
        if hasEnabledFields {
            content
        } else {
            EmptyView()
        }
    }
    
    private var hasEnabledFields: Bool {
        fieldPaths.contains { configManager.isFieldEnabled($0) }
    }
}

// MARK: - Field Configuration Environment
/// Environment key for field configuration
struct FieldConfigurationEnvironmentKey: EnvironmentKey {
    static let defaultValue: ItemFieldConfiguration = ItemFieldConfiguration.defaultConfiguration()
}

extension EnvironmentValues {
    var fieldConfiguration: ItemFieldConfiguration {
        get { self[FieldConfigurationEnvironmentKey.self] }
        set { self[FieldConfigurationEnvironmentKey.self] = newValue }
    }
}

// MARK: - Configuration-Aware Form Components

/// Text field that respects field configuration
struct ConfigurableTextField: View {
    let fieldPath: FieldPath
    let title: String
    @Binding var text: String
    let placeholder: String
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                
                if configManager.isFieldRequired(fieldPath) {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .fieldVisibility(fieldPath)
    }
}

/// Toggle that respects field configuration
struct ConfigurableToggle: View {
    let fieldPath: FieldPath
    let title: String
    @Binding var isOn: Bool
    let description: String?
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        
                        if configManager.isFieldRequired(fieldPath) {
                            Text("*")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .fieldVisibility(fieldPath)
    }
}

/// Picker that respects field configuration
struct ConfigurablePicker<SelectionValue: Hashable, Content: View>: View {
    let fieldPath: FieldPath
    let title: String
    @Binding var selection: SelectionValue
    let content: Content
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    init(
        fieldPath: FieldPath,
        title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.fieldPath = fieldPath
        self.title = title
        self._selection = selection
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                
                if configManager.isFieldRequired(fieldPath) {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.menu)
        }
        .fieldVisibility(fieldPath)
    }
}

// MARK: - Section Visibility Helper
/// Helper to determine if a section should be visible based on its fields
struct SectionVisibilityHelper {
    static func shouldShowBasicSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.basicFields.nameEnabled ||
               config.basicFields.descriptionEnabled ||
               config.basicFields.abbreviationEnabled ||
               config.basicFields.labelColorEnabled
    }
    
    static func shouldShowClassificationSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.classificationFields.categoryEnabled ||
               config.classificationFields.reportingCategoryEnabled ||
               config.classificationFields.productTypeEnabled
    }
    
    static func shouldShowPricingSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.pricingFields.variationsEnabled ||
               config.pricingFields.taxEnabled ||
               config.pricingFields.modifiersEnabled ||
               config.pricingFields.itemOptionsEnabled
    }
    
    static func shouldShowInventorySection(_ config: ItemFieldConfiguration) -> Bool {
        return config.inventoryFields.trackInventoryEnabled ||
               config.inventoryFields.inventoryAlertsEnabled ||
               config.inventoryFields.locationOverridesEnabled ||
               config.inventoryFields.stockOnHandEnabled
    }
    
    static func shouldShowServiceSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.serviceFields.serviceDurationEnabled ||
               config.serviceFields.teamMembersEnabled ||
               config.serviceFields.bookingEnabled
    }
    
    static func shouldShowAdvancedSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.advancedFields.customAttributesEnabled ||
               config.advancedFields.measurementUnitEnabled ||
               config.advancedFields.sellableEnabled ||
               config.advancedFields.stockableEnabled ||
               config.advancedFields.userDataEnabled ||
               config.advancedFields.channelsEnabled
    }
    
    static func shouldShowEcommerceSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.ecommerceFields.onlineVisibilityEnabled ||
               config.ecommerceFields.availabilityEnabled ||
               config.ecommerceFields.seoEnabled ||
               config.ecommerceFields.ecomVisibilityEnabled ||
               config.ecommerceFields.availabilityPeriodsEnabled
    }
    
    static func shouldShowTeamDataSection(_ config: ItemFieldConfiguration) -> Bool {
        return config.teamDataFields.caseDataEnabled ||
               config.teamDataFields.caseUpcEnabled ||
               config.teamDataFields.caseCostEnabled ||
               config.teamDataFields.caseQuantityEnabled ||
               config.teamDataFields.vendorEnabled ||
               config.teamDataFields.discontinuedEnabled ||
               config.teamDataFields.notesEnabled
    }
}

// MARK: - Configuration-Aware Section
/// Section that automatically hides if no fields are enabled
struct ConfigurableSection<Content: View>: View {
    let title: String
    let fieldPaths: [FieldPath]
    let content: Content
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    init(title: String, fieldPaths: [FieldPath], @ViewBuilder content: () -> Content) {
        self.title = title
        self.fieldPaths = fieldPaths
        self.content = content()
    }
    
    var body: some View {
        if hasVisibleFields {
            Section(title) {
                content
            }
        } else {
            EmptyView()
        }
    }
    
    private var hasVisibleFields: Bool {
        fieldPaths.contains { configManager.isFieldEnabled($0) }
    }
}

// MARK: - Preview Helpers
#if DEBUG
extension FieldConfigurationManager {
    static var preview: FieldConfigurationManager {
        return FieldConfigurationManager.shared
    }
}
#endif

// MARK: - Preview
#Preview {
    NavigationView {
        Form {
            ConfigurableTextField(
                fieldPath: .basicName,
                title: "Item Name",
                text: .constant("Sample Item"),
                placeholder: "Enter item name"
            )
            
            ConfigurableToggle(
                fieldPath: .inventoryTracking,
                title: "Track Inventory",
                isOn: .constant(true),
                description: "Enable inventory tracking for this item"
            )
            
            ConfigurablePicker(
                fieldPath: .classificationCategory,
                title: "Category",
                selection: .constant("Food")
            ) {
                Text("Food").tag("Food")
                Text("Beverage").tag("Beverage")
                Text("Retail").tag("Retail")
            }
        }
        .navigationTitle("Configuration Demo")
    }
}
