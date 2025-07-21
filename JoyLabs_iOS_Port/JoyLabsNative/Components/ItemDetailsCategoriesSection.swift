import SwiftUI

// MARK: - Item Details Categories Section
/// Handles categories, taxes, and modifiers
struct ItemDetailsCategoriesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Categories & Organization", icon: "folder")
            
            VStack(spacing: 12) {
                // Reporting Category (conditionally shown)
                if configManager.currentConfiguration.classificationFields.reportingCategoryEnabled {
                    ReportingCategorySelector(
                        reportingCategoryId: Binding(
                            get: { viewModel.itemData.reportingCategoryId },
                            set: { viewModel.itemData.reportingCategoryId = $0 }
                        ),
                        viewModel: viewModel
                    )
                }

                // Additional Categories (conditionally shown)
                if configManager.currentConfiguration.classificationFields.categoryEnabled {
                    AdditionalCategoriesSelector(
                        categoryIds: Binding(
                            get: { viewModel.itemData.categoryIds },
                            set: { viewModel.itemData.categoryIds = $0 }
                        )
                    )
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
                }
            }
        }
    }
}

// MARK: - Reporting Category Selector
struct ReportingCategorySelector: View {
    @Binding var reportingCategoryId: String?
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            Button(action: {
                showingPicker = true
            }) {
                HStack {
                    Text(reportingCategoryId ?? "Select reporting category")
                        .foregroundColor(reportingCategoryId == nil ? .secondary : .primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Text("Primary category for reporting and analytics")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                List {
                    ForEach(viewModel.availableCategories.indices, id: \.self) { index in
                        let category = viewModel.availableCategories[index]
                        Button(action: {
                            reportingCategoryId = category.name
                            showingPicker = false
                        }) {
                            HStack {
                                Text(category.name ?? "Unnamed Category")
                                    .foregroundColor(.primary)
                                Spacer()
                                if reportingCategoryId == category.name {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Select Category")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") {
                        showingPicker = false
                    }
                )
            }
        }
    }
}

// MARK: - Additional Categories Selector
struct AdditionalCategoriesSelector: View {
    @Binding var categoryIds: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Additional Categories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                // TODO: Show multi-category picker
            }) {
                HStack {
                    if categoryIds.isEmpty {
                        Text("Add categories")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(categoryIds.count) categories selected")
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Show selected categories
            if !categoryIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(categoryIds, id: \.self) { categoryId in
                        CategoryChip(categoryId: categoryId) {
                            categoryIds.removeAll { $0 == categoryId }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Category Chip
struct CategoryChip: View {
    let categoryId: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(categoryId) // TODO: Replace with actual category name
                .font(.caption)
                .foregroundColor(.primary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Tax Selector
struct TaxSelector: View {
    @Binding var taxIds: [String]
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tax Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                showingPicker = true
            }) {
                HStack {
                    if taxIds.isEmpty {
                        Text("No taxes applied")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(taxIds.count) tax(es) applied")
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                List {
                    ForEach(viewModel.availableTaxes.indices, id: \.self) { index in
                        let tax = viewModel.availableTaxes[index]
                        Button(action: {
                            if let taxName = tax.name {
                                if taxIds.contains(taxName) {
                                    taxIds.removeAll { $0 == taxName }
                                } else {
                                    taxIds.append(taxName)
                                }
                            }
                        }) {
                            HStack {
                                Text(tax.name ?? "Unnamed Tax")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let taxName = tax.name, taxIds.contains(taxName) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Select Taxes")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Done") {
                        showingPicker = false
                    }
                )
            }
        }
    }
}

// MARK: - Modifier List Selector
struct ModifierListSelector: View {
    @Binding var modifierListIds: [String]
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Modifier Lists")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                showingPicker = true
            }) {
                HStack {
                    if modifierListIds.isEmpty {
                        Text("No modifiers")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(modifierListIds.count) modifier list(s)")
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            Text("Add-ons and customizations for this item")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                List {
                    ForEach(viewModel.availableModifierLists.indices, id: \.self) { index in
                        let modifierList = viewModel.availableModifierLists[index]
                        Button(action: {
                            if let modifierName = modifierList.name {
                                if modifierListIds.contains(modifierName) {
                                    modifierListIds.removeAll { $0 == modifierName }
                                } else {
                                    modifierListIds.append(modifierName)
                                }
                            }
                        }) {
                            HStack {
                                Text(modifierList.name ?? "Unnamed Modifier List")
                                    .foregroundColor(.primary)
                                Spacer()
                                if let modifierName = modifierList.name, modifierListIds.contains(modifierName) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Select Modifier Lists")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Done") {
                        showingPicker = false
                    }
                )
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
