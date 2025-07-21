import SwiftUI
import Combine

// MARK: - Item Details Data
/// Complete data model for item details that captures all Square catalog fields
struct ItemDetailsData {
    // Core identification
    var id: String?
    var version: Int64?
    
    // Basic information
    var name: String = ""
    var description: String = ""
    var abbreviation: String = ""
    
    // Product classification
    var productType: ProductType = .regular
    var reportingCategoryId: String?
    var categoryIds: [String] = []
    
    // Pricing and variations
    var variations: [ItemDetailsVariationData] = []
    
    // Tax and modifiers
    var taxIds: [String] = []
    var modifierListIds: [String] = []
    
    // Images
    var imageIds: [String] = []
    
    // Advanced features
    var skipModifierScreen: Bool = false
    var availableOnline: Bool = true
    var availableForPickup: Bool = true
    var availableElectronically: Bool = false
    
    // Service-specific (for appointments)
    var serviceDuration: Int? // in milliseconds
    var teamMemberIds: [String] = []
    var availableForBooking: Bool = false
    
    // Inventory
    var trackInventory: Bool = false
    var inventoryAlertType: InventoryAlertType = .none
    var inventoryAlertThreshold: Int?
    
    // Custom attributes
    var customAttributes: [String: String] = [:]

    // Image
    var imageURL: String? = nil

    // Availability settings
    var isAvailableForSale: Bool = true
    var isAvailableOnline: Bool = true
    var isAvailableForPickup: Bool = true
    var availabilityStartDate: Date? = nil
    var availabilityEndDate: Date? = nil

    // Location settings
    var enabledAtAllLocations: Bool = true
    var enabledLocationIds: [String] = []

    // Metadata
    var isDeleted: Bool = false
    var presentAtAllLocations: Bool = true
    var updatedAt: String?
    var createdAt: String?
}

// MARK: - Supporting Enums
enum ProductType: String, CaseIterable {
    case regular = "REGULAR"
    case appointmentsService = "APPOINTMENTS_SERVICE"
    
    var displayName: String {
        switch self {
        case .regular:
            return "Regular Product"
        case .appointmentsService:
            return "Appointment Service"
        }
    }
}

enum InventoryAlertType: String, CaseIterable {
    case none = "NONE"
    case lowQuantity = "LOW_QUANTITY"
    
    var displayName: String {
        switch self {
        case .none:
            return "No Alerts"
        case .lowQuantity:
            return "Low Quantity Alert"
        }
    }
}

// MARK: - Item Variation Data
struct ItemDetailsVariationData: Identifiable {
    var id: String?
    var version: Int64?
    var name: String?
    var sku: String?
    var upc: String?
    var ordinal: Int = 0
    var pricingType: PricingType = .fixedPricing
    var priceMoney: MoneyData?
    var basePriceMoney: MoneyData?
    var locationOverrides: [LocationOverrideData] = []
    var trackInventory: Bool = false
    var inventoryAlertType: InventoryAlertType = .none
    var inventoryAlertThreshold: Int?
    var serviceDuration: Int? // in milliseconds
    var availableForBooking: Bool = false
    var teamMemberIds: [String] = []
    var stockable: Bool = true
    var sellable: Bool = true
}

enum PricingType: String, CaseIterable {
    case fixedPricing = "FIXED_PRICING"
    case variablePricing = "VARIABLE_PRICING"
    
    var displayName: String {
        switch self {
        case .fixedPricing:
            return "Fixed Price"
        case .variablePricing:
            return "Variable Price"
        }
    }
}

// MARK: - Money Data
struct MoneyData {
    var amount: Int // in cents
    var currency: String = "USD"
    
    var displayAmount: Double {
        return Double(amount) / 100.0
    }
    
    init(amount: Int, currency: String = "USD") {
        self.amount = amount
        self.currency = currency
    }
    
    init(dollars: Double, currency: String = "USD") {
        self.amount = Int(dollars * 100)
        self.currency = currency
    }
}

