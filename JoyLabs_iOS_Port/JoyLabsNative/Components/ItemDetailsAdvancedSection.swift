import SwiftUI

// MARK: - Item Details Advanced Section
/// Handles advanced features like inventory, service settings, and custom attributes
struct ItemDetailsAdvancedSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        ItemDetailsSection(title: "Advanced Settings", icon: "gearshape") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Availability Settings
                    ItemDetailsFieldRow {
                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                            ItemDetailsFieldLabel(title: "Availability")
                            
                            VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                ItemDetailsToggleRow(
                                    title: "Available Online",
                                    description: "Can be ordered through online channels",
                                    isOn: Binding(
                                        get: { viewModel.itemData.availableOnline },
                                        set: { viewModel.itemData.availableOnline = $0 }
                                    )
                                )
                                
                                ItemDetailsToggleRow(
                                    title: "Available for Pickup",
                                    description: "Can be picked up at physical locations",
                                    isOn: Binding(
                                        get: { viewModel.itemData.availableForPickup },
                                        set: { viewModel.itemData.availableForPickup = $0 }
                                    )
                                )
                                
                                ItemDetailsToggleRow(
                                    title: "Available Electronically",
                                    description: "Digital delivery available",
                                    isOn: Binding(
                                        get: { viewModel.itemData.availableElectronically },
                                        set: { viewModel.itemData.availableElectronically = $0 }
                                    )
                                )
                            }
                        }
                    }
                    
                    ItemDetailsFieldSeparator()
                    
                    // Inventory Settings
                    ItemDetailsFieldRow {
                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                            ItemDetailsFieldLabel(title: "Inventory")
                            
                            VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                ItemDetailsToggleRow(
                                    title: "Track Inventory",
                                    description: "Monitor stock levels for this item",
                                    isOn: Binding(
                                        get: { viewModel.itemData.trackInventory },
                                        set: { viewModel.itemData.trackInventory = $0 }
                                    )
                                )
                                
                                if viewModel.itemData.trackInventory {
                                    VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                        // Alert Type Picker
                                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                                            ItemDetailsFieldLabel(title: "Alert Type")
                                            
                                            Picker("Alert Type", selection: Binding(
                                                get: { viewModel.itemData.inventoryAlertType },
                                                set: { viewModel.itemData.inventoryAlertType = $0 }
                                            )) {
                                                ForEach(InventoryAlertType.allCases, id: \.self) { type in
                                                    Text(type.displayName).tag(type)
                                                }
                                            }
                                            .pickerStyle(SegmentedPickerStyle())
                                        }
                                        
                                        // Alert Threshold
                                        if viewModel.itemData.inventoryAlertType == .lowQuantity {
                                            ItemDetailsTextField(
                                                title: "Alert Threshold",
                                                placeholder: "Minimum quantity",
                                                text: Binding(
                                                    get: { 
                                                        if let threshold = viewModel.itemData.inventoryAlertThreshold {
                                                            return String(threshold)
                                                        }
                                                        return ""
                                                    },
                                                    set: { 
                                                        if let threshold = Int($0) {
                                                            viewModel.itemData.inventoryAlertThreshold = threshold
                                                        } else {
                                                            viewModel.itemData.inventoryAlertThreshold = nil
                                                        }
                                                    }
                                                ),
                                                keyboardType: .numberPad
                                            )
                                        }
                                    }
                                    .padding(.leading, ItemDetailsSpacing.compactSpacing)
                                }
                            }
                        }
                    }
                    
                    // Service Settings (for appointment services)
                    if viewModel.itemData.productType == .appointmentsService {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                ItemDetailsFieldLabel(title: "Service Settings")
                                
                                VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                    ItemDetailsToggleRow(
                                        title: "Available for Booking",
                                        description: "Can be booked through appointment system",
                                        isOn: Binding(
                                            get: { viewModel.itemData.availableForBooking },
                                            set: { viewModel.itemData.availableForBooking = $0 }
                                        )
                                    )
                                    
                                    if viewModel.itemData.availableForBooking {
                                        VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                            // Service Duration
                                            ItemDetailsTextField(
                                                title: "Service Duration (minutes)",
                                                placeholder: "Duration in minutes",
                                                text: Binding(
                                                    get: {
                                                        if let duration = viewModel.itemData.serviceDuration {
                                                            return String(duration / (60 * 1000))
                                                        }
                                                        return ""
                                                    },
                                                    set: { newValue in
                                                        if let minutes = Int(newValue) {
                                                            viewModel.itemData.serviceDuration = minutes * 60 * 1000
                                                        } else {
                                                            viewModel.itemData.serviceDuration = nil
                                                        }
                                                    }
                                                ),
                                                keyboardType: .numberPad
                                            )
                                            
                                            // Team Members - simplified for now
                                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                                                ItemDetailsFieldLabel(title: "Assigned Team Members")
                                                
                                                Button(action: {
                                                    // TODO: Show team member picker
                                                }) {
                                                    HStack {
                                                        if viewModel.itemData.teamMemberIds.isEmpty {
                                                            Text("Select team members")
                                                                .foregroundColor(.itemDetailsSecondaryText)
                                                        } else {
                                                            Text("\(viewModel.itemData.teamMemberIds.count) member(s) assigned")
                                                                .foregroundColor(.itemDetailsPrimaryText)
                                                        }
                                                        
                                                        Spacer()
                                                        
                                                        Image(systemName: "chevron.right")
                                                            .foregroundColor(.itemDetailsSecondaryText)
                                                            .font(.itemDetailsCaption)
                                                    }
                                                    .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                                                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                                                    .background(Color.itemDetailsFieldBackground)
                                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                                }
                                            }
                                        }
                                        .padding(.leading, ItemDetailsSpacing.compactSpacing)
                                    }
                                }
                            }
                        }
                    }
                    
                    ItemDetailsFieldSeparator()
                    
                    // Modifier Settings
                    ItemDetailsFieldRow {
                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                            ItemDetailsFieldLabel(title: "Modifier Behavior")
                            
                            ItemDetailsToggleRow(
                                title: "Skip Modifier Screen",
                                description: "Don't show modifier selection when adding to cart",
                                isOn: Binding(
                                    get: { viewModel.itemData.skipModifierScreen },
                                    set: { viewModel.itemData.skipModifierScreen = $0 }
                                )
                            )
                        }
                    }
                }
            }
        }
    }
}


#Preview("Advanced Section") {
    ScrollView {
        ItemDetailsAdvancedSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
