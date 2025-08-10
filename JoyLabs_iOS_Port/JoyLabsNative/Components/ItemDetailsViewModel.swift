import SwiftUI
import Combine
import os.log
import SQLite

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
    var isAlcoholic: Bool = false
    
    // Pricing and variations
    var variations: [ItemDetailsVariationData] = []
    
    // Tax and modifiers
    var taxIds: [String] = []
    var isTaxable: Bool = true // Square API default
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

    // Team Data (AppSync Integration)
    var teamData: TeamItemData?

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
    private let crudService: SquareCRUDService

    // MARK: - Initialization

    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        self.databaseManager = databaseManager ?? SquareAPIServiceFactory.createDatabaseManager()
        self.crudService = SquareAPIServiceFactory.createCRUDService()
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
        nameError == nil &&
        allUPCsValid
    }

    /// Check if all UPCs in variations are valid according to Square's requirements
    private var allUPCsValid: Bool {
        let duplicateService = DuplicateDetectionService()

        for variation in itemData.variations {
            if let upc = variation.upc, !upc.isEmpty {
                let validationResult = duplicateService.validateUPC(upc)
                if !validationResult.isValid {
                    return false
                }
            }
        }
        return true
    }

    // Override hasUnsavedChanges to use proper comparison
    var hasChanges: Bool {
        guard let original = originalItemData else {
            // For new items, check if any meaningful data has been entered
            let hasData = !itemData.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !itemData.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   itemData.variations.contains { variation in
                       !(variation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       !(variation.sku ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       !(variation.upc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       (variation.priceMoney?.amount ?? 0) > 0
                   }
            print("🔍 CHANGE DETECTION: New item has data: \(hasData)")
            return hasData
        }

        let hasChanges = !itemData.isEqual(to: original)
        print("🔍 CHANGE DETECTION: Existing item has changes: \(hasChanges)")
        return hasChanges
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
    
    /// Save the current item data using SquareCRUDService
    func saveItem() async -> ItemDetailsData? {
        print("Saving item data")

        guard canSave else {
            print("Cannot save - validation failed")
            await MainActor.run {
                self.error = "Cannot save - please check required fields"
            }
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let savedObject: CatalogObject

            let wasNewItem = itemData.id == nil || itemData.id?.isEmpty == true
            
            if wasNewItem {
                // CREATE: New item
                print("Creating new item via Square API")
                savedObject = try await crudService.createItem(itemData)
                print("✅ Item created successfully: \(savedObject.id)")
                
                // Process deferred image upload if needed
                if DeferredImageUploadManager.shared.isDeferredUpload(itemData.imageURL) {
                    print("🔄 Processing deferred image upload for new item: \(savedObject.id)")
                    
                    do {
                        let finalImageURL = try await DeferredImageUploadManager.shared.processDeferredUploads(
                            for: savedObject.id,
                            base64ImageURL: itemData.imageURL
                        )
                        
                        // Update itemData with final image URL before transformation
                        await MainActor.run {
                            self.itemData.imageURL = finalImageURL
                        }
                        
                        print("✅ Deferred image upload completed successfully")
                    } catch {
                        print("⚠️ Deferred image upload failed, but item was created: \(error)")
                        // Don't fail the entire save operation, just log the error
                        await MainActor.run {
                            self.itemData.imageURL = nil // Clear the invalid temp URL
                        }
                    }
                }
            } else {
                // UPDATE: Existing item
                print("Updating existing item via Square API: \(itemData.id!)")
                savedObject = try await crudService.updateItem(itemData)
                print("✅ Item updated successfully: \(savedObject.id) (version: \(savedObject.safeVersion))")
            }

            // Update local data with Square API response
            let updatedItemData = ItemDataTransformers.transformCatalogObjectToItemDetails(savedObject)
            await MainActor.run {
                self.itemData = updatedItemData
                self.originalItemData = updatedItemData
                self.hasUnsavedChanges = false
                self.error = nil // Clear any previous errors
            }
            print("✅ Local data synchronized with Square API response")
            return updatedItemData

        } catch {
            print("❌ Failed to save item: \(error.localizedDescription)")

            // Set user-friendly error message
            await MainActor.run {
                if error.localizedDescription.contains("timed out") {
                    self.error = "Request timed out. Please check your internet connection and try again."
                } else if error.localizedDescription.contains("authentication") {
                    self.error = "Authentication failed. Please reconnect to Square in Profile settings."
                } else {
                    self.error = "Failed to save: \(error.localizedDescription)"
                }
            }

            // Keep hasUnsavedChanges = true so user can retry
            return nil
        }
    }

    /// Delete the current item using SquareCRUDService
    func deleteItem() async -> Bool {
        guard let itemId = itemData.id, !itemId.isEmpty else {
            print("Cannot delete - no item ID")
            return false
        }

        print("Deleting item: \(itemId)")
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await crudService.deleteItem(itemId)
            print("✅ Item deleted successfully: \(itemId)")

            // Mark as deleted locally
            await MainActor.run {
                self.itemData.isDeleted = true
                self.hasUnsavedChanges = false
            }

            return true

        } catch {
            print("❌ Failed to delete item: \(error.localizedDescription)")
            return false
        }
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
        print("[ItemDetailsModal] Loading existing item: \(itemId)")

        // Use the shared database manager - no need to connect again
        let catalogManager = SquareAPIServiceFactory.createDatabaseManager()

        do {
            if let catalogObject = try catalogManager.fetchItemById(itemId) {
                // Successfully loaded item from database
                itemData = await transformCatalogObjectToItemDetails(catalogObject)
                print("[ItemDetailsModal] Successfully loaded item from database: \(itemData.name)")

            } else {
                // Item not found in database
                print("[ItemDetailsModal] ERROR: Item not found in database: \(itemId) - This will cause a blank modal!")
                error = "Item not found in database"

                // Create a new item with the provided ID as fallback
                setupNewItem()
                itemData.id = itemId
            }

        } catch {
            // Error loading item
            print("[ItemDetailsModal] ERROR: Failed to load item \(itemId): \(error) - This will cause a blank modal!")
            self.error = "Failed to load item: \(error.localizedDescription)"

            // Create a new item as fallback
            setupNewItem()
            itemData.id = itemId
        }
    }

    /// Refresh item data from database (called when catalog sync completes)
    func refreshItemData(itemId: String) async {
        logger.info("Refreshing item data for \(itemId) after catalog sync")
        
        // Only refresh if we're currently editing this item and haven't made changes
        guard case .editExisting(let currentItemId) = context,
              currentItemId == itemId,
              !hasUnsavedChanges else {
            logger.info("Skipping refresh - either different item, unsaved changes, or not in edit mode")
            return
        }
        
        // Use the shared database manager to reload the item
        let catalogManager = SquareAPIServiceFactory.createDatabaseManager()
        
        do {
            if let catalogObject = try catalogManager.fetchItemById(itemId) {
                // Transform and update the item data
                let refreshedData = await transformCatalogObjectToItemDetails(catalogObject)
                
                await MainActor.run {
                    self.itemData = refreshedData
                    // Update original data to reflect the refreshed state
                    self.originalItemData = refreshedData
                }
                
                logger.info("Successfully refreshed item data for \(itemId)")
            } else {
                logger.warning("Item \(itemId) not found during refresh")
            }
        } catch {
            logger.error("Failed to refresh item data for \(itemId): \(error)")
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
            // Debug: Log the raw data we're working with
            logger.info("🔍 ITEM MODAL: Processing item \(catalogObject.id)")
            logger.info("🔍 ITEM MODAL: taxIds in itemData: \(itemData.taxIds ?? [])")
            logger.info("🔍 ITEM MODAL: modifierListInfo count: \(itemData.modifierListInfo?.count ?? 0)")
            logger.info("🔍 ITEM MODAL: categories count: \(itemData.categories?.count ?? 0)")
            logger.info("🔍 ITEM MODAL: reportingCategory: \(itemData.reportingCategory?.id ?? "nil")")

            // CRITICAL DEBUG: Log the entire itemData structure to see what's missing
            if let modifierListInfo = itemData.modifierListInfo {
                logger.info("🔍 ITEM MODAL: modifierListInfo details: \(modifierListInfo)")
            }
            logger.info("🔍 ITEM MODAL: Full itemData structure available fields: name=\(itemData.name != nil), description=\(itemData.description != nil), categoryId=\(itemData.categoryId != nil), taxIds=\(itemData.taxIds != nil), variations=\(itemData.variations != nil), modifierListInfo=\(itemData.modifierListInfo != nil)")

            // Basic information
            itemDetails.name = itemData.name ?? ""
            itemDetails.description = itemData.description ?? ""
            itemDetails.abbreviation = itemData.abbreviation ?? ""

            // Product classification
            itemDetails.productType = transformProductType(itemData.productType)

            // CRITICAL: Extract categories following Square's logic and user requirements
            let allCategories = itemData.categories ?? []
            let explicitReportingCategory = itemData.reportingCategory

            if allCategories.count == 1 {
                // Rule 1: If item has only 1 category, it should be treated as the reporting category
                let singleCategory = allCategories.first!
                itemDetails.reportingCategoryId = singleCategory.id
                itemDetails.categoryIds = [] // No additional categories
                logger.info("Single category found - treating as reporting category: \(singleCategory.id)")

            } else if allCategories.count > 1 {
                // Rule 2: If there are multiple categories, use Square's explicit reporting_category field
                if let reportingCategory = explicitReportingCategory {
                    itemDetails.reportingCategoryId = reportingCategory.id
                    // Additional categories are all categories except the reporting category
                    itemDetails.categoryIds = allCategories.compactMap { category in
                        category.id != reportingCategory.id ? category.id : nil
                    }
                    logger.info("Multiple categories found - using explicit reporting category: \(reportingCategory.id), additional: \(itemDetails.categoryIds)")
                } else {
                    // Fallback: Use first category as reporting category if no explicit one is set
                    let firstCategory = allCategories.first!
                    itemDetails.reportingCategoryId = firstCategory.id
                    itemDetails.categoryIds = Array(allCategories.dropFirst()).map { $0.id }
                    logger.warning("Multiple categories but no explicit reporting category - using first as reporting: \(firstCategory.id)")
                }

            } else {
                // No categories at all - check legacy categoryId field
                if let legacyCategoryId = itemData.categoryId {
                    itemDetails.reportingCategoryId = legacyCategoryId
                    itemDetails.categoryIds = []
                    logger.info("No categories array - using legacy categoryId as reporting category: \(legacyCategoryId)")
                } else {
                    itemDetails.reportingCategoryId = nil
                    itemDetails.categoryIds = []
                    logger.info("No categories found for item: \(itemDetails.id ?? "no-id")")
                }
            }

            // CRITICAL: Extract modifier lists (from modifierListInfo)
            if let modifierListInfo = itemData.modifierListInfo {
                itemDetails.modifierListIds = modifierListInfo.compactMap { $0.modifierListId }
                logger.info("Loaded \(itemDetails.modifierListIds.count) modifier lists for item: \(itemDetails.modifierListIds)")
            } else {
                itemDetails.modifierListIds = []
                logger.info("No modifier lists found for item: \(itemDetails.id ?? "no-id")")
            }

            // Load actual variations from database
            await loadVariations(for: &itemDetails)

            // Availability and visibility
            itemDetails.availableOnline = itemData.availableOnline ?? false
            itemDetails.availableForPickup = itemData.availableForPickup ?? false
            itemDetails.skipModifierScreen = itemData.skipModifierScreen ?? false

            // Tax information (already working correctly)
            itemDetails.taxIds = itemData.taxIds ?? []
            logger.info("Loaded \(itemDetails.taxIds.count) taxes for item: \(itemDetails.taxIds)")
            
            // CRITICAL SQUARE API FIELDS - Previously missing extraction
            itemDetails.isTaxable = itemData.isTaxable ?? true // Square API default
            itemDetails.isAlcoholic = itemData.isAlcoholic ?? false // Square API default
            logger.info("Extracted Square API fields: isTaxable=\(itemDetails.isTaxable), isAlcoholic=\(itemDetails.isAlcoholic)")

            // PERFORMANCE OPTIMIZATION: Load pre-resolved tax and modifier names from database
            await loadPreResolvedNames(for: &itemDetails)

            // Images - use unified image service
            if let itemId = itemDetails.id {
                let primaryImageInfo = getPrimaryImageInfo(for: itemId)
                if let imageInfo = primaryImageInfo {
                    itemDetails.imageURL = imageInfo.imageURL
                    itemDetails.imageId = imageInfo.imageId // Use actual Square Image ID
                    logger.info("Loaded image for item modal: \(imageInfo.imageURL) (ID: \(imageInfo.imageId))")
                } else {
                    logger.info("No images found for item: \(itemId)")
                }
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
        itemData = ItemDetailsData()
        
        // Apply field configuration defaults
        let config = FieldConfigurationManager.shared.currentConfiguration
        itemData.skipModifierScreen = config.pricingFields.defaultSkipModifierScreen
        itemData.isTaxable = config.pricingFields.defaultIsTaxable
        itemData.isAlcoholic = config.classificationFields.defaultIsAlcoholic

        // Create variation with configurable default name
        var variation = ItemDetailsVariationData()
        variation.name = config.pricingFields.defaultVariationName
        itemData.variations = [variation]
    }
    
    private func setupNewItemFromSearch(query: String, queryType: SearchQueryType) {
        setupNewItem()

        switch queryType {
        case .upc:
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

    // MARK: - Unified Image Integration

    /// Get primary image info by reading database image_ids array in correct order
    private func getPrimaryImageInfo(for itemId: String) -> (imageURL: String, imageId: String)? {
        logger.info("🔍 [MODAL] Getting primary image info for item: \(itemId)")

        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("🔍 [MODAL] ❌ Database not connected")
                return nil
            }
            
            // Get item's image_ids array from database
            let selectQuery = """
                SELECT data_json FROM catalog_items
                WHERE id = ? AND is_deleted = 0
            """
            
            let statement = try db.prepare(selectQuery)
            for row in try statement.run([itemId]) {
                let dataJsonString = row[0] as? String ?? "{}"
                let dataJsonData = dataJsonString.data(using: String.Encoding.utf8) ?? Data()
                
                if let currentData = try JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any] {
                    var imageIds: [String]? = nil
                    
                    // Try nested under item_data first (current format)
                    if let itemData = currentData["item_data"] as? [String: Any] {
                        imageIds = itemData["image_ids"] as? [String]
                    }
                    
                    // Fallback to root level (legacy format)
                    if imageIds == nil {
                        imageIds = currentData["image_ids"] as? [String]
                    }
                    
                    if let imageIdArray = imageIds, let primaryImageId = imageIdArray.first {
                        logger.info("🔍 [MODAL] Found primary image ID from database: \(primaryImageId)")
                        
                        // Get image mapping for this specific image ID
                        let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
                        if let mapping = imageMappings.first(where: { $0.squareImageId == primaryImageId }) {
                            logger.info("🔍 [MODAL] ✅ Found mapping for primary image: \(primaryImageId) -> \(mapping.originalAwsUrl)")
                            return (imageURL: mapping.originalAwsUrl, imageId: primaryImageId)
                        } else {
                            logger.error("🔍 [MODAL] ❌ No mapping found for primary image ID: \(primaryImageId)")
                        }
                    } else {
                        logger.error("🔍 [MODAL] ❌ No image_ids found in database for item: \(itemId)")
                    }
                }
            }
            
        } catch {
            logger.error("🔍 [MODAL] ❌ Failed to get primary image info for item \(itemId): \(error)")
        }
        
        return nil
    }

    /// Get primary image URL using DIRECT image mapping lookup
    private func getPrimaryImageURL(for itemId: String) -> String? {
        logger.info("🔍 [MODAL] Getting primary image URL for item: \(itemId)")

        do {
            // DIRECTLY get image mappings for this item - NO JSON PARSING!
            let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
            logger.info("🔍 [MODAL] Found \(imageMappings.count) image mappings for item: \(itemId)")

            // Get the first mapping (primary image)
            if let primaryMapping = imageMappings.first {
                logger.info("🔍 [MODAL] ✅ Found primary image mapping: \(primaryMapping.squareImageId) -> \(primaryMapping.originalAwsUrl)")
                return primaryMapping.originalAwsUrl
            } else {
                logger.error("🔍 [MODAL] ❌ No image mappings found for item: \(itemId)")
                return nil
            }

        } catch {
            logger.error("🔍 [MODAL] ❌ Failed to get primary image URL for item \(itemId): \(error)")
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
            group.addTask { await self.loadLocations() }
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
                let _ = (row[2] as? Int64 ?? 0) != 0 // isDeleted - already filtered in query

                guard !id.isEmpty, !name.isEmpty else { continue }

                // Create a simple CategoryData for UI display
                let categoryData = CategoryData(
                    id: id,
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
                    id: id,
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
                    id: id,
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

    /// Load locations from local database (same pattern as other data)
    private func loadLocations() async {
        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("No database connection available")
                return
            }

            let query = """
                SELECT id, name, address, status
                FROM locations
                WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (status = 'ACTIVE' OR status IS NULL)
                ORDER BY name ASC
            """

            let statement = try db.prepare(query)
            var locations: [LocationData] = []

            for row in statement {
                let id = row[0] as? String ?? ""
                let name = row[1] as? String ?? ""
                let address = row[2] as? String ?? ""
                let status = row[3] as? String ?? ""

                guard !id.isEmpty, !name.isEmpty else { continue }

                // Create a LocationData for UI display
                let locationData = LocationData(
                    id: id,
                    name: name,
                    address: address,
                    isActive: status.uppercased() == "ACTIVE"
                )
                locations.append(locationData)
            }

            await MainActor.run {
                self.availableLocations = locations
                logger.debug("Loaded \(locations.count) locations for item modal")
            }
        } catch {
            logger.error("Failed to load locations: \(error)")
        }
    }

    /// PERFORMANCE OPTIMIZATION: Load pre-resolved tax and modifier names from database
    /// This avoids the need to do lookups every time the item modal is opened
    private func loadPreResolvedNames(for itemDetails: inout ItemDetailsData) async {
        guard let itemId = itemDetails.id else { return }

        do {
            guard let db = databaseManager.getConnection() else {
                logger.error("No database connection available for pre-resolved names")
                return
            }

            let query = """
                SELECT tax_names, modifier_names
                FROM catalog_items
                WHERE id = ? AND is_deleted = 0
            """

            let statement = try db.prepare(query)

            for row in try statement.run(itemId) {
                let taxNames = row[0] as? String
                let modifierNames = row[1] as? String

                // Store the pre-resolved names for display purposes
                // These will be used in the UI instead of doing repeated lookups
                if let taxNames = taxNames, !taxNames.isEmpty {
                    logger.info("📊 PERFORMANCE: Using pre-resolved tax names: '\(taxNames)' for item \(itemId)")
                    // You can store this in itemDetails if needed for display
                }

                if let modifierNames = modifierNames, !modifierNames.isEmpty {
                    logger.info("📊 PERFORMANCE: Using pre-resolved modifier names: '\(modifierNames)' for item \(itemId)")
                    // You can store this in itemDetails if needed for display
                }

                break // Only need the first row
            }

        } catch {
            logger.error("Failed to load pre-resolved names for item \(itemId): \(error)")
        }
    }

}
