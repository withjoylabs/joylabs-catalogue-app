import SwiftUI

// MARK: - Item Details Pricing Section
/// Handles pricing, variations, SKU, and UPC information
struct ItemDetailsPricingSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    let onVariationPrint: (ItemDetailsVariationData, @escaping (Bool) -> Void) -> Void
    @State private var printingVariationIndices = Set<Int>()
    
    var body: some View {
        ItemDetailsSection(title: "Pricing & Variations", icon: "dollarsign.circle") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.variations.enumerated()), id: \.offset) { index, variation in
                        VariationCard(
                            variation: Binding(
                                get: {
                                    // Safe bounds checking
                                    guard index < viewModel.variations.count else {
                                        return ItemDetailsVariationData()
                                    }
                                    return viewModel.variations[index]
                                },
                                set: { newValue in
                                    // Safe bounds checking
                                    guard index < viewModel.variations.count else { return }
                                    viewModel.variations[index] = newValue
                                    viewModel.hasChanges = true
                                }
                            ),
                            index: index,
                            onDelete: {
                                // Safe removal with bounds checking
                                guard index < viewModel.variations.count && viewModel.variations.count > 1 else { return }
                                viewModel.variations.remove(at: index)
                                viewModel.hasChanges = true
                            },
                            onPrint: { variation in
                                printingVariationIndices.insert(index)
                                onVariationPrint(variation) { _ in
                                    printingVariationIndices.remove(index)
                                }
                            },
                            isPrinting: printingVariationIndices.contains(index),
                            viewModel: viewModel
                        )
                        
                        // Add black spacing between variations
                        if index < viewModel.variations.count - 1 {
                            Rectangle()
                                .fill(Color.itemDetailsModalBackground)
                                .frame(height: ItemDetailsSpacing.sectionSpacing)
                        }
                        
                    }
                    
                    // Add variation button - separate section
                    if viewModel.variations.count < 5 {
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
                        .padding(ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsSectionBackground)
                        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
                    }
                }
            }
        }
    }

    private func addNewVariation() {
        let newVariation = ItemDetailsVariationData()
        viewModel.variations.append(newVariation)
    }
}

