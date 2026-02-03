import SwiftUI

// MARK: - Item Details Categories Section
struct ItemDetailsCategoriesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @FocusState.Binding var focusedField: ItemField?
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var showingCategoryMultiSelect = false
    @State private var showingReportingCategorySelect = false
    
    var body: some View {
        ItemDetailsSection(title: "Categories & Classification", icon: "tag") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Reporting Category
                    if configManager.currentConfiguration.classificationFields.reportingCategoryEnabled {
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                ItemDetailsFieldLabel(title: "Reporting Category", isRequired: true)
                                
                                Button(action: {
                                    focusedField = nil
                                    showingReportingCategorySelect = true
                                }) {
                                    HStack {
                                        Text(selectedReportingCategoryName ?? "Select category")
                                            .foregroundColor(viewModel.reportingCategoryId == nil ? .itemDetailsSecondaryText : .itemDetailsPrimaryText)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.itemDetailsSecondaryText)
                                            .font(.itemDetailsCaption)
                                    }
                                    .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                                    .background(Color.itemDetailsFieldBackground)
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                // Recent categories quick selector
                                if !viewModel.recentCategories.isEmpty {
                                    RecentCategoriesQuickSelector(
                                        recentCategories: viewModel.recentCategories,
                                        selectedCategoryId: viewModel.reportingCategoryId,
                                        onCategorySelected: { categoryId in
                                            viewModel.reportingCategoryId = categoryId
                                            viewModel.addToRecentCategories(categoryId)
                                        }
                                    )
                                }
                            }
                        }
                        
                        if hasMoreFields {
                            ItemDetailsFieldSeparator()
                        }
                    }
                    
                    // Additional Categories
                    if configManager.currentConfiguration.classificationFields.categoryEnabled {
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                // Label
                                ItemDetailsFieldLabel(title: "Additional Categories")

                                // Selected category tags
                                if !viewModel.categoryIds.isEmpty {
                                    FlowLayout(spacing: 4) {
                                        ForEach(viewModel.categoryIds, id: \.self) { categoryId in
                                            if let category = viewModel.availableCategories.first(where: { $0.id == categoryId }) {
                                                CategoryTag(
                                                    categoryName: category.name ?? "Unknown",
                                                    onRemove: {
                                                        viewModel.categoryIds.removeAll { $0 == categoryId }
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }

                                // Full-width button to open category selector
                                Button(action: {
                                    focusedField = nil
                                    showingCategoryMultiSelect = true
                                }) {
                                    HStack {
                                        Text("Manage Additional Categories")
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.itemDetailsSecondaryText)
                                            .font(.itemDetailsCaption)
                                    }
                                    .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                                    .background(Color.itemDetailsFieldBackground)
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                }
                                .buttonStyle(PlainButtonStyle())

                                // Recent categories multi-selector
                                if !viewModel.recentAdditionalCategories.isEmpty {
                                    RecentCategoriesMultiSelector(
                                        recentCategories: viewModel.recentAdditionalCategories,
                                        selectedCategoryIds: $viewModel.categoryIds,
                                        onCategoryToggled: { categoryId in
                                            viewModel.addToRecentAdditionalCategories(categoryId)
                                        }
                                    )
                                }
                            }
                        }
                        
                        if hasMoreFields {
                            ItemDetailsFieldSeparator()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCategoryMultiSelect) {
            ItemDetailsCategoryMultiSelectModal(
                isPresented: $showingCategoryMultiSelect,
                selectedCategoryIds: $viewModel.categoryIds,
                categories: viewModel.availableCategories,
                title: "Additional Categories",
                onCategoriesSelected: { categoryIds in
                    // Add each selected category to recents
                    for categoryId in categoryIds {
                        viewModel.addToRecentAdditionalCategories(categoryId)
                    }
                }
            )
            .nestedComponentModal()
        }
        .sheet(isPresented: $showingReportingCategorySelect) {
            ItemDetailsCategorySingleSelectModal(
                isPresented: $showingReportingCategorySelect,
                selectedCategoryId: $viewModel.reportingCategoryId,
                categories: viewModel.availableCategories,
                title: "Reporting Category",
                onCategorySelected: viewModel.addToRecentCategories
            )
            .nestedComponentModal()
        }
        .onChange(of: viewModel.reportingCategoryId) { _, newCategoryId in
            applyTaxDefaultsForCategory(newCategoryId)
        }
    }

    /// Apply tax defaults based on category selection
    private func applyTaxDefaultsForCategory(_ categoryId: String?) {
        guard let categoryId = categoryId else { return }

        let taxService = CategoryTaxDefaultsService.shared

        if taxService.isNonTaxable(categoryId: categoryId) {
            // Non-taxable category: explicitly uncheck all taxes
            viewModel.taxIds.removeAll()
            viewModel.staticData.isTaxable = false
        } else {
            // Taxable category: re-check taxes if "item is taxable" default is ON
            if configManager.currentConfiguration.pricingFields.defaultIsTaxable {
                viewModel.taxIds = viewModel.availableTaxes.compactMap { $0.id }
                viewModel.staticData.isTaxable = true
            }
            // If defaultIsTaxable is OFF, leave taxes unchanged
        }
    }
    
    private var selectedReportingCategoryName: String? {
        guard let categoryId = viewModel.reportingCategoryId else { return nil }
        return viewModel.availableCategories.first { $0.id == categoryId }?.name
    }
    
    private var categorySelectionText: String {
        let count = viewModel.categoryIds.count
        return count == 0 ? "Select categories" : "\(count) selected"
    }
    
    private var hasMoreFields: Bool {
        configManager.currentConfiguration.classificationFields.categoryEnabled ||
        configManager.currentConfiguration.pricingFields.taxEnabled ||
        configManager.currentConfiguration.pricingFields.modifiersEnabled ||
        configManager.currentConfiguration.pricingFields.isTaxableEnabled ||
        configManager.currentConfiguration.pricingFields.skipModifierScreenEnabled
    }
    
    private func toggleCategory(_ categoryId: String?) {
        guard let categoryId = categoryId else { return }
        
        if viewModel.categoryIds.contains(categoryId) {
            viewModel.categoryIds.removeAll { $0 == categoryId }
        } else {
            viewModel.categoryIds.append(categoryId)
        }
    }
}

// MARK: - Tax Selector
struct TaxSelector: View {
    @Binding var taxIds: [String]
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    // Computed property to check if all taxes are selected
    private var allTaxesSelected: Bool {
        !viewModel.availableTaxes.isEmpty &&
        viewModel.availableTaxes.allSatisfy { tax in
            guard let taxId = tax.id else { return false }
            return taxIds.contains(taxId)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            HStack {
                ItemDetailsFieldLabel(title: "Tax Settings")
                Spacer()
                if !viewModel.availableTaxes.isEmpty {
                    Button(action: {
                        if allTaxesSelected {
                            taxIds.removeAll()
                            viewModel.staticData.isTaxable = false
                        } else {
                            taxIds = viewModel.availableTaxes.compactMap { $0.id }
                            viewModel.staticData.isTaxable = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: allTaxesSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(allTaxesSelected ? .itemDetailsAccent : .itemDetailsSecondaryText)
                                .font(.itemDetailsCaption)
                            Text("Select All")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsPrimaryText)
                        }
                    }
                }
            }
            
            if viewModel.availableTaxes.isEmpty {
                Text("No taxes available")
                    .font(.itemDetailsCaption)
                    .foregroundColor(.itemDetailsSecondaryText)
            } else {
                VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    ForEach(viewModel.availableTaxes, id: \.id) { tax in
                        if let taxId = tax.id {
                            let isSelected = taxIds.contains(taxId)
                            Button(action: {
                                if isSelected {
                                    taxIds.removeAll { $0 == taxId }
                                } else {
                                    taxIds.append(taxId)
                                }
                            }) {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isSelected ? .itemDetailsAccent : .itemDetailsSecondaryText)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tax.name ?? "Unnamed Tax")
                                            .font(.itemDetailsSubheadline)
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        
                                        if let percentage = tax.percentage {
                                            Text("\(percentage)%")
                                                .font(.itemDetailsCaption)
                                                .foregroundColor(.itemDetailsSecondaryText)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Modifier List Selector
struct ModifierListSelector: View {
    @Binding var modifierListIds: [String]
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    // Computed property to check if all modifier lists are selected
    private var allModifiersSelected: Bool {
        !viewModel.availableModifierLists.isEmpty &&
        viewModel.availableModifierLists.allSatisfy { modifierList in
            guard let modifierId = modifierList.id else { return false }
            return modifierListIds.contains(modifierId)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            HStack {
                ItemDetailsFieldLabel(title: "Modifier Lists")
                Spacer()
                if !viewModel.availableModifierLists.isEmpty {
                    Button(action: {
                        if allModifiersSelected {
                            modifierListIds.removeAll()
                        } else {
                            modifierListIds = viewModel.availableModifierLists.compactMap { $0.id }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: allModifiersSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(allModifiersSelected ? .itemDetailsAccent : .itemDetailsSecondaryText)
                                .font(.itemDetailsCaption)
                            Text("Select All")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsPrimaryText)
                        }
                    }
                }
            }
            
            if viewModel.availableModifierLists.isEmpty {
                Text("No modifier lists available")
                    .font(.itemDetailsCaption)
                    .foregroundColor(.itemDetailsSecondaryText)
            } else {
                VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    ForEach(viewModel.availableModifierLists, id: \.id) { modifierList in
                        if let modifierId = modifierList.id {
                            let isSelected = modifierListIds.contains(modifierId)
                            Button(action: {
                                if isSelected {
                                    modifierListIds.removeAll { $0 == modifierId }
                                } else {
                                    modifierListIds.append(modifierId)
                                }
                            }) {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isSelected ? .itemDetailsAccent : .itemDetailsSecondaryText)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(modifierList.name ?? "Unnamed Modifier List")
                                            .font(.itemDetailsSubheadline)
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        
                                        if let selectionType = modifierList.selectionType {
                                            Text(selectionType.capitalized)
                                                .font(.itemDetailsCaption)
                                                .foregroundColor(.itemDetailsSecondaryText)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Recent Categories Quick Selector (Single Select)
struct RecentCategoriesQuickSelector: View {
    let recentCategories: [CategoryData]
    let selectedCategoryId: String?
    let onCategorySelected: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
            Text("Recently Used")
                .font(.itemDetailsCaption)
                .foregroundColor(.itemDetailsSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    ForEach(recentCategories, id: \.id) { category in
                        if let categoryId = category.id, let categoryName = category.name {
                            let isSelected = selectedCategoryId == categoryId

                            Button(action: {
                                onCategorySelected(categoryId)
                            }) {
                                Text(categoryName)
                                    .font(.itemDetailsSubheadline)
                                    .lineLimit(1)
                                    .foregroundColor(isSelected ? .itemDetailsAccent : .itemDetailsPrimaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Color.itemDetailsFieldBackground
                                            .overlay(
                                                RoundedRectangle(cornerRadius: ItemDetailsSpacing.fieldCornerRadius)
                                                    .stroke(isSelected ? Color.itemDetailsAccent : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 1) // Small padding to prevent clipping of border
            }
        }
        .padding(.top, ItemDetailsSpacing.minimalSpacing)
    }
}

// MARK: - Recent Categories Multi Selector (Multi Select)
struct RecentCategoriesMultiSelector: View {
    let recentCategories: [CategoryData]
    @Binding var selectedCategoryIds: [String]
    let onCategoryToggled: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
            Text("Recently Used")
                .font(.itemDetailsCaption)
                .foregroundColor(.itemDetailsSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    ForEach(recentCategories, id: \.id) { category in
                        if let categoryId = category.id, let categoryName = category.name {
                            let isSelected = selectedCategoryIds.contains(categoryId)

                            Button(action: {
                                if isSelected {
                                    selectedCategoryIds.removeAll { $0 == categoryId }
                                } else {
                                    selectedCategoryIds.append(categoryId)
                                }
                                onCategoryToggled(categoryId)
                            }) {
                                Text(categoryName)
                                    .font(.itemDetailsSubheadline)
                                    .lineLimit(1)
                                    .foregroundColor(isSelected ? .itemDetailsAccent : .itemDetailsPrimaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Color.itemDetailsFieldBackground
                                            .overlay(
                                                RoundedRectangle(cornerRadius: ItemDetailsSpacing.fieldCornerRadius)
                                                    .stroke(isSelected ? Color.itemDetailsAccent : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 1) // Small padding to prevent clipping of border
            }
        }
        .padding(.top, ItemDetailsSpacing.minimalSpacing)
    }
}

// MARK: - Flow Layout for Wrapping Tags
/// Simple wrapping layout for category tags
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // Simple wrapping using ScrollView for overflow handling
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Category Tag with Remove Button
/// Displays a selected category as a chip/tag with X button for removal
struct CategoryTag: View {
    let categoryName: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(categoryName)
                .font(.itemDetailsSubheadline)
                .foregroundColor(.itemDetailsAccent)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.itemDetailsAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.itemDetailsAccent.opacity(0.15))
        .cornerRadius(4)
    }
}

#Preview("Categories Section") {
    struct PreviewWrapper: View {
        @FocusState private var focusedField: ItemField?

        var body: some View {
            ScrollView {
                ItemDetailsCategoriesSection(viewModel: ItemDetailsViewModel(), focusedField: $focusedField)
                    .padding()
            }
        }
    }

    return PreviewWrapper()
}