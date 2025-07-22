import SwiftUI

// MARK: - Item Measurement Section
/// Handles measurement units, sellable/stockable settings, and unit-related configurations
struct ItemMeasurementSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemDetailsSectionHeader(title: "Measurement & Units", icon: "ruler")

            VStack(spacing: 4) {
                // Measurement Unit
                if configManager.currentConfiguration.advancedFields.measurementUnitEnabled {
                    MeasurementUnitSettings(
                        measurementUnitId: Binding(
                            get: { viewModel.itemData.measurementUnitId ?? "" },
                            set: { viewModel.itemData.measurementUnitId = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
                
                // Sellable/Stockable Settings
                if configManager.currentConfiguration.advancedFields.sellableEnabled ||
                   configManager.currentConfiguration.advancedFields.stockableEnabled {
                    SellableStockableSettings(
                        sellable: Binding(
                            get: { viewModel.itemData.sellable },
                            set: { viewModel.itemData.sellable = $0 }
                        ),
                        stockable: Binding(
                            get: { viewModel.itemData.stockable },
                            set: { viewModel.itemData.stockable = $0 }
                        ),
                        sellableEnabled: configManager.currentConfiguration.advancedFields.sellableEnabled,
                        stockableEnabled: configManager.currentConfiguration.advancedFields.stockableEnabled
                    )
                }
                
                // User Data (Custom JSON)
                if configManager.currentConfiguration.advancedFields.userDataEnabled {
                    UserDataSettings(
                        userData: Binding(
                            get: { viewModel.itemData.userData ?? "" },
                            set: { viewModel.itemData.userData = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Measurement Unit Settings
struct MeasurementUnitSettings: View {
    @Binding var measurementUnitId: String
    
    private let commonUnits = [
        MeasurementUnit(id: "unit_each", name: "Each", abbreviation: "ea"),
        MeasurementUnit(id: "unit_pound", name: "Pound", abbreviation: "lb"),
        MeasurementUnit(id: "unit_ounce", name: "Ounce", abbreviation: "oz"),
        MeasurementUnit(id: "unit_kilogram", name: "Kilogram", abbreviation: "kg"),
        MeasurementUnit(id: "unit_gram", name: "Gram", abbreviation: "g"),
        MeasurementUnit(id: "unit_liter", name: "Liter", abbreviation: "L"),
        MeasurementUnit(id: "unit_milliliter", name: "Milliliter", abbreviation: "mL"),
        MeasurementUnit(id: "unit_gallon", name: "Gallon", abbreviation: "gal"),
        MeasurementUnit(id: "unit_quart", name: "Quart", abbreviation: "qt"),
        MeasurementUnit(id: "unit_pint", name: "Pint", abbreviation: "pt"),
        MeasurementUnit(id: "unit_cup", name: "Cup", abbreviation: "cup"),
        MeasurementUnit(id: "unit_tablespoon", name: "Tablespoon", abbreviation: "tbsp"),
        MeasurementUnit(id: "unit_teaspoon", name: "Teaspoon", abbreviation: "tsp"),
        MeasurementUnit(id: "unit_foot", name: "Foot", abbreviation: "ft"),
        MeasurementUnit(id: "unit_inch", name: "Inch", abbreviation: "in"),
        MeasurementUnit(id: "unit_meter", name: "Meter", abbreviation: "m"),
        MeasurementUnit(id: "unit_centimeter", name: "Centimeter", abbreviation: "cm")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurement Unit")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                // Unit Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit of Measurement")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Picker("Measurement Unit", selection: $measurementUnitId) {
                        Text("No Unit")
                            .tag("")
                        
                        ForEach(commonUnits, id: \.id) { unit in
                            Text("\(unit.name) (\(unit.abbreviation))")
                                .tag(unit.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Selected unit display
                if !measurementUnitId.isEmpty {
                    if let selectedUnit = commonUnits.first(where: { $0.id == measurementUnitId }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            
                            Text("Selected: \(selectedUnit.name) (\(selectedUnit.abbreviation))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                }
                
                // Info text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Measurement Unit Guide:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("• Used for inventory tracking and pricing\n• Helps customers understand quantity\n• Required for some integrations\n• Can be changed later if needed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Sellable/Stockable Settings
struct SellableStockableSettings: View {
    @Binding var sellable: Bool
    @Binding var stockable: Bool
    let sellableEnabled: Bool
    let stockableEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item Properties")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                if sellableEnabled {
                    ToggleRow(
                        title: "Sellable",
                        description: "Item can be sold to customers",
                        isOn: $sellable
                    )
                }
                
                if stockableEnabled {
                    ToggleRow(
                        title: "Stockable",
                        description: "Item can be tracked in inventory",
                        isOn: $stockable
                    )
                }
                
                // Info about the settings
                VStack(alignment: .leading, spacing: 4) {
                    Text("Property Guide:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("• Sellable: Controls if item appears in sales channels\n• Stockable: Controls if item can be tracked in inventory\n• Both can be enabled independently")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - User Data Settings
struct UserDataSettings: View {
    @Binding var userData: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            
            if isExpanded {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JSON Data")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        TextField("Enter custom JSON data", text: $userData, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(5...10)
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    // JSON validation indicator
                    if !userData.isEmpty {
                        HStack {
                            Image(systemName: isValidJSON ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isValidJSON ? .green : .orange)
                            
                            Text(isValidJSON ? "Valid JSON" : "Invalid JSON format")
                                .font(.caption)
                                .foregroundColor(isValidJSON ? .green : .orange)
                            
                            Spacer()
                        }
                    }
                    
                    // Info text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Data Guide:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("• Store additional item metadata as JSON\n• Useful for integrations and custom fields\n• Must be valid JSON format\n• Example: {\"color\": \"red\", \"size\": \"large\"}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var isValidJSON: Bool {
        guard !userData.isEmpty else { return true }
        
        do {
            _ = try JSONSerialization.jsonObject(with: userData.data(using: .utf8) ?? Data())
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Measurement Unit Model
struct MeasurementUnit {
    let id: String
    let name: String
    let abbreviation: String
}

// Note: ToggleRow is defined in ItemDetailsAdvancedSection.swift

#Preview("Measurement Section") {
    ScrollView {
        ItemMeasurementSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
