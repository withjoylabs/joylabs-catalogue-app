import SwiftUI
import Combine
import os.log

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
    var imageURL: String? = nil
    var imageId: String? = nil
    
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

    // Location overrides
    var locationOverrides: [LocationOverrideData] = []

    // E-commerce fields
    var onlineVisibility: OnlineVisibility = .public
    var ecomVisibility: EcomVisibility = .unindexed
    var seoTitle: String?
    var seoDescription: String?
    var seoKeywords: String?
    var channels: [String] = []

    // Measurement and units
    var measurementUnitId: String?
    var sellable: Bool = true
    var stockable: Bool = true
    var userData: String?



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

    /// Check if this item data is equal to another (for change detection)
    func isEqual(to other: ItemDetailsData) -> Bool {
        return self.name == other.name &&
               self.description == other.description &&
               self.abbreviation == other.abbreviation &&
               self.productType == other.productType &&
               self.reportingCategoryId == other.reportingCategoryId &&
               self.categoryIds == other.categoryIds &&
               self.enabledAtAllLocations == other.enabledAtAllLocations &&
               self.variations.count == other.variations.count &&
               zip(self.variations, other.variations).allSatisfy { $0.isEqual(to: $1) }
    }
}

// MARK: - Supporting Enums
enum ProductType: String, CaseIterable, Codable {
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

enum InventoryAlertType: String, CaseIterable, Codable {
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

    /// Check if this variation data is equal to another (for change detection)
    func isEqual(to other: ItemDetailsVariationData) -> Bool {
        return self.name == other.name &&
               self.sku == other.sku &&
               self.upc == other.upc &&
               self.pricingType == other.pricingType &&
               self.priceMoney?.amount == other.priceMoney?.amount &&
               self.priceMoney?.currency == other.priceMoney?.currency
    }
}

enum PricingType: String, CaseIterable {
    case fixedPricing = "FIXED_PRICING"
    case variablePricing = "VARIABLE_PRICING"
    
