import SwiftUI
import os.log

// MARK: - Item Details Context
/// Defines how the item details modal was accessed and what data to pre-fill
enum ItemDetailsContext: Equatable {
    case editExisting(itemId: String)
    case createNew
    case createFromSearch(query: String, queryType: SearchQueryType)
    
    var isCreating: Bool {
        switch self {
        case .editExisting:
            return false
        case .createNew, .createFromSearch:
            return true
        }
    }
    
    var title: String {
        switch self {
        case .editExisting:
            return "Edit Item"
        case .createNew:
            return "Create New Item"
        case .createFromSearch:
            return "Create New Item"
        }
    }
}

// MARK: - Search Query Type
/// Specifies what type of search query was used to trigger item creation
enum SearchQueryType: String, CaseIterable {
    case upc = "UPC"
    case sku = "SKU"
    case name = "Name"

    var displayName: String {
        return self.rawValue
    }
}

// MARK: - Focus Field Enum
/// Defines all focusable text fields in the item details modal
enum ItemField: Hashable {
    case itemName
    case description
    case abbreviation
    case variationName(Int)
    case variationUPC(Int)
    case variationSKU(Int)
    case variationPrice(Int)
    case priceOverride(variationIndex: Int, overrideIndex: Int)
    case initialInventory(variationIndex: Int, locationIndex: Int)
}

// MARK: - Item Details Modal
/// Main modal coordinator that handles all entry points for item details
struct ItemDetailsModal: View {
    let context: ItemDetailsContext
    let onDismiss: () -> Void
    let onSave: (ItemDetailsData) -> Void

    @FocusState private var focusedField: ItemField?

    @StateObject private var viewModel = ItemDetailsViewModel()
    
    // Price selection data for FAB buttons
    @State private var availablePrices: [(variationIndex: Int, variationName: String, price: String)] = []
    @State private var needsSaveAfterPrint = false
    
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemDetailsModal")

