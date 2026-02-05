import SwiftUI
import SwiftData
import Combine
import os.log
import Foundation

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
    var presentAtAllLocations: Bool = true  // Square API field for location availability
    var presentAtLocationIds: [String] = [] // Specific location IDs where item is present
    var absentAtLocationIds: [String] = [] // Specific location IDs where item is absent
    
    // Computed property for "Available at all future locations" toggle
    var availableAtFutureLocations: Bool {
        get {
            // Available at future locations when presentAtAllLocations is true
            return presentAtAllLocations
        }
        set {
            // When setting future availability
            if newValue {
                // Enable future locations - set presentAtAllLocations to true
                presentAtAllLocations = true
                // If all current locations should be enabled too, clear absent list
                // Otherwise, keep current absent list for partial availability
            } else {
                // Disable future locations - set presentAtAllLocations to false
                presentAtAllLocations = false
                // Clear absent list since we're now using specific present list
                absentAtLocationIds = []
            }
        }
    }

    // Metadata
    var isDeleted: Bool = false
    var updatedAt: String?
    var createdAt: String?

    // Team Data (AppSync Integration)
    var teamData: TeamItemData?

    // Removed complex isEqual method - using simple flag-based change tracking instead
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

enum InventoryTrackingMode: String, CaseIterable, Codable {
    case untracked = "UNTRACKED"    // track_inventory omitted/false - always available
    case stockCount = "STOCK_COUNT"  // track_inventory=true - quantity-based tracking

    var displayName: String {
        switch self {
        case .untracked:
            return "Don't Track Inventory"
        case .stockCount:
            return "Track Stock Count"
        }
    }
}

// MARK: - Pending Image Data
/// Holds image data before item/variation ID is available (similar to pendingInventoryQty)
struct PendingImageData: Identifiable {
    let id = UUID()
    let imageData: Data
    let fileName: String
    var isPrimary: Bool = false  // First image is primary
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
    var imageIds: [String] = []  // Variation-specific images

    // Location presence controls (per-variation location availability)
    var presentAtAllLocations: Bool = true
    var presentAtLocationIds: [String] = []
    var absentAtLocationIds: [String] = []

    // Pending inventory quantity for new items (before variation ID is assigned)
    // Dictionary: locationId -> quantity
    var pendingInventoryQty: [String: Int] = [:]

    // Pending images for new items (before variation ID is assigned)
    var pendingImages: [PendingImageData] = []

    // DEPRECATED: Variation-level tracking mode - now managed per-location via locationOverrides
    // This property exists for backward compatibility and returns the first location's mode or unavailable
    // For new items without overrides, it acts as a template for creating initial location overrides
    var inventoryTrackingMode: InventoryTrackingMode {
        get {
            // If we have location overrides, return the first one's mode
            if let firstOverride = locationOverrides.first {
                return firstOverride.trackingMode
            }
            // For new items without overrides, derive from variation-level flags
            return trackInventory ? .stockCount : .untracked
        }
        set {
            // Update all existing location overrides to use this mode
            for index in locationOverrides.indices {
                locationOverrides[index].trackingMode = newValue
            }
            // Also update variation-level flags for backward compatibility
            switch newValue {
            case .untracked:
                trackInventory = false
            case .stockCount:
                trackInventory = true
                stockable = true
                sellable = true
            }
        }
    }

    // Removed complex isEqual method - using simple flag-based change tracking instead

    /// Check if this variation is "for sale" at a specific location
    func isForSale(at locationId: String) -> Bool {
        if presentAtAllLocations {
            // If present at all locations, check if this location is NOT in the absent list
            return !absentAtLocationIds.contains(locationId)
        } else {
            // If not present at all locations, check if this location IS in the present list
            return presentAtLocationIds.contains(locationId)
        }
    }

    /// Set whether this variation is "for sale" at a specific location
    mutating func setForSale(_ forSale: Bool, at locationId: String) {
        if presentAtAllLocations {
            // When present at all locations, manage the absent list
            if forSale {
                // Remove from absent list (make it available)
                absentAtLocationIds.removeAll { $0 == locationId }
            } else {
                // Add to absent list (make it unavailable)
                if !absentAtLocationIds.contains(locationId) {
                    absentAtLocationIds.append(locationId)
                }
            }
        } else {
            // When not present at all locations, manage the present list
            if forSale {
                // Add to present list (make it available)
                if !presentAtLocationIds.contains(locationId) {
                    presentAtLocationIds.append(locationId)
                }
            } else {
                // Remove from present list (make it unavailable)
                presentAtLocationIds.removeAll { $0 == locationId }
            }
        }
    }

    /// Check if inventory tracking is enabled at a specific location
    func isTracking(at locationId: String) -> Bool {
        if let override = locationOverrides.first(where: { $0.locationId == locationId }) {
            return override.trackingMode == .stockCount
        }
        return trackInventory
    }

