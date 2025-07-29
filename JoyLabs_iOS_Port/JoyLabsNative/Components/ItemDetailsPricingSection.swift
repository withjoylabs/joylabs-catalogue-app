import SwiftUI

// MARK: - Item Details Pricing Section
/// Handles pricing, variations, SKU, and UPC information
struct ItemDetailsPricingSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        // Variations list - same hierarchy as other sections
        ForEach(Array(viewModel.itemData.variations.enumerated()), id: \.offset) { index, variation in
                    VariationCard(
                        variation: Binding(
                            get: {
                                // Safe bounds checking
                                guard index < viewModel.itemData.variations.count else {
                                    return ItemDetailsVariationData()
                                }
                                return viewModel.itemData.variations[index]
                            },
                            set: { newValue in
                                // Safe bounds checking
                                guard index < viewModel.itemData.variations.count else { return }
                                viewModel.itemData.variations[index] = newValue
                                viewModel.hasUnsavedChanges = true
                            }
                        ),
                        index: index,
                        onDelete: {
                            // Safe removal with bounds checking
                            guard index < viewModel.itemData.variations.count && viewModel.itemData.variations.count > 1 else { return }
                            viewModel.itemData.variations.remove(at: index)
                            viewModel.hasUnsavedChanges = true
                        },
                        viewModel: viewModel
                    )
        }

        // Add variation button - same hierarchy
        if viewModel.itemData.variations.count < 5 {
            AddVariationButton {
                addNewVariation()
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
    @StateObject private var duplicateDetection = DuplicateDetectionService()
    @ObservedObject var viewModel: ItemDetailsViewModel

    // Check if variation has meaningful data
    private var variationHasData: Bool {
        return !(variation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.upc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               (variation.priceMoney?.amount ?? 0) > 0
    }

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
                        // Check if variation has data before showing confirmation
                        if variationHasData {
                            showingDeleteConfirmation = true
                        } else {
                            onDelete()
                        }
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
                
                // UPC and SKU row (UPC first)
                HStack(spacing: 12) {
                    VariationUPCField(
                        upc: Binding(
                            get: { variation.upc ?? "" },
                            set: {
                                variation.upc = $0.isEmpty ? nil : $0
                                // Trigger duplicate detection when UPC changes
                                duplicateDetection.checkForDuplicates(
                                    sku: variation.sku ?? "",
                                    upc: $0,
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        )
                    )

                    VariationSKUField(
                        sku: Binding(
                            get: { variation.sku ?? "" },
                            set: {
                                variation.sku = $0.isEmpty ? nil : $0
                                // Trigger duplicate detection when SKU changes
                                duplicateDetection.checkForDuplicates(
                                    sku: $0,
                                    upc: variation.upc ?? "",
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        )
                    )
                }

                // Validation and duplicate detection section (fixed height to prevent jittering)
                DuplicateDetectionSection(
                    variation: variation,
                    duplicateDetection: duplicateDetection
                )
                
                // Pricing type and price (50/50 split - always show both)
                HStack(spacing: 12) {
                    PriceField(
                        priceMoney: Binding(
                            get: { variation.priceMoney },
                            set: { variation.priceMoney = $0 }
                        ),
                        isDisabled: variation.pricingType == .variablePricing
                    )
                    .frame(maxWidth: .infinity)

                    PricingTypeSelector(
                        pricingType: Binding(
                            get: { variation.pricingType },
                            set: { variation.pricingType = $0 }
                        )
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
    let isDisabled: Bool

    init(priceMoney: Binding<MoneyData?>, isDisabled: Bool = false) {
        self._priceMoney = priceMoney
        self.isDisabled = isDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Price")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            HStack {
                Text("$")
                    .foregroundColor(isDisabled ? .secondary : .secondary)

                if isDisabled {
                    Text("Variable")
                        .foregroundColor(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                } else {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: priceText) { _, newValue in
                            updatePriceFromText(newValue)
                        }
                }
            }
        }
        .onAppear {
            if let price = priceMoney {
                priceText = String(format: "%.2f", price.displayAmount)
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
                    .font(.caption)

                Text("Add Variation")
                    .foregroundColor(.blue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

// MARK: - Duplicate Detection Section (Anti-Jitter)

/// Zero-jitter section for duplicate detection - only shows content when there's something to display
struct DuplicateDetectionSection: View {
    let variation: ItemDetailsVariationData
    @ObservedObject var duplicateDetection: DuplicateDetectionService

    var body: some View {
        VStack(spacing: 8) {
            // UPC validation error (always check immediately, no debounce)
            if let upc = variation.upc, !upc.isEmpty {
                let validationResult = duplicateDetection.validateUPC(upc)
                if !validationResult.isValid, case .invalid(let error) = validationResult {
                    UPCValidationErrorView(error: error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // ONLY show content when we actually have results - NO space reservation during search
            if !duplicateDetection.duplicateWarnings.isEmpty {
                DuplicateWarningView(warnings: duplicateDetection.duplicateWarnings)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // NO loading indicator - completely invisible during search to prevent UI movement
        }
        .animation(.easeInOut(duration: 0.2), value: duplicateDetection.duplicateWarnings.count)
    }
}

#Preview("Pricing Section") {
    ScrollView {
        ItemDetailsPricingSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
