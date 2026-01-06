import SwiftUI
import SwiftData
import Kingfisher

// MARK: - Supporting Types

/// Parameters for presenting inventory adjustment modal
private struct InventoryModalParams: Identifiable {
    let id = UUID()
    let variationId: String
    let locationId: String
}

// MARK: - Variation Card Header
struct VariationCardHeader: View {
    let index: Int
    let variation: ItemDetailsVariationData
    let onDelete: () -> Void
    let onPrint: (ItemDetailsVariationData) -> Void
    let isPrinting: Bool
    @State private var showDeleteAlert = false
    
    // Check if variation has meaningful data
    private var variationHasData: Bool {
        return !(variation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !(variation.upc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               (variation.priceMoney?.amount ?? 0) > 0
    }
    
    var body: some View {
        HStack {
            // Group label and trash icon together on the left
            HStack(spacing: 8) {
                ItemDetailsFieldLabel(title: "Variation \(index + 1)")
                
                // Trash icon for variations 2+ (immediately adjacent to variation number)
                if index > 0 { // Don't allow deleting the first variation
                    Button(action: {
                        // Check if variation has data before showing confirmation
                        if variationHasData {
                            showDeleteAlert = true
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
                    .alert("Delete Variation", isPresented: $showDeleteAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } message: {
                        Text("Are you sure you want to delete this variation? This action cannot be undone.")
                    }
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
    }
}

// MARK: - Variation Fields with Duplicate Detection
struct VariationCardFields: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    let viewModel: ItemDetailsViewModel
    let modelContext: ModelContext
    @State private var duplicateDetection: DuplicateDetectionService?

    var body: some View {
        VStack(spacing: 0) {
            // Variation name - using centralized component for touch targets
            ItemDetailsFieldRow {
                ItemDetailsTextField(
                    title: "Variation Name",
                    placeholder: "e.g., Small, Medium, Large",
                    text: Binding(
                        get: { variation.name ?? "" },
                        set: { variation.name = $0.isEmpty ? nil : $0 }
                    ),
                    focusedField: $focusedField,
                    fieldIdentifier: .variationName(index),
                    onSubmit: moveToNextField
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
                                duplicateDetection?.checkForDuplicates(
                                    sku: variation.sku ?? "",
                                    upc: $0,
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        ),
                        keyboardType: .numbersAndPunctuation,
                        focusedField: $focusedField,
                        fieldIdentifier: .variationUPC(index),
                        onSubmit: moveToNextField
                    )

                    ItemDetailsTextField(
                        title: "SKU",
                        placeholder: "Internal SKU",
                        text: Binding(
                            get: { variation.sku ?? "" },
                            set: {
                                variation.sku = $0.isEmpty ? nil : $0
                                duplicateDetection?.checkForDuplicates(
                                    sku: $0,
                                    upc: variation.upc ?? "",
                                    excludeItemId: viewModel.itemData.id
                                )
                            }
                        ),
                        focusedField: $focusedField,
                        fieldIdentifier: .variationSKU(index),
                        onSubmit: moveToNextField
                    )
                }
            }

            // Duplicate detection - only show when needed
            if !(duplicateDetection?.duplicateWarnings ?? []).isEmpty || 
               (variation.upc != nil && !variation.upc!.isEmpty && duplicateDetection?.validateUPC(variation.upc!).isValid == false) {
                Rectangle()
                    .fill(Color.itemDetailsSeparator)
                    .frame(height: 0.5)
                
                if let duplicateDetection = duplicateDetection {
                    DuplicateDetectionSection(
                        variation: variation,
                        duplicateDetection: duplicateDetection
                    )
                    .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                    .background(Color.itemDetailsSectionBackground)
                }
            }
        }
        .onAppear {
            if duplicateDetection == nil {
                duplicateDetection = DuplicateDetectionService(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Price Section
struct VariationCardPriceSection: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    let viewModel: ItemDetailsViewModel
    @StateObject private var capabilitiesService = SquareCapabilitiesService.shared

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
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.itemDetailsSeparator)
                .frame(height: 0.5)
            
            // Price and pricing type - reduced spacing
            HStack(spacing: 12) {
                PriceFieldWithTouchTarget(
                    variation: $variation,
                    index: index,
                    focusedField: $focusedField,
                    moveToNextField: moveToNextField
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

            // INVENTORY SECTION - After price overrides
            VariationInventorySection(
                variation: $variation,
                variationIndex: index,
                focusedField: $focusedField,
                moveToNextField: moveToNextField,
                viewModel: viewModel,
                capabilitiesService: capabilitiesService
            )
        }
    }
}

// MARK: - Variation Inventory Section
/// Displays inventory for a specific variation across all locations
/// Positioned below "Add Price Override" button as per requirements
struct VariationInventorySection: View {
    @Binding var variation: ItemDetailsVariationData
    let variationIndex: Int
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    @ObservedObject var viewModel: ItemDetailsViewModel
    @ObservedObject var capabilitiesService: SquareCapabilitiesService
    @State private var inventoryParams: InventoryModalParams?

    private var variationId: String? {
        variation.id
    }

    private var isNewItem: Bool {
        variationId == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with lock icon if premium not enabled
            ItemDetailsFieldSeparator()

            HStack {
                ItemDetailsFieldLabel(title: "Inventory")

                if !capabilitiesService.inventoryTrackingEnabled {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.itemDetailsWarning)
                        .font(.itemDetailsCaption)
                }

                Spacer()
            }
            .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
            .padding(.vertical, ItemDetailsSpacing.compactSpacing)

            // New item: Show editable inventory input fields for each location
            if isNewItem {
                ForEach(Array(viewModel.availableLocations.enumerated()), id: \.element.id) { locationIndex, location in
                    ItemDetailsFieldSeparator()

                    NewItemInventoryRow(
                        variation: $variation,
                        variationIndex: variationIndex,
                        locationIndex: locationIndex,
                        locationId: location.id,
                        locationName: location.name,
                        focusedField: $focusedField,
                        moveToNextField: moveToNextField
                    )
                }
            }
            // Inventory error message (scopes or premium)
            else if !capabilitiesService.inventoryTrackingEnabled {
                ItemDetailsFieldSeparator()

                VStack(spacing: ItemDetailsSpacing.minimalSpacing) {
                    HStack {
                        Image(systemName: capabilitiesService.inventoryError?.contains("reconnect") == true ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundColor(.itemDetailsWarning)
                            .font(.itemDetailsFootnote)
                        Text(capabilitiesService.inventoryError ?? "Inventory tracking requires Square for Retail Plus")
                            .font(.itemDetailsFootnote)
                            .foregroundColor(.itemDetailsSecondaryText)
                        Spacer()
                    }

                    // Show "Go to Profile" button for authentication errors
                    if capabilitiesService.inventoryError?.contains("reconnect") == true {
                        ItemDetailsButton(
                            title: "Go to Profile to Reconnect",
                            icon: "arrow.right.circle",
                            style: .secondary
                        ) {
                            // Navigate to profile tab
                            NotificationCenter.default.post(name: NSNotification.Name("navigateToProfile"), object: nil)
                        }
                    }
                }
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
            } else if let variationId = variationId {
                // Show inventory for each location (only if variation has ID)
                ForEach(viewModel.availableLocations, id: \.id) { location in
                    ItemDetailsFieldSeparator()

                    VariationInventoryRow(
                        variation: $variation,
                        variationIndex: variationIndex,
                        variationId: variationId,
                        locationId: location.id,
                        locationName: location.name,
                        viewModel: viewModel,
                        onTap: {
                            inventoryParams = InventoryModalParams(
                                variationId: variationId,
                                locationId: location.id
                            )
                        }
                    )
                }
            }
        }
        .sheet(item: $inventoryParams) { params in
            InventoryAdjustmentModal(
                viewModel: viewModel,
                variationId: params.variationId,
                locationId: params.locationId,
                onDismiss: {
                    inventoryParams = nil
                }
            )
            .quantityModal()
        }
    }
}

// MARK: - New Item Inventory Row
/// Editable inventory input field for new items (no variation ID yet)
private struct NewItemInventoryRow: View {
    @Binding var variation: ItemDetailsVariationData
    let variationIndex: Int
    let locationIndex: Int
    let locationId: String
    let locationName: String
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void

    private var currentQty: String {
        if let qty = variation.pendingInventoryQty[locationId] {
            return String(qty)
        }
        return ""
    }

    var body: some View {
        HStack(spacing: ItemDetailsSpacing.compactSpacing) {
            // Location name (if multiple locations)
            if locationName != "Default Location" {
                Text(locationName)
                    .font(.itemDetailsBody)
                    .foregroundColor(.itemDetailsSecondaryText)
                    .frame(minWidth: 80, alignment: .leading)
            }

            Spacer()

            // Editable quantity field
            Text("Initial Stock")
                .font(.itemDetailsCaption)
                .foregroundColor(.itemDetailsSecondaryText)

            TextField("0", text: Binding(
                get: { currentQty },
                set: { newValue in
                    if newValue.isEmpty {
                        variation.pendingInventoryQty[locationId] = nil
                    } else if let qty = Int(newValue), qty >= 0 {
                        variation.pendingInventoryQty[locationId] = qty
                        // Auto-switch to stock count mode when quantity is entered
                        if qty > 0 && variation.inventoryTrackingMode == .unavailable {
                            variation.inventoryTrackingMode = .stockCount
                        }
                    }
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 80)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .focused($focusedField, equals: .initialInventory(variationIndex: variationIndex, locationIndex: locationIndex))
            .onSubmit(moveToNextField)
        }
        .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
        .id(ItemField.initialInventory(variationIndex: variationIndex, locationIndex: locationIndex))
    }
}

// MARK: - Variation Inventory Row
/// Single row showing stock on hand, committed, and available to sell for one location
/// Uses @Query for automatic SwiftData reactivity - UI updates automatically when inventory changes
/// Now supports per-location tracking modes
private struct VariationInventoryRow: View {
    @Binding var variation: ItemDetailsVariationData
    let variationIndex: Int
    let variationId: String // Note: Already unwrapped in parent, guaranteed non-nil
    let locationId: String
    let locationName: String
    @ObservedObject var viewModel: ItemDetailsViewModel
    let onTap: () -> Void

    // SwiftData query for automatic reactivity - UI updates when database changes!
    @Query private var inventoryCounts: [InventoryCountModel]

    init(variation: Binding<ItemDetailsVariationData>, variationIndex: Int, variationId: String, locationId: String, locationName: String, viewModel: ItemDetailsViewModel, onTap: @escaping () -> Void) {
        self._variation = variation
        self.variationIndex = variationIndex
        self.variationId = variationId
        self.locationId = locationId
        self.locationName = locationName
        self.viewModel = viewModel
        self.onTap = onTap

        // Query for IN_STOCK count for this variation + location
        let compositeId = "\(variationId)_\(locationId)_IN_STOCK"
        let predicate = #Predicate<InventoryCountModel> { model in
            model.id == compositeId
        }
        _inventoryCounts = Query(filter: predicate)
    }

    private var inventoryCount: InventoryCountModel? {
        inventoryCounts.first
    }

    private var stockOnHand: Int? {
        inventoryCount?.quantityInt
    }

    // Direct binding to tracking mode in location overrides array
    private var trackingMode: Binding<InventoryTrackingMode> {
        Binding(
            get: {
                // Find existing per-location override
                if let override = variation.locationOverrides.first(where: { $0.locationId == locationId }) {
                    return override.trackingMode
                }

                // No per-location override - derive from variation-level flags
                if !variation.trackInventory {
                    return .unavailable
                }
                return variation.stockable ? .stockCount : .availability
            },
            set: { newMode in
                // Find index of existing override
                if let index = variation.locationOverrides.firstIndex(where: { $0.locationId == locationId }) {
                    // Update existing override
                    variation.locationOverrides[index].trackingMode = newMode
                } else {
                    // Create new override
                    var newOverride = LocationOverrideData(locationId: locationId, trackingMode: newMode)
                    variation.locationOverrides.append(newOverride)
                }
            }
        )
    }

    // Binding to soldOut status in location overrides array
    private var soldOutBinding: Binding<Bool> {
        Binding(
            get: {
                variation.locationOverrides.first(where: { $0.locationId == locationId })?.soldOut ?? false
            },
            set: { newValue in
                var updatedVariation = variation.wrappedValue
                if let index = updatedVariation.locationOverrides.firstIndex(where: { $0.locationId == locationId }) {
                    updatedVariation.locationOverrides[index].soldOut = newValue
                } else {
                    var newOverride = LocationOverrideData(locationId: locationId, trackingMode: .availability, soldOut: newValue)
                    updatedVariation.locationOverrides.append(newOverride)
                }
                variation.wrappedValue = updatedVariation
            }
        )
    }

    // Responsive column widths
    private var numericColumnWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 90 : 50
    }

    private var buttonColumnWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 70 : 50
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tracking mode picker
            ItemDetailsFieldRow {
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    HStack {
                        Text(locationName)
                            .font(.itemDetailsBody)
                            .fontWeight(.medium)
                            .foregroundColor(.itemDetailsPrimaryText)

                        Spacer()
                    }

                    Picker("Tracking Mode", selection: trackingMode) {
                        ForEach(InventoryTrackingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Conditional UI based on tracking mode
            ItemDetailsFieldSeparator()

            ItemDetailsFieldRow {
                switch trackingMode.wrappedValue {
                case .unavailable:
                    // Show grayed out UI
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        Text("Inventory tracking is disabled for this location")
                            .font(.itemDetailsCaption)
                            .foregroundColor(.itemDetailsSecondaryText)

                        if let stock = stockOnHand {
                            Text("Stock on Hand: \(stock) (preserved)")
                                .font(.itemDetailsBody)
                                .foregroundColor(.itemDetailsSecondaryText)
                        }
                    }

                case .availability:
                    // Show Available/Sold Out picker (consistent with app UX - saves when user clicks main Save button)
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                        Text("Availability Status")
                            .font(.itemDetailsCaption)
                            .foregroundColor(.itemDetailsSecondaryText)

                        Picker("Status", selection: soldOutBinding) {
                            Text("Available").tag(false)
                            Text("Sold Out").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                case .stockCount:
                    // Show stock count UI (original implementation)
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        // Column headers
                        HStack(spacing: 8) {
                            Text("Stock on hand")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsSecondaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            Text("Committed")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsSecondaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            Text("Available")
                                .font(.itemDetailsCaption)
                                .foregroundColor(.itemDetailsSecondaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            Spacer()
                                .frame(width: buttonColumnWidth)
                        }

                        // Values and button
                        HStack(spacing: 8) {
                            // Stock on hand
                            Text(stockOnHand != nil ? "\(stockOnHand!)" : "N/A")
                                .font(.itemDetailsBody)
                                .foregroundColor(stockOnHand == nil ? .itemDetailsSecondaryText : .itemDetailsPrimaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            // Committed (always 0 for now)
                            Text("0")
                                .font(.itemDetailsBody)
                                .foregroundColor(.itemDetailsPrimaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            // Available to sell
                            Text(stockOnHand != nil ? "\(stockOnHand!)" : "N/A")
                                .font(.itemDetailsBody)
                                .foregroundColor(stockOnHand == nil ? .itemDetailsSecondaryText : .itemDetailsPrimaryText)
                                .frame(width: numericColumnWidth, alignment: .center)

                            // Adjust button
                            Button(action: onTap) {
                                Text("Adjust")
                                    .font(.itemDetailsBody)
                                    .foregroundColor(.blue)
                            }
                            .frame(width: buttonColumnWidth)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Missing Components from Original VariationCard

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

// MARK: - Price Field With Touch Target
/// Price field with expanded touch target and calculator-style input
struct PriceFieldWithTouchTarget: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
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
                focusedField = .variationPrice(index)
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
                        .focused($focusedField, equals: .variationPrice(index))
                        .onSubmit(moveToNextField)
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
        .id(ItemField.variationPrice(index))
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

// MARK: - Price Override Row
/// Individual row for location-specific price overrides
struct PriceOverrideRow: View {
    @Binding var override: LocationOverrideData
    let availableLocations: [LocationData]
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
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
                            showDeleteConfirmation = true
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
        .alert("Delete Price Override", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this price override for \(locationName)?")
        }
    }
}

// MARK: - Variation Image Gallery
/// Image thumbnail gallery specifically for variation-level images
/// Smaller thumbnails (60px) to differentiate from item-level gallery
struct VariationImageGallery: View {
    @Binding var variation: ItemDetailsVariationData
    let onReorder: ([String]) -> Void
    let onDelete: (String) -> Void
    let onUpload: () -> Void
    let viewModel: ItemDetailsViewModel

    @State private var selectedImageId: String?
    @State private var showingPreview = false

    // Drag and drop state tracking
    @State private var draggedImageId: String?
    @State private var dropTargetId: String?
    @State private var dropSide: DropSide? = nil

    private let thumbnailSize: CGFloat = 60  // Smaller than item-level (80px)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Variation Images")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onUpload) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Image")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)

            if variation.imageIds.isEmpty {
                // Empty state (simple message)
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)

                    Text("No variation images")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 12)
            } else {
                // Thumbnail grid with drag-to-reorder
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(variation.imageIds.enumerated()), id: \.element) { index, imageId in
                            // Gap BEFORE this thumbnail (shows when hovering LEFT half of THIS image)
                            VariationDropGapView(
                                showLine: dropTargetId == imageId && dropSide == .before && draggedImageId != imageId,
                                height: thumbnailSize,
                                isHalfWidth: index == 0  // First image uses half-width gap
                            )

                            VariationThumbnailView(
                                imageId: imageId,
                                isPrimary: index == 0,
                                size: thumbnailSize,
                                isDragging: draggedImageId == imageId,
                                viewModel: viewModel,
                                onTap: {
                                    selectedImageId = imageId
                                    showingPreview = true
                                }
                            )
                            .opacity(draggedImageId == imageId ? 0.5 : 1.0)
                            .onDrag {
                                draggedImageId = imageId
                                return NSItemProvider(object: imageId as NSString)
                            }
                            .onDrop(of: [.text], delegate: DropViewDelegate(
                                draggedItem: $draggedImageId,
                                dropTargetItem: $dropTargetId,
                                dropSide: $dropSide,
                                items: Binding(
                                    get: { variation.imageIds },
                                    set: { variation.imageIds = $0 }
                                ),
                                currentItem: imageId,
                                thumbnailSize: thumbnailSize,
                                onReorder: onReorder
                            ))

                            // Gap AFTER this thumbnail (shows when hovering RIGHT half of THIS image)
                            VariationDropGapView(
                                showLine: dropTargetId == imageId && dropSide == .after && draggedImageId != imageId,
                                height: thumbnailSize
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .onChange(of: draggedImageId) { oldValue, newValue in
                        // Clear state when drag ends
                        if newValue == nil && oldValue != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                dropTargetId = nil
                                dropSide = nil
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingPreview) {
            if let imageId = selectedImageId {
                ImagePreviewModal(
                    imageId: imageId,
                    isPrimary: variation.imageIds.first == imageId,
                    onDelete: {
                        onDelete(imageId)
                        showingPreview = false
                    },
                    onDismiss: {
                        showingPreview = false
                    }
                )
            }
        }
    }
}

// MARK: - Variation Thumbnail View
private struct VariationThumbnailView: View {
    let imageId: String
    let isPrimary: Bool
    let size: CGFloat
    let isDragging: Bool
    let viewModel: ItemDetailsViewModel
    let onTap: () -> Void

    @Query private var images: [ImageModel]

    init(imageId: String, isPrimary: Bool, size: CGFloat, isDragging: Bool, viewModel: ItemDetailsViewModel, onTap: @escaping () -> Void) {
        self.imageId = imageId
        self.isPrimary = isPrimary
        self.size = size
        self.isDragging = isDragging
        self.viewModel = viewModel
        self.onTap = onTap

        // Query for this specific image using native SwiftData
        let predicate = #Predicate<ImageModel> { model in
            model.id == imageId
        }
        _images = Query(filter: predicate)
    }

    private var imageURL: String? {
        images.first?.url
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Image with Kingfisher caching
                if let url = imageURL, !url.isEmpty, let validURL = URL(string: url) {
                    KFImage(validURL)
                        .placeholder {
                            ProgressView()
                                .frame(width: size, height: size)
                        }
                        .onFailure { error in
                            // Silently handle image load failures
                        }
                        .resizable()
                        .aspectRatio(contentMode: SwiftUI.ContentMode.fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                        .background(Color(.systemGray5))
                }

                // Primary badge (smaller for variation thumbnails, hidden during drag)
                if isPrimary && !isDragging {
                    Text("PRIMARY")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue)
                        .cornerRadius(3)
                        .padding(3)
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isPrimary ? Color.blue : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
// MARK: - Drop Gap View (for Variations)
/// Renders a gap with optional centered blue drop indicator line
private struct VariationDropGapView: View {
    let showLine: Bool
    let height: CGFloat
    var isHalfWidth: Bool = false  // Half-width for start gap (5px vs 10px)

    var body: some View {
        HStack(spacing: 0) {
            if !isHalfWidth {
                Spacer().frame(width: 3.5)  // Left padding (only for full-width gaps)
            }
            if showLine {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3, height: height)
                    .transition(.opacity)
            } else {
                Spacer().frame(width: 3)
            }
            Spacer().frame(width: 3.5)  // Right padding (always present)
        }
    }
}
