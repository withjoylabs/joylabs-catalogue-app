import Foundation
import os.log

/// Utility class for transforming data between database models and UI models
class ItemDataTransformers {
    private static let logger = Logger(subsystem: "com.joylabs.native", category: "ItemDataTransformers")
    
    // MARK: - Database to UI Transformations
    
    /// Transform a CatalogObject from database to ItemDetailsData for UI
    static func transformCatalogObjectToItemDetails(_ catalogObject: CatalogObject, teamData: TeamData? = nil) -> ItemDetailsData {
        logger.info("Transforming CatalogObject to ItemDetailsData: \(catalogObject.id)")
        
        var itemDetails = ItemDetailsData()
        
        // Basic identification
        itemDetails.id = catalogObject.id
        itemDetails.version = catalogObject.version
        itemDetails.updatedAt = catalogObject.updatedAt
        itemDetails.isDeleted = catalogObject.isDeleted
        itemDetails.presentAtAllLocations = catalogObject.presentAtAllLocations ?? true
        
        // Extract item data
        if let itemData = catalogObject.itemData {
            // Basic information
            itemDetails.name = itemData.name ?? ""
            itemDetails.description = itemData.description ?? ""
            itemDetails.abbreviation = itemData.abbreviation ?? ""
            itemDetails.labelColor = itemData.labelColor
            
            // Product classification
            itemDetails.productType = transformProductType(itemData.productType)
            itemDetails.categoryId = itemData.categoryId
            
            // Transform variations
            itemDetails.variations = transformVariations(itemData.variations ?? [])
            
            // Availability and visibility
            itemDetails.availableOnline = itemData.availableOnline ?? false
            itemDetails.availableForPickup = itemData.availableForPickup ?? false
            itemDetails.skipModifierScreen = itemData.skipModifierScreen ?? false
            
            // Modifier lists
            itemDetails.modifierListInfo = transformModifierListInfo(itemData.modifierListInfo ?? [])
            
            // Tax information
            itemDetails.taxIds = itemData.taxIds ?? []
            
            // Images
            itemDetails.imageIds = itemData.imageIds ?? []
            
            // Inventory tracking
            itemDetails.trackInventory = itemData.trackInventory ?? false
            itemDetails.inventoryAlertType = transformInventoryAlertType(itemData.inventoryAlertType)
            itemDetails.inventoryAlertThreshold = itemData.inventoryAlertThreshold
            
            // E-commerce
            itemDetails.ecomVisibility = transformEcomVisibility(itemData.ecomVisibility)
            itemDetails.ecomSeoData = transformEcomSeoData(itemData.ecomSeoData)
            
            // Measurement and units
            itemDetails.measurementUnitId = itemData.measurementUnitId
            itemDetails.sellable = itemData.sellable ?? true
            itemDetails.stockable = itemData.stockable ?? true
        }
        
        // Add team data if available
        if let teamData = teamData {
            itemDetails.teamData = ItemDetailsTeamData(
                caseUpc: teamData.caseUpc ?? "",
                caseCost: teamData.caseCost ?? 0.0,
                caseQuantity: teamData.caseQuantity ?? 1,
                vendor: teamData.vendor ?? "",
                discontinued: teamData.discontinued,
                notes: teamData.notes ?? ""
            )
        }
        
        logger.info("Successfully transformed CatalogObject to ItemDetailsData")
        return itemDetails
    }
    
    // MARK: - UI to Database Transformations
    
