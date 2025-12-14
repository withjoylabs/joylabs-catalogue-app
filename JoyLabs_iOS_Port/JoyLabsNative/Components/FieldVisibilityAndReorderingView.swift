import SwiftUI

// MARK: - Field Visibility & Reordering View
/// Unified interface for managing field visibility and section reordering
struct FieldVisibilityAndReorderingView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var showingResetAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            controlButtonsSection
            sectionsListView
        }
        .navigationTitle("Field Visibility & Reordering")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset to Defaults", isPresented: $showingResetAlert) {
            Button("Reset", role: .destructive) {
                configManager.resetToDefault()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset all field visibility and section order to default values. This action cannot be undone.")
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Field Visibility & Reordering")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Control which fields appear and drag sections to reorder them.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    private var controlButtonsSection: some View {
        HStack(spacing: 12) {
            Button("Toggle All") {
                toggleAllSections()
            }
            .buttonStyle(.bordered)
            
            Button("Reset Arrangement") {
                resetSectionOrder()
            }
            .buttonStyle(.bordered)
            
            Button("Reset to Defaults") {
                showingResetAlert = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding(.horizontal)
    }
    
    private var sectionsListView: some View {
        List {
            ForEach(configManager.currentConfiguration.orderedSections, id: \.id) { section in
                SectionConfigurationCard(
                    section: section,
                    onToggleEnabled: {
                        configManager.updateSectionConfiguration(section.id) { $0.isEnabled.toggle() }
                    }
                )
                .listRowBackground(Color.clear) // Remove List's gray background
                .listRowSeparator(.hidden) // Remove List's separators
                .listRowInsets(EdgeInsets()) // Remove List's padding
            }
            .onMove(perform: moveSection)
        }
        .listStyle(.plain) // Use plain style to reduce List chrome
        .environment(\.editMode, .constant(.active)) // Always show drag handles
        .scrollContentBackground(.hidden) // Remove List's background
        .background(Color(.systemGroupedBackground)) // Match our original background
        .cornerRadius(12) // Match original corner radius
        .padding(.horizontal) // Match original padding
    }
    
    // MARK: - List Reordering (iOS 16+ Standard Approach)
    
    private func moveSection(from source: IndexSet, to destination: Int) {
        var sections = configManager.currentConfiguration.orderedSections
        sections.move(fromOffsets: source, toOffset: destination)
        
        // Update order values
        var updatedConfigurations = [String: SectionConfiguration]()
        for (index, var section) in sections.enumerated() {
            section.order = index
            updatedConfigurations[section.id] = section
        }
        
        configManager.updateAllSectionConfigurations(updatedConfigurations)
    }
    
    // MARK: - Helper Methods
    
    private func toggleAllSections() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let allEnabled = configManager.currentConfiguration.orderedSections.allSatisfy { $0.isEnabled }
            let newEnabledState = !allEnabled
            
            for section in configManager.currentConfiguration.orderedSections {
                configManager.updateSectionConfiguration(section.id) { $0.isEnabled = newEnabledState }
            }
        }
    }
    
    private func resetSectionOrder() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // Preserve current visibility states
            let currentStates = configManager.currentConfiguration.orderedSections.reduce(into: [String: Bool]()) {
                $0[$1.id] = $1.isEnabled
            }
            
            // Get default section order
            let defaultSections = SectionConfiguration.defaultSections
            var updatedConfigurations = configManager.currentConfiguration.sectionConfigurations
            
            // Reset order to default while preserving enabled states
            for (index, defaultSection) in defaultSections.enumerated() {
                if var section = updatedConfigurations[defaultSection.id] {
                    section.order = index
                    section.isEnabled = currentStates[defaultSection.id] ?? defaultSection.isEnabled
                    updatedConfigurations[defaultSection.id] = section
                }
            }
            
            // Apply the changes
            configManager.updateAllSectionConfigurations(updatedConfigurations)
        }
    }
}

// MARK: - Section Configuration Card
struct SectionConfigurationCard: View {
    let section: SectionConfiguration
    let onToggleEnabled: () -> Void
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Main section row - NO Button wrapper to avoid interaction conflicts
            HStack(spacing: 12) {
                // Drag handle (matching native iOS style)
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(Color(.tertiaryLabel))
                    .font(.system(size: 18, weight: .regular))
                    .imageScale(.medium)
                
                // Section icon
                Image(systemName: section.icon)
                    .foregroundColor(section.isEnabled ? .accentColor : .secondary)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)
                
