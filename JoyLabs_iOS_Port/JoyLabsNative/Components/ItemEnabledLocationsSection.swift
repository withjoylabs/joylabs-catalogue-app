import SwiftUI

// MARK: - Item Enabled Locations Section
struct ItemEnabledLocationsSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Enabled at Locations", icon: "location")
            
            VStack(spacing: 12) {
                // All Locations Toggle
                HStack {
                    Text("Enable at All Locations")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.itemData.enabledAtAllLocations)
                        .labelsHidden()
                        .onChange(of: viewModel.itemData.enabledAtAllLocations) { newValue in
                            if newValue {
                                // If enabling at all locations, select all
                                viewModel.itemData.enabledLocationIds = viewModel.availableLocations.map { $0.id }
                            }
                        }
                }
                
                if !viewModel.itemData.enabledAtAllLocations {
                    Divider()
                    
                    // Individual Location Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Specific Locations")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        if viewModel.availableLocations.isEmpty {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                Text("No locations available. Connect to Square to sync locations.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
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
                
                // Summary
                if !viewModel.itemData.enabledLocationIds.isEmpty {
                    Divider()
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        if viewModel.itemData.enabledAtAllLocations {
                            Text("Enabled at all locations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Enabled at \(viewModel.itemData.enabledLocationIds.count) location(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                    .font(.body)
                    .foregroundColor(.primary)
                
                if !location.address.isEmpty {
                    Text(location.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .padding(.vertical, 4)
    }
}

#Preview {
    ItemEnabledLocationsSection(viewModel: ItemDetailsViewModel())
        .padding()
}
