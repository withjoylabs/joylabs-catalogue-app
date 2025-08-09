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
                            title: "Enable at All Locations",
                            isOn: $viewModel.itemData.enabledAtAllLocations
                        )
                        .onChange(of: viewModel.itemData.enabledAtAllLocations) { _, newValue in
                            if newValue {
                                // If enabling at all locations, select all
                                viewModel.itemData.enabledLocationIds = viewModel.availableLocations.map { $0.id }
                            }
                        }
                    }

                    if !viewModel.itemData.enabledAtAllLocations {
                        ItemDetailsFieldSeparator()

                        // Individual Location Selection
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.fieldSpacing) {
                                Text("Select Specific Locations")
                                    .font(.itemDetailsSubheadline)
                                    .foregroundColor(.itemDetailsSecondaryText)
                                
                                if viewModel.availableLocations.isEmpty {
                                    ItemDetailsInfoView(
                                        message: "No locations available. Connect to Square to sync locations.",
                                        style: .warning
                                    )
                                } else {
                                    VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                                        ForEach(viewModel.availableLocations, id: \.id) { location in
                                            LocationToggleRow(
                                                location: location,
                                                isEnabled: viewModel.itemData.enabledLocationIds.contains(location.id)
                                            ) { isEnabled in
                                                if isEnabled {
                                                    if !viewModel.itemData.enabledLocationIds.contains(location.id) {
                                                        viewModel.itemData.enabledLocationIds.append(location.id)
                                                    }
                                                } else {
                                                    viewModel.itemData.enabledLocationIds.removeAll { $0 == location.id }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Summary
                    if !viewModel.itemData.enabledLocationIds.isEmpty {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.itemDetailsSuccess)
                                    .font(.itemDetailsBody.weight(.medium))
                                
                                if viewModel.itemData.enabledAtAllLocations {
                                    Text("Enabled at all locations")
                                        .font(.itemDetailsCaption)
                                        .foregroundColor(.itemDetailsSecondaryText)
                                } else {
                                    Text("Enabled at \(viewModel.itemData.enabledLocationIds.count) location(s)")
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