                // Expandable content area (only this part is tappable for expand/collapse)
                HStack(spacing: 8) {
                    // Section title
                    Text(section.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(section.isEnabled ? .primary : .secondary)
                    
                    Spacer()
                    
                    // Chevron for expandable sections
                    if hasConfigurableFields {
                        Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasConfigurableFields {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            configManager.updateSectionConfiguration(section.id) { $0.isExpanded.toggle() }
                        }
                    }
                }
                
                // Toggle - Always interactive, never disabled
                Toggle("", isOn: Binding(
                    get: { section.isEnabled },
                    set: { newValue in
                        onToggleEnabled()
                        // CASCADE: Toggle all child fields when parent section is toggled
                        if hasConfigurableFields {
                            toggleAllChildFields(to: newValue)
                        }
                    }
                ))
                .labelsHidden()
                .scaleEffect(0.8)
                .allowsHitTesting(true) // Ensure toggle is always interactive
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            // Expanded field list (only for sections with configurable fields)
            if section.isExpanded && hasConfigurableFields {
                VStack(spacing: 0) {
                    Divider()
                    
                    // PERFORMANCE: Use VStack instead of LazyVStack for small lists (better for <10 items)
                    VStack(spacing: 0) {
                        ForEach(Array(fieldsForSection.enumerated()), id: \.offset) { index, fieldData in
                            FieldConfigurationRow(
                                fieldName: fieldData.name,
                                description: fieldData.description,
                                isEnabled: fieldData.enabledBinding,
                                isRequired: fieldData.requiredBinding
                            )
                            
                            if index < fieldsForSection.count - 1 {
                                Divider()
                                    .padding(.leading, 24)
                            }
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top))) // Native iOS transition
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    // MARK: - Helper Properties
    private var hasConfigurableFields: Bool {
        return !fieldsForSection.isEmpty
    }

    // PERFORMANCE: Cache field calculation to avoid repeated computation
    private var fieldsForSection: [FieldData] {
        getFieldsForSection(section.id)
    }

    // MARK: - Helper Methods

    /// Toggle all child fields when parent section is toggled (improved UX)
    private func toggleAllChildFields(to newValue: Bool) {
        let fields = getFieldsForSection(section.id)
        for field in fields {
            field.enabledBinding.wrappedValue = newValue
        }
    }

    private func getFieldsForSection(_ sectionId: String) -> [FieldData] {
        let config = configManager.currentConfiguration
        
        switch sectionId {
        case "basicInfo":
            return [
                FieldData(
                    name: "Item Name",
                    description: "The primary name of the item (Required by Square API)",
                    enabledBinding: Binding(
                        get: { config.basicFields.nameEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.nameEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.basicFields.nameRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.nameRequired, value: $0) }
                    )
                ),
                FieldData(
                    name: "Description",
                    description: "Detailed description of the item",
                    enabledBinding: Binding(
                        get: { config.basicFields.descriptionEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.descriptionEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.basicFields.descriptionRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.descriptionRequired, value: $0) }
                    )
                ),
                FieldData(
                    name: "Abbreviation",
                    description: "Short abbreviation for the item",
                    enabledBinding: Binding(
                        get: { config.basicFields.abbreviationEnabled },
                        set: { configManager.updateFieldConfiguration(\.basicFields.abbreviationEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.basicFields.abbreviationRequired },
                        set: { configManager.updateFieldConfiguration(\.basicFields.abbreviationRequired, value: $0) }
                    )
                )
            ]
        case "categories":
            return [
                FieldData(
                    name: "Primary Category",
                    description: "Primary product category",
                    enabledBinding: Binding(
                        get: { config.classificationFields.categoryEnabled },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.categoryEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.classificationFields.categoryRequired },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.categoryRequired, value: $0) }
                    )
                ),
                FieldData(
                    name: "Reporting Category",
                    description: "Category used for reporting purposes",
                    enabledBinding: Binding(
                        get: { config.classificationFields.reportingCategoryEnabled },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.reportingCategoryEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.classificationFields.reportingCategoryRequired },
                        set: { configManager.updateFieldConfiguration(\.classificationFields.reportingCategoryRequired, value: $0) }
                    )
                )
            ]
        case "taxes":
            return [
                FieldData(
                    name: "Tax Selection",
                    description: "Tax configuration for the item",
                    enabledBinding: Binding(
                        get: { config.pricingFields.taxEnabled },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.taxEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.pricingFields.taxRequired },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.taxRequired, value: $0) }
                    )
                ),
                FieldData(
                    name: "Item is Taxable",
                    description: "Toggle whether item is subject to taxes",
                    enabledBinding: Binding(
                        get: { config.pricingFields.isTaxableEnabled },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.isTaxableEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.pricingFields.isTaxableRequired },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.isTaxableRequired, value: $0) }
                    )
                )
            ]
        case "modifiers":
            return [
                FieldData(
                    name: "Modifier Lists",
                    description: "Modifier lists that can be applied to this item",
                    enabledBinding: Binding(
                        get: { config.pricingFields.modifiersEnabled },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.modifiersEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.pricingFields.modifiersRequired },
                        set: { configManager.updateFieldConfiguration(\.pricingFields.modifiersRequired, value: $0) }
                    )
                )
            ]
        case "locations":
            return [
                FieldData(
                    name: "Enabled Locations",
                    description: "Specify which locations this item is available at",
                    enabledBinding: Binding(
                        get: { config.advancedFields.enabledLocationsEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.enabledLocationsEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.advancedFields.enabledLocationsRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.enabledLocationsRequired, value: $0) }
                    )
                )
            ]
        case "customAttributes":
            return [
                FieldData(
                    name: "Custom Attributes",
                    description: "Add custom key-value pairs for additional item metadata",
                    enabledBinding: Binding(
                        get: { config.advancedFields.customAttributesEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.customAttributesEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.advancedFields.customAttributesRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.customAttributesRequired, value: $0) }
                    )
                )
            ]
        case "ecommerce":
            return [
                FieldData(
                    name: "Online Visibility",
                    description: "Control item visibility in online channels",
                    enabledBinding: Binding(
                        get: { config.ecommerceFields.onlineVisibilityEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.onlineVisibilityEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.ecommerceFields.onlineVisibilityRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.onlineVisibilityRequired, value: $0) }
                    )
                ),
                FieldData(
                    name: "SEO Settings",
                    description: "SEO title, description, and keywords for search optimization",
                    enabledBinding: Binding(
                        get: { config.ecommerceFields.seoEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.seoEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.ecommerceFields.seoRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.seoRequired, value: $0) }
                    )
                )
            ]
        case "salesChannels":
            return [
                FieldData(
                    name: "Sales Channels Display",
                    description: "Show Square-managed sales channels (read-only)",
                    enabledBinding: Binding(
                        get: { config.ecommerceFields.salesChannelsEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.salesChannelsEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.ecommerceFields.salesChannelsRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.salesChannelsRequired, value: $0) }
                    )
                )
            ]
        case "fulfillment":
            return [
                FieldData(
                    name: "Fulfillment Methods",
                    description: "Online fulfillment options (shipping, pickup, delivery) and alcohol indicator",
                    enabledBinding: Binding(
                        get: { config.ecommerceFields.fulfillmentMethodsEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.fulfillmentMethodsEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.ecommerceFields.fulfillmentMethodsRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.fulfillmentMethodsRequired, value: $0) }
                    )
                )
            ]
        case "measurementUnit":
            return [
                FieldData(
                    name: "Measurement Units",
                    description: "Set measurement units and sellable/stockable properties",
                    enabledBinding: Binding(
                        get: { config.advancedFields.measurementUnitEnabled },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.measurementUnitEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.advancedFields.measurementUnitRequired },
                        set: { configManager.updateFieldConfiguration(\.advancedFields.measurementUnitRequired, value: $0) }
                    )
                )
            ]
        default:
            // Single-purpose sections (Image, Product Type, Skip Modifier) have no configurable fields
            return []
        }
    }
}

// MARK: - Field Data Model
struct FieldData {
    let name: String
    let description: String
    let enabledBinding: Binding<Bool>
    let requiredBinding: Binding<Bool>
}

// MARK: - Field Configuration Row
struct FieldConfigurationRow: View {
    let fieldName: String
    let description: String
    @Binding var isEnabled: Bool
    @Binding var isRequired: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fieldName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            
            // Required toggle (only shown when field is enabled)
            if isEnabled {
                HStack {
                    Text("Required")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $isRequired)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationView {
        FieldVisibilityAndReorderingView()
    }
}
