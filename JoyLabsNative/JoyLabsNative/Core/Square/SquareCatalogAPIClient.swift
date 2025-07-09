import Foundation

/// Direct Square Catalog API client for efficient catalog sync
/// Implements direct HTTP calls to Square API endpoints for 18,000+ item catalogs
/// Based on Square API documentation: https://developer.squareup.com/reference/square/catalog-api
class SquareCatalogAPIClient {
    
    // MARK: - Configuration
    
    private let baseURL = "https://connect.squareup.com"
    private let session: URLSession
    private let accessToken: String
    
    // MARK: - API Response Models
    
    struct SearchCatalogObjectsRequest: Codable {
        let objectTypes: [String]
        let includeRelatedObjects: Bool
        let includeDeletedObjects: Bool
        let beginTime: String?
        let query: CatalogQuery?
        let limit: Int
        let cursor: String?
        
        enum CodingKeys: String, CodingKey {
            case objectTypes = "object_types"
            case includeRelatedObjects = "include_related_objects"
            case includeDeletedObjects = "include_deleted_objects"
            case beginTime = "begin_time"
            case query
            case limit
            case cursor
        }
    }
    
    struct CatalogQuery: Codable {
        let sortedAttributeQuery: CatalogQuerySortedAttribute?
        
        enum CodingKeys: String, CodingKey {
            case sortedAttributeQuery = "sorted_attribute_query"
        }
    }
    
    struct CatalogQuerySortedAttribute: Codable {
        let attributeName: String
        let initialAttributeValue: String?
        let sortOrder: String
        
        enum CodingKeys: String, CodingKey {
            case attributeName = "attribute_name"
            case initialAttributeValue = "initial_attribute_value"
            case sortOrder = "sort_order"
        }
    }
    
    struct SearchCatalogObjectsResponse: Codable {
        let objects: [CatalogObject]?
        let relatedObjects: [CatalogObject]?
        let cursor: String?
        let errors: [SquareError]?
    }
    
    struct CatalogObject: Codable {
        let type: String
        let id: String
        let updatedAt: String?
        let createdAt: String?
        let version: Int?
        let isDeleted: Bool?
        let presentAtAllLocations: Bool?
        let presentAtLocationIds: [String]?
        let absentAtLocationIds: [String]?
        let customAttributeValues: [String: CatalogCustomAttributeValue]?
        
        // Object-specific data
        let itemData: CatalogItem?
        let itemVariationData: CatalogItemVariation?
        let categoryData: CatalogCategory?
        let imageData: CatalogImage?
        let taxData: CatalogTax?
        let discountData: CatalogDiscount?
        let modifierListData: CatalogModifierList?
        let modifierData: CatalogModifier?
        
        enum CodingKeys: String, CodingKey {
            case type, id, version
            case updatedAt = "updated_at"
            case createdAt = "created_at"
            case isDeleted = "is_deleted"
            case presentAtAllLocations = "present_at_all_locations"
            case presentAtLocationIds = "present_at_location_ids"
            case absentAtLocationIds = "absent_at_location_ids"
            case customAttributeValues = "custom_attribute_values"
            case itemData = "item_data"
            case itemVariationData = "item_variation_data"
            case categoryData = "category_data"
            case imageData = "image_data"
            case taxData = "tax_data"
            case discountData = "discount_data"
            case modifierListData = "modifier_list_data"
            case modifierData = "modifier_data"
        }
    }
    
    struct CatalogCustomAttributeValue: Codable {
        let name: String?
        let stringValue: String?
        let numberValue: String?
        let booleanValue: Bool?
        let selectionUidValues: [String]?
        let key: String?
        
        enum CodingKeys: String, CodingKey {
            case name
            case stringValue = "string_value"
            case numberValue = "number_value"
            case booleanValue = "boolean_value"
            case selectionUidValues = "selection_uid_values"
            case key
        }
    }
    
