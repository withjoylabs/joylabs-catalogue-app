import SwiftUI

// MARK: - Item Product Type Section
/// Handles product type selection (Regular Product vs Appointment Service)
struct ItemProductTypeSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        if configManager.currentConfiguration.classificationFields.productTypeEnabled {
            ItemDetailsSection(title: "Product Type", icon: "tag") {
                ItemDetailsCard {
                    VStack(spacing: 0) {
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                                ItemDetailsFieldLabel(title: "Product Type", helpText: "Choose the type of product")
                                
                                Picker("Product Type", selection: Binding(
                                    get: { viewModel.staticData.productType },
                                    set: { viewModel.staticData.productType = $0 }
                                )) {
                                    ForEach(ProductType.allCases, id: \.self) { type in
                                        Text(type.displayName)
                                            .tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ItemProductTypeSection(viewModel: ItemDetailsViewModel())
        .padding()
}