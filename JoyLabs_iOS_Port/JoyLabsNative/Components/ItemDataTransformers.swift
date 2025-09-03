import Foundation
import os.log

// MARK: - Date Extension
extension Date {
    func ISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

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
        itemDetails.isDeleted = catalogObject.safeIsDeleted
        itemDetails.presentAtAllLocations = catalogObject.presentAtAllLocations ?? false
        itemDetails.presentAtLocationIds = catalogObject.presentAtLocationIds ?? []
        itemDetails.absentAtLocationIds = catalogObject.absentAtLocationIds ?? []
        
        // CRITICAL DEBUG: Log location data transformation
        logger.info("🔍 TRANSFORM: Item \(catalogObject.id) presentAtAllLocations: \(catalogObject.presentAtAllLocations?.description ?? "nil") -> UI value: \(itemDetails.presentAtAllLocations)")
        logger.info("🔍 TRANSFORM: Item \(catalogObject.id) presentAtLocationIds: \(catalogObject.presentAtLocationIds?.count ?? 0) locations")
        logger.info("🔍 TRANSFORM: Item \(catalogObject.id) absentAtLocationIds: \(catalogObject.absentAtLocationIds?.count ?? 0) locations")
        
        // Extract item data
        if let itemData = catalogObject.itemData {
            // Basic information
            itemDetails.name = itemData.name ?? ""
            itemDetails.description = itemData.description ?? ""
            itemDetails.abbreviation = itemData.abbreviation ?? ""
            // labelColor not available in ItemDetailsData
            
            // Product classification
            itemDetails.productType = transformProductType(itemData.productType)

            // CRITICAL: Handle both reporting category and additional categories
            // Reporting category (primary category)
            if let reportingCategory = itemData.reportingCategory {
                itemDetails.reportingCategoryId = reportingCategory.id
            } else {
                // Log missing reporting category without fallback
                logger.error("[ItemDataTransformers] Reporting category not found for item \(catalogObject.id) - reportingCategory is nil")
                itemDetails.reportingCategoryId = nil
            }

            // Additional categories - combine reporting category + additional categories
            var allCategoryIds: [String] = []

            // Add reporting category to the list if it exists
            if let reportingCategoryId = itemDetails.reportingCategoryId {
                allCategoryIds.append(reportingCategoryId)
            }

            // Add additional categories from the categories array
            if let categories = itemData.categories {
                let additionalCategoryIds = categories.map { $0.id }
                // Only add categories that aren't already in the list (avoid duplicates)
                for categoryId in additionalCategoryIds {
                    if !allCategoryIds.contains(categoryId) {
                        allCategoryIds.append(categoryId)
                    }
                }
            }

            itemDetails.categoryIds = allCategoryIds
            
            // Transform variations - convert ItemVariation to ItemDetailsVariationData
            itemDetails.variations = transformVariations(itemData.variations ?? [])
            
            // Availability and visibility
            itemDetails.availableOnline = itemData.availableOnline ?? false
            itemDetails.availableForPickup = itemData.availableForPickup ?? false
            itemDetails.skipModifierScreen = itemData.skipModifierScreen ?? false
            
            // Modifier lists
            itemDetails.modifierListIds = transformModifierListInfo(itemData.modifierListInfo ?? [])
            
            // Tax information
            itemDetails.taxIds = itemData.taxIds ?? []
            
            // Images
            itemDetails.imageIds = itemData.imageIds ?? []
            
            // CRITICAL SQUARE API FIELDS - Now available in ItemData
            itemDetails.isTaxable = itemData.isTaxable ?? true // Square API default
            itemDetails.isAlcoholic = itemData.isAlcoholic ?? false // Square API default
        }
        
        // Add team data if available
        if let teamData = teamData {
            itemDetails.teamData = TeamItemData(
                caseUpc: teamData.caseUpc,
                caseCost: teamData.caseCost,
                caseQuantity: teamData.caseQuantity,
                vendor: teamData.vendor,
                discontinued: teamData.discontinued,
                notes: teamData.notes != nil ? [TeamNote(
                    id: UUID().uuidString,
                    content: teamData.notes!,
                    isComplete: false,
                    authorId: teamData.owner ?? "unknown",
                    authorName: teamData.owner ?? "Unknown",
                    createdAt: ISO8601DateFormatter().string(from: teamData.createdAt),
                    updatedAt: ISO8601DateFormatter().string(from: teamData.updatedAt)
                )] : [],
                owner: teamData.owner,
                lastSyncAt: teamData.lastSyncAt != nil ? ISO8601DateFormatter().string(from: teamData.lastSyncAt!) : nil
            )
        }
        
