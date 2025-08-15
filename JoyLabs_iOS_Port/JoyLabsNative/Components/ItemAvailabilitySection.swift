import SwiftUI

// MARK: - Item Availability Section
struct ItemAvailabilitySection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        ItemDetailsSection(title: "Availability", icon: "clock") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Available for Sale Toggle
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Available for Sale",
                            isOn: Binding(
                                get: { viewModel.staticData.isAvailableForSale },
                                set: { viewModel.staticData.isAvailableForSale = $0 }
                            )
                        )
                    }

                    ItemDetailsFieldSeparator()

                    // Available Online Toggle
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Available Online",
                            isOn: Binding(
                                get: { viewModel.staticData.isAvailableOnline },
                                set: { viewModel.staticData.isAvailableOnline = $0 }
                            )
                        )
                    }

                    ItemDetailsFieldSeparator()

                    // Available for Pickup Toggle
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Available for Pickup",
                            isOn: Binding(
                                get: { viewModel.staticData.isAvailableForPickup },
                                set: { viewModel.staticData.isAvailableForPickup = $0 }
                            )
                        )
                    }
                
                    // Availability Schedule (if needed)
                    if viewModel.showAdvancedFeatures {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                ItemDetailsFieldLabel(title: "Availability Schedule", helpText: "Set specific dates when this item is available")
                                
                                VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                    HStack {
                                        Text("Start Date")
                                            .font(.itemDetailsSubheadline)
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        
                                        Spacer()
                                        
                                        if let startDate = viewModel.staticData.availabilityStartDate {
                                            Text(startDate, style: .date)
                                                .font(.itemDetailsBody)
                                                .foregroundColor(.itemDetailsAccent)
                                        } else {
                                            Text("Not Set")
                                                .font(.itemDetailsBody)
                                                .foregroundColor(.itemDetailsSecondaryText)
                                        }
                                    }
                                    
                                    HStack {
                                        Text("End Date")
                                            .font(.itemDetailsSubheadline)
                                            .foregroundColor(.itemDetailsPrimaryText)
                                        
                                        Spacer()
                                        
                                        if let endDate = viewModel.staticData.availabilityEndDate {
                                            Text(endDate, style: .date)
                                                .font(.itemDetailsBody)
                                                .foregroundColor(.itemDetailsAccent)
                                        } else {
                                            Text("Not Set")
                                                .font(.itemDetailsBody)
                                                .foregroundColor(.itemDetailsSecondaryText)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ItemAvailabilitySection(viewModel: ItemDetailsViewModel())
        .padding()
}
