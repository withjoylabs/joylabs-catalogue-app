import SwiftUI

// MARK: - Item Fulfillment Section
/// Controls online fulfillment methods and alcohol indicator
/// Maps to Square API fields: available_online, available_for_pickup, available_electronically, is_alcoholic
struct ItemFulfillmentSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared

    var body: some View {
        ItemDetailsSection(title: "Fulfillment", icon: "shippingbox") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Online Fulfillment Methods Header
                    ItemDetailsFieldRow {
                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                            ItemDetailsFieldLabel(
                                title: "Online Fulfillment Methods",
                                helpText: "Select how customers can receive this item when ordering online"
                            )
                        }
                    }

                    ItemDetailsFieldSeparator()

                    // Available Online (Shipping)
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Shipping",
                            description: "Item can be shipped to customers",
                            isOn: Binding(
                                get: { viewModel.staticData.isAvailableOnline },
                                set: { viewModel.staticData.isAvailableOnline = $0 }
                            )
                        )
                    }

                    ItemDetailsFieldSeparator()

                    // Available for Pickup
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Pickup",
                            description: "Item can be picked up in-store",
                            isOn: Binding(
                                get: { viewModel.staticData.isAvailableForPickup },
                                set: { viewModel.staticData.isAvailableForPickup = $0 }
                            )
                        )
                    }

                    ItemDetailsFieldSeparator()

                    // Available Electronically (Self-serve / Local Delivery)
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Local Delivery",
                            description: "Item available for electronic/digital fulfillment",
                            isOn: Binding(
                                get: { viewModel.staticData.availableElectronically },
                                set: { viewModel.staticData.availableElectronically = $0 }
                            )
                        )
                    }

                    // Item Contains Alcohol (if enabled in config)
                    if configManager.currentConfiguration.classificationFields.isAlcoholicEnabled {
                        ItemDetailsFieldSeparator()

                        ItemDetailsFieldRow {
                            ItemDetailsToggleRow(
                                title: "Item Contains Alcohol",
                                description: "Mark if this item contains alcoholic content",
                                isOn: Binding(
                                    get: { viewModel.staticData.isAlcoholic },
                                    set: { viewModel.staticData.isAlcoholic = $0 }
                                )
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let viewModel = ItemDetailsViewModel()
    viewModel.staticData.isAvailableOnline = true
    viewModel.staticData.isAvailableForPickup = true
    viewModel.staticData.availableElectronically = false
    viewModel.staticData.isAlcoholic = false

    return ItemFulfillmentSection(viewModel: viewModel)
        .padding()
}
