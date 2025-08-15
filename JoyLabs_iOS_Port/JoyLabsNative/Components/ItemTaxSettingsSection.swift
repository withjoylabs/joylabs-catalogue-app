import SwiftUI

// MARK: - Item Tax Settings Section
/// Handles tax configuration including tax selection and taxable toggle
struct ItemTaxSettingsSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        if shouldShowTaxSection {
            ItemDetailsSection(title: "Tax Settings", icon: "percent") {
                ItemDetailsCard {
                    VStack(spacing: 0) {
                        // Tax Selection
                        if configManager.currentConfiguration.pricingFields.taxEnabled {
                            ItemDetailsFieldRow {
                                TaxSelector(
                                    taxIds: $viewModel.taxIds,
                                    viewModel: viewModel
                                )
                            }
                            
                            if configManager.currentConfiguration.pricingFields.isTaxableEnabled {
                                ItemDetailsFieldSeparator()
                            }
                        }
                        
                        // Taxable Toggle
                        if configManager.currentConfiguration.pricingFields.isTaxableEnabled {
                            ItemDetailsFieldRow {
                                ItemDetailsToggleRow(
                                    title: "Item is Taxable",
                                    description: "Apply taxes at checkout",
                                    isOn: Binding(
                                        get: { viewModel.staticData.isTaxable },
                                        set: { viewModel.staticData.isTaxable = $0 }
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var shouldShowTaxSection: Bool {
        return configManager.currentConfiguration.pricingFields.taxEnabled ||
               configManager.currentConfiguration.pricingFields.isTaxableEnabled
    }
}

#Preview {
    ItemTaxSettingsSection(viewModel: ItemDetailsViewModel())
        .padding()
}