    /// Set inventory tracking for a specific location
    mutating func setTracking(_ tracking: Bool, at locationId: String) {
        if let index = locationOverrides.firstIndex(where: { $0.locationId == locationId }) {
            locationOverrides[index].trackingMode = tracking ? .stockCount : .untracked
            locationOverrides[index].trackInventory = tracking
        } else {
            var override = LocationOverrideData(locationId: locationId)
            override.trackingMode = tracking ? .stockCount : .untracked
            override.trackInventory = tracking
            locationOverrides.append(override)
        }
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
struct MoneyData: Equatable {
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
        self.amount = Int(round(dollars * 100))
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
    var trackingMode: InventoryTrackingMode = .untracked
    var inventoryAlertType: InventoryAlertType?
    var inventoryAlertThreshold: Int?
    var stockOnHand: Int = 0

    init(locationId: String, priceMoney: MoneyData? = nil, trackInventory: Bool = false, trackingMode: InventoryTrackingMode = .untracked, stockOnHand: Int = 0) {
        self.locationId = locationId
        self.priceMoney = priceMoney
        self.trackInventory = trackInventory
        self.trackingMode = trackingMode
        self.stockOnHand = stockOnHand
    }
}

// MARK: - Location Data
// LocationData is now defined in LocationCacheManager.swift to avoid duplication

// MARK: - Static Data Container
/// Contains less frequently changed item properties to reduce @Published overhead
struct ItemDetailsStaticData {
    // Core identification
    var id: String?
    var version: Int64?
    
    // Product classification
    var productType: ProductType = .regular
    var isAlcoholic: Bool = false
    
    // Tax and modifier settings
    var isTaxable: Bool = true
    
    // Images
    var imageIds: [String] = []

    // Pending images for new items (before item ID is assigned)
    var pendingImages: [PendingImageData] = []

    // Advanced features
    var skipModifierScreen: Bool = false
    var availableOnline: Bool = true
    var availableForPickup: Bool = true
    var availableElectronically: Bool = false
    
    // Service-specific
    var serviceDuration: Int?
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
    var presentAtAllLocations: Bool = true
    var presentAtLocationIds: [String] = []
    var absentAtLocationIds: [String] = []
    
    // Computed property for "Available at all future locations" toggle
    var availableAtFutureLocations: Bool {
        get {
            return presentAtAllLocations
        }
        set {
            // Simple setter - complex logic handled at UI binding level in ViewModel
            presentAtAllLocations = newValue
            if !newValue {
                absentAtLocationIds = []
            }
        }
    }
    
    // Computed property for master "Locations" toggle (Square Dashboard equivalent)
    var locationsEnabled: Bool {
        get {
            // Master toggle is ON when item has ANY location availability
            return presentAtAllLocations || !presentAtLocationIds.isEmpty
        }
        set {
            if newValue {
                // Enable locations - if no specific rules exist, default to future availability only
                if !presentAtAllLocations && presentAtLocationIds.isEmpty {
                    presentAtAllLocations = true
                    absentAtLocationIds = [] // Will show individual location toggles as OFF
                }
                // If already has location rules, don't change them
            } else {
                // Disable all location availability
                presentAtAllLocations = false
                presentAtLocationIds = []
                absentAtLocationIds = []
            }
        }
    }
    
    // Check if specific location is enabled based on Square API logic
    func isLocationEnabled(_ locationId: String) -> Bool {
        if presentAtAllLocations {
            // When present at all locations, location is enabled UNLESS it's in absent list
            return !absentAtLocationIds.contains(locationId)
        } else {
            // When not present at all locations, location is enabled ONLY if in present list
            return presentAtLocationIds.contains(locationId)
        }
    }
    
    // Update location enabled state using Square API logic
    mutating func setLocationEnabled(_ locationId: String, enabled: Bool) {
        // When enabling a location and master toggle is OFF, we need to switch to specific locations mode
        if enabled && !locationsEnabled {
            presentAtAllLocations = false
            presentAtLocationIds = [locationId]
            absentAtLocationIds = []
        } else if enabled {
            // Master toggle is ON - operate in current mode
            if presentAtAllLocations {
                // Present at all locations mode - use absent list for exceptions
                // Remove from absent list (if present)
                absentAtLocationIds.removeAll { $0 == locationId }
            } else {
                // Specific locations mode - use present list
                // Add to present list (if not already present)
                if !presentAtLocationIds.contains(locationId) {
                    presentAtLocationIds.append(locationId)
                }
                // Remove from absent list (cleanup)
                absentAtLocationIds.removeAll { $0 == locationId }
            }
        } else {
            // Disabling a location
            if presentAtAllLocations {
                // Present at all locations mode - add to absent list
                if !absentAtLocationIds.contains(locationId) {
                    absentAtLocationIds.append(locationId)
                }
            } else {
                // Specific locations mode - remove from present list
                presentAtLocationIds.removeAll { $0 == locationId }
                
                // If no locations remain enabled, clear master toggle
                if presentAtLocationIds.isEmpty {
                    presentAtAllLocations = false
                    absentAtLocationIds = []
                }
            }
        }
    }

    // Metadata
    var isDeleted: Bool = false
    var updatedAt: String?
    var createdAt: String?

    // Team Data
    var teamData: TeamItemData?
}

// MARK: - Item Details View Model
/// Manages the business logic and state for the item details modal
@MainActor
class ItemDetailsViewModel: ObservableObject {
    // MARK: - Granular Published Properties (Performance Optimized)
    // Frequently changed fields get individual @Published properties to avoid full hierarchy updates
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var abbreviation: String = ""
    @Published var reportingCategoryId: String?
    @Published var categoryIds: [String] = []
    @Published var variations: [ItemDetailsVariationData] = []
    @Published var taxIds: [String] = []
    @Published var modifierListIds: [String] = []
    @Published var imageURL: String?
    @Published var imageId: String?
    
    // Less frequently changed fields remain in a struct to reduce @Published overhead
    @Published var staticData = ItemDetailsStaticData()

    // Original values for true change detection (comparison-based, industry standard)
    private var originalName: String = ""
    private var originalDescription: String = ""
    private var originalAbbreviation: String = ""
    private var originalReportingCategoryId: String?
    private var originalCategoryIds: [String] = []
    private var originalTaxIds: [String] = []
    private var originalModifierListIds: [String] = []
    private var originalVariations: [ItemDetailsVariationData] = []
    private var originalStaticData = ItemDetailsStaticData()

    // System state
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    // UI state
    @Published var showAdvancedFeatures = false

    // True change detection via comparison (not flag-based)
    // Images excluded - they have their own separate CRUD process
    var hasChanges: Bool {
        // Compare text fields
        if name != originalName { return true }
        if description != originalDescription { return true }
        if abbreviation != originalAbbreviation { return true }

        // Compare selections
        if reportingCategoryId != originalReportingCategoryId { return true }
        if categoryIds != originalCategoryIds { return true }
        if taxIds != originalTaxIds { return true }
        if modifierListIds != originalModifierListIds { return true }

        // Compare variations (count and content)
        if variations.count != originalVariations.count { return true }
        for (index, variation) in variations.enumerated() {
            guard index < originalVariations.count else { return true }
            let original = originalVariations[index]
            if variation.name != original.name { return true }
            if variation.sku != original.sku { return true }
            if variation.upc != original.upc { return true }
            if variation.priceMoney?.amount != original.priceMoney?.amount { return true }
            if variation.pricingType != original.pricingType { return true }
            if variation.trackInventory != original.trackInventory { return true }
            if variation.locationOverrides.count != original.locationOverrides.count { return true }
        }

        // Compare static data fields that matter
        if staticData.productType != originalStaticData.productType { return true }
        if staticData.skipModifierScreen != originalStaticData.skipModifierScreen { return true }
        if staticData.isTaxable != originalStaticData.isTaxable { return true }
        if staticData.presentAtAllLocations != originalStaticData.presentAtAllLocations { return true }
        if staticData.presentAtLocationIds != originalStaticData.presentAtLocationIds { return true }
        if staticData.absentAtLocationIds != originalStaticData.absentAtLocationIds { return true }

        // Fulfillment toggles
        if staticData.isAvailableOnline != originalStaticData.isAvailableOnline { return true }
        if staticData.isAvailableForPickup != originalStaticData.isAvailableForPickup { return true }
        if staticData.availableElectronically != originalStaticData.availableElectronically { return true }
        if staticData.isAlcoholic != originalStaticData.isAlcoholic { return true }

        // Other availability toggles
        if staticData.availableOnline != originalStaticData.availableOnline { return true }
        if staticData.availableForPickup != originalStaticData.availableForPickup { return true }
        if staticData.availableForBooking != originalStaticData.availableForBooking { return true }
        if staticData.isAvailableForSale != originalStaticData.isAvailableForSale { return true }

        // Inventory toggles
        if staticData.trackInventory != originalStaticData.trackInventory { return true }
        if staticData.sellable != originalStaticData.sellable { return true }
        if staticData.stockable != originalStaticData.stockable { return true }

        return false
    }

    // Available locations (loaded from Square)
    @Published var availableLocations: [LocationData] = []

    // Critical data for dropdowns and selections (loaded from local database)
    @Published var availableCategories: [CategoryData] = []
    @Published var availableTaxes: [TaxData] = []
    @Published var availableModifierLists: [ModifierListData] = []
    @Published var recentCategories: [CategoryData] = []  // For reporting category
    @Published var recentAdditionalCategories: [CategoryData] = []  // For additional categories

    // Inventory management - Now using SwiftData @Query for automatic reactivity!
    // No manual loading needed - UI updates automatically when InventoryCountModel changes

    // Private state for applying defaults
    private var shouldApplyTaxDefaults = false

    // Track original variation IDs to detect deletions at save time
    private var originalVariationIds: Set<String> = []

    // Service dependencies
    private let databaseManager: SwiftDataCatalogManager
    private let crudService: SquareCRUDService
    private let inventoryService: SquareInventoryService

    // MARK: - Initialization

    init(databaseManager: SwiftDataCatalogManager? = nil) {
        self.databaseManager = databaseManager ?? SquareAPIServiceFactory.createDatabaseManager()
        self.crudService = SquareAPIServiceFactory.createCRUDService()
        self.inventoryService = SquareAPIServiceFactory.createInventoryService()
        setupValidationAndTracking()
    }

    // Context
    var context: ItemDetailsContext = .createNew

    // Removed originalItemData - no longer needed with simple flag-based tracking

    // Validation
    @Published var nameError: String?
    @Published var variationErrors: [String: String] = [:]
    
    // MARK: - Computed Properties
    
    /// Computed property that assembles complete ItemDetailsData from granular properties
    var itemData: ItemDetailsData {
        var data = ItemDetailsData()
        
        // Core identification from static data
        data.id = staticData.id
        data.version = staticData.version
        
        // Frequently changed fields from individual @Published properties
        data.name = name
        data.description = description
        data.abbreviation = abbreviation
        data.reportingCategoryId = reportingCategoryId
        data.categoryIds = categoryIds
        data.variations = variations
        data.taxIds = taxIds
        data.modifierListIds = modifierListIds
        data.imageURL = imageURL
        data.imageId = imageId
        
        // Less frequently changed fields from static data
        data.productType = staticData.productType
        data.isAlcoholic = staticData.isAlcoholic
        data.isTaxable = staticData.isTaxable
        data.imageIds = staticData.imageIds
        data.skipModifierScreen = staticData.skipModifierScreen
        data.availableOnline = staticData.availableOnline
        data.availableForPickup = staticData.availableForPickup
        data.availableElectronically = staticData.availableElectronically
        data.serviceDuration = staticData.serviceDuration
        data.teamMemberIds = staticData.teamMemberIds
        data.availableForBooking = staticData.availableForBooking
        data.trackInventory = staticData.trackInventory
        data.inventoryAlertType = staticData.inventoryAlertType
        data.inventoryAlertThreshold = staticData.inventoryAlertThreshold
        data.customAttributes = staticData.customAttributes
        data.locationOverrides = staticData.locationOverrides
        data.onlineVisibility = staticData.onlineVisibility
        data.ecomVisibility = staticData.ecomVisibility
        data.seoTitle = staticData.seoTitle
        data.seoDescription = staticData.seoDescription
        data.seoKeywords = staticData.seoKeywords
        data.channels = staticData.channels
        data.measurementUnitId = staticData.measurementUnitId
        data.sellable = staticData.sellable
        data.stockable = staticData.stockable
        data.userData = staticData.userData
        data.isAvailableForSale = staticData.isAvailableForSale
        data.isAvailableOnline = staticData.isAvailableOnline
        data.isAvailableForPickup = staticData.isAvailableForPickup
        data.availabilityStartDate = staticData.availabilityStartDate
        data.availabilityEndDate = staticData.availabilityEndDate
        data.presentAtAllLocations = staticData.presentAtAllLocations
        data.presentAtLocationIds = staticData.presentAtLocationIds
        data.absentAtLocationIds = staticData.absentAtLocationIds
        // enabledLocationIds is legacy UI field - not sent to Square API
        data.isDeleted = staticData.isDeleted
        data.updatedAt = staticData.updatedAt
        data.createdAt = staticData.createdAt
        data.teamData = staticData.teamData
        
        return data
    }
    
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !variations.isEmpty &&
        !isSaving &&
        nameError == nil &&
        allUPCsValid
    }

    /// Check if all UPCs in variations are valid according to Square's requirements
    private var allUPCsValid: Bool {
        let duplicateService = DuplicateDetectionService(modelContext: databaseManager.getContext())

        for variation in variations {
            if let upc = variation.upc, !upc.isEmpty {
                let validationResult = duplicateService.validateUPC(upc)
                if !validationResult.isValid {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Change Detection Methods

    /// Capture current state as the baseline for change detection
    /// Called after loading item data or saving changes
    private func captureOriginalState() {
        originalName = name
        originalDescription = description
        originalAbbreviation = abbreviation
        originalReportingCategoryId = reportingCategoryId
        originalCategoryIds = categoryIds
        originalTaxIds = taxIds
        originalModifierListIds = modifierListIds
        originalVariations = variations
        originalStaticData = staticData
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    // ImageURLManager removed - using CatalogLookupService for pure SwiftData approach
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

        switch context {
        case .editExisting(let itemId, _):
            await loadExistingItem(itemId: itemId)

        case .createNew:
            setupNewItem()

        case .createFromSearch(let query, let queryType):
            setupNewItemFromSearch(query: query, queryType: queryType)
        }

        // Show UI immediately after item loads - don't wait for dropdowns
        isLoading = false

        // Load critical dropdown data in background (UI updates reactively via @Published)
        Task { await loadCriticalData() }
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

            let wasNewItem = staticData.id == nil || staticData.id?.isEmpty == true
            
            // Get current complete item data for API call
            let currentItemData = itemData
            
            if wasNewItem {
                // CREATE: New item
                print("Creating new item via Square API")
                savedObject = try await crudService.createItem(currentItemData)
                print("✅ Item created successfully: \(savedObject.id)")

                // Process deferred image upload if needed
                if DeferredImageUploadManager.shared.isDeferredUpload(imageURL) {
                    print("🔄 Processing deferred image upload for new item: \(savedObject.id)")

                    do {
                        let finalImageURL = try await DeferredImageUploadManager.shared.processDeferredUploads(
                            for: savedObject.id,
                            base64ImageURL: imageURL
                        )

                        // Update imageURL with final image URL
                        await MainActor.run {
                            self.imageURL = finalImageURL
                        }

                        print("✅ Deferred image upload completed successfully")
                    } catch {
                        print("⚠️ Deferred image upload failed, but item was created: \(error)")
                        // Don't fail the entire save operation, just log the error
                        await MainActor.run {
                            self.imageURL = nil // Clear the invalid temp URL
                        }
                    }
                }

                // Set initial inventory from pendingInventoryQty if user entered any
                try await setInitialInventoryForNewItem(savedObject: savedObject, originalVariations: currentItemData.variations)

                // Upload pending images for new item (after item ID is assigned)
                try await uploadPendingImagesForNewItem(savedObject: savedObject, originalItemData: currentItemData)
            } else {
                // UPDATE: Existing item
                print("Updating existing item via Square API: \(staticData.id!)")

                // Compute which variations were deleted (original IDs - current IDs)
                let currentVariationIds = Set(currentItemData.variations.compactMap { $0.id })
                let deletedVariationIds = originalVariationIds.subtracting(currentVariationIds)

                if !deletedVariationIds.isEmpty {
                    print("[ItemDetailsViewModel] Variations deleted by user: \(deletedVariationIds)")
                }

                savedObject = try await crudService.updateItem(currentItemData, deletedVariationIds: deletedVariationIds)
                print("✅ Item updated successfully: \(savedObject.id) (version: \(savedObject.safeVersion))")
            }

            // Update IDs and version from Square response (keep user's data in @Published properties)
            await MainActor.run {
                // Update item ID and version
                if wasNewItem {
                    self.staticData.id = savedObject.id
                }
                self.staticData.version = savedObject.version

                // Update variation IDs and versions from Square response
                if let apiVariations = savedObject.itemData?.variations {
                    for (index, apiVar) in apiVariations.enumerated() where index < self.variations.count {
                        if wasNewItem {
                            self.variations[index].id = apiVar.id  // New items get IDs from Square
                        }
                        self.variations[index].version = apiVar.version  // All items get version for optimistic locking
                    }
                }

                self.captureOriginalState()
                self.error = nil
            }
            print("✅ Item saved successfully")
            return itemData

        } catch {
            print("❌ Failed to save item: \(error.localizedDescription)")

            // Set user-friendly error message
            await MainActor.run {
                if error.localizedDescription.contains("timed out") {
                    self.error = "Request timed out. Please check your internet connection and try again."
                } else if error.localizedDescription.contains("authentication") {
                    self.error = "Authentication failed. Please reconnect to Square in Profile settings."
                } else if error.localizedDescription.contains("out of sync with Square") {
                    // Sync error from strict validation
                    self.error = "Data is out of sync with Square. Please perform a full catalog sync and try again."
                    logger.error("Sync error detected: \(error.localizedDescription)")
                } else {
                    self.error = "Failed to save: \(error.localizedDescription)"
                }
            }

            // hasChanges remains true (computed from unsaved modifications) so user can retry
            return nil
        }
    }

    /// Delete the current item using SquareCRUDService
    func deleteItem() async -> Bool {
        guard let itemId = staticData.id, !itemId.isEmpty else {
            print("Cannot delete - no item ID")
            return false
        }
        
        // Prevent duplicate delete operations
        guard !isSaving else {
            print("Delete already in progress")
            return false
        }

        print("[ItemDetailsViewModel] Deleting item: \(itemId)")
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await crudService.deleteItem(itemId)
            print("[ItemDetailsViewModel] ✅ Item deleted successfully: \(itemId)")

            // Mark as deleted locally
            await MainActor.run {
                self.staticData.isDeleted = true
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
        $name
            .removeDuplicates()
            .sink { [weak self] name in
                self?.validateName(name)
            }
            .store(in: &cancellables)
    }
    
    private func setupChangeTracking() {
        // Change detection via computed property comparison (industry standard)
        // hasChanges compares current values against originalValues captured at load/save
        // No manual tracking needed - automatic detection of actual changes
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

        // Use the instance database manager
        let catalogManager = self.databaseManager

        do {
            if let catalogObject = try catalogManager.fetchItemById(itemId) {
                // CRITICAL: Load locations FIRST before processing catalog object
                // This ensures availableLocations is populated for location initialization logic
                await loadLocations()
                
                // Then load item data with populated locations
                await loadItemDataFromCatalogObject(catalogObject)
                print("[ItemDetailsModal] Successfully loaded item from database: \(name)")

                // Load inventory counts from Square API in background (non-blocking)
                // UI will update reactively via @Published when inventory data arrives
                if SquareCapabilitiesService.shared.inventoryTrackingEnabled && !variations.isEmpty {
                    Task { await fetchInventoryFromSquare() }
                }

            } else {
                // Item not found in database
                print("[ItemDetailsModal] ERROR: Item not found in database: \(itemId) - This will cause a blank modal!")
                error = "Item not found in database"

                // Create a new item with the provided ID as fallback
                setupNewItem()
                staticData.id = itemId
            }

        } catch {
            // Error loading item
            print("[ItemDetailsModal] ERROR: Failed to load item \(itemId): \(error) - This will cause a blank modal!")
            self.error = "Failed to load item: \(error.localizedDescription)"

            // Create a new item as fallback
            setupNewItem()
            staticData.id = itemId
        }
    }

    /// Refresh item data from database (called when catalog sync completes)
    func refreshItemData(itemId: String) async {
        logger.info("Refreshing item data for \(itemId) after catalog sync")
        
        // Only refresh if we're currently editing this item and haven't made changes
        guard case .editExisting(let currentItemId, _) = context,
              currentItemId == itemId,
              !hasChanges else {
            logger.info("Skipping refresh - either different item, unsaved changes, or not in edit mode")
            return
        }
        
        // Use the instance database manager to reload the item
        let catalogManager = self.databaseManager
        
        do {
            if let catalogObject = try catalogManager.fetchItemById(itemId) {
                // Transform and update the item data
                await loadItemDataFromCatalogObject(catalogObject)
                
                // No need to update original data - using simple flag tracking
                
                logger.info("Successfully refreshed item data for \(itemId)")
            } else {
                logger.warning("Item \(itemId) not found during refresh")
            }
        } catch {
            logger.error("Failed to refresh item data for \(itemId): \(error)")
        }
    }

    // MARK: - Data Transformation

    /// Load item data from CatalogObject into granular properties for performance
    private func loadItemDataFromCatalogObject(_ catalogObject: CatalogObject) async {
        // Basic identification
        staticData.id = catalogObject.id
        staticData.version = catalogObject.version
        staticData.updatedAt = catalogObject.updatedAt
        staticData.isDeleted = catalogObject.safeIsDeleted
        staticData.presentAtAllLocations = catalogObject.presentAtAllLocations ?? false
        staticData.presentAtLocationIds = catalogObject.presentAtLocationIds ?? []
        staticData.absentAtLocationIds = catalogObject.absentAtLocationIds ?? []
        
        // Location data is now handled purely through Square API fields
        // UI toggles use isLocationEnabled() which computes from presentAtAllLocations + present/absent arrays

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

            // Basic information - set individual @Published properties
            self.name = itemData.name ?? ""
            self.description = itemData.description ?? ""
            self.abbreviation = itemData.abbreviation ?? ""

            // Product classification
            staticData.productType = transformProductType(itemData.productType)

            // CRITICAL: Extract categories following Square's logic and user requirements
            let allCategories = itemData.categories ?? []
            let explicitReportingCategory = itemData.reportingCategory

            if allCategories.count == 1 {
                // Rule 1: If item has only 1 category, it should be treated as the reporting category
                let singleCategory = allCategories.first!
                self.reportingCategoryId = singleCategory.id
                self.categoryIds = [] // No additional categories
                logger.info("Single category found - treating as reporting category: \(singleCategory.id)")

            } else if allCategories.count > 1 {
                // Rule 2: If there are multiple categories, use Square's explicit reporting_category field
                if let reportingCategory = explicitReportingCategory {
                    self.reportingCategoryId = reportingCategory.id
                    // Additional categories are all categories except the reporting category
                    self.categoryIds = allCategories.compactMap { category in
                        category.id != reportingCategory.id ? category.id : nil
                    }
                    logger.info("Multiple categories found - using explicit reporting category: \(reportingCategory.id), additional: \(self.categoryIds)")
                } else {
                    // Fallback: Use first category as reporting category if no explicit one is set
                    let firstCategory = allCategories.first!
                    self.reportingCategoryId = firstCategory.id
                    self.categoryIds = Array(allCategories.dropFirst()).map { $0.id }
                    logger.warning("Multiple categories but no explicit reporting category - using first as reporting: \(firstCategory.id)")
                }

            } else {
                // No categories at all - check legacy categoryId field
                if let legacyCategoryId = itemData.categoryId {
                    self.reportingCategoryId = legacyCategoryId
                    self.categoryIds = []
                    logger.info("No categories array - using legacy categoryId as reporting category: \(legacyCategoryId)")
                } else {
                    self.reportingCategoryId = nil
                    self.categoryIds = []
                    logger.info("No categories found for item: \(self.staticData.id ?? "no-id")")
                }
            }

            // CRITICAL: Extract modifier lists (from modifierListInfo)
            if let modifierListInfo = itemData.modifierListInfo {
                self.modifierListIds = modifierListInfo.compactMap { $0.modifierListId }
                logger.info("Loaded \(self.modifierListIds.count) modifier lists for item: \(self.modifierListIds)")
            } else {
                self.modifierListIds = []
                logger.info("No modifier lists found for item: \(self.staticData.id ?? "no-id")")
            }

            // Load actual variations from database
            await loadVariationsForCurrentItem()

            // Availability and visibility
            self.staticData.availableOnline = itemData.availableOnline ?? false
            self.staticData.availableForPickup = itemData.availableForPickup ?? false
            self.staticData.skipModifierScreen = itemData.skipModifierScreen ?? false

            // Tax information (already working correctly)
            self.taxIds = itemData.taxIds ?? []
            logger.info("Loaded \(self.taxIds.count) taxes for item: \(self.taxIds)")
            
            // CRITICAL SQUARE API FIELDS - Previously missing extraction
            self.staticData.isTaxable = itemData.isTaxable ?? true // Square API default
            self.staticData.isAlcoholic = itemData.isAlcoholic ?? false // Square API default
            logger.info("Extracted Square API fields: isTaxable=\(self.staticData.isTaxable), isAlcoholic=\(self.staticData.isAlcoholic)")

            // PERFORMANCE OPTIMIZATION: Load pre-resolved tax and modifier names from database
            await loadPreResolvedNamesForCurrentItem()

            // Images - use SwiftData property (updated by both sync AND local uploads)
            // Don't use itemData.imageIds which comes from stale dataJson blob
            if let itemId = self.staticData.id,
               let swiftDataItem = CatalogLookupService.shared.getItem(id: itemId) {
                self.staticData.imageIds = swiftDataItem.imageIds ?? []
                logger.info("Loaded \(self.staticData.imageIds.count) image IDs from SwiftData property")
            } else {
                self.staticData.imageIds = itemData.imageIds ?? []
                logger.info("Fallback: Loaded \(self.staticData.imageIds.count) image IDs from JSON")
            }

            if let itemId = self.staticData.id {
                let imageURL = getPrimaryImageURL(for: itemId)
                if let imageURL = imageURL {
                    self.imageURL = imageURL
                    self.imageId = nil  // Use URL-based approach, not Square Image ID
                    logger.info("Loaded image for item modal: \(imageURL)")
                } else {
                    logger.info("No images found for item: \(itemId)")
                }
            }

            // Capture original state for true change detection
            captureOriginalState()
        }
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
        // Clear all individual properties
        self.name = ""
        self.description = ""
        self.abbreviation = ""
        self.reportingCategoryId = nil
        self.categoryIds = []
        self.taxIds = []
        self.modifierListIds = []
        self.imageURL = nil
        self.imageId = nil
        
        // Reset static data with defaults
        self.staticData = ItemDetailsStaticData()
        
        // Apply field configuration defaults
        let config = FieldConfigurationManager.shared.currentConfiguration
        
        // Basic field defaults
        staticData.presentAtAllLocations = config.basicFields.defaultPresentAtAllLocations
        
        // Product classification defaults
        staticData.productType = config.classificationFields.defaultProductType
        staticData.isAlcoholic = config.classificationFields.defaultIsAlcoholic
        
        // Pricing and modifier defaults
        staticData.skipModifierScreen = config.pricingFields.defaultSkipModifierScreen
        staticData.isTaxable = config.pricingFields.defaultIsTaxable
        
        // E-commerce availability defaults
        staticData.availableOnline = config.ecommerceFields.defaultAvailableOnline
        staticData.availableForPickup = config.ecommerceFields.defaultAvailableForPickup
        staticData.availableElectronically = config.ecommerceFields.defaultAvailableElectronically
        
        // Availability section defaults (for ItemAvailabilitySection)
        staticData.isAvailableForSale = true // Always default to true
        staticData.isAvailableOnline = config.ecommerceFields.defaultAvailableOnline
        staticData.isAvailableForPickup = config.ecommerceFields.defaultAvailableForPickup

        // Create variation with configurable defaults
        var variation = ItemDetailsVariationData()
        variation.name = config.pricingFields.defaultVariationName
        variation.inventoryTrackingMode = config.inventoryFields.defaultInventoryTrackingMode
        self.variations = [variation]
        
        // Apply tax defaults - auto-select all taxes if default is taxable
        if config.pricingFields.defaultIsTaxable {
            // Tax selection will be applied after availableTaxes is loaded in loadCriticalData()
            // Mark that we need to apply tax defaults
            shouldApplyTaxDefaults = true
        }
        
        // Capture original state for true change detection
        captureOriginalState()
    }

    private func setupNewItemFromSearch(query: String, queryType: SearchQueryType) {
        setupNewItem()

        switch queryType {
        case .upc:
            if !self.variations.isEmpty {
                self.variations[0].upc = query
            }
        case .sku:
            if !self.variations.isEmpty {
                self.variations[0].sku = query
            }
        case .name:
            self.name = query
        }

        // Re-capture after search query modifications
        captureOriginalState()
    }

    // MARK: - Unified Image Integration


    /// Get primary image URL using SwiftData relationships (Pure SwiftData approach)
    private func getPrimaryImageURL(for itemId: String) -> String? {
        logger.info("🔍 [MODAL] Getting primary image URL for item: \(itemId)")
        
        let imageURL = CatalogLookupService.shared.getPrimaryImageUrl(for: itemId)
        
        if let imageURL = imageURL {
            logger.info("🔍 [MODAL] ✅ Found primary image URL: \(imageURL)")
        } else {
            logger.warning("🔍 [MODAL] ⚠️ No image URL found for item: \(itemId)")
        }
        
        return imageURL
    }

    /// Load variations from database for the current item
    private func loadVariationsForCurrentItem() async {
        let db = databaseManager.getContext()

        do {
            let itemId = self.staticData.id ?? ""
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && variation.isDeleted == false
                },
                sortBy: [SortDescriptor(\.ordinal)]
            )
            
            let variationModels = try db.fetch(descriptor)
            var loadedVariations: [ItemDetailsVariationData] = []

            for variationModel in variationModels {
                var variation = ItemDetailsVariationData()
                variation.id = variationModel.id
                variation.name = variationModel.name
                variation.sku = variationModel.sku
                variation.upc = variationModel.upc
                variation.ordinal = variationModel.ordinal ?? 0

                // Parse pricing type
                if let pricingTypeStr = variationModel.pricingType {
                    variation.pricingType = transformPricingType(pricingTypeStr)
                }

                // Parse price money
                if let priceAmount = variationModel.priceAmount,
                   let priceCurrency = variationModel.priceCurrency {
                    variation.priceMoney = MoneyData(amount: Int(priceAmount), currency: priceCurrency)
                }
                
                // Parse version (stored as TEXT in database)
                let versionStr = variationModel.version
                variation.version = Int64(versionStr)

                // Load ALL fields from stored variation data (dataJson contains complete CatalogObject)
                if let variationData = variationModel.toItemVariationData() {
                    // Images - prefer SwiftData property (updated by local uploads) over decoded JSON
                    // SwiftData property is updated when images are uploaded locally
                    // JSON data is updated when syncing from Square API
                    variation.imageIds = variationModel.imageIds ?? variationData.imageIds ?? []

                    // CRITICAL: Inventory tracking fields (previously missing - caused "Unavailable" bug)
                    variation.trackInventory = variationData.trackInventory ?? false
                    variation.stockable = variationData.stockable ?? true
                    variation.sellable = variationData.sellable ?? true

                    // Transform location overrides from Square API format to UI format
                    // This is what makes per-location tracking modes work
                    variation.locationOverrides = ItemDataTransformers.transformLocationOverrides(variationData.locationOverrides)

                    // Inventory alerts
                    variation.inventoryAlertType = ItemDataTransformers.transformInventoryAlertType(variationData.inventoryAlertType)
                    variation.inventoryAlertThreshold = variationData.inventoryAlertThreshold.map(Int.init)

                    // Service fields
                    variation.serviceDuration = variationData.serviceDuration.map(Int.init)
                    variation.availableForBooking = variationData.availableForBooking ?? false
                } else {
                    // Fallback: Load imageIds directly from SwiftData property if no JSON data
                    variation.imageIds = variationModel.imageIds ?? []
                }

                loadedVariations.append(variation)
                logger.info("Loaded variation: \(variation.name ?? "unnamed") - SKU: \(variation.sku ?? "none") - UPC: \(variation.upc ?? "none") - Version: \(variation.version?.description ?? "nil")")
            }

            // If no variations found, create default one
            if loadedVariations.isEmpty {
                var variation = ItemDetailsVariationData()
                variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
                loadedVariations = [variation]
                logger.info("No variations found, created default variation")
            }

            self.variations = loadedVariations

            // Capture original variation IDs to detect deletions at save time
            self.originalVariationIds = Set(loadedVariations.compactMap { $0.id })

        } catch {
            logger.error("Failed to load variations: \(error)")
            // Fallback to default variation
            var variation = ItemDetailsVariationData()
            variation.name = ItemFieldConfiguration.defaultConfiguration().pricingFields.defaultVariationName
            self.variations = [variation]
        }
    }

    // MARK: - Critical Data Loading

    /// Load all critical dropdown data from local database using same patterns as search
    private func loadCriticalData() async {
        // Load main data in parallel including locations for new item modals
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCategories() }
            group.addTask { await self.loadTaxes() }
            group.addTask { await self.loadModifierLists() }
            group.addTask { await self.loadLocations() } // Added for new item support
        }
        
        // Load recent categories after categories are available
        await loadRecentCategories()
        await loadRecentAdditionalCategories()

        // Apply tax defaults after data is loaded
        if shouldApplyTaxDefaults {
            await MainActor.run {
                self.taxIds = self.availableTaxes.compactMap { $0.id }
                self.shouldApplyTaxDefaults = false
            }
        }
    }