// MARK: - Variation Card
struct VariationCard: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    let onDelete: () -> Void
    let onPrint: (ItemDetailsVariationData) -> Void
    let isPrinting: Bool

    @StateObject private var duplicateDetection = DuplicateDetectionService()
    @StateObject private var dialogService = ConfirmationDialogService.shared
    @ObservedObject var viewModel: ItemDetailsViewModel

    // Check if variation has meaningful data
    private var variationHasData: Bool {
        return !(variation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.upc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               (variation.priceMoney?.amount ?? 0) > 0
    }
    
    // Check if user can add more price overrides
    private var canAddPriceOverride: Bool {
        let usedLocationIds = Set(variation.locationOverrides.map { $0.locationId })
        let availableLocationIds = Set(viewModel.availableLocations.map { $0.id })
        return usedLocationIds.count < availableLocationIds.count
    }
    
    // Add a new price override for the first available location
    private func addPriceOverride() {
        let usedLocationIds = Set(variation.locationOverrides.map { $0.locationId })
        
        if let firstAvailableLocation = viewModel.availableLocations.first(where: { !usedLocationIds.contains($0.id) }) {
            let newOverride = LocationOverrideData(
                locationId: firstAvailableLocation.id,
                priceMoney: MoneyData(dollars: 0.0),
                trackInventory: false
            )
            
            variation.locationOverrides.append(newOverride)
            viewModel.hasChanges = true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with variation name, delete button, and print button
            HStack {
                // Group label and trash icon together on the left
                HStack(spacing: 8) {
                    ItemDetailsFieldLabel(title: "Variation \(index + 1)")
                    
                    // Trash icon for variations 2+ (immediately adjacent to variation number)
                    if index > 0 { // Don't allow deleting the first variation
                        Button(action: {
                            // Check if variation has data before showing confirmation
                            if variationHasData {
                                let config = ConfirmationDialogConfig(
                                    title: "Delete Variation",
                                    message: "Are you sure you want to delete this variation? This action cannot be undone.",
                                    confirmButtonText: "Delete",
                                    cancelButtonText: "Cancel",
                                    isDestructive: true,
                                    onConfirm: {
                                        onDelete()
                                    }
                                )
                                dialogService.show(config)
                            } else {
                                onDelete()
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.itemDetailsDestructive)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Spacer()
                
                // Print button alone on the right
                Button(action: {
                    if !isPrinting {
                        onPrint(variation)
                    }
                }) {
                    if isPrinting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "printer.fill")
                            .foregroundColor(.itemDetailsAccent)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isPrinting)
            }
            .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
            .padding(.vertical, ItemDetailsSpacing.compactSpacing)
            .background(Color.itemDetailsSectionBackground)
            
            VStack(spacing: 0) {
                // Variation name - using centralized component for touch targets
                ItemDetailsFieldRow {
                    ItemDetailsTextField(
                        title: "Variation Name",
                        placeholder: "e.g., Small, Medium, Large",
                        text: Binding(
                            get: { variation.name ?? "" },
                            set: { variation.name = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
                
                Rectangle()
                    .fill(Color.itemDetailsSeparator)
                    .frame(height: 0.5)
                
                // UPC and SKU row - using centralized components
                ItemDetailsFieldRow {
                    HStack(spacing: 12) {
                        ItemDetailsTextField(
                            title: "UPC",
                            placeholder: "Barcode number",
                            text: Binding(
                                get: { variation.upc ?? "" },
                                set: {
                                    variation.upc = $0.isEmpty ? nil : $0
                                    duplicateDetection.checkForDuplicates(
                                        sku: variation.sku ?? "",
                                        upc: $0,
                                        excludeItemId: viewModel.itemData.id
                                    )
                                }
                            ),
                            keyboardType: .numbersAndPunctuation
                        )

                        ItemDetailsTextField(
                            title: "SKU",
                            placeholder: "Internal SKU",
                            text: Binding(
                                get: { variation.sku ?? "" },
                                set: {
                                    variation.sku = $0.isEmpty ? nil : $0
                                    duplicateDetection.checkForDuplicates(
                                        sku: $0,
                                        upc: variation.upc ?? "",
                                        excludeItemId: viewModel.itemData.id
                                    )
                                }
                            )
                        )
                    }
                }

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
                    .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                    .background(Color.itemDetailsSectionBackground)
                }
                
                Rectangle()
                    .fill(Color.itemDetailsSeparator)
                    .frame(height: 0.5)
                
                // Price and pricing type - reduced spacing
                HStack(spacing: 12) {
                    PriceFieldWithTouchTarget(
                        variation: $variation
                    )
                    
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
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                .padding(.vertical, ItemDetailsSpacing.minimalSpacing)
                .background(Color.itemDetailsSectionBackground)
                
                // Price overrides section - following CLAUDE.md centralized pattern
                if variation.pricingType != .variablePricing {
                    // Existing price overrides
                    ForEach(Array(variation.locationOverrides.enumerated()), id: \.element.id) { overrideIndex, override in
                        ItemDetailsFieldSeparator()
                        
                        PriceOverrideRow(
                            override: Binding(
                                get: { variation.locationOverrides[overrideIndex] },
                                set: { variation.locationOverrides[overrideIndex] = $0 }
                            ),
                            availableLocations: viewModel.availableLocations,
                            onDelete: {
                                variation.locationOverrides.remove(at: overrideIndex)
                                viewModel.hasChanges = true
                            }
                        )
                    }
                    
                    // Add Price Override button - AFTER existing overrides
                    if canAddPriceOverride {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            ItemDetailsButton(
                                title: "Add Price Override",
                                icon: "plus.circle",
                                style: .secondary
                            ) {
                                addPriceOverride()
                            }
                        }
                    }
                }
            }
        }
        .background(Color.itemDetailsSectionBackground)
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
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
                        .keyboardType(.numbersAndPunctuation)
                        .font(.itemDetailsBody)
                        .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
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

// MARK: - Price Override Row
/// Individual row for location-specific price overrides
struct PriceOverrideRow: View {
    @Binding var override: LocationOverrideData
    let availableLocations: [LocationData]
    let onDelete: () -> Void
    
    @StateObject private var dialogService = ConfirmationDialogService.shared
    @State private var priceInCents: Int = 0
    @State private var digitString: String = "0.00"
    
    private var locationName: String {
        availableLocations.first { $0.id == override.locationId }?.name ?? "Unknown Location"
    }
    
    var body: some View {
        // Two-column layout: Price on left, Location on right - following CLAUDE.md pattern
        ItemDetailsFieldRow {
            HStack(spacing: 12) {
                // LEFT COLUMN: Price field
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    ItemDetailsFieldLabel(title: "Override Price")
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.itemDetailsSecondaryText)
                        
                        TextField("0.00", text: $digitString)
                            .onChange(of: digitString) { oldValue, newValue in
                                // Only keep digits
                                let digitsOnly = newValue.filter { $0.isNumber }
                                
                                // Limit to 7 digits max
                                let limited = String(digitsOnly.prefix(7))
                                
                                // Update the stored digits
                                digitString = limited
                                
                                // Convert to cents
                                if let cents = Int(limited) {
                                    priceInCents = cents
                                    
                                    // Format back to display with decimal
                                    let dollars = cents / 100
                                    let remainingCents = cents % 100
                                    digitString = String(format: "%d.%02d", dollars, remainingCents)
                                    
                                    // Update the binding
                                    override.priceMoney = cents > 0 ? MoneyData(amount: cents) : nil
                                } else if limited.isEmpty {
                                    priceInCents = 0
                                    digitString = "0.00"
                                    override.priceMoney = nil
                                }
                            }
                        .keyboardType(.numberPad)
                        .font(.itemDetailsBody)
                        .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }
                
                // RIGHT COLUMN: Location dropdown + Delete button
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    HStack {
                        ItemDetailsFieldLabel(title: "Location")
                        
                        Spacer()
                        
                        // Delete button
                        Button(action: {
                            let config = ConfirmationDialogConfig(
                                title: "Delete Price Override",
                                message: "Are you sure you want to delete this price override for \(locationName)?",
                                confirmButtonText: "Delete",
                                cancelButtonText: "Cancel",
                                isDestructive: true,
                                onConfirm: {
                                    onDelete()
                                }
                            )
                            dialogService.show(config)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.itemDetailsDestructive)
                                .font(.itemDetailsSubheadline)
                        }
                    }
                    
                    // Location dropdown
                    Menu {
                        ForEach(availableLocations, id: \.id) { location in
                            Button(location.name) {
                                override.locationId = location.id
                                override.locationName = location.name
                            }
                        }
                    } label: {
                        HStack {
                            Text(locationName)
                                .font(.itemDetailsBody)
                                .foregroundColor(.itemDetailsPrimaryText)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsSecondaryText)
                        }
                        .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                    }
                }
            }
        }
        .onAppear {
            // Initialize from existing price
            priceInCents = override.priceMoney?.amount ?? 0
            let dollars = priceInCents / 100
            let cents = priceInCents % 100
            digitString = String(format: "%d.%02d", dollars, cents)
        }
        .onChange(of: override.priceMoney) { _, newValue in
            // Update display when external changes occur
            if let newAmount = newValue?.amount, newAmount != priceInCents {
                priceInCents = newAmount
                let dollars = priceInCents / 100
                let cents = priceInCents % 100
                digitString = String(format: "%d.%02d", dollars, cents)
            }
        }
    }
}

// MARK: - Price Field With Touch Target
/// Price field with expanded touch target and calculator-style input
struct PriceFieldWithTouchTarget: View {
    @Binding var variation: ItemDetailsVariationData
    @FocusState private var isFocused: Bool
    @State private var priceInCents: Int = 0
    
    // Format cents to display string
    private var displayPrice: String {
        let dollars = priceInCents / 100
        let cents = priceInCents % 100
        return String(format: "%d.%02d", dollars, cents)
    }
    
    // Store raw digit string for proper calculator-style input
    @State private var digitString: String = ""
    
    var body: some View {
        Button(action: {
            if variation.pricingType != .variablePricing {
                isFocused = true
            }
        }) {
            VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                ItemDetailsFieldLabel(title: "Price")
                
                HStack {
                    Text("$")
                        .foregroundColor(.itemDetailsSecondaryText)
                    
                    if variation.pricingType == .variablePricing {
                        Text("Variable")
                            .foregroundColor(.itemDetailsSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.itemDetailsFieldBackground)
                            .cornerRadius(6)
                    } else {
                        TextField("0.00", text: $digitString)
                            .onChange(of: digitString) { oldValue, newValue in
                                // Only keep digits
                                let digitsOnly = newValue.filter { $0.isNumber }
                                
                                // Limit to 7 digits max
                                let limited = String(digitsOnly.prefix(7))
                                
                                // Update the stored digits
                                digitString = limited
                                
                                // Convert to cents
                                if let cents = Int(limited) {
                                    priceInCents = cents
                                    
                                    // Format back to display with decimal
                                    let dollars = cents / 100
                                    let remainingCents = cents % 100
                                    digitString = String(format: "%d.%02d", dollars, remainingCents)
                                } else if limited.isEmpty {
                                    priceInCents = 0
                                    digitString = "0.00"
                                }
                            }
                        .keyboardType(.numberPad)
                        .font(.itemDetailsBody)
                        .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onChange(of: priceInCents) { _, newValue in
                            // Update the variation's price immediately
                            variation.priceMoney = newValue > 0 ? MoneyData(amount: newValue) : nil
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(variation.pricingType == .variablePricing)
        .onAppear {
            // Initialize from existing price
            priceInCents = variation.priceMoney?.amount ?? 0
            let dollars = priceInCents / 100
            let cents = priceInCents % 100
            digitString = String(format: "%d.%02d", dollars, cents)
        }
        .onChange(of: variation.priceMoney) { _, newValue in
            // Update display when external changes occur
            if let newAmount = newValue?.amount, newAmount != priceInCents {
                priceInCents = newAmount
                let dollars = priceInCents / 100
                let cents = priceInCents % 100
                digitString = String(format: "%d.%02d", dollars, cents)
            }
        }
    }
}

#Preview("Pricing Section") {
    ScrollView {
        ItemDetailsPricingSection(
            viewModel: ItemDetailsViewModel(),
            onVariationPrint: { variation, completion in
                print("Print variation: \(variation.name ?? "Unnamed")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    completion(true)
                }
            }
        )
        .padding()
    }
}