    struct CatalogItem: Codable {
        let name: String?
        let description: String?
        let descriptionHtml: String?
        let descriptionPlaintext: String?
        let abbreviation: String?
        let labelColor: String?
        let isTaxable: Bool?
        let categoryId: String?
        let taxIds: [String]?
        let modifierListInfo: [CatalogItemModifierListInfo]?
        let variations: [CatalogObject]?
        let productType: String?
        let skipModifierScreen: Bool?
        let itemOptions: [CatalogItemOptionForItem]?
        let imageIds: [String]?
        let sortName: String?
        let categories: [CatalogObjectCategory]?
        let channels: [String]?
        let isArchived: Bool?
        let ecomSeoData: CatalogEcomSeoData?
        let foodAndBeverageDetails: CatalogItemFoodAndBeverageDetails?
        let reportingCategory: CatalogObjectCategory?
        let isAlcoholic: Bool?
        
        enum CodingKeys: String, CodingKey {
            case name, description, abbreviation, variations, channels
            case descriptionHtml = "description_html"
            case descriptionPlaintext = "description_plaintext"
            case labelColor = "label_color"
            case isTaxable = "is_taxable"
            case categoryId = "category_id"
            case taxIds = "tax_ids"
            case modifierListInfo = "modifier_list_info"
            case productType = "product_type"
            case skipModifierScreen = "skip_modifier_screen"
            case itemOptions = "item_options"
            case imageIds = "image_ids"
            case sortName = "sort_name"
            case categories
            case isArchived = "is_archived"
            case ecomSeoData = "ecom_seo_data"
            case foodAndBeverageDetails = "food_and_beverage_details"
            case reportingCategory = "reporting_category"
            case isAlcoholic = "is_alcoholic"
        }
    }
    
    struct CatalogItemModifierListInfo: Codable {
        let modifierListId: String
        let modifierOverrides: [CatalogModifierOverride]?
        let minSelectedModifiers: Int?
        let maxSelectedModifiers: Int?
        let enabled: Bool?
        let ordinal: Int?
        
        enum CodingKeys: String, CodingKey {
            case modifierListId = "modifier_list_id"
            case modifierOverrides = "modifier_overrides"
            case minSelectedModifiers = "min_selected_modifiers"
            case maxSelectedModifiers = "max_selected_modifiers"
            case enabled, ordinal
        }
    }
    
    struct CatalogModifierOverride: Codable {
        let modifierId: String
        let onByDefault: Bool?
        
        enum CodingKeys: String, CodingKey {
            case modifierId = "modifier_id"
            case onByDefault = "on_by_default"
        }
    }
    
    struct CatalogItemOptionForItem: Codable {
        let itemOptionId: String?
        
        enum CodingKeys: String, CodingKey {
            case itemOptionId = "item_option_id"
        }
    }
    
    struct CatalogObjectCategory: Codable {
        let id: String?
        let ordinal: Int?
        
        enum CodingKeys: String, CodingKey {
            case id, ordinal
        }
    }
    
    struct CatalogEcomSeoData: Codable {
        let pageTitle: String?
        let pageDescription: String?
        let permalink: String?
        
        enum CodingKeys: String, CodingKey {
            case pageTitle = "page_title"
            case pageDescription = "page_description"
            case permalink
        }
    }
    
    struct CatalogItemFoodAndBeverageDetails: Codable {
        let caloricRating: String?
        let dietaryPreferences: [CatalogItemFoodAndBeverageDetailsDietaryPreference]?
        let ingredients: [CatalogItemFoodAndBeverageDetailsIngredient]?
        
        enum CodingKeys: String, CodingKey {
            case caloricRating = "caloric_rating"
            case dietaryPreferences = "dietary_preferences"
            case ingredients
        }
    }
    
    struct CatalogItemFoodAndBeverageDetailsDietaryPreference: Codable {
        let type: String?
        let standardName: String?
        let customName: String?
        
