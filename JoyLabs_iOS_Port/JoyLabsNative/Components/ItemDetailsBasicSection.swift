import SwiftUI

// MARK: - Item Details Basic Section
/// Handles basic item information fields (name, description, abbreviation)
struct ItemDetailsBasicSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                // Item Name (always shown - required field)
                ItemNameField(
                    name: Binding(
                        get: { viewModel.itemData.name },
                        set: { viewModel.itemData.name = $0 }
                    ),
                    error: viewModel.nameError
                )

                // Description (configurable)
                if configManager.isFieldEnabled(.basicDescription) {
                    ItemDescriptionField(
                        description: Binding(
                            get: { viewModel.itemData.description },
                            set: { viewModel.itemData.description = $0 }
                        )
                    )
                }

                // Abbreviation (configurable)
                if configManager.isFieldEnabled(.basicAbbreviation) {
                    ItemAbbreviationField(
                        abbreviation: Binding(
                            get: { viewModel.itemData.abbreviation },
                            set: { viewModel.itemData.abbreviation = $0 }
                        )
                    )
                }

                // Product Type (configurable)
                if configManager.isFieldEnabled(.classificationCategory) {
                    ProductTypeSelector(
                        productType: Binding(
                            get: { viewModel.itemData.productType },
                            set: { viewModel.itemData.productType = $0 }
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Item Details Section Header
struct ItemDetailsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.headline)

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

// MARK: - Item Name Field
struct ItemNameField: View {
    @Binding var name: String
    let error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Item Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
                
                Spacer()
            }
            
            TextField("Enter item name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Item Description Field
struct ItemDescriptionField: View {
    @Binding var description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            TextField("Enter item description (optional)", text: $description, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Item Abbreviation Field
struct ItemAbbreviationField: View {
    @Binding var abbreviation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Abbreviation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextField("Short name for receipts", text: $abbreviation)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
            
            Text("Used on receipts and POS displays when space is limited")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Product Type Selector
struct ProductTypeSelector: View {
    @Binding var productType: ProductType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Product Type")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Picker("Product Type", selection: $productType) {
                ForEach(ProductType.allCases, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Show description based on selected type
            Text(productTypeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var productTypeDescription: String {
        switch productType {
        case .regular:
            return "Standard product for sale"
        case .appointmentsService:
            return "Service that can be booked with appointments"
        }
    }
}

#Preview("Basic Section") {
    ScrollView {
        ItemDetailsBasicSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