    /// Load categories from local database (same pattern as search)
    private func loadCategories() async {
        do {
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<CategoryModel>(
                predicate: #Predicate { category in
                    category.isDeleted == false
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let categoryModels = try db.fetch(descriptor)
            var categories: [CategoryData] = []

            for categoryModel in categoryModels {
                let id = categoryModel.id
                let name = categoryModel.name ?? ""

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
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<TaxModel>(
                predicate: #Predicate { tax in
                    tax.isDeleted == false && tax.enabled == true
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let taxModels = try db.fetch(descriptor)
            var taxes: [TaxData] = []

            for taxModel in taxModels {
                let id = taxModel.id
                let name = taxModel.name ?? ""
                let percentage = taxModel.percentage
                let enabled = taxModel.enabled ?? true

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
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<ModifierListModel>(
                predicate: #Predicate { modifierList in
                    modifierList.isDeleted == false
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let modifierListModels = try db.fetch(descriptor)
            var modifierLists: [ModifierListData] = []

            for modifierListModel in modifierListModels {
                let id = modifierListModel.id
                let name = modifierListModel.name ?? ""
                let selectionType = modifierListModel.selectionType

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
    /// Load locations from app-wide cache (instant, no HTTP calls)
    private func loadLocations() async {
        // Skip if locations already loaded (avoid duplicate loads)
        guard availableLocations.isEmpty else { return }

        // Failsafe: If cache is empty, load from API first
        if LocationCacheManager.shared.locations.isEmpty {
            logger.info("Location cache empty - loading from API as fallback")
            await LocationCacheManager.shared.loadLocations()
        }

        // Use cached locations from LocationCacheManager
        await MainActor.run {
            self.availableLocations = LocationCacheManager.shared.locations
            logger.debug("Loaded \(self.availableLocations.count) cached locations for item modal")
        }
    }

    /// PERFORMANCE OPTIMIZATION: Load pre-resolved tax and modifier names from database
    /// This avoids the need to do lookups every time the item modal is opened
    private func loadPreResolvedNamesForCurrentItem() async {
        guard let itemId = staticData.id else { return }

        do {
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && item.isDeleted == false
                }
            )

            let catalogItems = try db.fetch(descriptor)

            for catalogItem in catalogItems {
                let taxNames = catalogItem.taxNames
                let modifierNames = catalogItem.modifierNames

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
    
    // MARK: - Recent Categories Management
    
    private func loadRecentCategories() async {
        let recentCategoryIds = UserDefaults.standard.stringArray(forKey: "recentCategoryIds") ?? []
        let recent = availableCategories.filter { category in
            guard let id = category.id else { return false }
            return recentCategoryIds.contains(id)
        }
        
        // Preserve order from UserDefaults
        var orderedRecent: [CategoryData] = []
        for categoryId in recentCategoryIds {
            if let category = recent.first(where: { $0.id == categoryId }) {
                orderedRecent.append(category)
            }
        }
        
        await MainActor.run {
            self.recentCategories = Array(orderedRecent.prefix(15)) // Keep only 15 most recent
        }
    }
    
    func addToRecentCategories(_ categoryId: String?) {
        guard let categoryId = categoryId else { return }

        var recentIds = UserDefaults.standard.stringArray(forKey: "recentCategoryIds") ?? []

        // Remove if already exists
        recentIds.removeAll { $0 == categoryId }

        // Add to beginning
        recentIds.insert(categoryId, at: 0)

        // Keep only 15 most recent
        recentIds = Array(recentIds.prefix(15))

        UserDefaults.standard.set(recentIds, forKey: "recentCategoryIds")

        // Update UI
        Task {
            await loadRecentCategories()
        }
    }

    private func loadRecentAdditionalCategories() async {
        let recentCategoryIds = UserDefaults.standard.stringArray(forKey: "recentAdditionalCategoryIds") ?? []
        let recent = availableCategories.filter { category in
            guard let id = category.id else { return false }
            return recentCategoryIds.contains(id)
        }

        // Preserve order from UserDefaults
        var orderedRecent: [CategoryData] = []
        for categoryId in recentCategoryIds {
            if let category = recent.first(where: { $0.id == categoryId }) {
                orderedRecent.append(category)
            }
        }

        await MainActor.run {
            self.recentAdditionalCategories = Array(orderedRecent.prefix(15)) // Keep only 15 most recent
        }
    }

    func addToRecentAdditionalCategories(_ categoryId: String?) {
        guard let categoryId = categoryId else { return }

        var recentIds = UserDefaults.standard.stringArray(forKey: "recentAdditionalCategoryIds") ?? []

        // Remove if already exists
        recentIds.removeAll { $0 == categoryId }

        // Add to beginning
        recentIds.insert(categoryId, at: 0)

        // Keep only 15 most recent
        recentIds = Array(recentIds.prefix(15))

        UserDefaults.standard.set(recentIds, forKey: "recentAdditionalCategoryIds")

        // Update UI
        Task {
            await loadRecentAdditionalCategories()
        }
    }

    // MARK: - Inventory Management

    /// Fetch inventory counts from Square API
    /// SwiftData @Query automatically updates UI when InventoryCountModel changes!
    func fetchInventoryFromSquare() async {
        let variationIds = variations.compactMap { $0.id }
        guard !variationIds.isEmpty else { return }

        do {
            let counts = try await inventoryService.fetchInventoryCounts(
                catalogObjectIds: variationIds,
                locationIds: nil // Fetch for all locations
            )

            // Update database - SwiftData @Query views will auto-update!
            let db = databaseManager.getContext()
            for countData in counts {
                _ = InventoryCountModel.createOrUpdate(from: countData, in: db)
            }
            try db.save()

            // Mark inventory as enabled (successful API call means feature is available)
            await MainActor.run {
                SquareCapabilitiesService.shared.markInventoryAsEnabled()
            }

        } catch {
            logger.error("[InventoryViewModel] Failed to fetch inventory: \(error)")

            // Update capability flag based on error
            await MainActor.run {
                SquareCapabilitiesService.shared.markInventoryAsDisabled(error: error)
            }
        }
    }

    /// Submit inventory adjustment
    func submitInventoryAdjustment(
        variationId: String,
        locationId: String,
        quantity: Int,
        reason: InventoryAdjustmentReason
    ) async throws {
        logger.info("[InventoryViewModel] Submitting inventory adjustment: variation=\(variationId), qty=\(quantity), reason=\(reason.displayName)")

        do {
            let counts = try await inventoryService.submitInventoryAdjustment(
                variationId: variationId,
                locationId: locationId,
                quantity: quantity,
                reason: reason
            )

            // Update database - SwiftData @Query views will auto-update!
            let db = databaseManager.getContext()
            for countData in counts {
                _ = InventoryCountModel.createOrUpdate(from: countData, in: db)
            }
            try db.save()

            // Mark inventory as enabled on successful adjustment
            await MainActor.run {
                SquareCapabilitiesService.shared.markInventoryAsEnabled()
            }

        } catch {
            // Update capability flag on error
            await MainActor.run {
                SquareCapabilitiesService.shared.markInventoryAsDisabled(error: error)
            }
            throw error
        }
    }

    /// Set initial inventory for newly created item
    /// Called after item creation to use newly assigned variation IDs
    private func setInitialInventoryForNewItem(savedObject: CatalogObject, originalVariations: [ItemDetailsVariationData]) async throws {
        guard let itemData = savedObject.itemData,
              let savedVariations = itemData.variations else {
            return
        }

        logger.info("[InventoryViewModel] Setting initial inventory for new item variations")

        let inventoryService = SquareAPIServiceFactory.createInventoryService()

        // Match saved variations (with IDs) to original variations (with pending inventory)
        for (index, savedVariation) in savedVariations.enumerated() {
            guard index < originalVariations.count else { continue }
            guard let variationId = savedVariation.id else { continue }

            let originalVariation = originalVariations[index]

            // Process pending inventory for each location
            for (locationId, quantity) in originalVariation.pendingInventoryQty {
                guard quantity > 0 else { continue }

                do {
                    logger.info("[InventoryViewModel] Setting initial stock: variation=\(variationId), location=\(locationId), qty=\(quantity)")

                    let counts = try await inventoryService.setInitialStock(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: quantity
                    )

                    // Update database - SwiftData @Query views will auto-update!
                    let db = databaseManager.getContext()
                    for countData in counts {
                        _ = InventoryCountModel.createOrUpdate(from: countData, in: db)
                    }
                    try db.save()

                    logger.info("[InventoryViewModel] ✅ Initial stock set successfully")
                } catch {
                    logger.error("[InventoryViewModel] ⚠️ Failed to set initial stock for variation \(variationId): \(error)")
                    // Continue with other variations even if one fails
                }
            }
        }
    }

    /// Upload pending images for newly created item
    /// Called after item creation to use newly assigned item/variation IDs
    /// Similar to setInitialInventoryForNewItem pattern
    private func uploadPendingImagesForNewItem(savedObject: CatalogObject, originalItemData: ItemDetailsData) async throws {
        let itemId = savedObject.id
        logger.info("[ImageUpload] Uploading pending images for new item: \(itemId)")

        let imageService = SimpleImageService.shared

        // 1. Upload item-level pending images
        if !self.staticData.pendingImages.isEmpty {
            logger.info("[ImageUpload] Uploading \(self.staticData.pendingImages.count) item-level images")
            var uploadedImageIds: [String] = []

            for (index, pendingImage) in self.staticData.pendingImages.enumerated() {
                do {
                    let (imageId, _) = try await imageService.uploadImageWithId(
                        imageData: pendingImage.imageData,
                        fileName: pendingImage.fileName,
                        itemId: itemId
                    )

                    uploadedImageIds.append(imageId)
                    logger.info("[ImageUpload] ✅ Uploaded item image \(index + 1)/\(self.staticData.pendingImages.count): \(imageId)")
                } catch {
                    logger.error("[ImageUpload] ⚠️ Failed to upload item image \(index + 1): \(error)")
                    // Continue with other images even if one fails
                }
            }

            // Update item's imageIds via Square API to establish proper relationships
            if !uploadedImageIds.isEmpty {
                logger.info("[ImageUpload] Attaching \(uploadedImageIds.count) images to item")
                // Images are already attached during upload via Square API
                // Update local state
                await MainActor.run {
                    self.staticData.imageIds = uploadedImageIds
                    self.staticData.pendingImages.removeAll()
                }
            }
        }

        // 2. Upload variation-level pending images
        guard let itemData = savedObject.itemData,
              let savedVariations = itemData.variations else {
            return
        }

        for (index, savedVariation) in savedVariations.enumerated() {
            guard index < originalItemData.variations.count else { continue }
            guard let variationId = savedVariation.id else { continue }

            let originalVariation = originalItemData.variations[index]

            if !originalVariation.pendingImages.isEmpty {
                logger.info("[ImageUpload] Uploading \(originalVariation.pendingImages.count) images for variation \(index + 1)")
                var uploadedImageIds: [String] = []

                for (imageIndex, pendingImage) in originalVariation.pendingImages.enumerated() {
                    do {
                        let (imageId, _) = try await imageService.uploadImageWithId(
                            imageData: pendingImage.imageData,
                            fileName: pendingImage.fileName,
                            itemId: variationId
                        )

                        uploadedImageIds.append(imageId)
                        logger.info("[ImageUpload] ✅ Uploaded variation image \(imageIndex + 1)/\(originalVariation.pendingImages.count): \(imageId)")
                    } catch {
                        logger.error("[ImageUpload] ⚠️ Failed to upload variation image: \(error)")
                        // Continue with other images
                    }
                }

                // Update local variation state
                if !uploadedImageIds.isEmpty {
                    await MainActor.run {
                        if index < self.variations.count {
                            self.variations[index].imageIds = uploadedImageIds
                            self.variations[index].pendingImages.removeAll()
                        }
                    }
                }
            }
        }

        logger.info("[ImageUpload] ✅ Completed uploading all pending images")
    }

    // MARK: - Image Helper Methods

    /// Refresh item data from Square API (used when CRUD operations fail to revert local state)
    func refreshFromSquare() async {
        guard let itemId = staticData.id, !itemId.isEmpty else {
            logger.warning("Cannot refresh: no item ID")
            return
        }

        do {
            let squareAPIService = SquareAPIServiceFactory.createService()
            let catalogObject = try await squareAPIService.fetchCatalogObjectById(itemId)

            await MainActor.run {
                // Update from fresh Square data
                if let itemData = catalogObject.itemData {
                    self.staticData.imageIds = itemData.imageIds ?? []
                }
                logger.info("Successfully refreshed item data from Square")
            }
        } catch {
            logger.error("Failed to refresh from Square: \(error)")
        }
    }

}
