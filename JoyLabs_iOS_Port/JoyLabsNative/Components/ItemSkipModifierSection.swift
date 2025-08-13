import SwiftUI

// MARK: - Item Skip Modifier Section
/// Handles the skip modifier screen at checkout setting
struct ItemSkipModifierSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        if configManager.currentConfiguration.pricingFields.skipModifierScreenEnabled {
            ItemDetailsSection(title: "Skip Details Screen at Checkout", icon: "forward.circle") {
                ItemDetailsCard {
                    VStack(spacing: 0) {
                        ItemDetailsFieldRow {
                            ItemDetailsToggleRow(
                                title: "Skip Details Screen at Checkout",
                                description: "Don't show modifier selection when adding to cart",
                                isOn: $viewModel.itemData.skipModifierScreen
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ItemSkipModifierSection(viewModel: ItemDetailsViewModel())
        .padding()
}