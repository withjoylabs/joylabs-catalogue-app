import SwiftUI

// MARK: - Item Location Overrides Section
/// Handles location-specific pricing and inventory overrides
struct ItemLocationOverridesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingAddOverride = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Location Overrides", icon: "location.circle")
            
            VStack(spacing: 12) {
                // Info text
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Set different prices or inventory settings for specific locations")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(.vertical, 4)
                
                // Existing overrides
                ForEach(Array(viewModel.staticData.locationOverrides.enumerated()), id: \.offset) { index, override in
                    LocationOverrideCard(
                        override: Binding(
                            get: { viewModel.staticData.locationOverrides[index] },
                            set: { viewModel.staticData.locationOverrides[index] = $0 }
                        ),
                        availableLocations: viewModel.availableLocations,
                        onDelete: {
                            viewModel.staticData.locationOverrides.remove(at: index)
                        }
                    )
                }
                
                // Add override button
                if viewModel.availableLocations.count > viewModel.staticData.locationOverrides.count {
                    Button(action: {
                        showingAddOverride = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                            Text("Add Location Override")
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddOverride) {
            AddLocationOverrideSheet(
                availableLocations: viewModel.availableLocations.filter { location in
                    !viewModel.staticData.locationOverrides.contains { $0.locationId == location.id }
                },
                onAdd: { newOverride in
                    viewModel.staticData.locationOverrides.append(newOverride)
                }
            )
            .nestedComponentModal()
        }
    }
}

// MARK: - Location Override Card
struct LocationOverrideCard: View {
    @Binding var override: LocationOverrideData
    let availableLocations: [LocationData]
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with location name and delete button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Location Override")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            VStack(spacing: 12) {
                // Price override
                if let priceMoney = override.priceMoney {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Override Price")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("$")
                                .foregroundColor(Color.secondary)
                            
                            TextField("0.00", value: Binding(
                                get: { priceMoney.displayAmount },
                                set: { newValue in
                                    override.priceMoney = MoneyData(dollars: newValue)
                                }
                            ), format: .number.precision(.fractionLength(2)))
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                // Inventory override
                if override.trackInventory {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stock on Hand")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        TextField("Quantity", value: $override.stockOnHand, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Toggle options
                VStack(spacing: 8) {
                    Toggle("Override Price", isOn: Binding(
                        get: { override.priceMoney != nil },
                        set: { enabled in
                            if enabled {
                                override.priceMoney = MoneyData(dollars: 0.0)
                            } else {
                                override.priceMoney = nil
                            }
                        }
                    ))
                    .font(.caption)
                    
                    Toggle("Track Inventory", isOn: $override.trackInventory)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .confirmationDialog(
            "Delete Location Override",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this location override?")
        }
    }
    
    private var locationName: String {
        availableLocations.first { $0.id == override.locationId }?.name ?? "Unknown Location"
    }
}

// MARK: - Add Location Override Sheet
struct AddLocationOverrideSheet: View {
    let availableLocations: [LocationData]
    let onAdd: (LocationOverrideData) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocationId: String = ""
    @State private var overridePrice = false
    @State private var trackInventory = false
    @State private var priceAmount: Double = 0.0
    @State private var stockOnHand: Int = 0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Location") {
                    Picker("Select Location", selection: $selectedLocationId) {
                        ForEach(availableLocations, id: \.id) { location in
                            Text(location.name)
                                .tag(location.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Override Settings") {
                    Toggle("Override Price", isOn: $overridePrice)
                    
                    if overridePrice {
                        HStack {
                            Text("Price")
                            Spacer()
                            Text("$")
                            TextField("0.00", value: $priceAmount, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                        }
                    }
                    
                    Toggle("Track Inventory", isOn: $trackInventory)
                    
                    if trackInventory {
                        HStack {
                            Text("Stock on Hand")
                            Spacer()
                            TextField("0", value: $stockOnHand, format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                        }
                    }
                }
            }
            .navigationTitle("Add Location Override")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addOverride()
                    }
                    .disabled(selectedLocationId.isEmpty)
                }
            }
        }
        .onAppear {
            if let firstLocation = availableLocations.first {
                selectedLocationId = firstLocation.id
            }
        }
    }
    
    private func addOverride() {
        let newOverride = LocationOverrideData(
            locationId: selectedLocationId,
            priceMoney: overridePrice ? MoneyData(dollars: priceAmount) : nil,
            trackInventory: trackInventory,
            stockOnHand: trackInventory ? stockOnHand : 0
        )
        
        onAdd(newOverride)
        dismiss()
    }
}

#Preview("Location Overrides Section") {
    ScrollView {
        ItemLocationOverridesSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