    /// Transform ItemDetailsData from UI to CatalogObject for database/API
    static func transformItemDetailsToCatalogObject(_ itemDetails: ItemDetailsData) -> CatalogObject {
        logger.info("Transforming ItemDetailsData to CatalogObject: \(itemDetails.id ?? "new")")
        
        // Create item data
        let itemData = ItemData(
            name: itemDetails.name.isEmpty ? nil : itemDetails.name,
            description: itemDetails.description.isEmpty ? nil : itemDetails.description,
            abbreviation: itemDetails.abbreviation.isEmpty ? nil : itemDetails.abbreviation,
            labelColor: itemDetails.labelColor,
            categoryId: itemDetails.categoryId,
            taxIds: itemDetails.taxIds.isEmpty ? nil : itemDetails.taxIds,
            variations: transformVariationsToAPI(itemDetails.variations),
            productType: transformProductTypeToAPI(itemDetails.productType),
            skipModifierScreen: itemDetails.skipModifierScreen,
            modifierListInfo: transformModifierListInfoToAPI(itemDetails.modifierListInfo),
            imageIds: itemDetails.imageIds.isEmpty ? nil : itemDetails.imageIds,
            trackInventory: itemDetails.trackInventory,
            inventoryAlertType: transformInventoryAlertTypeToAPI(itemDetails.inventoryAlertType),
            inventoryAlertThreshold: itemDetails.inventoryAlertThreshold,
            availableOnline: itemDetails.availableOnline,
            availableForPickup: itemDetails.availableForPickup,
            ecomVisibility: transformEcomVisibilityToAPI(itemDetails.ecomVisibility),
            ecomSeoData: transformEcomSeoDataToAPI(itemDetails.ecomSeoData),
            measurementUnitId: itemDetails.measurementUnitId,
            sellable: itemDetails.sellable,
            stockable: itemDetails.stockable
        )
        
        // Create catalog object
        let catalogObject = CatalogObject(
            id: itemDetails.id ?? UUID().uuidString,
            type: "ITEM",
            updatedAt: itemDetails.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
            version: itemDetails.version ?? 1,
            isDeleted: itemDetails.isDeleted,
            presentAtAllLocations: itemDetails.presentAtAllLocations,
            itemData: itemData,
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil,
            imageData: nil
        )
        
        logger.info("Successfully transformed ItemDetailsData to CatalogObject")
        return catalogObject
    }
    
    // MARK: - Helper Transformation Methods
    
    private static func transformVariations(_ variations: [ItemVariationData]) -> [ItemDetailsVariationData] {
        return variations.map { variation in
            var variationData = ItemDetailsVariationData()
            variationData.variationId = variation.id
            variationData.name = variation.name ?? ""
            variationData.sku = variation.sku ?? ""
            variationData.upc = variation.upc ?? ""
            variationData.ordinal = variation.ordinal ?? 0
            variationData.pricingType = transformPricingType(variation.pricingType)
            variationData.priceMoney = transformMoney(variation.priceMoney)
            variationData.trackInventory = variation.trackInventory ?? false
            variationData.inventoryAlertType = transformInventoryAlertType(variation.inventoryAlertType)
            variationData.inventoryAlertThreshold = variation.inventoryAlertThreshold
            variationData.stockOnHand = variation.stockOnHand ?? 0
            return variationData
        }
    }
    
    private static func transformVariationsToAPI(_ variations: [ItemDetailsVariationData]) -> [ItemVariationData]? {
        guard !variations.isEmpty else { return nil }
        
        return variations.map { variation in
            ItemVariationData(
                id: variation.variationId,
                name: variation.name.isEmpty ? nil : variation.name,
                sku: variation.sku.isEmpty ? nil : variation.sku,
                upc: variation.upc.isEmpty ? nil : variation.upc,
                ordinal: variation.ordinal,
                pricingType: transformPricingTypeToAPI(variation.pricingType),
                priceMoney: transformMoneyToAPI(variation.priceMoney),
                basePriceMoney: nil,
                defaultUnitCost: nil,
                trackInventory: variation.trackInventory,
                inventoryAlertType: transformInventoryAlertTypeToAPI(variation.inventoryAlertType),
                inventoryAlertThreshold: variation.inventoryAlertThreshold,
                stockOnHand: variation.stockOnHand,
                serviceDuration: nil,
                availableForBooking: nil,
                itemOptionValues: nil,
                measurementUnitId: nil,
                sellable: nil,
                stockable: nil,
                teamMemberIds: nil,
                stockableConversion: nil,
                itemId: nil,
                version: nil,
                isDeleted: nil,
                presentAtAllLocations: nil,
                presentAtLocationIds: nil,
                absentAtLocationIds: nil,
                locationOverrides: nil
            )
        }
    }
    
