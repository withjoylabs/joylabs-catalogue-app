import SwiftUI

// MARK: - Item Details Pricing Section
/// Handles pricing, variations, SKU, and UPC information
struct ItemDetailsPricingSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        ItemDetailsSection(title: "Pricing & Variations", icon: "dollarsign.circle") {
            ItemDetailsCard {
                VStack(spacing: 0) {
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
                        
                        // Add black spacing between variations
                        if index < viewModel.itemData.variations.count - 1 {
                            Rectangle()
                                .fill(Color.itemDetailsModalBackground)
                                .frame(height: ItemDetailsSpacing.sectionSpacing)
                        }
                        
                        // Add separator only if this is not the last variation and we can add more
                        if index == viewModel.itemData.variations.count - 1 && viewModel.itemData.variations.count < 5 {
                            ItemDetailsFieldSeparator()
                        }
                    }
                    
                    // Add variation button - separate section
                    if viewModel.itemData.variations.count < 5 {
                        Rectangle()
                            .fill(Color.itemDetailsModalBackground)
                            .frame(height: ItemDetailsSpacing.compactSpacing)
                        
                        ItemDetailsButton(
                            title: "Add Variation",
                            icon: "plus.circle",
                            style: .secondary
                        ) {
                            addNewVariation()
                        }
                        .padding(ItemDetailsSpacing.fieldSpacing)
                        .background(Color.itemDetailsSectionBackground)
                        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
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
        VStack(alignment: .leading, spacing: 0) {
            // Header with variation name and delete button - with background and padding
            HStack {
                ItemDetailsFieldLabel(title: "Variation \(index + 1)")
                
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
                            .foregroundColor(.itemDetailsDestructive)
                            .font(.itemDetailsSubheadline)
                    }
                }
            }
            .padding(.horizontal, ItemDetailsSpacing.fieldSpacing)
            .padding(.vertical, ItemDetailsSpacing.fieldSpacing)
            .background(Color.itemDetailsSectionBackground)
            
            VStack(spacing: 0) {
                // Variation name - reduced spacing
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    ItemDetailsFieldLabel(title: "Variation Name")
                    
                    TextField("e.g., Small, Medium, Large", text: Binding(
                        get: { variation.name ?? "" },
                        set: { variation.name = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.itemDetailsBody)
                    .padding(ItemDetailsSpacing.fieldPadding)
                    .background(Color.itemDetailsFieldBackground)
                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .padding(.horizontal, ItemDetailsSpacing.fieldSpacing)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsSectionBackground)
                
                Rectangle()
                    .fill(Color.itemDetailsSeparator)
                    .frame(height: 0.5)
                
                // UPC and SKU row - reduced spacing
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        ItemDetailsFieldLabel(title: "UPC")
                        
                        TextField("Barcode number", text: Binding(
                            get: { variation.upc ?? "" },
                            set: {
                                variation.upc = $0.isEmpty ? nil : $0
                                duplicateDetection.checkForDuplicates(
                                    sku: variation.sku ?? "",
                                    upc: $0,
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        ))
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        ItemDetailsFieldLabel(title: "SKU")
                        
                        TextField("Internal SKU", text: Binding(
                            get: { variation.sku ?? "" },
                            set: {
                                variation.sku = $0.isEmpty ? nil : $0
                                duplicateDetection.checkForDuplicates(
                                    sku: $0,
                                    upc: variation.upc ?? "",
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        ))
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }
                .padding(.horizontal, ItemDetailsSpacing.fieldSpacing)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsSectionBackground)

                // Duplicate detection - only show when needed
                if !duplicateDetection.duplicateWarnings.isEmpty || 
                   (variation.upc != nil && !variation.upc!.isEmpty && !duplicateDetection.validateUPC(variation.upc!).isValid) {
                    Rectangle()
                        .fill(Color.itemDetailsSeparator)
                        .frame(height: 0.5)
                    
                    DuplicateDetectionSection(
                        variation: variation,
                        duplicateDetection: duplicateDetection
                    )
                    .padding(.horizontal, ItemDetailsSpacing.fieldSpacing)
                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                    .background(Color.itemDetailsSectionBackground)
                }
                
                Rectangle()
                    .fill(Color.itemDetailsSeparator)
                    .frame(height: 0.5)
                
                // Price and pricing type - reduced spacing
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        ItemDetailsFieldLabel(title: "Price")
                        
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            
                            if variation.pricingType == .variablePricing {
                                Text("Variable")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            } else {
                                TextField("0.00", text: Binding(
                                    get: { 
                                        if let price = variation.priceMoney {
                                            return String(format: "%.2f", price.displayAmount)
                                        }
                                        return ""
                                    },
                                    set: { text in
                                        if let amount = Double(text) {
                                            variation.priceMoney = MoneyData(dollars: amount)
                                        } else if text.isEmpty {
                                            variation.priceMoney = nil
                                        }
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .font(.itemDetailsBody)
                                .padding(ItemDetailsSpacing.fieldPadding)
                                .background(Color.itemDetailsFieldBackground)
                                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        ItemDetailsFieldLabel(title: "Pricing Type")
                        
                        Picker("Pricing Type", selection: Binding(
                            get: { variation.pricingType },
                            set: { variation.pricingType = $0 }
                        )) {
                            ForEach(PricingType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                .padding(.horizontal, ItemDetailsSpacing.fieldSpacing)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsSectionBackground)
            }
        }
        .background(Color.itemDetailsSectionBackground)
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
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
        ItemDetailsTextField(
            title: "Variation Name",
            placeholder: "e.g., Small, Medium, Large",
            text: $name
        )
    }
}

// MARK: - Variation SKU Field
struct VariationSKUField: View {
    @Binding var sku: String
    
    var body: some View {
        ItemDetailsTextField(
            title: "SKU",
            placeholder: "Internal SKU",
            text: $sku
        )
    }
}

// MARK: - Variation UPC Field
struct VariationUPCField: View {
    @Binding var upc: String
    
    var body: some View {
        ItemDetailsTextField(
            title: "UPC",
            placeholder: "Barcode number",
            text: $upc,
            keyboardType: .numberPad
        )
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
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            Text("Price")
                .font(.itemDetailsFieldLabel)
                .foregroundColor(.itemDetailsPrimaryText)

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
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
