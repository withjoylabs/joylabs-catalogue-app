import Foundation

// MARK: - Data Transformation Utilities
// Convert between different data model representations
// Note: Uses existing types from CatalogModels.swift and ItemDetailsViewModel.swift

/// Transforms data between Square API models, database models, and UI models
struct ItemDataTransformers {
    
    // MARK: - Square API to Comprehensive Model
    
    /// Convert Square CatalogObject to ComprehensiveItemData
    static func fromSquareCatalogObject(_ catalogObject: CatalogObject) -> ComprehensiveItemData? {
        guard catalogObject.type == "ITEM",
              let itemData = catalogObject.itemData else {
            return nil
        }
        
        var comprehensive = ComprehensiveItemData()
        
        // Core identification
        comprehensive.id = catalogObject.id
        comprehensive.version = catalogObject.version
        comprehensive.updatedAt = catalogObject.updatedAt
        comprehensive.isDeleted = catalogObject.isDeleted
        comprehensive.presentAtAllLocations = catalogObject.presentAtAllLocations ?? true
        
        // Basic information
        comprehensive.name = itemData.name ?? ""
        comprehensive.description = itemData.description ?? ""
        comprehensive.abbreviation = itemData.abbreviation ?? ""
        comprehensive.labelColor = itemData.labelColor
        comprehensive.sortName = itemData.sortName
        
        // Product classification
        if let productTypeString = itemData.productType {
            comprehensive.productType = ProductType(rawValue: productTypeString) ?? .regular
        }
        comprehensive.categoryId = itemData.categoryId
        if let categories = itemData.categories {
            comprehensive.categories = categories
        }
        comprehensive.reportingCategory = itemData.reportingCategory
        
        // Tax and modifiers
        comprehensive.taxIds = itemData.taxIds ?? []
        if let modifierListInfo = itemData.modifierListInfo {
            comprehensive.modifierListInfo = modifierListInfo
        }
        comprehensive.skipModifierScreen = itemData.skipModifierScreen ?? false

        // Images
        comprehensive.imageIds = itemData.imageIds ?? []
        if let images = itemData.images {
            comprehensive.images = images
        }
        
        // Availability
        comprehensive.availableOnline = itemData.availableOnline ?? true
        comprehensive.availableForPickup = itemData.availableForPickup ?? true
        comprehensive.availableElectronically = itemData.availableElectronically ?? false
        
        // Item options
        if let itemOptions = itemData.itemOptions {
            comprehensive.itemOptions = itemOptions
        }
        
        // Convert variations
        if let variations = itemData.variations {
            comprehensive.variations = variations.compactMap { variation in
                fromSquareItemVariation(variation)
            }
        }
        
        return comprehensive
    }
    
    /// Convert Square ItemVariation to ComprehensiveVariationData
    static func fromSquareItemVariation(_ variation: ItemVariation) -> ComprehensiveVariationData? {
        var variationData = ComprehensiveVariationData()
        
        variationData.variationId = variation.id
        variationData.itemId = variation.itemId
        variationData.name = variation.name ?? ""
        variationData.sku = variation.sku ?? ""
        variationData.upc = variation.upc ?? ""
        variationData.ordinal = variation.ordinal ?? 0
        
        // Pricing
        if let pricingTypeString = variation.pricingType {
            variationData.pricingType = PricingType(rawValue: pricingTypeString) ?? .fixedPricing
        }
        variationData.priceMoney = variation.priceMoney
        variationData.basePriceMoney = variation.basePriceMoney
        variationData.defaultUnitCost = variation.defaultUnitCost
        
        // Inventory
        variationData.trackInventory = variation.trackInventory ?? false
        if let alertTypeString = variation.inventoryAlertType {
            variationData.inventoryAlertType = InventoryAlertType(rawValue: alertTypeString) ?? .none
        }
        variationData.inventoryAlertThreshold = variation.inventoryAlertThreshold
        
        // Service
        variationData.serviceDuration = variation.serviceDuration
        variationData.availableForBooking = variation.availableForBooking ?? false
        
        // Options and overrides
        if let itemOptionValues = variation.itemOptionValues {
            variationData.itemOptionValues = itemOptionValues
        }
        if let locationOverrides = variation.locationOverrides {
            variationData.locationOverrides = locationOverrides
        }
        
        // Measurement
        variationData.measurementUnitId = variation.measurementUnitId
        variationData.sellable = variation.sellable ?? true
        variationData.stockable = variation.stockable ?? true
        
        variationData.userData = variation.userData
        
        return variationData
    }
    
    // MARK: - Comprehensive Model to Square API
    
