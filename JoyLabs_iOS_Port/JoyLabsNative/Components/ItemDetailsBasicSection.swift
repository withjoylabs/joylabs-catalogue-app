import SwiftUI

// MARK: - Item Details Basic Section
/// Handles basic item information fields (name, description, abbreviation)
struct ItemDetailsBasicSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        ItemDetailsSection(title: "Basic Information", icon: "square.and.pencil") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Item Name (always shown - required field)
                    ItemDetailsFieldRow {
                        ItemDetailsTextField(
                            title: "Item Name",
                            placeholder: "Enter item name",
                            text: Binding(
                                get: { viewModel.itemData.name },
                                set: { viewModel.itemData.name = $0 }
                            ),
                            error: viewModel.nameError,
                            isRequired: true
                        )
                    }

                    // Description (configurable)
                    if configManager.isFieldEnabled(.basicDescription) {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                ItemDetailsFieldLabel(title: "Description", helpText: "Optional item description")
                                
                                TextField("Enter item description (optional)", text: Binding(
                                    get: { viewModel.itemData.description },
                                    set: { viewModel.itemData.description = $0 }
                                ), axis: .vertical)
                                    .font(.itemDetailsBody)
                                    .padding(ItemDetailsSpacing.fieldPadding)
                                    .background(Color.itemDetailsFieldBackground)
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                    .lineLimit(3...6)
                                    .autocorrectionDisabled()
                            }
                        }
                    }

                    // Abbreviation (configurable)
                    if configManager.isFieldEnabled(.basicAbbreviation) {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            ItemDetailsTextField(
                                title: "Abbreviation",
                                placeholder: "Short name for receipts",
                                text: Binding(
                                    get: { viewModel.itemData.abbreviation },
                                    set: { viewModel.itemData.abbreviation = $0 }
                                ),
                                helpText: "Used on receipts and POS displays when space is limited"
                            )
                        }
                    }

                    // Product Type (configurable)
                    if configManager.isFieldEnabled(.classificationCategory) {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                ItemDetailsFieldLabel(title: "Product Type", helpText: "Choose the type of product")
                                
                                Picker("Product Type", selection: Binding(
                                    get: { viewModel.itemData.productType },
                                    set: { viewModel.itemData.productType = $0 }
                                )) {
                                    ForEach(ProductType.allCases, id: \.self) { type in
                                        Text(type.displayName)
                                            .tag(type)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                        }
                    }
                }
            }
        }
    }
}

// ItemDetailsSectionHeader and other individual components moved to ItemDetailsStyles.swift for centralized styling

#Preview("Basic Section") {
    ScrollView {
        ItemDetailsBasicSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
