import Foundation

/// MockDatabaseManager - In-memory database for Phase 7 testing
/// This provides the same interface as DatabaseManager but stores data in memory
@MainActor
class MockDatabaseManager: ObservableObject {
    // MARK: - In-Memory Storage
    private var catalogItems: [String: CatalogObject] = [:]
    private var categories: [String: CatalogObject] = [:]
    private var itemVariations: [String: [CatalogObject]] = [:]
    
    // MARK: - Initialization
    init() {
        // Pre-populate with sample data
        populateSampleData()
    }
    
    // MARK: - Public Methods
    func initializeDatabase() async throws {
        // Mock initialization - already done in init
        print("[MockDatabase] INFO: Mock database initialized")
    }
    
    func upsertCatalogObjects(_ objects: [CatalogObject]) async throws {
        print("[MockDatabase] DEBUG: Upserting \(objects.count) catalog objects")
        
        for object in objects {
            switch object.type {
            case "ITEM":
                catalogItems[object.id] = object
            case "CATEGORY":
                categories[object.id] = object
            case "ITEM_VARIATION":
                if let itemId = object.itemVariationData?.itemId {
                    if itemVariations[itemId] == nil {
                        itemVariations[itemId] = []
                    }
                    itemVariations[itemId]?.append(object)
                }
            default:
                break
            }
        }
        
        print("[MockDatabase] DEBUG: Successfully upserted \(objects.count) objects")
    }
    
    func searchCatalogItems(searchTerm: String, filters: SearchFilters) async throws -> [SearchResultItem] {
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmedTerm.isEmpty else {
            return []
        }
        
        var results: [SearchResultItem] = []
        
        // Search through catalog items
        for (_, object) in catalogItems {
            guard let itemData = object.itemData else { continue }
            
            var matchType: String?
            var matchContext: String?
            
            // Name search
            if filters.name, let name = itemData.name, name.lowercased().contains(trimmedTerm) {
                matchType = "name"
                matchContext = name
            }
            
            // SKU search (check variations)
            if filters.sku, let variations = itemVariations[object.id] {
                for variation in variations {
                    if let variationData = variation.itemVariationData,
                       let sku = variationData.sku,
                       sku.lowercased().contains(trimmedTerm) {
                        matchType = "sku"
                        matchContext = sku
                        break
                    }
                }
            }
            
            // Barcode search (check variations)
            if filters.barcode, let variations = itemVariations[object.id] {
                for variation in variations {
                    if let variationData = variation.itemVariationData,
                       let upc = variationData.upc,
                       upc.contains(trimmedTerm) {
                        matchType = "barcode"
                        matchContext = upc
                        break
                    }
                }
            }
            
            // Category search
            if filters.category, let categoryId = itemData.categoryId,
               let category = categories[categoryId],
               let categoryData = category.categoryData,
               let categoryName = categoryData.name,
               categoryName.lowercased().contains(trimmedTerm) {
                matchType = "category"
                matchContext = categoryName
            }
            
            // If we found a match, create a search result
            if let matchType = matchType {
                let searchResult = SearchResultItem(
                    id: object.id,
                    name: itemData.name,
                    sku: getFirstSKU(for: object.id),
                    price: getFirstPrice(for: object.id),
                    barcode: getFirstBarcode(for: object.id),
                    categoryId: itemData.categoryId,
                    categoryName: getCategoryName(for: itemData.categoryId),
                    images: nil, // TODO: Implement images
                    matchType: matchType,
                    matchContext: matchContext,
                    isFromCaseUpc: false,
                    caseUpcData: nil
                )
                results.append(searchResult)
            }
        }
        
        print("[MockDatabase] DEBUG: Search for '\(trimmedTerm)' returned \(results.count) results")
        return results
    }
    
    // MARK: - Helper Methods
    private func getFirstSKU(for itemId: String) -> String? {
        return itemVariations[itemId]?.first?.itemVariationData?.sku
    }
    
    private func getFirstPrice(for itemId: String) -> Double? {
        if let variation = itemVariations[itemId]?.first,
           let variationData = variation.itemVariationData,
           let priceMoney = variationData.priceMoney,
           let amount = priceMoney.amount {
            return Double(amount) / 100.0 // Convert cents to dollars
        }
        return nil
    }
    
    private func getFirstBarcode(for itemId: String) -> String? {
        return itemVariations[itemId]?.first?.itemVariationData?.upc
    }
    
