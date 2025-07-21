import SwiftUI

// MARK: - Item Details Categories Section
/// Handles categories, taxes, and modifiers
struct ItemDetailsCategoriesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Categories & Organization", icon: "folder")
            
            VStack(spacing: 12) {
                // Reporting Category
                ReportingCategorySelector(
                    reportingCategoryId: Binding(
                        get: { viewModel.itemData.reportingCategoryId },
                        set: { viewModel.itemData.reportingCategoryId = $0 }
                    )
                )
                
                // Additional Categories
                AdditionalCategoriesSelector(
                    categoryIds: Binding(
                        get: { viewModel.itemData.categoryIds },
                        set: { viewModel.itemData.categoryIds = $0 }
                    )
                )
                
                // Tax Settings
                TaxSelector(
                    taxIds: Binding(
                        get: { viewModel.itemData.taxIds },
                        set: { viewModel.itemData.taxIds = $0 }
                    )
                )
                
                // Modifier Lists
                ModifierListSelector(
                    modifierListIds: Binding(
                        get: { viewModel.itemData.modifierListIds },
                        set: { viewModel.itemData.modifierListIds = $0 }
                    )
                )
            }
        }
    }
}

// MARK: - Reporting Category Selector
struct ReportingCategorySelector: View {
    @Binding var reportingCategoryId: String?
    
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
                // TODO: Show category picker
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
                // TODO: Show tax picker
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
    }
}

// MARK: - Modifier List Selector
struct ModifierListSelector: View {
    @Binding var modifierListIds: [String]
    
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
                // TODO: Show modifier list picker
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
    }
}

#Preview("Categories Section") {
    ScrollView {
        ItemDetailsCategoriesSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