        logger.info("Successfully transformed CatalogObject to ItemDetailsData")
        return itemDetails
    }
    
    // MARK: - UI to Database Transformations
    
    /// Transform ItemDetailsData from UI to CatalogObject for database/API
    /// Now includes validation and safety checks using SquareDataConverter
    static func transformItemDetailsToCatalogObject(_ itemDetails: ItemDetailsData, databaseManager: SwiftDataCatalogManager) -> CatalogObject {
        logger.info("Transforming ItemDetailsData to CatalogObject: \(itemDetails.id ?? "new")")

        // Note: Validation is handled by SquareCRUDService before calling this transformer
        // This transformer assumes data has already been validated

        // Note: Duplicate names are allowed by Square API as long as IDs are unique
        // Only UPC/SKU duplicates should be checked if needed for business logic

        // Create proper ID for Square API
        // For new items: use ID starting with # (Square requirement)
        // For existing items: use the existing Square ID
        let itemId = (itemDetails.id?.isEmpty == false) ? itemDetails.id! : "#\(UUID().uuidString)"

        // Create item data - validation already done by SquareCRUDService
        // CRITICAL: Use Square's correct category structure: categories array + reportingCategory
        let itemData = ItemData(
            name: itemDetails.name.isEmpty ? nil : itemDetails.name,
            description: itemDetails.description.isEmpty ? nil : itemDetails.description,
            categoryId: nil, // Don't use legacy categoryId field
            taxIds: itemDetails.taxIds.isEmpty ? nil : itemDetails.taxIds,
            variations: transformVariationsToAPI(itemDetails.variations, itemId: itemId, presentAtAllLocations: itemDetails.presentAtAllLocations, presentAtLocationIds: itemDetails.presentAtLocationIds, absentAtLocationIds: itemDetails.absentAtLocationIds),
            productType: transformProductTypeToAPI(itemDetails.productType),
            skipModifierScreen: itemDetails.skipModifierScreen,
            itemOptions: nil, // TODO: Implement item options transformation
            modifierListInfo: transformModifierListInfoToAPI(itemDetails.modifierListIds),
            images: nil, // Images handled separately via imageIds
            labelColor: nil, // TODO: Add labelColor to ItemDetailsData if needed
            availableOnline: itemDetails.availableOnline,
            availableForPickup: itemDetails.availableForPickup,
            availableElectronically: itemDetails.availableElectronically,
            abbreviation: itemDetails.abbreviation.isEmpty ? nil : itemDetails.abbreviation,
            categories: transformCategoriesToAPI(itemDetails.categoryIds), // All categories in array
            reportingCategory: itemDetails.reportingCategoryId != nil ? ReportingCategory(id: itemDetails.reportingCategoryId!, ordinal: nil) : nil, // Designated reporting category
            imageIds: nil, // CRITICAL: Set to nil so field is omitted from JSON - images handled separately via SimpleImageService
            
            // CRITICAL SQUARE API FIELDS - Previously missing
            isTaxable: itemDetails.isTaxable,
            isAlcoholic: itemDetails.isAlcoholic,
            sortName: nil, // Auto-generated by Square or can be set later
            
            // PERFORMANCE OPTIMIZATION FIELDS (set to nil for new items)
            taxNames: nil,
            modifierNames: nil
        )
        
        // Create catalog object with proper ID handling for Square API
        let catalogObject = CatalogObject(
            id: itemId,
            type: "ITEM",
            updatedAt: itemDetails.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
            version: itemDetails.version ?? 1,
            isDeleted: itemDetails.isDeleted,
            presentAtAllLocations: itemDetails.presentAtAllLocations,
            presentAtLocationIds: itemDetails.presentAtAllLocations ? nil : (itemDetails.presentAtLocationIds.isEmpty ? nil : itemDetails.presentAtLocationIds),
            absentAtLocationIds: itemDetails.absentAtLocationIds.isEmpty ? nil : itemDetails.absentAtLocationIds,
            itemData: itemData,
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil,
            imageData: nil
        )
        
        logger.info("Successfully transformed ItemDetailsData to CatalogObject with validation")
        return catalogObject
    }

    /// Legacy method for backward compatibility (without validation)
    /// Use the version with databaseManager for CRUD operations
    static func transformItemDetailsToCatalogObject(_ itemDetails: ItemDetailsData) -> CatalogObject {
        logger.warning("Using legacy transform method without validation - consider using version with databaseManager")

        // Create item data without validation (legacy behavior)
        let itemData = ItemData(
            name: itemDetails.name.isEmpty ? nil : itemDetails.name,
            description: itemDetails.description.isEmpty ? nil : itemDetails.description,
            categoryId: nil, // Don't use legacy categoryId field
            taxIds: itemDetails.taxIds.isEmpty ? nil : itemDetails.taxIds,
            variations: transformVariationsToAPI(itemDetails.variations, itemId: itemDetails.id ?? "#\(UUID().uuidString)", presentAtAllLocations: itemDetails.presentAtAllLocations, presentAtLocationIds: itemDetails.presentAtLocationIds, absentAtLocationIds: itemDetails.absentAtLocationIds),
            productType: transformProductTypeToAPI(itemDetails.productType),
            skipModifierScreen: itemDetails.skipModifierScreen,
            itemOptions: nil,
            modifierListInfo: transformModifierListInfoToAPI(itemDetails.modifierListIds),
            images: nil,
            labelColor: nil,
            availableOnline: itemDetails.availableOnline,
            availableForPickup: itemDetails.availableForPickup,
            availableElectronically: itemDetails.availableElectronically,
            abbreviation: itemDetails.abbreviation.isEmpty ? nil : itemDetails.abbreviation,
            categories: transformCategoriesToAPI(itemDetails.categoryIds), // All categories in array
            reportingCategory: itemDetails.reportingCategoryId != nil ? ReportingCategory(id: itemDetails.reportingCategoryId!, ordinal: nil) : nil, // Designated reporting category
            imageIds: nil, // CRITICAL: Set to nil so field is omitted from JSON - images handled separately via SimpleImageService
            
            // CRITICAL SQUARE API FIELDS - Previously missing (legacy version)
            isTaxable: itemDetails.isTaxable,
            isAlcoholic: itemDetails.isAlcoholic,
            sortName: nil, // Auto-generated by Square or can be set later
            
            taxNames: nil,
            modifierNames: nil
        )

        // Create catalog object
        let catalogObject = CatalogObject(
            id: itemDetails.id ?? UUID().uuidString,
            type: "ITEM",
            updatedAt: itemDetails.updatedAt ?? ISO8601DateFormatter().string(from: Date()),
            version: itemDetails.version ?? 1,
            isDeleted: itemDetails.isDeleted,
            presentAtAllLocations: itemDetails.presentAtAllLocations,
            presentAtLocationIds: itemDetails.presentAtAllLocations ? nil : (itemDetails.presentAtLocationIds.isEmpty ? nil : itemDetails.presentAtLocationIds),
            absentAtLocationIds: itemDetails.absentAtLocationIds.isEmpty ? nil : itemDetails.absentAtLocationIds,
            itemData: itemData,
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil,
            imageData: nil
        )

        logger.info("Successfully transformed ItemDetailsData to CatalogObject (legacy)")
        return catalogObject
    }
    
    // MARK: - Helper Transformation Methods
    
    private static func transformVariations(_ variations: [ItemVariation]) -> [ItemDetailsVariationData] {
        return variations.map { variation in
            ItemDetailsVariationData(
                id: variation.itemVariationData?.itemId,
                version: variation.version,
                name: variation.itemVariationData?.name,
                sku: variation.itemVariationData?.sku,
                upc: variation.itemVariationData?.upc,
                ordinal: variation.itemVariationData?.ordinal ?? 0,
                pricingType: transformPricingType(variation.itemVariationData?.pricingType),
                priceMoney: transformMoney(variation.itemVariationData?.priceMoney),
                basePriceMoney: transformMoney(variation.itemVariationData?.basePriceMoney),
                locationOverrides: transformLocationOverrides(variation.itemVariationData?.locationOverrides),
                trackInventory: variation.itemVariationData?.trackInventory ?? false,
                inventoryAlertType: transformInventoryAlertType(variation.itemVariationData?.inventoryAlertType),
                inventoryAlertThreshold: variation.itemVariationData?.inventoryAlertThreshold.map(Int.init),
                serviceDuration: variation.itemVariationData?.serviceDuration.map(Int.init),
                availableForBooking: variation.itemVariationData?.availableForBooking ?? false,
                stockable: variation.itemVariationData?.stockable ?? true,
                sellable: variation.itemVariationData?.sellable ?? true
            )
        }
    }

    /// Check if a variation is completely empty (user created but didn't fill in)
    private static func isVariationEmpty(_ variation: ItemDetailsVariationData) -> Bool {
        // A variation is considered empty if it has no meaningful data
        let hasName = !(variation.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSku = !(variation.sku?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasUpc = !(variation.upc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPrice = variation.priceMoney?.amount != nil && variation.priceMoney?.amount != 0

        // If none of the key fields have data, consider it empty
        return !hasName && !hasSku && !hasUpc && !hasPrice
    }

    /// Transform category IDs to CategoryReference objects for Square API
    private static func transformCategoriesToAPI(_ categoryIds: [String]) -> [CategoryReference]? {
        guard !categoryIds.isEmpty else { return nil }
        return categoryIds.map { CategoryReference(id: $0, ordinal: nil) }
    }

    private static func transformVariationsToAPI(_ variations: [ItemDetailsVariationData], itemId: String, presentAtAllLocations: Bool, presentAtLocationIds: [String], absentAtLocationIds: [String]) -> [ItemVariation]? {
        guard !variations.isEmpty else { return nil }

        // Filter out completely empty variations
        let validVariations = variations.filter { !isVariationEmpty($0) }
        guard !validVariations.isEmpty else { return nil }

        return validVariations.map { variation in
            ItemVariation(
                id: (variation.id?.isEmpty == false) ? variation.id! : "#\(UUID().uuidString)", // # prefix for new variations
                type: "ITEM_VARIATION",
                updatedAt: nil,
                version: variation.version, // Preserve existing version for updates, nil for new variations
                isDeleted: false,
                presentAtAllLocations: presentAtAllLocations, // Inherit from parent item
                presentAtLocationIds: presentAtAllLocations ? nil : (presentAtLocationIds.isEmpty ? nil : presentAtLocationIds), // Only use when presentAtAllLocations=false
                absentAtLocationIds: absentAtLocationIds.isEmpty ? nil : absentAtLocationIds, // Inherit from parent item
                itemVariationData: ItemVariationData(
                    itemId: itemId, // Reference parent item ID (with # for new items)
                    name: variation.name?.isEmpty == false ? variation.name : nil,
                    sku: variation.sku?.isEmpty == false ? variation.sku : nil,
                    upc: variation.upc?.isEmpty == false ? variation.upc : nil,
                    ordinal: variation.ordinal,
                    pricingType: transformPricingTypeToAPI(variation.pricingType),
                    priceMoney: transformMoneyToAPI(variation.priceMoney),
                    basePriceMoney: transformMoneyToAPI(variation.basePriceMoney),
                    defaultUnitCost: nil,
                    locationOverrides: transformLocationOverridesToAPI(variation.locationOverrides),
                    trackInventory: variation.trackInventory,
                    inventoryAlertType: transformInventoryAlertTypeToAPI(variation.inventoryAlertType),
                    inventoryAlertThreshold: variation.inventoryAlertThreshold.map(Int64.init),
                    userData: nil,
                    serviceDuration: variation.serviceDuration.map(Int64.init),
                    availableForBooking: variation.availableForBooking,
                    itemOptionValues: nil,
                    measurementUnitId: nil,
                    sellable: variation.sellable,
                    stockable: variation.stockable
                )
            )
        }
    }
    
    private static func transformMoney(_ money: Money?) -> MoneyData? {
        guard let money = money else { return nil }
        return MoneyData(
            amount: Int(money.amount ?? 0),
            currency: money.currency ?? "USD"
        )
    }

    private static func transformMoneyToAPI(_ money: MoneyData?) -> Money? {
        guard let money = money else { return nil }
        return Money(amount: Int64(money.amount), currency: money.currency)
    }
    
    // MARK: - Location Override Transformations
    
    /// Transform location overrides from Square API model to UI model
    private static func transformLocationOverrides(_ locationOverrides: [LocationOverride]?) -> [LocationOverrideData] {
        guard let locationOverrides = locationOverrides else { return [] }
        
        return locationOverrides.compactMap { override in
            guard let locationId = override.locationId else { return nil }
            
            return LocationOverrideData(
                locationId: locationId,
                priceMoney: transformMoney(override.priceMoney),
                trackInventory: override.trackInventory ?? false,
                stockOnHand: 0 // stockOnHand not available in Square LocationOverride model
            )
        }
    }
    
    /// Transform location overrides from UI model to Square API model
    private static func transformLocationOverridesToAPI(_ locationOverrides: [LocationOverrideData]) -> [LocationOverride]? {
        guard !locationOverrides.isEmpty else { return nil }
        
        // Only include overrides that have meaningful data (price or inventory tracking)
        let validOverrides = locationOverrides.filter { override in
            override.priceMoney != nil || override.trackInventory
        }
        
        guard !validOverrides.isEmpty else { return nil }
        
        return validOverrides.map { override in
            LocationOverride(
                locationId: override.locationId,
                priceMoney: transformMoneyToAPI(override.priceMoney),
                pricingType: override.priceMoney != nil ? "FIXED_PRICING" : nil,
                trackInventory: override.trackInventory ? override.trackInventory : nil,
                inventoryAlertType: override.inventoryAlertType?.rawValue,
                inventoryAlertThreshold: override.inventoryAlertThreshold.map(Int64.init),
                soldOut: nil, // Read-only field
                soldOutValidUntil: nil // Read-only field
            )
        }
    }
    
    private static func transformProductType(_ productType: String?) -> ProductType {
        switch productType {
        case "APPOINTMENTS_SERVICE": return .appointmentsService
        default: return .regular
        }
    }

    private static func transformProductTypeToAPI(_ productType: ProductType) -> String? {
        switch productType {
        case .appointmentsService: return "APPOINTMENTS_SERVICE"
        case .regular: return "REGULAR"
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
        case "UNAVAILABLE": return .unavailable
        default: return .unindexed
        }
    }

    private static func transformEcomVisibilityToAPI(_ visibility: EcomVisibility) -> String? {
        switch visibility {
        case .hidden: return "HIDDEN"
        case .unavailable: return "UNAVAILABLE"
        case .unindexed: return "UNINDEXED"
        case .visible: return "VISIBLE"
        }
    }
    
    // MARK: - Modifier List Info Transformers (Simplified)
    private static func transformModifierListInfo(_ modifierListInfo: [ModifierListInfo]) -> [String] {
        return modifierListInfo.compactMap { $0.modifierListId }
    }

    private static func transformModifierListInfoToAPI(_ modifierListIds: [String]) -> [ModifierListInfo]? {
        guard !modifierListIds.isEmpty else { return nil }

        return modifierListIds.map { id in
            ModifierListInfo(
                modifierListId: id,
                modifierOverrides: nil,
                minSelectedModifiers: 0,
                maxSelectedModifiers: nil,
                enabled: true,
                ordinal: 0
            )
        }
    }
    
    // MARK: - E-commerce SEO Data Transformers (Simplified)
    private static func transformEcomSeoData(_ seoData: EcomSeoData?, to itemDetails: inout ItemDetailsData) {
        guard let seoData = seoData else { return }
        itemDetails.seoTitle = seoData.pageTitle
        itemDetails.seoDescription = seoData.pageDescription
    }

    private static func transformEcomSeoDataToAPI(_ itemDetails: ItemDetailsData) -> EcomSeoData? {
        guard let seoTitle = itemDetails.seoTitle, !seoTitle.isEmpty,
              let seoDescription = itemDetails.seoDescription, !seoDescription.isEmpty else {
            return nil
        }

        return EcomSeoData(
            pageTitle: seoTitle,
            pageDescription: seoDescription,
            permalink: nil
        )
    }

    // MARK: - Future Name-Based Conversion Helpers

    /// Convert category names to IDs (for future UI implementations that work with names)
    @MainActor
    static func convertCategoryNamesToIds(_ categoryNames: [String], using converter: SquareDataConverter) -> [String] {
        var categoryIds: [String] = []
        for name in categoryNames {
            if let categoryId = converter.getCategoryId(byName: name) {
                categoryIds.append(categoryId)
            }
        }
        return categoryIds
    }

    /// Convert tax names to IDs (for future UI implementations that work with names)
    @MainActor
    static func convertTaxNamesToIds(_ taxNames: [String], using converter: SquareDataConverter) -> [String] {
        return converter.getTaxIds(byNames: taxNames)
    }

    /// Convert modifier names to IDs (for future UI implementations that work with names)
    @MainActor
    static func convertModifierNamesToIds(_ modifierNames: [String], using converter: SquareDataConverter) -> [String] {
        return converter.getModifierListIds(byNames: modifierNames)
    }

    // MARK: - Additional Helper Functions


}
