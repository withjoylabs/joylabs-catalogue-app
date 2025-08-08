import SwiftUI

// MARK: - Item Details Categories Section
/// Handles categories, taxes, and modifiers
struct ItemDetailsCategoriesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                // Reporting Category (conditionally shown)
                if configManager.currentConfiguration.classificationFields.reportingCategoryEnabled {
                    ReportingCategorySelector(
                        reportingCategoryId: Binding(
                            get: { viewModel.itemData.reportingCategoryId },
                            set: { viewModel.itemData.reportingCategoryId = $0 }
                        ),
                        viewModel: viewModel
                    )
                    .padding(.bottom, 16)

                    Divider()
                        .padding(.bottom, 16)
                }

                // Additional Categories (conditionally shown)
                if configManager.currentConfiguration.classificationFields.categoryEnabled {
                    AdditionalCategoriesSelector(
                        categoryIds: Binding(
                            get: { viewModel.itemData.categoryIds },
                            set: { viewModel.itemData.categoryIds = $0 }
                        ),
                        reportingCategoryId: Binding(
                            get: { viewModel.itemData.reportingCategoryId },
                            set: { viewModel.itemData.reportingCategoryId = $0 }
                        ),
                        viewModel: viewModel
                    )
                    .padding(.bottom, 16)

                    Divider()
                        .padding(.bottom, 16)
                }

                // Tax Settings (conditionally shown)
                if configManager.currentConfiguration.pricingFields.taxEnabled {
                    TaxSelector(
                        taxIds: Binding(
                            get: { viewModel.itemData.taxIds },
                            set: { viewModel.itemData.taxIds = $0 }
                        ),
                        viewModel: viewModel
                    )
                    .padding(.bottom, 16)

                    Divider()
                        .padding(.bottom, 16)
                }

                // Modifier Lists (conditionally shown)
                if configManager.currentConfiguration.pricingFields.modifiersEnabled {
                    ModifierListSelector(
                        modifierListIds: Binding(
                            get: { viewModel.itemData.modifierListIds },
                            set: { viewModel.itemData.modifierListIds = $0 }
                        ),
                        viewModel: viewModel
                    )
                    // No divider after the last section
                }
            }
        }
    }
}

// MARK: - Reporting Category Selector
struct ReportingCategorySelector: View {
    @Binding var reportingCategoryId: String?
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingDropdown = false
    @State private var searchText = ""

    // Computed property to get the category name for display
    private var selectedCategoryName: String? {
        guard let categoryId = reportingCategoryId else { return nil }
        return viewModel.availableCategories.first { $0.id == categoryId }?.name
    }

