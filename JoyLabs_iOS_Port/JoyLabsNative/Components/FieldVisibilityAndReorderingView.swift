import SwiftUI
import UniformTypeIdentifiers

// MARK: - Field Visibility & Reordering View
/// Unified interface for managing field visibility and section reordering
struct FieldVisibilityAndReorderingView: View {
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var draggedSection: SectionConfiguration?
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(configManager.currentConfiguration.orderedSections.enumerated()), id: \.offset) { index, section in
                    sectionRow(section: section, index: index)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func sectionRow(section: SectionConfiguration, index: Int) -> some View {
        VStack(spacing: 0) {
            SectionConfigurationCard(
                section: section,
                onToggleEnabled: {
                    configManager.updateSectionConfiguration(section.id) { $0.isEnabled.toggle() }
                }
            )
            .onDrag {
                self.draggedSection = section
                return NSItemProvider(object: section.id as NSString)
            }
            .onDrop(of: [UTType.text], delegate: SectionDropDelegate(
                destinationSection: section,
                draggedSection: $draggedSection,
                configManager: configManager
            ))
            .background(draggedSection?.id == section.id ? Color.blue.opacity(0.1) : Color.clear)
            
            // Divider (except for last item)
            if index < configManager.currentConfiguration.orderedSections.count - 1 {
                Divider()
                    .padding(.leading, 16)
            }
        }
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
            // Reset to default section order by calling resetToDefault and preserving current visibility states
            let currentStates = configManager.currentConfiguration.orderedSections.reduce(into: [String: Bool]()) {
                $0[$1.id] = $1.isEnabled
            }
            
            configManager.resetToDefault()
            
            // Restore the visibility states
            for (sectionId, isEnabled) in currentStates {
                configManager.updateSectionConfiguration(sectionId) { $0.isEnabled = isEnabled }
            }
        }
    }
}

// MARK: - Section Configuration Card
struct SectionConfigurationCard: View {
    let section: SectionConfiguration
    let onToggleEnabled: () -> Void
    
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main section row - wrapped in Button for native iOS feel
            Button(action: {
                if hasConfigurableFields {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack(spacing: 12) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .medium))
                    
                    // Section icon
                    Image(systemName: section.icon)
                        .foregroundColor(section.isEnabled ? .accentColor : .secondary)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 20)
                    
                    // Section title
                    Text(section.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(section.isEnabled ? .primary : .secondary)
                    
                    Spacer()
                    
                    // Enabled toggle
                    Toggle("", isOn: Binding(
                        get: { section.isEnabled },
                        set: { _ in onToggleEnabled() }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.8)
                    
                    // FIXED: Consistent spacing for chevron area (always 24pt width)
                    HStack {
                        if hasConfigurableFields {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(width: 24, alignment: .center) // Fixed width ensures alignment
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle()) // Native iOS button feel
            .disabled(!hasConfigurableFields) // Only interactive if expandable
            
            // Expanded field list (only for sections with configurable fields)
            if isExpanded && hasConfigurableFields {
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
        case "availability":
            return [
                FieldData(
                    name: "Availability Settings",
                    description: "Control item availability for sale, online, and pickup",
                    enabledBinding: Binding(
                        get: { config.ecommerceFields.availabilityEnabled },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.availabilityEnabled, value: $0) }
                    ),
                    requiredBinding: Binding(
                        get: { config.ecommerceFields.availabilityRequired },
                        set: { configManager.updateFieldConfiguration(\.ecommerceFields.availabilityRequired, value: $0) }
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

// MARK: - Drop Delegate (same as before)
struct SectionDropDelegate: DropDelegate {
    let destinationSection: SectionConfiguration
    @Binding var draggedSection: SectionConfiguration?
    let configManager: FieldConfigurationManager
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedSection = draggedSection else { return false }
        
        // Reorder sections
        let sourceOrder = draggedSection.order
        let destinationOrder = destinationSection.order
        
        if sourceOrder != destinationOrder {
            // CRITICAL FIX: Preserve all section properties during reordering
            let orderedSections = configManager.currentConfiguration.orderedSections
            var reorderedSections = orderedSections
            
            // Find indices
            guard let sourceIndex = reorderedSections.firstIndex(where: { $0.id == draggedSection.id }),
                  let destinationIndex = reorderedSections.firstIndex(where: { $0.id == destinationSection.id }) else {
                return false
            }
            
            // Perform the move operation preserving all section properties
            let movedSection = reorderedSections.remove(at: sourceIndex)
            reorderedSections.insert(movedSection, at: destinationIndex)
            
            // Update orders while preserving all other properties (especially isEnabled)
            var updatedConfigurations = configManager.currentConfiguration.sectionConfigurations
            for (index, section) in reorderedSections.enumerated() {
                var updatedSection = section
                updatedSection.order = index
                updatedConfigurations[section.id] = updatedSection
            }
            
            // Apply changes
            configManager.updateAllSectionConfigurations(updatedConfigurations)
        }
        
        self.draggedSection = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback: subtle highlighting when drag enters drop zone
    }
    
    func dropExited(info: DropInfo) {
        // Visual feedback: remove highlighting when drag exits drop zone
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Provide feedback during drag operations
        return DropProposal(operation: .move)
    }
}

#Preview {
    NavigationView {
        FieldVisibilityAndReorderingView()
    }
}