    var displayName: String {
        switch self {
        case .fixedPricing:
            return "Fixed"
        case .variablePricing:
            return "Variable"
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
    var trackInventory: Bool = false
    var inventoryAlertType: InventoryAlertType?
    var inventoryAlertThreshold: Int?
    var stockOnHand: Int = 0

    init(locationId: String, priceMoney: MoneyData? = nil, trackInventory: Bool = false, stockOnHand: Int = 0) {
        self.locationId = locationId
        self.priceMoney = priceMoney
        self.trackInventory = trackInventory
        self.stockOnHand = stockOnHand
    }
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

    // Critical data for dropdowns and selections (loaded from local database)
    @Published var availableCategories: [CategoryData] = []
    @Published var availableTaxes: [TaxData] = []
    @Published var availableModifierLists: [ModifierListData] = []

    // Service dependencies
    private let databaseManager: SQLiteSwiftCatalogManager

    // MARK: - Initialization

    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        self.databaseManager = databaseManager ?? SquareAPIServiceFactory.createDatabaseManager()
        setupValidationAndTracking()
    }

    // Context
    var context: ItemDetailsContext = .createNew

    // Store original data for change detection
    private var originalItemData: ItemDetailsData?

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

    // Override hasUnsavedChanges to use proper comparison
    var hasChanges: Bool {
        guard let original = originalItemData else {
            // For new items, check if any meaningful data has been entered
            return !itemData.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !itemData.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   itemData.variations.contains { variation in
                       !(variation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       !(variation.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       !(variation.upc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       (variation.priceMoney?.amount ?? 0) > 0
                   }
        }
        return !itemData.isEqual(to: original)
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let imageURLManager = SquareAPIServiceFactory.createImageURLManager()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemDetailsViewModel")

    // MARK: - Additional Initialization
    private func setupValidationAndTracking() {
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

        // Store original data for change detection
        originalItemData = itemData
        hasUnsavedChanges = false

        // Load critical dropdown data
        await loadCriticalData()
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

        // Use the shared database manager - no need to connect again
        let catalogManager = SquareAPIServiceFactory.createDatabaseManager()

        do {
            if let catalogObject = try catalogManager.fetchItemById(itemId) {
                // Successfully loaded item from database
                itemData = await transformCatalogObjectToItemDetails(catalogObject)
                print("Successfully loaded item from database: \(itemData.name)")

            } else {
                // Item not found in database
                print("Item not found in database: \(itemId)")
                error = "Item not found in database"

                // Create a new item with the provided ID as fallback
                setupNewItem()
                itemData.id = itemId
            }

        } catch {
            // Error loading item
            print("Error loading item \(itemId): \(error)")
            self.error = "Failed to load item: \(error.localizedDescription)"

            // Create a new item as fallback
            setupNewItem()
            itemData.id = itemId
        }
    }

    // MARK: - Data Transformation

    /// Transform a CatalogObject from database to ItemDetailsData for UI
    private func transformCatalogObjectToItemDetails(_ catalogObject: CatalogObject) async -> ItemDetailsData {
        var itemDetails = ItemDetailsData()

        // Basic identification
        itemDetails.id = catalogObject.id
        itemDetails.version = catalogObject.version
        itemDetails.updatedAt = catalogObject.updatedAt
        itemDetails.isDeleted = catalogObject.safeIsDeleted
        itemDetails.presentAtAllLocations = catalogObject.presentAtAllLocations ?? true

        // Extract item data
        if let itemData = catalogObject.itemData {
            // Basic information
            itemDetails.name = itemData.name ?? ""
            itemDetails.description = itemData.description ?? ""
            itemDetails.abbreviation = itemData.abbreviation ?? ""

            // Product classification
            itemDetails.productType = transformProductType(itemData.productType)

            // Load actual variations from database
            await loadVariations(for: &itemDetails)

            // Availability and visibility
            itemDetails.availableOnline = itemData.availableOnline ?? false
            itemDetails.availableForPickup = itemData.availableForPickup ?? false
            itemDetails.skipModifierScreen = itemData.skipModifierScreen ?? false

            // Tax information
            itemDetails.taxIds = itemData.taxIds ?? []

            // Images - use the EXACT same logic as search results
            let images = populateImageData(for: itemDetails.id ?? "")
            if let firstImage = images?.first {
                itemDetails.imageURL = firstImage.imageData?.url
                itemDetails.imageId = firstImage.id
                logger.info("Loaded image for item modal: \(firstImage.id ?? "no-id") -> \(firstImage.imageData?.url ?? "no-url")")
            } else {
                logger.info("No images found for item: \(itemDetails.id ?? "no-id")")
            }
        }

        return itemDetails
    }

    // MARK: - Helper Transformation Methods

    private func transformProductType(_ productType: String?) -> ProductType {
        switch productType {
        case "APPOINTMENTS_SERVICE": return .appointmentsService
        default: return .regular
        }
    }

    private func transformPricingType(_ pricingType: String?) -> PricingType {
        switch pricingType {
        case "VARIABLE_PRICING": return .variablePricing
        default: return .fixedPricing
        }
    }

    private func transformInventoryAlertType(_ alertType: String?) -> InventoryAlertType {
        switch alertType {
        case "LOW_QUANTITY": return .lowQuantity
        default: return .none
        }
    }

    private func transformEcomVisibility(_ visibility: String?) -> EcomVisibility {
        switch visibility {
        case "HIDDEN": return .hidden
        case "VISIBLE": return .visible
        default: return .unindexed
        }
    }
    
    private func setupNewItem() {
        print("Setting up new item")

        itemData = ItemDetailsData()

        // Create variation with configurable default name
        var variation = ItemDetailsVariationData()
        variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
        itemData.variations = [variation]
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

    /// Populate image data for an item - EXACT same logic as SearchManager
    private func populateImageData(for itemId: String) -> [CatalogImage]? {
        do {
            // Get image mappings for this item
            let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")

            guard !imageMappings.isEmpty else {
                return nil
            }

            // Convert image mappings to CatalogImage objects
            let catalogImages = imageMappings.map { mapping in
                return CatalogImage(
                    id: mapping.squareImageId,
                    type: "IMAGE",
                    updatedAt: ISO8601DateFormatter().string(from: mapping.lastAccessedAt),
                    version: nil,
                    isDeleted: false,
                    presentAtAllLocations: true,
                    imageData: ImageData(
                        name: nil,
                        url: mapping.originalAwsUrl, // Use original AWS URL for Swift to download
                        caption: nil,
                        photoStudioOrderId: nil
                    )
                )
            }

            return catalogImages.isEmpty ? nil : catalogImages
        } catch {
            logger.error("Failed to populate image data for item \(itemId): \(error)")
            return nil
        }
    }

    /// Load variations from database for an item
    private func loadVariations(for itemDetails: inout ItemDetailsData) async {
        guard let db = databaseManager.getConnection() else {
            // Fallback to default variation if no database connection
            var variation = ItemDetailsVariationData()
            variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
            itemDetails.variations = [variation]
            return
        }

        do {
            let sql = """
                SELECT id, name, sku, upc, ordinal, pricing_type, price_amount, price_currency, data_json
                FROM item_variations
                WHERE item_id = ? AND is_deleted = 0
                ORDER BY ordinal ASC
            """
            let statement = try db.prepare(sql)
            var variations: [ItemDetailsVariationData] = []

            for row in try statement.run(itemDetails.id ?? "") {
                var variation = ItemDetailsVariationData()
                variation.id = row[0] as? String
                variation.name = row[1] as? String
                variation.sku = row[2] as? String
                variation.upc = row[3] as? String
                variation.ordinal = (row[4] as? Int64).map(Int.init) ?? 0

                // Parse pricing type
                if let pricingTypeStr = row[5] as? String {
                    variation.pricingType = transformPricingType(pricingTypeStr)
                }

                // Parse price money
                if let priceAmount = row[6] as? Int64,
                   let priceCurrency = row[7] as? String {
                    variation.priceMoney = MoneyData(amount: Int(priceAmount), currency: priceCurrency)
                }

                variations.append(variation)
                logger.info("Loaded variation: \(variation.name ?? "unnamed") - SKU: \(variation.sku ?? "none") - UPC: \(variation.upc ?? "none")")
            }

            // If no variations found, create default one
            if variations.isEmpty {
                var variation = ItemDetailsVariationData()
                variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
                variations = [variation]
                logger.info("No variations found, created default variation")
            }

            itemDetails.variations = variations

        } catch {
            logger.error("Failed to load variations: \(error)")
            // Fallback to default variation
            var variation = ItemDetailsVariationData()
            variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
            itemDetails.variations = [variation]
        }
    }

    // MARK: - Critical Data Loading

    /// Load all critical dropdown data from local database using same patterns as search
    private func loadCriticalData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCategories() }
            group.addTask { await self.loadTaxes() }
            group.addTask { await self.loadModifierLists() }
        }
    }

    /// Load categories from local database (same pattern as search)
    private func loadCategories() async {
        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("No database connection available")
                return
            }

            let query = """
                SELECT id, name, is_deleted
                FROM categories
                WHERE is_deleted = 0
                ORDER BY name ASC
            """

            let statement = try db.prepare(query)
            var categories: [CategoryData] = []

            for row in statement {
                let id = row[0] as? String ?? ""
                let name = row[1] as? String ?? ""
                let isDeleted = (row[2] as? Int64 ?? 0) != 0

                guard !id.isEmpty, !name.isEmpty else { continue }

                // Create a simple CategoryData for UI display
                let categoryData = CategoryData(
                    name: name,
                    imageIds: nil,
                    imageUrl: nil,
                    categoryType: nil,
                    parentCategory: nil,
                    isTopLevel: nil,
                    channels: nil,
                    availabilityPeriodIds: nil,
                    onlineVisibility: nil,
                    rootCategory: nil,
                    ecomSeoData: nil,
                    pathToRoot: nil
                )
                categories.append(categoryData)
            }

            await MainActor.run {
                self.availableCategories = categories
                logger.debug("Loaded \(categories.count) categories for item modal")
            }
        } catch {
            logger.error("Failed to load categories: \(error)")
        }
    }

    /// Load taxes from local database (same pattern as search)
    private func loadTaxes() async {
        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("No database connection available")
                return
            }

            let query = """
                SELECT id, name, percentage, enabled
                FROM taxes
                WHERE is_deleted = 0 AND enabled = 1
                ORDER BY name ASC
            """

            let statement = try db.prepare(query)
            var taxes: [TaxData] = []

            for row in statement {
                let id = row[0] as? String ?? ""
                let name = row[1] as? String ?? ""
                let percentage = row[2] as? String
                let enabled = (row[3] as? Int64 ?? 0) != 0

                guard !id.isEmpty, !name.isEmpty else { continue }

                // Create a simple TaxData for UI display
                let taxData = TaxData(
                    name: name,
                    calculationPhase: nil,
                    inclusionType: nil,
                    percentage: percentage,
                    appliesToCustomAmounts: nil,
                    enabled: enabled
                )
                taxes.append(taxData)
            }

            await MainActor.run {
                self.availableTaxes = taxes
                logger.debug("Loaded \(taxes.count) taxes for item modal")
            }
        } catch {
            logger.error("Failed to load taxes: \(error)")
        }
    }

    /// Load modifier lists from local database (same pattern as search)
    private func loadModifierLists() async {
        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("No database connection available")
                return
            }

            let query = """
                SELECT id, name, selection_type
                FROM modifier_lists
                WHERE is_deleted = 0
                ORDER BY name ASC
            """

            let statement = try db.prepare(query)
            var modifierLists: [ModifierListData] = []

            for row in statement {
                let id = row[0] as? String ?? ""
                let name = row[1] as? String ?? ""
                let selectionType = row[2] as? String

                guard !id.isEmpty, !name.isEmpty else { continue }

                // Create a simple ModifierListData for UI display
                let modifierListData = ModifierListData(
                    name: name,
                    ordinal: nil,
                    selectionType: selectionType,
                    modifiers: nil,
                    imageIds: nil
                )
                modifierLists.append(modifierListData)
            }

            await MainActor.run {
                self.availableModifierLists = modifierLists
                logger.debug("Loaded \(modifierLists.count) modifier lists for item modal")
            }
        } catch {
            logger.error("Failed to load modifier lists: \(error)")
        }
    }

}
