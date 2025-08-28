import SwiftUI

// MARK: - Item Enabled Locations Section
struct ItemEnabledLocationsSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        ItemDetailsSection(title: "Enabled at Locations", icon: "location") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // All Locations Toggle
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Locations",
                            isOn: Binding(
                                get: { viewModel.staticData.locationsEnabled },
                                set: { newValue in
                                    viewModel.staticData.locationsEnabled = newValue
                                }
                            )
                        )
                    }
                    
                    ItemDetailsFieldSeparator()
                    
                    // Future Locations Toggle
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Available at All Future Locations",
                            isOn: Binding(
                                get: { viewModel.staticData.availableAtFutureLocations },
                                set: { newValue in
                                    viewModel.staticData.availableAtFutureLocations = newValue
                                    if !newValue {
                                        // If disabling future locations, must also disable present at all locations
                                        viewModel.staticData.presentAtAllLocations = false
                                        // Convert to specific location mode
                                        viewModel.staticData.presentAtLocationIds = viewModel.staticData.enabledLocationIds
                                        viewModel.staticData.absentAtLocationIds = []
                                    }
                                    // When enabling, the computed property sets presentAtAllLocations = true
                                }
                            )
                        )
                    }

                    if viewModel.staticData.locationsEnabled {
                        ItemDetailsFieldSeparator()

                        // Individual Location Selection
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                                Text("Select Specific Locations")
                                    .font(.itemDetailsSubheadline)
                                    .foregroundColor(.itemDetailsSecondaryText)
                                
                                if viewModel.availableLocations.isEmpty {
                                    ItemDetailsInfoView(
                                        message: "No locations available. Connect to Square to sync locations.",
                                        style: .warning
                                    )
                                } else {
                                    VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                                        ForEach(viewModel.availableLocations, id: \.id) { location in
                                            LocationToggleRow(
                                                location: location,
                                                isEnabled: viewModel.staticData.isLocationEnabled(location.id)
                                            ) { isEnabled in
                                                viewModel.staticData.setLocationEnabled(location.id, enabled: isEnabled)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Summary
                    if viewModel.staticData.locationsEnabled {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.itemDetailsSuccess)
                                    .font(.itemDetailsBody.weight(.medium))
                                
                                let enabledLocationCount = viewModel.availableLocations.filter { viewModel.staticData.isLocationEnabled($0.id) }.count
                                let totalLocationCount = viewModel.availableLocations.count
                                
                                if viewModel.staticData.presentAtAllLocations && viewModel.staticData.absentAtLocationIds.isEmpty {
                                    Text("Present at all locations")
                                        .font(.itemDetailsCaption)
                                        .foregroundColor(.itemDetailsSecondaryText)
                                } else if enabledLocationCount > 0 {
                                    Text("Enabled at \(enabledLocationCount) of \(totalLocationCount) location(s)")
                                        .font(.itemDetailsCaption)
                                        .foregroundColor(.itemDetailsSecondaryText)
                                } else {
                                    Text("Available at future locations only")
                                        .font(.itemDetailsCaption)
                                        .foregroundColor(.itemDetailsSecondaryText)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Location Toggle Row
struct LocationToggleRow: View {
    let location: LocationData
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.itemDetailsBody)
                    .foregroundColor(.itemDetailsPrimaryText)
                
                if !location.address.isEmpty {
                    Text(location.address)
                        .font(.itemDetailsCaption)
                        .foregroundColor(.itemDetailsSecondaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
        .frame(minHeight: ItemDetailsSpacing.minimumTouchTarget)
    }
}

#Preview {
    ItemEnabledLocationsSection(viewModel: ItemDetailsViewModel())
        .padding()
}