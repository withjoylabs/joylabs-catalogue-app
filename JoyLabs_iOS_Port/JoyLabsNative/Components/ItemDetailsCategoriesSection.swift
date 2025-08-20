import SwiftUI

// MARK: - Item Details Categories Section
struct ItemDetailsCategoriesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
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
                                ItemDetailsFieldLabel(title: "Additional Categories")
                                
                                Button(action: {
                                    showingCategoryMultiSelect = true
                                }) {
                                    HStack {
                                        Text(categorySelectionText)
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        Spacer()
                                        Image(systemName: "square.grid.3x3")
                                            .foregroundColor(.itemDetailsSecondaryText)
                                            .font(.itemDetailsCaption)
                                    }
                                    .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                                    .background(Color.itemDetailsFieldBackground)
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                }
                                .buttonStyle(PlainButtonStyle())
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
                title: "Additional Categories"
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

// MARK: - Recent Categories Quick Selector
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
                                    .font(.itemDetailsCaption)
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

#Preview("Categories Section") {
    ScrollView {
        ItemDetailsCategoriesSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}