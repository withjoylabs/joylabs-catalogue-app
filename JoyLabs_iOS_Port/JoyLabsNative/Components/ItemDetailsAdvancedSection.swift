import SwiftUI

// MARK: - Item Details Advanced Section
/// Handles advanced features like inventory, service settings, and custom attributes
struct ItemDetailsAdvancedSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Advanced Settings", icon: "gearshape")
            
            VStack(spacing: 16) {
                // Availability Settings
                AvailabilitySettings(
                    availableOnline: Binding(
                        get: { viewModel.itemData.availableOnline },
                        set: { viewModel.itemData.availableOnline = $0 }
                    ),
                    availableForPickup: Binding(
                        get: { viewModel.itemData.availableForPickup },
                        set: { viewModel.itemData.availableForPickup = $0 }
                    ),
                    availableElectronically: Binding(
                        get: { viewModel.itemData.availableElectronically },
                        set: { viewModel.itemData.availableElectronically = $0 }
                    )
                )
                
                // Inventory Settings
                InventorySettings(
                    trackInventory: Binding(
                        get: { viewModel.itemData.trackInventory },
                        set: { viewModel.itemData.trackInventory = $0 }
                    ),
                    inventoryAlertType: Binding(
                        get: { viewModel.itemData.inventoryAlertType },
                        set: { viewModel.itemData.inventoryAlertType = $0 }
                    ),
                    inventoryAlertThreshold: Binding(
                        get: { viewModel.itemData.inventoryAlertThreshold },
                        set: { viewModel.itemData.inventoryAlertThreshold = $0 }
                    )
                )
                
                // Service Settings (for appointment services)
                if viewModel.itemData.productType == .appointmentsService {
                    ServiceSettings(
                        serviceDuration: Binding(
                            get: { viewModel.itemData.serviceDuration },
                            set: { viewModel.itemData.serviceDuration = $0 }
                        ),
                        availableForBooking: Binding(
                            get: { viewModel.itemData.availableForBooking },
                            set: { viewModel.itemData.availableForBooking = $0 }
                        ),
                        teamMemberIds: Binding(
                            get: { viewModel.itemData.teamMemberIds },
                            set: { viewModel.itemData.teamMemberIds = $0 }
                        )
                    )
                }
                
                // Modifier Settings
                ModifierSettings(
                    skipModifierScreen: Binding(
                        get: { viewModel.itemData.skipModifierScreen },
                        set: { viewModel.itemData.skipModifierScreen = $0 }
                    )
                )
            }
        }
    }
}

// MARK: - Availability Settings
struct AvailabilitySettings: View {
    @Binding var availableOnline: Bool
    @Binding var availableForPickup: Bool
    @Binding var availableElectronically: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Availability")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ToggleRow(
                    title: "Available Online",
                    description: "Can be ordered through online channels",
                    isOn: $availableOnline
                )
                
                ToggleRow(
                    title: "Available for Pickup",
                    description: "Can be picked up at physical locations",
                    isOn: $availableForPickup
                )
                
                ToggleRow(
                    title: "Available Electronically",
                    description: "Digital delivery available",
                    isOn: $availableElectronically
                )
            }
        }
    }
}

// MARK: - Inventory Settings
struct InventorySettings: View {
    @Binding var trackInventory: Bool
    @Binding var inventoryAlertType: InventoryAlertType
    @Binding var inventoryAlertThreshold: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inventory")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ToggleRow(
                    title: "Track Inventory",
                    description: "Monitor stock levels for this item",
                    isOn: $trackInventory
                )
                
                if trackInventory {
                    VStack(spacing: 8) {
                        // Alert Type Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Alert Type")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Picker("Alert Type", selection: $inventoryAlertType) {
                                ForEach(InventoryAlertType.allCases, id: \.self) { type in
                                    Text(type.displayName)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        // Alert Threshold
                        if inventoryAlertType == .lowQuantity {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Alert Threshold")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                TextField("Minimum quantity", value: $inventoryAlertThreshold, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Service Settings
struct ServiceSettings: View {
    @Binding var serviceDuration: Int?
    @Binding var availableForBooking: Bool
    @Binding var teamMemberIds: [String]
    
    @State private var durationMinutes: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service Settings")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ToggleRow(
                    title: "Available for Booking",
                    description: "Can be booked through appointment system",
                    isOn: $availableForBooking
                )
                
                if availableForBooking {
                    VStack(spacing: 8) {
                        // Service Duration
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Service Duration (minutes)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            TextField("Duration in minutes", text: $durationMinutes)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .onChange(of: durationMinutes) { _, newValue in
                                    if let minutes = Int(newValue) {
                                        serviceDuration = minutes * 60 * 1000 // Convert to milliseconds
                                    } else {
                                        serviceDuration = nil
                                    }
                                }
                                .onAppear {
                                    if let duration = serviceDuration {
                                        durationMinutes = String(duration / (60 * 1000))
                                    }
                                }
                        }
                        
                        // Team Members
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Assigned Team Members")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Button(action: {
                                // TODO: Show team member picker
                            }) {
                                HStack {
                                    if teamMemberIds.isEmpty {
                                        Text("Select team members")
                                            .foregroundColor(Color.secondary)
                                    } else {
                                        Text("\(teamMemberIds.count) member(s) assigned")
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Color.secondary)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Modifier Settings
struct ModifierSettings: View {
    @Binding var skipModifierScreen: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modifier Behavior")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            ToggleRow(
                title: "Skip Modifier Screen",
                description: "Don't show modifier selection when adding to cart",
                isOn: $skipModifierScreen
            )
        }
    }
}

// MARK: - Toggle Row
struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview("Advanced Section") {
    ScrollView {
        ItemDetailsAdvancedSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