        enum CodingKeys: String, CodingKey {
            case type
            case standardName = "standard_name"
            case customName = "custom_name"
        }
    }
    
    struct CatalogItemFoodAndBeverageDetailsIngredient: Codable {
        let type: String?
        let standardName: String?
        let customName: String?
        
        enum CodingKeys: String, CodingKey {
            case type
            case standardName = "standard_name"
            case customName = "custom_name"
        }
    }
    

    
    // MARK: - Initialization
    
    init(accessToken: String) {
        self.accessToken = accessToken
        self.session = URLSession(configuration: .default)
    }

    // MARK: - API Methods

    /// Search catalog objects with pagination support
    /// Implements: POST /v2/catalog/search
    func searchCatalogObjects(
        objectTypes: [String] = ["ITEM", "ITEM_VARIATION", "CATEGORY", "TAX", "DISCOUNT", "MODIFIER_LIST", "MODIFIER", "IMAGE"],
        includeRelatedObjects: Bool = true,
        includeDeletedObjects: Bool = true,
        beginTime: String? = nil,
        limit: Int = 1000,
        cursor: String? = nil
    ) async throws -> SearchCatalogObjectsResponse {

        let url = URL(string: "\(baseURL)/v2/catalog/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Create query for sorted results by updated_at
        let sortQuery = CatalogQuerySortedAttribute(
            attributeName: "updated_at",
            initialAttributeValue: beginTime,
            sortOrder: "ASC"
        )

        let query = CatalogQuery(sortedAttributeQuery: sortQuery)

        let requestBody = SearchCatalogObjectsRequest(
            objectTypes: objectTypes,
            includeRelatedObjects: includeRelatedObjects,
            includeDeletedObjects: includeDeletedObjects,
            beginTime: beginTime,
            query: query,
            limit: limit,
            cursor: cursor
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SquareCatalogError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SquareCatalogError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(SearchCatalogObjectsResponse.self, from: data)

        if let errors = searchResponse.errors, !errors.isEmpty {
            throw SquareCatalogError.squareAPIError(errors)
        }

        return searchResponse
    }

    /// Perform full catalog sync with pagination
    func performFullCatalogSync() -> AsyncThrowingStream<CatalogSyncProgress, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var cursor: String? = nil
                    var totalObjects = 0
                    var syncedObjects = 0

                    repeat {
                        let response = try await searchCatalogObjects(cursor: cursor)

                        if let objects = response.objects {
                            totalObjects += objects.count

                            // Process objects in batches
                            for object in objects {
                                // Yield progress
                                syncedObjects += 1
                                let progress = CatalogSyncProgress(
                                    totalObjects: totalObjects,
                                    syncedObjects: syncedObjects,
                                    currentObject: object,
                                    cursor: cursor
                                )
                                continuation.yield(progress)
                            }
                        }

                        if let relatedObjects = response.relatedObjects {
                            totalObjects += relatedObjects.count

                            for object in relatedObjects {
                                syncedObjects += 1
                                let progress = CatalogSyncProgress(
                                    totalObjects: totalObjects,
                                    syncedObjects: syncedObjects,
                                    currentObject: object,
                                    cursor: cursor
                                )
                                continuation.yield(progress)
                            }
                        }

                        cursor = response.cursor

                    } while cursor != nil

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Perform incremental catalog sync since last sync time
    func performIncrementalCatalogSync(since: String) -> AsyncThrowingStream<CatalogSyncProgress, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var cursor: String? = nil
                    var totalObjects = 0
                    var syncedObjects = 0

                    repeat {
                        let response = try await searchCatalogObjects(
                            beginTime: since,
                            cursor: cursor
                        )

                        if let objects = response.objects {
                            totalObjects += objects.count

                            for object in objects {
                                syncedObjects += 1
                                let progress = CatalogSyncProgress(
                                    totalObjects: totalObjects,
                                    syncedObjects: syncedObjects,
                                    currentObject: object,
                                    cursor: cursor
                                )
                                continuation.yield(progress)
                            }
                        }

                        if let relatedObjects = response.relatedObjects {
                            totalObjects += relatedObjects.count

                            for object in relatedObjects {
                                syncedObjects += 1
                                let progress = CatalogSyncProgress(
                                    totalObjects: totalObjects,
                                    syncedObjects: syncedObjects,
                                    currentObject: object,
                                    cursor: cursor
                                )
                                continuation.yield(progress)
                            }
                        }

                        cursor = response.cursor

                    } while cursor != nil

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Progress information for catalog sync operations
struct CatalogSyncProgress {
    let totalObjects: Int
    let syncedObjects: Int
    let currentObject: SquareCatalogAPIClient.CatalogObject
    let cursor: String?

    var progressPercentage: Double {
        guard totalObjects > 0 else { return 0.0 }
        return Double(syncedObjects) / Double(totalObjects)
    }
}

/// Errors that can occur during catalog sync
enum SquareCatalogError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case squareAPIError([SquareError])
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Square API"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .squareAPIError(let errors):
            return "Square API error: \(errors.first?.detail ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Additional Catalog Object Types

extension SquareCatalogAPIClient {

    struct CatalogItemVariation: Codable {
        let itemId: String?
        let name: String?
        let sku: String?
        let upc: String?
        let ordinal: Int?
        let pricingType: String?
        let priceMoney: Money?
        let locationOverrides: [ItemVariationLocationOverrides]?
        let trackInventory: Bool?
        let inventoryAlertType: String?
        let inventoryAlertThreshold: Int?
        let userData: String?
        let serviceDuration: Int?
        let availableForBooking: Bool?
        let itemOptionValues: [CatalogItemOptionValueForItemVariation]?
        let measurementUnitId: String?
        let sellable: Bool?
        let stockable: Bool?
        let imageIds: [String]?
        let teamMemberIds: [String]?
        let stockableConversion: CatalogStockConversion?

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case name, sku, upc, ordinal
            case pricingType = "pricing_type"
            case priceMoney = "price_money"
            case locationOverrides = "location_overrides"
            case trackInventory = "track_inventory"
            case inventoryAlertType = "inventory_alert_type"
            case inventoryAlertThreshold = "inventory_alert_threshold"
            case userData = "user_data"
            case serviceDuration = "service_duration"
            case availableForBooking = "available_for_booking"
            case itemOptionValues = "item_option_values"
            case measurementUnitId = "measurement_unit_id"
            case sellable, stockable
            case imageIds = "image_ids"
            case teamMemberIds = "team_member_ids"
            case stockableConversion = "stockable_conversion"
        }
    }

    struct Money: Codable {
        let amount: Int?
        let currency: String?
    }

    struct ItemVariationLocationOverrides: Codable {
        let locationId: String?
        let priceMoney: Money?
        let pricingType: String?
        let trackInventory: Bool?
        let inventoryAlertType: String?
        let inventoryAlertThreshold: Int?
        let soldOut: Bool?
        let soldOutValidUntil: String?

        enum CodingKeys: String, CodingKey {
            case locationId = "location_id"
            case priceMoney = "price_money"
            case pricingType = "pricing_type"
            case trackInventory = "track_inventory"
            case inventoryAlertType = "inventory_alert_type"
            case inventoryAlertThreshold = "inventory_alert_threshold"
            case soldOut = "sold_out"
            case soldOutValidUntil = "sold_out_valid_until"
        }
    }

    struct CatalogItemOptionValueForItemVariation: Codable {
        let itemOptionId: String?
        let itemOptionValueId: String?

        enum CodingKeys: String, CodingKey {
            case itemOptionId = "item_option_id"
            case itemOptionValueId = "item_option_value_id"
        }
    }

    struct CatalogStockConversion: Codable {
        let stockableItemVariationId: String?
        let stockableQuantity: String?
        let nonstockableQuantity: String?

        enum CodingKeys: String, CodingKey {
            case stockableItemVariationId = "stockable_item_variation_id"
            case stockableQuantity = "stockable_quantity"
            case nonstockableQuantity = "nonstockable_quantity"
        }
    }

    struct CatalogCategory: Codable {
        let name: String?
        let imageIds: [String]?
        let categoryType: String?
        let parentCategory: CatalogObjectCategory?
        let isTopLevel: Bool?
        let channels: [String]?
        let availabilityPeriodIds: [String]?
        let onlineVisibility: Bool?
        let rootCategory: String?
        let ecomSeoData: CatalogEcomSeoData?
        let pathToRoot: [CategoryPathToRootNode]?

        enum CodingKeys: String, CodingKey {
            case name
            case imageIds = "image_ids"
            case categoryType = "category_type"
            case parentCategory = "parent_category"
            case isTopLevel = "is_top_level"
            case channels
            case availabilityPeriodIds = "availability_period_ids"
            case onlineVisibility = "online_visibility"
            case rootCategory = "root_category"
            case ecomSeoData = "ecom_seo_data"
            case pathToRoot = "path_to_root"
        }
    }

    struct CategoryPathToRootNode: Codable {
        let categoryId: String?
        let categoryName: String?

        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case categoryName = "category_name"
        }
    }

    struct CatalogImage: Codable {
        let name: String?
        let url: String?
        let caption: String?
        let photoStudioOrderId: String?

        enum CodingKeys: String, CodingKey {
            case name, url, caption
            case photoStudioOrderId = "photo_studio_order_id"
        }
    }

    struct CatalogTax: Codable {
        let name: String?
        let calculationPhase: String?
        let inclusionType: String?
        let percentage: String?
        let appliesToCustomAmounts: Bool?
        let enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case calculationPhase = "calculation_phase"
            case inclusionType = "inclusion_type"
            case percentage
            case appliesToCustomAmounts = "applies_to_custom_amounts"
            case enabled
        }
    }

