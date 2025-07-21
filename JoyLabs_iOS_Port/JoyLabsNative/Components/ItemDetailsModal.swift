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
    case barcode = "UPC"
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
    
    @StateObject private var viewModel = ItemDetailsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemDetailsModal")
    
    var body: some View {
        NavigationView {
            ZStack {
                ItemDetailsContent(
                    context: context,
                    viewModel: viewModel,
                    onSave: handleSave
                )
                .navigationTitle(context.title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(true)

                // Floating Action Buttons
                VStack {
                    Spacer()

                    FloatingActionButtons(
                        onCancel: handleCancel,
                        onPrint: handlePrint,
                        onSave: handleSave,
                        onSaveAndPrint: handleSaveAndPrint,
                        canSave: viewModel.canSave
                    )
                }
            }
        }
        .onAppear {
            setupForContext()
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
                    dismiss()
                }
            }
        }
    }
    
    private func handleCancel() {
        print("Cancel button tapped")

        if viewModel.hasUnsavedChanges {
            // TODO: Show confirmation dialog
            print("User has unsaved changes - should show confirmation")
        }

        onDismiss()
        dismiss()
    }

    private func handlePrint() {
        print("Print button tapped")
        // TODO: Implement print functionality
    }

    private func handleSaveAndPrint() {
        print("Save & Print button tapped")

        Task {
            if let itemData = await viewModel.saveItem() {
                await MainActor.run {
                    onSave(itemData)
                    // TODO: Implement print functionality
                    print("Item saved and ready to print")
                    onDismiss()
                    dismiss()
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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Context-specific header message
                if case .createFromSearch(let query, let queryType) = context {
                    CreateFromSearchHeader(query: query, queryType: queryType)
                }

                // Item Image Section
                ItemImageSection(viewModel: viewModel)

                // Basic item information
                ItemDetailsBasicSection(viewModel: viewModel)
                
                // Pricing and variations
                ItemDetailsPricingSection(viewModel: viewModel)
                
                // Categories and organization
                ItemDetailsCategoriesSection(viewModel: viewModel)
                
                // Advanced features (conditionally shown)
                if viewModel.showAdvancedFeatures {
                    ItemDetailsAdvancedSection(viewModel: viewModel)
                }

                // Item Availability Section
                ItemAvailabilitySection(viewModel: viewModel)

                // Enabled Locations Section
                ItemEnabledLocationsSection(viewModel: viewModel)

                // Delete Button Section
                ItemDeleteSection(viewModel: viewModel)

                // Bottom spacing for floating buttons
                Spacer()
                    .frame(height: 120)
            }
            .padding()
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
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Creating new item")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Pre-filled \(queryType.displayName): \(query)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
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
        context: .createFromSearch(query: "1234567890123", queryType: .barcode),
        onDismiss: {},
        onSave: { _ in }
    )
}
