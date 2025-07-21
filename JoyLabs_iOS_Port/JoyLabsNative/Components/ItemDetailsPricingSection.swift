import SwiftUI

// MARK: - Item Details Pricing Section
/// Handles pricing, variations, SKU, and UPC information
struct ItemDetailsPricingSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Pricing & Variations", icon: "dollarsign.circle")
            
            VStack(spacing: 16) {
                // Variations list
                ForEach(Array(viewModel.itemData.variations.enumerated()), id: \.offset) { index, variation in
                    VariationCard(
                        variation: Binding(
                            get: { viewModel.itemData.variations[index] },
                            set: { viewModel.itemData.variations[index] = $0 }
                        ),
                        index: index,
                        onDelete: {
                            if viewModel.itemData.variations.count > 1 {
                                viewModel.itemData.variations.remove(at: index)
                            }
                        }
                    )
                }
                
                // Add variation button
                if viewModel.itemData.variations.count < 5 {
                    AddVariationButton {
                        addNewVariation()
                    }
                }
            }
        }
    }
    
    private func addNewVariation() {
        let newVariation = ItemDetailsVariationData()
        viewModel.itemData.variations.append(newVariation)
    }
}

// MARK: - Variation Card
struct VariationCard: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with variation name and delete button
            HStack {
                Text("Variation \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if index > 0 { // Don't allow deleting the first variation
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            VStack(spacing: 12) {
                // Variation name
                VariationNameField(
                    name: Binding(
                        get: { variation.name ?? "" },
                        set: { variation.name = $0.isEmpty ? nil : $0 }
                    )
                )
                
                // SKU and UPC row
                HStack(spacing: 12) {
                    VariationSKUField(
                        sku: Binding(
                            get: { variation.sku ?? "" },
                            set: { variation.sku = $0.isEmpty ? nil : $0 }
                        )
                    )
                    
                    VariationUPCField(
                        upc: Binding(
                            get: { variation.upc ?? "" },
                            set: { variation.upc = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
                
                // Pricing type and price
                VStack(spacing: 8) {
                    PricingTypeSelector(
                        pricingType: Binding(
                            get: { variation.pricingType },
                            set: { variation.pricingType = $0 }
                        )
                    )
                    
                    if variation.pricingType == .fixedPricing {
                        PriceField(
                            priceMoney: Binding(
                                get: { variation.priceMoney },
                                set: { variation.priceMoney = $0 }
                            )
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .confirmationDialog(
            "Delete Variation",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this variation? This action cannot be undone.")
        }
    }
}

// MARK: - Variation Name Field
struct VariationNameField: View {
    @Binding var name: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Variation Name")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            TextField("e.g., Small, Medium, Large", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Variation SKU Field
struct VariationSKUField: View {
    @Binding var sku: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SKU")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            TextField("Internal SKU", text: $sku)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Variation UPC Field
struct VariationUPCField: View {
    @Binding var upc: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UPC/Barcode")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            TextField("Barcode number", text: $upc)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - Pricing Type Selector
struct PricingTypeSelector: View {
    @Binding var pricingType: PricingType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pricing Type")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Picker("Pricing Type", selection: $pricingType) {
                ForEach(PricingType.allCases, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
}

// MARK: - Price Field
struct PriceField: View {
    @Binding var priceMoney: MoneyData?
    @State private var priceText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Price")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            HStack {
                Text("$")
                    .foregroundColor(.secondary)
                
                TextField("0.00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: priceText) { newValue in
                        updatePriceFromText(newValue)
                    }
                    .onAppear {
                        if let price = priceMoney {
                            priceText = String(format: "%.2f", price.displayAmount)
                        }
                    }
            }
        }
    }
    
    private func updatePriceFromText(_ text: String) {
        if let amount = Double(text) {
            priceMoney = MoneyData(dollars: amount)
        } else if text.isEmpty {
            priceMoney = nil
        }
    }
}

// MARK: - Add Variation Button
struct AddVariationButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus.circle")
                    .foregroundColor(.blue)
                
                Text("Add Variation")
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

#Preview("Pricing Section") {
    ScrollView {
        ItemDetailsPricingSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