    struct CatalogDiscount: Codable {
        let name: String?
        let discountType: String?
        let percentage: String?
        let amountMoney: Money?
        let pinRequired: Bool?
        let labelColor: String?
        let modifyTaxBasis: String?
        let maximumAmountMoney: Money?

        enum CodingKeys: String, CodingKey {
            case name
            case discountType = "discount_type"
            case percentage
            case amountMoney = "amount_money"
            case pinRequired = "pin_required"
            case labelColor = "label_color"
            case modifyTaxBasis = "modify_tax_basis"
            case maximumAmountMoney = "maximum_amount_money"
        }
    }

    struct CatalogModifierList: Codable {
        let name: String?
        let ordinal: Int?
        let selectionType: String?
        let modifiers: [CatalogObject]?
        let imageIds: [String]?

        enum CodingKeys: String, CodingKey {
            case name, ordinal, modifiers
            case selectionType = "selection_type"
            case imageIds = "image_ids"
        }
    }

    struct CatalogModifier: Codable {
        let name: String?
        let priceMoney: Money?
        let ordinal: Int?
        let modifierListId: String?
        let locationOverrides: [ModifierLocationOverrides]?
        let imageIds: [String]?

        enum CodingKeys: String, CodingKey {
            case name, ordinal
            case priceMoney = "price_money"
            case modifierListId = "modifier_list_id"
            case locationOverrides = "location_overrides"
            case imageIds = "image_ids"
        }
    }

    struct ModifierLocationOverrides: Codable {
        let locationId: String?
        let priceMoney: Money?
        let soldOut: Bool?
        let soldOutValidUntil: String?

        enum CodingKeys: String, CodingKey {
            case locationId = "location_id"
            case priceMoney = "price_money"
            case soldOut = "sold_out"
            case soldOutValidUntil = "sold_out_valid_until"
        }
    }
}