    /// Convert ComprehensiveItemData to Square CatalogObject for API submission
    static func toSquareCatalogObject(_ comprehensive: ComprehensiveItemData) -> CatalogObject {
        let itemData = ItemData(
            name: comprehensive.name.isEmpty ? nil : comprehensive.name,
            description: comprehensive.description.isEmpty ? nil : comprehensive.description,
            categoryId: comprehensive.categoryId,
            taxIds: comprehensive.taxIds.isEmpty ? nil : comprehensive.taxIds,
            variations: comprehensive.variations.map { toSquareItemVariation($0) },
            productType: comprehensive.productType.rawValue,
            skipModifierScreen: comprehensive.skipModifierScreen,
            itemOptions: comprehensive.itemOptions.isEmpty ? nil : comprehensive.itemOptions,
            modifierListInfo: comprehensive.modifierListInfo.isEmpty ? nil : comprehensive.modifierListInfo,
            images: comprehensive.images.isEmpty ? nil : comprehensive.images,
            labelColor: comprehensive.labelColor,
            availableOnline: comprehensive.availableOnline,
            availableForPickup: comprehensive.availableForPickup,
            availableElectronically: comprehensive.availableElectronically,
            abbreviation: comprehensive.abbreviation.isEmpty ? nil : comprehensive.abbreviation,
            categories: comprehensive.categories.isEmpty ? nil : comprehensive.categories,
            reportingCategory: comprehensive.reportingCategory,
            imageIds: comprehensive.imageIds.isEmpty ? nil : comprehensive.imageIds
        )
        
        return CatalogObject(
            id: comprehensive.id ?? "",
            type: comprehensive.type.rawValue,
            updatedAt: comprehensive.updatedAt ?? "",
            version: comprehensive.version ?? 0,
            isDeleted: comprehensive.isDeleted,
            presentAtAllLocations: comprehensive.presentAtAllLocations,
            itemData: itemData,
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil,
            imageData: nil
        )
    }
    
    /// Convert ComprehensiveVariationData to Square ItemVariation
    static func toSquareItemVariation(_ variation: ComprehensiveVariationData) -> ItemVariation {
        return ItemVariation(
            id: variation.variationId,
            itemId: variation.itemId,
            name: variation.name.isEmpty ? nil : variation.name,
            sku: variation.sku.isEmpty ? nil : variation.sku,
            upc: variation.upc.isEmpty ? nil : variation.upc,
            ordinal: variation.ordinal,
            pricingType: variation.pricingType.rawValue,
            priceMoney: variation.priceMoney,
            basePriceMoney: variation.basePriceMoney,
            defaultUnitCost: variation.defaultUnitCost,
            locationOverrides: variation.locationOverrides.isEmpty ? nil : variation.locationOverrides,
            trackInventory: variation.trackInventory,
            inventoryAlertType: variation.inventoryAlertType.rawValue,
            inventoryAlertThreshold: variation.inventoryAlertThreshold,
            userData: variation.userData,
            serviceDuration: variation.serviceDuration,
            availableForBooking: variation.availableForBooking,
            itemOptionValues: variation.itemOptionValues.isEmpty ? nil : variation.itemOptionValues,
            measurementUnitId: variation.measurementUnitId,
            sellable: variation.sellable,
            stockable: variation.stockable
        )
    }
    
    // MARK: - Database Model Conversion
    
    /// Convert database CatalogItem to ComprehensiveItemData
    static func fromDatabaseCatalogItem(_ dbItem: CatalogItem) -> ComprehensiveItemData? {
        guard let dataJsonData = dbItem.dataJson.data(using: .utf8),
              let catalogObject = try? JSONDecoder().decode(CatalogObject.self, from: dataJsonData) else {
            return nil
        }
        
        var comprehensive = fromSquareCatalogObject(catalogObject)
        
        // Override with database-specific fields
        comprehensive?.id = dbItem.id
        comprehensive?.version = Int64(dbItem.version)
        comprehensive?.updatedAt = dbItem.updatedAt
        comprehensive?.isDeleted = dbItem.isDeleted
        comprehensive?.presentAtAllLocations = dbItem.presentAtAllLocations
        comprehensive?.name = dbItem.name ?? comprehensive?.name ?? ""
        comprehensive?.description = dbItem.description ?? comprehensive?.description ?? ""
        comprehensive?.categoryId = dbItem.categoryId ?? comprehensive?.categoryId
        
        return comprehensive
    }
    
    /// Convert ComprehensiveItemData to database CatalogItem
    static func toDatabaseCatalogItem(_ comprehensive: ComprehensiveItemData) -> CatalogItem? {
        let catalogObject = toSquareCatalogObject(comprehensive)
        
        guard let dataJsonData = try? JSONEncoder().encode(catalogObject),
              let dataJsonString = String(data: dataJsonData, encoding: .utf8) else {
            return nil
        }
        
        return CatalogItem(
            id: comprehensive.id ?? UUID().uuidString,
            updatedAt: comprehensive.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
            version: String(comprehensive.version ?? 1),
            isDeleted: comprehensive.isDeleted,
            presentAtAllLocations: comprehensive.presentAtAllLocations,
            name: comprehensive.name.isEmpty ? nil : comprehensive.name,
            description: comprehensive.description.isEmpty ? nil : comprehensive.description,
            categoryId: comprehensive.categoryId,
            dataJson: dataJsonString
        )
    }
    