    private static func transformMoney(_ money: Money?) -> ItemDetailsMoney? {
        guard let money = money else { return nil }
        return ItemDetailsMoney(
            amount: money.amount ?? 0,
            currency: money.currency ?? "USD"
        )
    }
    
    private static func transformMoneyToAPI(_ money: ItemDetailsMoney?) -> Money? {
        guard let money = money else { return nil }
        return Money(amount: money.amount, currency: money.currency)
    }
    
    private static func transformProductType(_ productType: String?) -> ProductType {
        switch productType {
        case "APPOINTMENTS_SERVICE": return .appointmentsService
        case "RETAIL": return .retail
        default: return .regular
        }
    }
    
    private static func transformProductTypeToAPI(_ productType: ProductType) -> String? {
        switch productType {
        case .appointmentsService: return "APPOINTMENTS_SERVICE"
        case .retail: return "RETAIL"
        case .regular: return nil
        }
    }
    
    private static func transformPricingType(_ pricingType: String?) -> PricingType {
        switch pricingType {
        case "VARIABLE_PRICING": return .variablePricing
        default: return .fixedPricing
        }
    }
    
    private static func transformPricingTypeToAPI(_ pricingType: PricingType) -> String? {
        switch pricingType {
        case .variablePricing: return "VARIABLE_PRICING"
        case .fixedPricing: return "FIXED_PRICING"
        }
    }
    
    private static func transformInventoryAlertType(_ alertType: String?) -> InventoryAlertType {
        switch alertType {
        case "LOW_QUANTITY": return .lowQuantity
        default: return .none
        }
    }
    
    private static func transformInventoryAlertTypeToAPI(_ alertType: InventoryAlertType) -> String? {
        switch alertType {
        case .lowQuantity: return "LOW_QUANTITY"
        case .none: return "NONE"
        }
    }
    
    private static func transformEcomVisibility(_ visibility: String?) -> EcomVisibility {
        switch visibility {
        case "HIDDEN": return .hidden
        case "PUBLIC": return .public
        default: return .unindexed
        }
    }
    
    private static func transformEcomVisibilityToAPI(_ visibility: EcomVisibility) -> String? {
        switch visibility {
        case .hidden: return "HIDDEN"
        case .public: return "PUBLIC"
        case .unindexed: return "UNINDEXED"
        }
    }
    
    private static func transformModifierListInfo(_ modifierListInfo: [ModifierListInfo]) -> [ItemDetailsModifierListInfo] {
        return modifierListInfo.map { info in
            ItemDetailsModifierListInfo(
                modifierListId: info.modifierListId ?? "",
                minSelectedModifiers: info.minSelectedModifiers ?? 0,
                maxSelectedModifiers: info.maxSelectedModifiers,
                enabled: info.enabled ?? true,
                ordinal: info.ordinal ?? 0
            )
        }
    }
    
    private static func transformModifierListInfoToAPI(_ modifierListInfo: [ItemDetailsModifierListInfo]) -> [ModifierListInfo]? {
        guard !modifierListInfo.isEmpty else { return nil }
        
        return modifierListInfo.map { info in
            ModifierListInfo(
                modifierListId: info.modifierListId,
                minSelectedModifiers: info.minSelectedModifiers,
                maxSelectedModifiers: info.maxSelectedModifiers,
                enabled: info.enabled,
                ordinal: info.ordinal
            )
        }
    }
    
    private static func transformEcomSeoData(_ seoData: EcomSeoData?) -> ItemDetailsEcomSeoData? {
        guard let seoData = seoData else { return nil }
        return ItemDetailsEcomSeoData(
            pageTitle: seoData.pageTitle ?? "",
            pageDescription: seoData.pageDescription ?? "",
            permalink: seoData.permalink ?? ""
        )
    }
    
    private static func transformEcomSeoDataToAPI(_ seoData: ItemDetailsEcomSeoData?) -> EcomSeoData? {
        guard let seoData = seoData else { return nil }
        return EcomSeoData(
            pageTitle: seoData.pageTitle.isEmpty ? nil : seoData.pageTitle,
            pageDescription: seoData.pageDescription.isEmpty ? nil : seoData.pageDescription,
            permalink: seoData.permalink.isEmpty ? nil : seoData.permalink
        )
    }
}