// MARK: - Location Override Data
struct LocationOverrideData: Identifiable {
    var id = UUID()
    var locationId: String
    var locationName: String?
    var priceMoney: MoneyData?
    var trackInventory: Bool?
    var inventoryAlertType: InventoryAlertType?
    var inventoryAlertThreshold: Int?
}

// MARK: - Location Data
struct LocationData: Identifiable {
    let id: String
    let name: String
    let address: String
    let isActive: Bool

    init(id: String, name: String, address: String = "", isActive: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.isActive = isActive
    }
}

// MARK: - Item Details View Model
/// Manages the business logic and state for the item details modal
@MainActor
class ItemDetailsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var itemData = ItemDetailsData()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    
    // UI state
    @Published var showAdvancedFeatures = false
    @Published var hasUnsavedChanges = false

    // Available locations (loaded from Square)
    @Published var availableLocations: [LocationData] = []

    // Context
    var context: ItemDetailsContext = .createNew

    // Validation
    @Published var nameError: String?
    @Published var variationErrors: [String: String] = [:]
    
    // MARK: - Computed Properties
    var canSave: Bool {
        !itemData.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !itemData.variations.isEmpty &&
        !isSaving &&
        nameError == nil
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupValidation()
        setupChangeTracking()
    }
    
    // MARK: - Public Methods
    
    /// Setup the view model for a specific context
    func setupForContext(_ context: ItemDetailsContext) async {
        print("Setting up for context: \(String(describing: context))")

        // Store the context
        self.context = context

        isLoading = true
        defer { isLoading = false }
        
        switch context {
        case .editExisting(let itemId):
            await loadExistingItem(itemId: itemId)
            
        case .createNew:
            setupNewItem()
            
        case .createFromSearch(let query, let queryType):
            setupNewItemFromSearch(query: query, queryType: queryType)
        }
        
        hasUnsavedChanges = false
    }
    
    /// Save the current item data
    func saveItem() async -> ItemDetailsData? {
        print("Saving item data")

        guard canSave else {
            print("Cannot save - validation failed")
            return nil
        }
        
        isSaving = true
        defer { isSaving = false }
        
        // TODO: Implement actual save logic with Square API
        print("Item saved successfully")
        hasUnsavedChanges = false
        return itemData
    }
    
    // MARK: - Private Methods
    
    private func setupValidation() {
        // Validate name changes
        $itemData
            .map(\.name)
            .removeDuplicates()
            .sink { [weak self] name in
                self?.validateName(name)
            }
            .store(in: &cancellables)
    }
    
    private func setupChangeTracking() {
        $itemData
            .dropFirst()
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }
    
    private func validateName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            nameError = "Item name is required"
        } else if trimmedName.count > 255 {
            nameError = "Item name must be 255 characters or less"
        } else {
            nameError = nil
        }
    }
    
    private func loadExistingItem(itemId: String) async {
        print("Loading existing item: \(itemId)")
        
        // TODO: Implement loading from database/API
        // For now, create a placeholder
        itemData.id = itemId
        itemData.name = "Sample Item"
        itemData.variations = [ItemDetailsVariationData()]
    }
    
    private func setupNewItem() {
        print("Setting up new item")
        
        itemData = ItemDetailsData()
        itemData.variations = [ItemDetailsVariationData()]
    }
    
    private func setupNewItemFromSearch(query: String, queryType: SearchQueryType) {
        print("Setting up new item from search: \(query) (\(queryType))")
        
        setupNewItem()

        switch queryType {
        case .barcode:
            if !itemData.variations.isEmpty {
                itemData.variations[0].upc = query
            }
        case .sku:
            if !itemData.variations.isEmpty {
                itemData.variations[0].sku = query
            }
        case .name:
            itemData.name = query
        }
    }

    // MARK: - Delete Item
    func deleteItem() async {
        guard case .editExisting(let itemId) = self.context else {
            print("Cannot delete - not editing existing item")
            return
        }

        isLoading = true
        error = nil

        // TODO: Implement actual delete logic with Square API
        print("Deleting item: \(itemId)")

        // Simulate API call
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        isLoading = false

        // For now, just dismiss the modal
        // In real implementation, this would call the Square API to delete the item
        print("Item deleted successfully")
    }
}