    // MARK: - Legacy ItemDetailsData Conversion
    
    /// Convert legacy ItemDetailsData to ComprehensiveItemData
    static func fromLegacyItemDetailsData(_ legacy: ItemDetailsData) -> ComprehensiveItemData {
        var comprehensive = ComprehensiveItemData()
        
        comprehensive.id = legacy.id
        comprehensive.version = legacy.version
        comprehensive.name = legacy.name
        comprehensive.description = legacy.description
        comprehensive.abbreviation = legacy.abbreviation
        comprehensive.productType = legacy.productType
        if let reportingCategoryId = legacy.reportingCategoryId {
            comprehensive.reportingCategory = ReportingCategory(id: reportingCategoryId)
        }
        comprehensive.categories = legacy.categoryIds.map { CategoryReference(id: $0) }
        comprehensive.taxIds = legacy.taxIds
        comprehensive.modifierListInfo = legacy.modifierListIds.map { ModifierListInfo(id: $0) }
        comprehensive.imageIds = legacy.imageIds
        comprehensive.skipModifierScreen = legacy.skipModifierScreen
        comprehensive.availableOnline = legacy.availableOnline
        comprehensive.availableForPickup = legacy.availableForPickup
        comprehensive.availableElectronically = legacy.availableElectronically
        comprehensive.trackInventory = legacy.trackInventory
        comprehensive.inventoryAlertType = legacy.inventoryAlertType
        comprehensive.inventoryAlertThreshold = legacy.inventoryAlertThreshold
        comprehensive.isDeleted = legacy.isDeleted
        comprehensive.presentAtAllLocations = legacy.presentAtAllLocations
        comprehensive.updatedAt = legacy.updatedAt
        
        // Convert service fields
        if let serviceDurationMs = legacy.serviceDuration {
            comprehensive.serviceDuration = ServiceDuration(duration: serviceDurationMs)
        }
        comprehensive.teamMemberIds = legacy.teamMemberIds
        comprehensive.availableForBooking = legacy.availableForBooking
        
        // Convert variations
        comprehensive.variations = legacy.variations.map { legacyVar in
            var variation = ComprehensiveVariationData()
            variation.name = legacyVar.name
            variation.sku = legacyVar.sku
            variation.upc = legacyVar.upc
            variation.priceMoney = Money.fromDollars(Double(legacyVar.price) ?? 0.0)
            variation.defaultUnitCost = Money.fromDollars(Double(legacyVar.cost) ?? 0.0)
            variation.trackInventory = legacyVar.trackInventory
            variation.stockOnHand = legacyVar.stockOnHand
            return variation
        }
        
        return comprehensive
    }
    
    /// Convert ComprehensiveItemData to legacy ItemDetailsData
    static func toLegacyItemDetailsData(_ comprehensive: ComprehensiveItemData) -> ItemDetailsData {
        var legacy = ItemDetailsData()
        
        legacy.id = comprehensive.id
        legacy.version = comprehensive.version
        legacy.name = comprehensive.name
        legacy.description = comprehensive.description
        legacy.abbreviation = comprehensive.abbreviation
        legacy.productType = comprehensive.productType
        legacy.reportingCategoryId = comprehensive.reportingCategory?.id
        legacy.categoryIds = comprehensive.categories.map { $0.id }
        legacy.taxIds = comprehensive.taxIds
        legacy.modifierListIds = comprehensive.modifierListInfo.map { $0.id }
        legacy.imageIds = comprehensive.imageIds
        legacy.skipModifierScreen = comprehensive.skipModifierScreen
        legacy.availableOnline = comprehensive.availableOnline
        legacy.availableForPickup = comprehensive.availableForPickup
        legacy.availableElectronically = comprehensive.availableElectronically
        legacy.trackInventory = comprehensive.trackInventory
        legacy.inventoryAlertType = comprehensive.inventoryAlertType
        legacy.inventoryAlertThreshold = comprehensive.inventoryAlertThreshold
        legacy.isDeleted = comprehensive.isDeleted
        legacy.presentAtAllLocations = comprehensive.presentAtAllLocations
        legacy.updatedAt = comprehensive.updatedAt
        
        // Convert service fields
        legacy.serviceDuration = comprehensive.serviceDuration?.duration
        legacy.teamMemberIds = comprehensive.teamMemberIds
        legacy.availableForBooking = comprehensive.availableForBooking
        
        // Convert variations
        legacy.variations = comprehensive.variations.map { compVar in
            var legacyVar = ItemDetailsVariationData()
            legacyVar.name = compVar.name
            legacyVar.sku = compVar.sku
            legacyVar.upc = compVar.upc
            legacyVar.price = String(compVar.priceMoney?.toDollars ?? 0.0)
            legacyVar.cost = String(compVar.defaultUnitCost?.toDollars ?? 0.0)
            legacyVar.trackInventory = compVar.trackInventory
            legacyVar.stockOnHand = compVar.stockOnHand
            return legacyVar
        }
        
        return legacy
    }
}