    private func getCategoryName(for categoryId: String?) -> String? {
        guard let categoryId = categoryId,
              let category = categories[categoryId] else {
            return nil
        }
        return category.categoryData?.name
    }
    
    private func populateSampleData() {
        // Create sample categories
        let beverageCategory = CatalogObject(
            id: "cat_beverages",
            type: "CATEGORY",
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: nil,
            categoryData: CategoryData(name: "Beverages"),
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        let snacksCategory = CatalogObject(
            id: "cat_snacks",
            type: "CATEGORY", 
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: nil,
            categoryData: CategoryData(name: "Snacks"),
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        categories["cat_beverages"] = beverageCategory
        categories["cat_snacks"] = snacksCategory
        
        // Create sample items
        let coffeeItem = CatalogObject(
            id: "item_coffee",
            type: "ITEM",
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: ItemData(
                name: "Premium Coffee Beans",
                description: "High-quality arabica coffee beans from Colombia",
                categoryId: "cat_beverages",
                abbreviation: nil,
                labelColor: nil,
                availableOnline: true,
                availableForPickup: true,
                availableElectronically: false,
                categoryData: nil,
                taxIds: nil,
                modifierListInfo: nil,
                variations: nil,
                productType: "REGULAR",
                skipModifierScreen: false,
                itemOptions: nil,
                imageIds: nil,
                sortName: nil,
                descriptionHtml: nil,
                descriptionPlaintext: nil
            ),
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        let teaItem = CatalogObject(
            id: "item_tea",
            type: "ITEM",
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: ItemData(
                name: "Organic Green Tea",
                description: "Premium organic green tea leaves",
                categoryId: "cat_beverages",
                abbreviation: nil,
                labelColor: nil,
                availableOnline: true,
                availableForPickup: true,
                availableElectronically: false,
                categoryData: nil,
                taxIds: nil,
                modifierListInfo: nil,
                variations: nil,
                productType: "REGULAR",
                skipModifierScreen: false,
                itemOptions: nil,
                imageIds: nil,
                sortName: nil,
                descriptionHtml: nil,
                descriptionPlaintext: nil
            ),
            categoryData: nil,
            itemVariationData: nil,
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        catalogItems["item_coffee"] = coffeeItem
        catalogItems["item_tea"] = teaItem
        
        // Create sample variations
        let coffeeVariation = CatalogObject(
            id: "var_coffee_1lb",
            type: "ITEM_VARIATION",
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: nil,
            categoryData: nil,
            itemVariationData: ItemVariationData(
                itemId: "item_coffee",
                name: "1 lb bag",
                sku: "COFFEE-1LB-001",
                upc: "123456789012",
                ordinal: 1,
                pricingType: "FIXED_PRICING",
                priceMoney: Money(amount: 1299, currency: "USD"), // $12.99
                locationOverrides: nil,
                trackInventory: true,
                inventoryAlertType: nil,
                inventoryAlertThreshold: nil,
                userData: nil,
                serviceDuration: nil,
                availableForBooking: nil,
                itemOptionValues: nil,
                measurementUnitId: nil,
                sellable: true,
                stockable: true,
                imageIds: nil,
                teamMemberIds: nil,
                stockableConversion: nil
            ),
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        let teaVariation = CatalogObject(
            id: "var_tea_50bags",
            type: "ITEM_VARIATION",
            updatedAt: "2024-01-01T00:00:00Z",
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: nil,
            categoryData: nil,
            itemVariationData: ItemVariationData(
                itemId: "item_tea",
                name: "50 tea bags",
                sku: "TEA-50BAG-001",
                upc: "987654321098",
                ordinal: 1,
                pricingType: "FIXED_PRICING",
                priceMoney: Money(amount: 899, currency: "USD"), // $8.99
                locationOverrides: nil,
                trackInventory: true,
                inventoryAlertType: nil,
                inventoryAlertThreshold: nil,
                userData: nil,
                serviceDuration: nil,
                availableForBooking: nil,
                itemOptionValues: nil,
                measurementUnitId: nil,
                sellable: true,
                stockable: true,
                imageIds: nil,
                teamMemberIds: nil,
                stockableConversion: nil
            ),
            modifierData: nil,
            modifierListData: nil,
            taxData: nil,
            discountData: nil
        )
        
        itemVariations["item_coffee"] = [coffeeVariation]
        itemVariations["item_tea"] = [teaVariation]
        
        print("[MockDatabase] INFO: Sample data populated: \(catalogItems.count) items, \(categories.count) categories")
    }
}
