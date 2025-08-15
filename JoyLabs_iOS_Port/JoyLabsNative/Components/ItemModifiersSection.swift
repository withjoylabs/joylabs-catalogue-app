import SwiftUI

// MARK: - Item Modifiers Section
/// Handles modifier list selection
struct ItemModifiersSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        if configManager.currentConfiguration.pricingFields.modifiersEnabled {
            ItemDetailsSection(title: "Modifiers", icon: "plus.circle") {
                ItemDetailsCard {
                    VStack(spacing: 0) {
                        ItemDetailsFieldRow {
                            ModifierListSelector(
                                modifierListIds: $viewModel.modifierListIds,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ItemModifiersSection(viewModel: ItemDetailsViewModel())
        .padding()
}