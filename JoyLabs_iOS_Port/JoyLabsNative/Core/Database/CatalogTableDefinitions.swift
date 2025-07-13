import Foundation
import SQLite
import os.log

/// Centralized table and column definitions for the catalog database
/// This keeps all schema definitions in one place for maintainability
class CatalogTableDefinitions {
    
    // MARK: - Categories Table
    static let categories = Table("categories")
    static let categoryId = Expression<String>("id")
    static let categoryName = Expression<String?>("name")
    static let categoryImageUrl = Expression<String?>("image_url")
    static let categoryIsDeleted = Expression<Bool>("is_deleted")
    static let categoryUpdatedAt = Expression<String>("updated_at")
    static let categoryVersion = Expression<String>("version")
    static let categoryDataJson = Expression<String?>("data_json")
    
    // MARK: - Items Table
    static let catalogItems = Table("catalog_items")
    static let itemId = Expression<String>("id")
    static let itemName = Expression<String?>("name")
    static let itemDescription = Expression<String?>("description")
    static let itemCategoryId = Expression<String?>("category_id")
    static let itemIsDeleted = Expression<Bool>("is_deleted")
    static let itemUpdatedAt = Expression<String>("updated_at")
    static let itemVersion = Expression<String>("version")
    static let itemDataJson = Expression<String?>("data_json")
    
    // MARK: - Item Variations Table
    static let itemVariations = Table("item_variations")
    static let variationId = Expression<String>("id")
    static let variationItemId = Expression<String>("item_id")
    static let variationName = Expression<String?>("name")
    static let variationSku = Expression<String?>("sku")
    static let variationUpc = Expression<String?>("upc")
    static let variationOrdinal = Expression<Int64?>("ordinal")
    static let variationPricingType = Expression<String?>("pricing_type")
    static let variationPriceAmount = Expression<Int64?>("price_amount")
    static let variationPriceCurrency = Expression<String?>("price_currency")
    static let variationIsDeleted = Expression<Bool>("is_deleted")
    static let variationUpdatedAt = Expression<String>("updated_at")
    static let variationVersion = Expression<String>("version")
    static let variationDataJson = Expression<String?>("data_json")
    
    // MARK: - Taxes Table
    static let taxes = Table("taxes")
    static let taxId = Expression<String>("id")
    static let taxUpdatedAt = Expression<String>("updated_at")
    static let taxVersion = Expression<String>("version")
    static let taxIsDeleted = Expression<Bool>("is_deleted")
    static let taxName = Expression<String?>("name")
    static let taxCalculationPhase = Expression<String?>("calculation_phase")
    static let taxInclusionType = Expression<String?>("inclusion_type")
    static let taxPercentage = Expression<String?>("percentage")
    static let taxAppliesToCustomAmounts = Expression<Bool?>("applies_to_custom_amounts")
    static let taxEnabled = Expression<Bool?>("enabled")
    static let taxDataJson = Expression<String?>("data_json")

    // MARK: - Modifiers Table
    static let modifiers = Table("modifiers")
    static let modifierId = Expression<String>("id")
    static let modifierUpdatedAt = Expression<String>("updated_at")
    static let modifierVersion = Expression<String>("version")
    static let modifierIsDeleted = Expression<Bool>("is_deleted")
    static let modifierName = Expression<String?>("name")
    static let modifierListId = Expression<String?>("modifier_list_id")
    static let modifierPriceAmount = Expression<Int64?>("price_amount")
    static let modifierPriceCurrency = Expression<String?>("price_currency")
    static let modifierOrdinal = Expression<Int64?>("ordinal")
    static let modifierOnByDefault = Expression<Bool?>("on_by_default")
    static let modifierDataJson = Expression<String?>("data_json")

    // MARK: - Modifier Lists Table
    static let modifierLists = Table("modifier_lists")
    static let modifierListPrimaryId = Expression<String>("id")
    static let modifierListUpdatedAt = Expression<String>("updated_at")
    static let modifierListVersion = Expression<String>("version")
    static let modifierListIsDeleted = Expression<Bool>("is_deleted")
    static let modifierListName = Expression<String?>("name")
    static let modifierListSelectionType = Expression<String?>("selection_type")
    static let modifierListOrdinal = Expression<Int64?>("ordinal")
    static let modifierListDataJson = Expression<String?>("data_json")
    
    // MARK: - Discounts Table
    static let discounts = Table("discounts")
    static let discountId = Expression<String>("id")
    static let discountName = Expression<String?>("name")
    static let discountIsDeleted = Expression<Bool>("is_deleted")
    static let discountUpdatedAt = Expression<String>("updated_at")
    static let discountVersion = Expression<String>("version")
    static let discountDataJson = Expression<String?>("data_json")
    
    // MARK: - Images Table
    static let images = Table("images")
    static let imageId = Expression<String>("id")
    static let imageName = Expression<String?>("name")
    static let imageUrl = Expression<String?>("url")
    static let imageCaption = Expression<String?>("caption")
    static let imageIsDeleted = Expression<Bool>("is_deleted")
    static let imageUpdatedAt = Expression<String>("updated_at")
    static let imageVersion = Expression<String>("version")
    static let imageDataJson = Expression<String?>("data_json")
    
    // MARK: - Team Data Table (AppSync Integration)
    static let teamData = Table("team_data")
    static let teamDataItemId = Expression<String>("item_id")
    static let teamCaseUpc = Expression<String?>("case_upc")
    static let teamCaseCost = Expression<Double?>("case_cost")
    static let teamCaseQuantity = Expression<Int64?>("case_quantity")
    static let teamVendor = Expression<String?>("vendor")
    static let teamDiscontinued = Expression<Bool>("discontinued")
    static let teamNotes = Expression<String?>("notes")
    static let teamCreatedAt = Expression<String>("created_at")
    static let teamUpdatedAt = Expression<String>("updated_at")
    static let teamLastSyncAt = Expression<String?>("last_sync_at")
    static let teamOwner = Expression<String?>("owner")
    
    // MARK: - Sync Status Table
    static let syncStatus = Table("sync_status")
    static let syncKey = Expression<String>("key")
    static let syncValue = Expression<String>("value")
    static let syncUpdatedAt = Expression<String>("updated_at")
}