    // Filtered categories based on search
    private var filteredCategories: [CategoryData] {
        if searchText.isEmpty {
            return viewModel.availableCategories
        } else {
            return viewModel.availableCategories.filter { category in
                category.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text("Reporting Category")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)

                Spacer()
            }

            // Description
            Text("Primary category for reporting and analytics")
                .font(.caption)
                .foregroundColor(Color.secondary)

            // Dropdown Button
            Button(action: {
                showingDropdown.toggle()
            }) {
                HStack {
                    Text(selectedCategoryName ?? "Select reporting category")
                        .foregroundColor(reportingCategoryId == nil ? .secondary : .primary)

                    Spacer()

                    Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(Color.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Dropdown Content
            if showingDropdown {
                VStack(spacing: 0) {
                    // Search Field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color.secondary)
                        TextField("Search categories...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))

                    Divider()

                    // Categories List
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredCategories.indices, id: \.self) { index in
                                    let category = filteredCategories[index]
                                    Button(action: {
                                        reportingCategoryId = category.id
                                        showingDropdown = false
                                        searchText = ""
                                    }) {
                                        HStack {
                                            Text(category.name ?? "Unnamed Category")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if reportingCategoryId == category.id {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    }
                                    .background(Color(.systemBackground))

                                    if index < filteredCategories.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: min(geometry.size.height * 0.3, 300))
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            // Recent Categories Horizontal Scroll
            RecentCategoriesScroll(reportingCategoryId: $reportingCategoryId, viewModel: viewModel)
        }
    }
}

// MARK: - Recent Categories Scroll
struct RecentCategoriesScroll: View {
    @Binding var reportingCategoryId: String?
    @ObservedObject var viewModel: ItemDetailsViewModel

    // For now, we'll use the first 10 categories as "recent"
    // TODO: Implement actual recent categories tracking
    private var recentCategories: [CategoryData] {
        Array(viewModel.availableCategories.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Categories")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentCategories.indices, id: \.self) { index in
                        let category = recentCategories[index]
                        Button(action: {
                            reportingCategoryId = category.id
                        }) {
                            Text(category.name ?? "Unnamed")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    reportingCategoryId == category.id ?
                                    Color.blue : Color(.systemGray5)
                                )
                                .foregroundColor(
                                    reportingCategoryId == category.id ?
                                    .white : .primary
                                )
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

// MARK: - Additional Categories Selector with Dropdown
struct AdditionalCategoriesSelector: View {
    @Binding var categoryIds: [String]
    @Binding var reportingCategoryId: String?
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingDropdown = false
    @State private var searchText = ""

    // Filtered categories based on search
    private var filteredCategories: [CategoryData] {
        if searchText.isEmpty {
            return viewModel.availableCategories
        } else {
            return viewModel.availableCategories.filter { category in
                category.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text("Additional Categories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Text("Optional")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }

            // Dropdown Button
            Button(action: {
                showingDropdown.toggle()
            }) {
                HStack {
                    if categoryIds.isEmpty {
                        Text("Add categories")
                            .foregroundColor(Color.secondary)
                    } else {
                        Text("\(categoryIds.count) categories selected")
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(Color.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Dropdown Content
            if showingDropdown {
                VStack(spacing: 0) {
                    // Search Field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color.secondary)
                            .font(.caption)
                        TextField("Search categories...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()

                    // Categories List
                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredCategories.indices, id: \.self) { index in
                                    let category = filteredCategories[index]
                                    if let categoryId = category.id {
                                        Button(action: {
                                            if categoryIds.contains(categoryId) {
                                                categoryIds.removeAll { $0 == categoryId }
                                            } else {
                                                categoryIds.append(categoryId)
                                            }
                                        }) {
                                            HStack {
                                                // Show if this is the reporting category
                                                if reportingCategoryId == categoryId {
                                                    Text("\(category.name ?? "Unnamed Category") (Reporting)")
                                                        .foregroundColor(.blue)
                                                        .fontWeight(.medium)
                                                } else {
                                                    Text(category.name ?? "Unnamed Category")
                                                        .foregroundColor(.primary)
                                                }

                                                Spacer()

                                                if categoryIds.contains(categoryId) {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                        }
                                        .background(Color(.systemBackground))
                                        .disabled(reportingCategoryId == categoryId) // Can't select reporting category as additional

                                        if index < filteredCategories.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: min(geometry.size.height * 0.3, 300))
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            // Show selected categories as chips
            if !categoryIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(categoryIds, id: \.self) { categoryId in
                        CategoryChip(categoryId: categoryId, viewModel: viewModel) {
                            categoryIds.removeAll { $0 == categoryId }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Category Chip
struct CategoryChip: View {
    let categoryId: String
    let viewModel: ItemDetailsViewModel
    let onRemove: () -> Void

    // Get category name from viewModel
    private var categoryName: String {
        viewModel.availableCategories.first { $0.id == categoryId }?.name ?? "Unknown Category"
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(categoryName)
                .font(.caption)
                .foregroundColor(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Tax Checkboxes (Inline)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tax Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                // Select All Button (inline with header)
                if !viewModel.availableTaxes.isEmpty {
                    Button(action: {
                        if allTaxesSelected {
                            // Deselect all
                            taxIds.removeAll()
                        } else {
                            // Select all
                            taxIds = viewModel.availableTaxes.compactMap { $0.id }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: allTaxesSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(allTaxesSelected ? .blue : .secondary)
                                .font(.caption)

                            Text("Select All")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            // Individual Tax Checkboxes
            ForEach(viewModel.availableTaxes.indices, id: \.self) { index in
                let tax = viewModel.availableTaxes[index]
                if let taxId = tax.id {
                    let isSelected = taxIds.contains(taxId)
                    Button(action: {
                        print("🔍 TAX DEBUG: Tapping tax \(tax.name ?? "Unknown") (ID: \(taxId))")
                        print("🔍 TAX DEBUG: Current taxIds: \(taxIds)")
                        print("🔍 TAX DEBUG: Is currently selected: \(isSelected)")

                        if isSelected {
                            taxIds.removeAll { $0 == taxId }
                        } else {
                            taxIds.append(taxId)
                        }

                        print("🔍 TAX DEBUG: New taxIds: \(taxIds)")
                    }) {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(isSelected ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tax.name ?? "Unnamed Tax")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                if let percentage = tax.percentage {
                                    Text("\(percentage)%")
                                        .font(.caption)
                                        .foregroundColor(Color.secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if viewModel.availableTaxes.isEmpty {
                Text("No taxes available")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Modifier List Checkboxes (Inline)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Modifier Lists")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                // Select All Button (inline with header)
                if !viewModel.availableModifierLists.isEmpty {
                    Button(action: {
                        if allModifiersSelected {
                            // Deselect all
                            modifierListIds.removeAll()
                        } else {
                            // Select all
                            modifierListIds = viewModel.availableModifierLists.compactMap { $0.id }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: allModifiersSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(allModifiersSelected ? .blue : .secondary)
                                .font(.caption)

                            Text("Select All")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            // Individual Modifier List Checkboxes
            ForEach(viewModel.availableModifierLists.indices, id: \.self) { index in
                let modifierList = viewModel.availableModifierLists[index]
                if let modifierId = modifierList.id {
                    let isSelected = modifierListIds.contains(modifierId)
                    Button(action: {
                        print("🔍 MODIFIER DEBUG: Tapping modifier \(modifierList.name ?? "Unknown") (ID: \(modifierId))")
                        print("🔍 MODIFIER DEBUG: Current modifierListIds: \(modifierListIds)")
                        print("🔍 MODIFIER DEBUG: Is currently selected: \(isSelected)")

                        if isSelected {
                            modifierListIds.removeAll { $0 == modifierId }
                        } else {
                            modifierListIds.append(modifierId)
                        }

                        print("🔍 MODIFIER DEBUG: New modifierListIds: \(modifierListIds)")
                    }) {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(isSelected ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(modifierList.name ?? "Unnamed Modifier List")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                if let selectionType = modifierList.selectionType {
                                    Text(selectionType.capitalized)
                                        .font(.caption)
                                        .foregroundColor(Color.secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if viewModel.availableModifierLists.isEmpty {
                Text("No modifier lists available")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.vertical, 8)
            } else {
                Text("Add-ons and customizations for this item")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview("Categories Section") {
    ScrollView {
        ItemDetailsCategoriesSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
