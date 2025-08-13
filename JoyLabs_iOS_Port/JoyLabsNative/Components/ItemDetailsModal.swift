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

// MARK: - Item Details Modal
/// Main modal coordinator that handles all entry points for item details
struct ItemDetailsModal: View {
    let context: ItemDetailsContext
    let onDismiss: () -> Void
    let onSave: (ItemDetailsData) -> Void

    @State private var showingCancelConfirmation = false
    @FocusState private var isAnyFieldFocused: Bool
    
    @StateObject private var viewModel = ItemDetailsViewModel()
    
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
            // Custom header
            HStack {
                Button("Cancel") {
                    handleCancel()
                }
                .foregroundColor(.itemDetailsDestructive)
                
                Spacer()
                
                Text(dynamicTitle)
                    .font(.itemDetailsSectionTitle)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Save") {
                    handleSave()
                }
                .disabled(!viewModel.canSave)
                .foregroundColor(viewModel.canSave ? .itemDetailsAccent : .itemDetailsSecondaryText)
                .fontWeight(.semibold)
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
                    onSave: handleSave
                )
                .focused($isAnyFieldFocused)
                .onTapGesture {
                    // Dismiss keyboard when tapping outside text fields
                    isAnyFieldFocused = false
                    hideKeyboard()
                }

                // Floating Action Buttons (hidden during confirmation with animation)
                VStack {
                    Spacer()

                    FloatingActionButtons(
                        onCancel: handleCancel,
                        onPrint: handlePrint,
                        onSave: handleSave,
                        onSaveAndPrint: handleSaveAndPrint,
                        canSave: viewModel.canSave
                    )
                    .opacity(showingCancelConfirmation ? 0 : 1)
                    .animation(.easeInOut(duration: 0.1), value: showingCancelConfirmation)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .interactiveDismissDisabled(false)
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
        }
        .onDisappear {
            // Only reset when modal is actually being dismissed (not during presentation animation)
            // We'll let the parent handle modal lifecycle properly
            print("[ItemDetailsModal] onDisappear called")
        }
        .onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { _ in
            // Refresh item data when catalog sync completes (for webhook updates)
            // Add defensive check to prevent race conditions during modal presentation
            if case .editExisting(let itemId) = context {
                logger.info("Catalog sync completed - refreshing item data for \(itemId)")
                // Small delay to ensure modal is fully loaded before responding to notifications
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task {
                        await viewModel.refreshItemData(itemId: itemId)
                    }
                }
            }
        }
        .actionSheet(isPresented: $showingCancelConfirmation) {
            ActionSheet(
                title: Text("Discard Changes?"),
                message: Text("You have unsaved changes. Are you sure you want to discard them?"),
                buttons: [
                    .destructive(Text("Discard Changes")) {
                        onDismiss()
                    },
                    .cancel(Text("Keep Editing"))
                ]
            )
        }
        .scrollDismissesKeyboard(.immediately)
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
        isAnyFieldFocused = false
        hideKeyboard()

        if viewModel.hasChanges {
            print("User has unsaved changes - showing confirmation")
            // Small delay to ensure keyboard dismissal completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showingCancelConfirmation = true
            }
        } else {
            onDismiss()
        }
    }


    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func createPrintData(from itemData: ItemDetailsData) -> PrintData {
        let firstVariation = itemData.variations.first
        let priceAmount = firstVariation?.priceMoney?.amount
        let priceString = priceAmount.map { String(format: "%.2f", Double($0) / 100.0) }
        
        return PrintData(
            itemName: itemData.name,
            variationName: firstVariation?.name,
            price: priceString,
            originalPrice: nil,
            upc: firstVariation?.upc,
            sku: firstVariation?.sku,
            categoryName: nil, // Would need to look up category name from ID
            categoryId: itemData.reportingCategoryId,
            description: itemData.description,
            createdAt: nil,
            updatedAt: nil,
            qtyForPrice: nil,
            qtyPrice: nil
        )
    }

    private func handlePrint() {
        print("Print button tapped")
        
        Task {
            do {
                let printData = createPrintData(from: viewModel.itemData)
                try await LabelLivePrintService.shared.printLabel(with: printData)
                
                await MainActor.run {
                    print("Print completed successfully")
                }
            } catch LabelLivePrintError.printSuccess {
                await MainActor.run {
                    print("Print completed successfully")
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                }
            }
        }
    }

    private func handleSaveAndPrint() {
        print("Save & Print button tapped")

        Task {
            // First save the item
            if let itemData = await viewModel.saveItem() {
                await MainActor.run {
                    onSave(itemData)
                }
                
                // Then print after successful save
                do {
                    let printData = createPrintData(from: itemData)
                    try await LabelLivePrintService.shared.printLabel(with: printData)
                    
                    await MainActor.run {
                        print("Item saved and printed successfully")
                        onDismiss()
                    }
                } catch LabelLivePrintError.printSuccess {
                    await MainActor.run {
                        print("Item saved and printed successfully")
                        onDismiss()
                    }
                } catch {
                    await MainActor.run {
                        // Item was saved but print failed
                        viewModel.error = "Item saved but print failed: \(error.localizedDescription)"
                        // Don't dismiss modal so user can retry or manually print
                    }
                }
            }
        }
    }
}

// MARK: - Item Details Content
/// Main content view that displays the form fields
struct ItemDetailsContent: View {
    let context: ItemDetailsContext
    @ObservedObject var viewModel: ItemDetailsViewModel
    let onSave: () -> Void
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ItemDetailsSpacing.compactSpacing) {
                    // Context-specific header message
                    if case .createFromSearch(let query, let queryType) = context {
                        CreateFromSearchHeader(query: query, queryType: queryType)
                    }

                    // Dynamic sections based on user configuration
                    ForEach(configManager.currentConfiguration.orderedSections.filter { $0.isEnabled }, id: \.id) { section in
                        sectionView(for: section.id)
                    }

                    // Delete Button Section (always last)
                    ItemDeleteSection(viewModel: viewModel)

                    // Bottom spacing for floating buttons and keyboard
                    Spacer()
                        .frame(height: 120)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Dynamic Section Rendering
    @ViewBuilder
    private func sectionView(for sectionId: String) -> some View {
        switch sectionId {
        case "image":
            ItemImageSection(viewModel: viewModel)
            
        case "basicInfo":
            ItemDetailsBasicSection(viewModel: viewModel)
            
        case "productType":
            ItemProductTypeSection(viewModel: viewModel)
            
        case "pricing":
            if shouldShowPricingSection {
                ItemDetailsPricingSection(viewModel: viewModel)
            }
            
        case "categories":
            if shouldShowCategoriesSection {
                ItemDetailsCategoriesSection(viewModel: viewModel)
            }
            
        case "taxes":
            ItemTaxSettingsSection(viewModel: viewModel)
            
        case "modifiers":
            ItemModifiersSection(viewModel: viewModel)
            
        case "skipModifier":
            ItemSkipModifierSection(viewModel: viewModel)
            
        case "availability":
            if configManager.currentConfiguration.ecommerceFields.availabilityEnabled {
                ItemAvailabilitySection(viewModel: viewModel)
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

#Preview("Create New Item") {
    ItemDetailsModal(
        context: .createNew,
        onDismiss: {},
        onSave: { _ in }
    )
}

#Preview("Create From Search") {
    ItemDetailsModal(
        context: .createFromSearch(query: "1234567890123", queryType: .upc),
        onDismiss: {},
        onSave: { _ in }
    )
}