    // Dynamic title showing item name or fallback
    private var dynamicTitle: String {
        let itemName = viewModel.itemData.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if itemName.isEmpty {
            return context.title
        } else {
            return itemName
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Simplified header - title only
            HStack {
                Spacer()
                
                Text(dynamicTitle)
                    .font(.itemDetailsSectionTitle)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding()
            .background(Color.itemDetailsModalBackground)
            .overlay(
                Divider()
                    .frame(maxWidth: .infinity, maxHeight: 1)
                    .background(Color.itemDetailsSeparator),
                alignment: .bottom
            )
            
            // Content area
            ZStack {
                ItemDetailsContent(
                    context: context,
                    viewModel: viewModel,
                    focusedField: $focusedField,
                    onSave: handleSave,
                    onDismiss: onDismiss,
                    onVariationPrint: handleVariationPrint
                )

                // Floating Action Buttons (hidden during confirmation with animation)
                VStack {
                    Spacer()

                    FloatingActionButtons(
                        onCancel: handleCancel,
                        onPrint: handlePrint,
                        onSave: handleSave,
                        onSaveAndPrint: handleSaveAndPrint,
                        canSave: viewModel.canSave,
                        availablePrices: availablePrices,
                        onPriceSelected: handlePrintWithSelectedPrice,
                        hasChanges: viewModel.hasChanges,
                        onForceClose: { onDismiss() }
                    )
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .frame(maxHeight: .infinity)
        .interactiveDismissDisabled(viewModel.hasChanges)
        .presentationDragIndicator(.visible)
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .onDisappear {
            // Ensure keyboard is dismissed when modal disappears
            hideKeyboard()
        }
        .onAppear {
            print("[ItemDetailsModal] onAppear called for context: \(context)")
            setupForContext()
            
            // Register with centralized item update manager for automatic refresh
            if case .editExisting(let itemId) = context {
                CentralItemUpdateManager.shared.registerItemDetailsModal(itemId: itemId, viewModel: viewModel)
            }
        }
        .onDisappear {
            // Only reset when modal is actually being dismissed (not during presentation animation)
            // We'll let the parent handle modal lifecycle properly
            print("[ItemDetailsModal] onDisappear called")
            
            // Unregister from centralized item update manager
            if case .editExisting(let itemId) = context {
                CentralItemUpdateManager.shared.unregisterItemDetailsModal(itemId: itemId)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupForContext() {
        logger.info("Setting up modal for context: \(String(describing: context))")
        
        Task {
            await viewModel.setupForContext(context)
        }
    }
    
    private func handleSave() {
        logger.info("Save button tapped")
        
        Task {
            if let itemData = await viewModel.saveItem() {
                await MainActor.run {
                    onSave(itemData)
                    onDismiss()
                }
            }
        }
    }
    
    private func handleCancel() {
        print("Cancel button tapped")

        // Dismiss keyboard first to prevent layout conflicts
        focusedField = nil
        hideKeyboard()

        // This is called from FAB when hasChanges is false
        // If hasChanges is true, FAB handles the confirmation
        onDismiss()
    }


    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    
    // MARK: - Smart Print Logic
    
    /// Creates print data for generic item labels (main print buttons)
    /// Handles both saved and unsaved items gracefully
    /// Returns nil if price selection modal is needed
    private func createGenericPrintData() -> PrintData? {
        let variations = viewModel.itemData.variations
        
        if variations.count == 1 {
            // Single variation: include variation name if not nil/empty
            let variation = variations[0]
            let hasVariationName = variation.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            
            return PrintData(
                itemName: viewModel.itemData.name.isEmpty ? "New Item" : viewModel.itemData.name,
                variationName: hasVariationName ? variation.name : nil,
                price: formatPrice(variation.priceMoney),
                originalPrice: nil,
                upc: variation.upc,
                sku: variation.sku,
                categoryName: nil,
                categoryId: viewModel.itemData.reportingCategoryId,
                description: viewModel.itemData.description,
                createdAt: nil,
                updatedAt: nil,
                qtyForPrice: nil,
                qtyPrice: nil
            )
        } else {
            // Multiple variations: check if we can print generically
            let allPricesSet = variations.allSatisfy { formatPrice($0.priceMoney) != nil }
            let uniquePrices = getUniquePrices()
            
            if allPricesSet && uniquePrices.count > 1 {
                // All variations have prices and they differ - show price selection modal
                preparePriceSelectionModal()
                return nil // Return nil to indicate modal is needed
            } else {
                // Either not all prices are set, or all prices are the same
                // Use generic format with best available data
                let firstVariation = variations[0]
                let bestPrice = uniquePrices.first ?? formatPrice(firstVariation.priceMoney)
                
                return PrintData(
                    itemName: viewModel.itemData.name.isEmpty ? "New Item" : viewModel.itemData.name,
                    variationName: nil, // No variation name for generic multi-variation label
                    price: bestPrice,
                    originalPrice: nil,
                    upc: firstVariation.upc,
                    sku: firstVariation.sku,
                    categoryName: nil,
                    categoryId: viewModel.itemData.reportingCategoryId,
                    description: viewModel.itemData.description,
                    createdAt: nil,
                    updatedAt: nil,
                    qtyForPrice: nil,
                    qtyPrice: nil
                )
            }
        }
    }
    
    /// Creates fallback print data when price selection modal is triggered
    private func createFallbackPrintData() -> PrintData {
        let firstVariation = viewModel.itemData.variations[0]
        return PrintData(
            itemName: viewModel.itemData.name.isEmpty ? "New Item" : viewModel.itemData.name,
            variationName: nil,
            price: formatPrice(firstVariation.priceMoney),
            originalPrice: nil,
            upc: firstVariation.upc,
            sku: firstVariation.sku,
            categoryName: nil,
            categoryId: viewModel.itemData.reportingCategoryId,
            description: viewModel.itemData.description,
            createdAt: nil,
            updatedAt: nil,
            qtyForPrice: nil,
            qtyPrice: nil
        )
    }
    
    /// Creates print data for specific variation (variation print buttons)
    /// Handles both saved and unsaved variations gracefully
    private func createVariationPrintData(variation: ItemDetailsVariationData) -> PrintData {
        return PrintData(
            itemName: viewModel.itemData.name.isEmpty ? "New Item" : viewModel.itemData.name,
            variationName: variation.name?.isEmpty == false ? variation.name : nil,
            price: formatPrice(variation.priceMoney),
            originalPrice: nil,
            upc: variation.upc,
            sku: variation.sku,
            categoryName: nil,
            categoryId: viewModel.itemData.reportingCategoryId,
            description: viewModel.itemData.description,
            createdAt: nil,
            updatedAt: nil,
            qtyForPrice: nil,
            qtyPrice: nil
        )
    }
    
    /// Helper to format price from MoneyData
    private func formatPrice(_ priceMoney: MoneyData?) -> String? {
        guard let amount = priceMoney?.amount, amount > 0 else { return nil }
        return String(format: "%.2f", Double(amount) / 100.0)
    }
    
    /// Gets unique prices across all variations
    private func getUniquePrices() -> [String] {
        let prices = viewModel.itemData.variations.compactMap { formatPrice($0.priceMoney) }
        return Array(Set(prices)).sorted()
    }
    
    /// Prepares data for price selection modal
    private func preparePriceSelectionModal() {
        var priceOptions: [(variationIndex: Int, variationName: String, price: String)] = []
        
        print("[PriceModal] Preparing price selection for \(viewModel.itemData.variations.count) variations")
        
        for (index, variation) in viewModel.itemData.variations.enumerated() {
            let price = formatPrice(variation.priceMoney) ?? "0.00"
            let variationName = variation.name?.isEmpty == false ? variation.name! : "Unnamed"
            
            print("[PriceModal] Variation \(index + 1): name='\(variationName)', price='$\(price)'")
            
            priceOptions.append((variationIndex: index, variationName: variationName, price: price))
        }
        
        // Sort by variation index to maintain original order
        availablePrices = priceOptions.sorted { $0.variationIndex < $1.variationIndex }
        
        print("[PriceModal] Available prices: \(availablePrices.count) options")
    }
    
    /// Handles print for specific variation
    func handleVariationPrint(_ variation: ItemDetailsVariationData, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let printData = createVariationPrintData(variation: variation)
                try await LabelLivePrintService.shared.printLabel(with: printData)
                
                await MainActor.run {
                    ToastNotificationService.shared.showSuccess("Label printed successfully")
                    completion(true)
                }
            } catch LabelLivePrintError.printSuccess {
                await MainActor.run {
                    ToastNotificationService.shared.showSuccess("Label printed successfully")
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                    completion(false)
                }
            }
        }
    }
    
    /// Handles print with user-selected price from ActionSheet
    private func handlePrintWithSelectedPrice(_ selectedPrice: String) {
        let firstVariation = viewModel.itemData.variations[0]
        let printData = PrintData(
            itemName: viewModel.itemData.name,
            variationName: nil, // No variation name for generic multi-variation label
            price: selectedPrice,
            originalPrice: nil,
            upc: firstVariation.upc,
            sku: firstVariation.sku,
            categoryName: nil,
            categoryId: viewModel.itemData.reportingCategoryId,
            description: viewModel.itemData.description,
            createdAt: nil,
            updatedAt: nil,
            qtyForPrice: nil,
            qtyPrice: nil
        )
        
        // Check if this came from Save & Print button
        if needsSaveAfterPrint {
            Task {
                // Start both operations concurrently for snappy UX
                async let printTask: Void = performPrintInBackground(with: printData)
                
                // Save immediately (don't wait for print)
                if let itemData = await viewModel.saveItem() {
                    await MainActor.run {
                        onSave(itemData)
                        onDismiss() // Dismiss immediately after save
                    }
                }
                
                // Let print continue in background
                await printTask
                needsSaveAfterPrint = false
            }
        } else {
            // Just print (from Print button)
            performPrint(with: printData)
        }
    }
    
    /// Performs the actual print operation
    private func performPrint(with printData: PrintData) {
        Task {
            do {
                try await LabelLivePrintService.shared.printLabel(with: printData)
                
                await MainActor.run {
                    print("Print completed successfully")
                    ToastNotificationService.shared.showSuccess("Label printed successfully")
                }
            } catch LabelLivePrintError.printSuccess {
                await MainActor.run {
                    print("Print completed successfully")
                    ToastNotificationService.shared.showSuccess("Label printed successfully")
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                }
            }
        }
    }
    
    /// Performs print operation in background for concurrent Save & Print
    private func performPrintInBackground(with printData: PrintData) async {
        do {
            try await LabelLivePrintService.shared.printLabel(with: printData)
            
            await MainActor.run {
                print("Background print completed successfully")
                ToastNotificationService.shared.showSuccess("Label printed successfully")
            }
        } catch LabelLivePrintError.printSuccess {
            await MainActor.run {
                print("Background print completed successfully")
                ToastNotificationService.shared.showSuccess("Label printed successfully")
            }
        } catch {
            await MainActor.run {
                print("Background print failed: \(error)")
                // Don't show error to user since save succeeded and modal dismissed
            }
        }
    }

    private func handlePrint() -> Bool {
        print("Print button tapped")
        
        // Create print data - if price selection needed, data will be prepared for ActionSheet
        if let printData = createGenericPrintData() {
            // Direct print (single variation or same prices)
            performPrint(with: printData)
            return false // No ActionSheet needed
        } else {
            // Price selection needed - availablePrices is set
            return true // ActionSheet needed
        }
    }

    private func handleSaveAndPrint() {
        print("Save & Print button tapped")

        // Check if we need price selection first
        if let printData = createGenericPrintData() {
            // No price selection needed - run print and save concurrently
            Task {
                // Start both operations concurrently for snappy UX
                async let printTask: Void = performPrintInBackground(with: printData)
                
                // Save immediately (don't wait for print)
                if let itemData = await viewModel.saveItem() {
                    await MainActor.run {
                        onSave(itemData)
                        onDismiss() // Dismiss immediately after save
                    }
                }
                
                // Let print continue in background
                await printTask
            }
        } else {
            // Price selection needed - set flag and return true to show ActionSheet
            // The FloatingActionButtons will show the price selection ActionSheet
            needsSaveAfterPrint = true
            // availablePrices is already set by createGenericPrintData()
        }
}

// MARK: - Item Details Content
/// Main content view that displays the form fields
struct ItemDetailsContent: View {
    let context: ItemDetailsContext
    @ObservedObject var viewModel: ItemDetailsViewModel
    @FocusState.Binding var focusedField: ItemField?
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onVariationPrint: (ItemDetailsVariationData, @escaping (Bool) -> Void) -> Void
    @StateObject private var configManager = FieldConfigurationManager.shared
    @State private var hasInitialFocused = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    // Context-specific header message
                    if case .createFromSearch(let query, let queryType) = context {
                        CreateFromSearchHeader(query: query, queryType: queryType)
                    }

                    // Dynamic sections based on user configuration
                    ForEach(configManager.currentConfiguration.orderedSections.filter { $0.isEnabled }, id: \.id) { section in
                        sectionView(for: section.id)
                    }

                    // Delete Button Section (always last)
                    ItemDeleteSection(
                        viewModel: viewModel,
                        onDismiss: onDismiss
                    )

                    // Bottom spacing for floating buttons and keyboard
                    Spacer()
                        .frame(height: 120)
                }
                .padding()
            }
            .onChange(of: focusedField) { _, newValue in
                if let field = newValue {
                    // Skip scroll for initial itemName focus to keep image visible
                    if field == .itemName && !hasInitialFocused {
                        hasInitialFocused = true
                        return
                    }
                    hasInitialFocused = true

                    // Auto-scroll to focused field at 20% from top
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.2))
                    }
                }
            }
        }
    }
    
    // MARK: - Dynamic Section Rendering
    @ViewBuilder
    private func sectionView(for sectionId: String) -> some View {
        switch sectionId {
        case "image":
            ItemImageSection(viewModel: viewModel, focusedField: $focusedField)

        case "basicInfo":
            ItemDetailsBasicSection(viewModel: viewModel, focusedField: $focusedField, moveToNextField: moveToNextField)

        case "productType":
            ItemProductTypeSection(viewModel: viewModel)

        case "pricing":
            if shouldShowPricingSection {
                ItemDetailsPricingSection(viewModel: viewModel, focusedField: $focusedField, moveToNextField: moveToNextField, onVariationPrint: onVariationPrint)
            }

        case "inventory":
            // Inventory section now integrated into each variation card (below Add Price Override)
            // No standalone section needed
            EmptyView()

        case "categories":
            if shouldShowCategoriesSection {
                ItemDetailsCategoriesSection(viewModel: viewModel, focusedField: $focusedField)
            }
            
        case "taxes":
            ItemTaxSettingsSection(viewModel: viewModel)
            
        case "modifiers":
            ItemModifiersSection(viewModel: viewModel)
            
        case "skipModifier":
            ItemSkipModifierSection(viewModel: viewModel)

        case "salesChannels":
            if configManager.currentConfiguration.ecommerceFields.salesChannelsEnabled {
                ItemSalesChannelsSection(viewModel: viewModel)
            }

        case "fulfillment":
            if configManager.currentConfiguration.ecommerceFields.fulfillmentMethodsEnabled {
                ItemFulfillmentSection(viewModel: viewModel)
            }

        case "locations":
            if configManager.currentConfiguration.advancedFields.enabledLocationsEnabled {
                ItemEnabledLocationsSection(viewModel: viewModel)
            }
            
        case "customAttributes":
            if configManager.currentConfiguration.advancedFields.customAttributesEnabled {
                ItemCustomAttributesSection(viewModel: viewModel)
            }
            
        case "ecommerce":
            if shouldShowEcommerceSection {
                ItemEcommerceSection(viewModel: viewModel)
            }
            
        case "measurementUnit":
            if shouldShowMeasurementSection {
                ItemMeasurementSection(viewModel: viewModel)
            }
            
        default:
            EmptyView()
        }
    }

    // MARK: - Computed Properties
    private var shouldShowPricingSection: Bool {
        return configManager.currentConfiguration.pricingFields.variationsEnabled ||
               configManager.currentConfiguration.pricingFields.taxEnabled ||
               configManager.currentConfiguration.pricingFields.modifiersEnabled ||
               configManager.currentConfiguration.pricingFields.itemOptionsEnabled
    }

    private var shouldShowCategoriesSection: Bool {
        return configManager.currentConfiguration.classificationFields.categoryEnabled ||
               configManager.currentConfiguration.classificationFields.reportingCategoryEnabled ||
               configManager.currentConfiguration.pricingFields.taxEnabled ||
               configManager.currentConfiguration.pricingFields.modifiersEnabled
    }

    private var shouldShowEcommerceSection: Bool {
        return configManager.currentConfiguration.ecommerceFields.onlineVisibilityEnabled ||
               configManager.currentConfiguration.ecommerceFields.seoEnabled ||
               configManager.currentConfiguration.advancedFields.channelsEnabled
    }

    private var shouldShowMeasurementSection: Bool {
        return configManager.currentConfiguration.advancedFields.measurementUnitEnabled ||
               configManager.currentConfiguration.advancedFields.sellableEnabled ||
               configManager.currentConfiguration.advancedFields.stockableEnabled ||
               configManager.currentConfiguration.advancedFields.userDataEnabled
    }

    // MARK: - Field Navigation
    private func moveToNextField() {
        guard let current = focusedField else { return }

        switch current {
        case .itemName:
            // Move to description if enabled
            if configManager.isFieldEnabled(.basicDescription) {
                focusedField = .description
            } else if configManager.isFieldEnabled(.basicAbbreviation) {
                focusedField = .abbreviation
            } else {
                // Move to first variation
                focusedField = .variationName(0)
            }

        case .description:
            // Move to abbreviation if enabled
            if configManager.isFieldEnabled(.basicAbbreviation) {
                focusedField = .abbreviation
            } else {
                // Move to first variation
                focusedField = .variationName(0)
            }

        case .abbreviation:
            // Move to first variation
            focusedField = .variationName(0)

        case .variationName(let index):
            focusedField = .variationUPC(index)

        case .variationUPC(let index):
            focusedField = .variationSKU(index)

        case .variationSKU(let index):
            focusedField = .variationPrice(index)

        case .variationPrice(let index):
            // Check if there are price overrides for this variation
            if index < viewModel.variations.count {
                let variation = viewModel.variations[index]
                if !variation.locationOverrides.isEmpty && variation.pricingType != .variablePricing {
                    // Move to first price override
                    focusedField = .priceOverride(variationIndex: index, overrideIndex: 0)
                    return
                }
            }

            // Check if this variation is new (no ID) and needs initial inventory fields
            if index < viewModel.variations.count {
                let variation = viewModel.variations[index]
                if variation.id == nil && !viewModel.availableLocations.isEmpty {
                    // Move to first initial inventory field
                    focusedField = .initialInventory(variationIndex: index, locationIndex: 0)
                    return
                }
            }

            // Move to next variation or done
            let nextIndex = index + 1
            if nextIndex < viewModel.variations.count {
                focusedField = .variationName(nextIndex)
            } else {
                // All fields complete - re-set focus to prevent iOS responder advancement
                focusedField = .variationPrice(index)
                return
            }

        case .priceOverride(let variationIndex, let overrideIndex):
            // Check if there's another override for this variation
            let nextOverrideIndex = overrideIndex + 1
            if variationIndex < viewModel.variations.count {
                let variation = viewModel.variations[variationIndex]
                if nextOverrideIndex < variation.locationOverrides.count {
                    focusedField = .priceOverride(variationIndex: variationIndex, overrideIndex: nextOverrideIndex)
                    return
                }
            }

            // Check if this variation is new (no ID) and needs initial inventory fields
            if variationIndex < viewModel.variations.count {
                let variation = viewModel.variations[variationIndex]
                if variation.id == nil && !viewModel.availableLocations.isEmpty {
                    // Move to first initial inventory field
                    focusedField = .initialInventory(variationIndex: variationIndex, locationIndex: 0)
                    return
                }
            }

            // Move to next variation or done
            let nextVariationIndex = variationIndex + 1
            if nextVariationIndex < viewModel.variations.count {
                focusedField = .variationName(nextVariationIndex)
            } else {
                // All fields complete - re-set focus to prevent iOS responder advancement
                focusedField = .priceOverride(variationIndex: variationIndex, overrideIndex: overrideIndex)
                return
            }

        case .initialInventory(let variationIndex, let locationIndex):
            // Move to next location's inventory field
            let nextLocationIndex = locationIndex + 1
            if nextLocationIndex < viewModel.availableLocations.count {
                focusedField = .initialInventory(variationIndex: variationIndex, locationIndex: nextLocationIndex)
            } else {
                // All locations done for this variation, move to next variation or done
                let nextVariationIndex = variationIndex + 1
                if nextVariationIndex < viewModel.variations.count {
                    focusedField = .variationName(nextVariationIndex)
                } else {
                    // All fields complete - re-set focus to prevent iOS responder advancement
                    focusedField = .initialInventory(variationIndex: variationIndex, locationIndex: locationIndex)
                    return
                }
            }
        }
    }
}

// MARK: - Create From Search Header
/// Shows context when creating an item from a search query
struct CreateFromSearchHeader: View {
    let query: String
    let queryType: SearchQueryType
    
    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.itemDetailsAccent)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Creating new item")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Pre-filled \(queryType.displayName): \(query)")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.itemDetailsAccent.opacity(0.1))
        .cornerRadius(8)
    }
}

// Preview removed due to complexity - test in app instead
}
