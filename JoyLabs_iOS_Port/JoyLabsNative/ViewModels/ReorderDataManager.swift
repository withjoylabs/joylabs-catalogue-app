import Foundation
import SQLite
import Combine

@MainActor
class ReorderDataManager: ObservableObject {
    private weak var viewModel: ReorderViewModel?
    
    func setViewModel(_ viewModel: ReorderViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Data Persistence
    func loadReorderData() -> [ReorderItem] {
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            print("📦 Loaded \(items.count) reorder items from storage")
            
            // DEBUG: Log image URLs
            for item in items {
                print("📸 [ReorderLoad] Item '\(item.name)' imageUrl: \(item.imageUrl ?? "nil")")
            }
            
            return items
        } else {
            print("📦 No saved reorder items found")
            return []
        }
    }
    
    func saveReorderData(_ items: [ReorderItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "reorderItems")
            print("💾 Saved \(items.count) reorder items to storage")
        }
    }
    
    // MARK: - Dynamic Data Refresh
    func refreshDynamicDataForReorderItems(_ items: [ReorderItem]) async -> [ReorderItem] {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            print("❌ [ReorderRefresh] Database not connected")
            return items
        }
        
        var updatedItems: [ReorderItem] = []
        
        for item in items {
            do {
                // Query catalog_items table to get ALL current catalog data
                let itemQuery = CatalogTableDefinitions.catalogItems
                    .select(CatalogTableDefinitions.itemName,
                           CatalogTableDefinitions.itemCategoryName,
                           CatalogTableDefinitions.itemReportingCategoryName,
                           CatalogTableDefinitions.itemDataJson)
                    .filter(CatalogTableDefinitions.itemId == item.itemId)
                    .filter(CatalogTableDefinitions.itemIsDeleted == false)
                
                guard let itemRow = try db.pluck(itemQuery) else {
                    print("⚠️ [ReorderRefresh] Item not found in database: \(item.itemId)")
                    updatedItems.append(item)
                    continue
                }
                
                // Get current item name from database
                let currentItemName = try? itemRow.get(CatalogTableDefinitions.itemName)
                
                // Get pre-computed category names
                let reportingCategoryName = try? itemRow.get(CatalogTableDefinitions.itemReportingCategoryName)
                let regularCategoryName = try? itemRow.get(CatalogTableDefinitions.itemCategoryName)
                let categoryName = reportingCategoryName ?? regularCategoryName
                
                let dataJson = try? itemRow.get(CatalogTableDefinitions.itemDataJson)
                
                // Get first variation data for price, SKU, and barcode
                let variationQuery = CatalogTableDefinitions.itemVariations
                    .select(CatalogTableDefinitions.variationPriceAmount,
                           CatalogTableDefinitions.variationSku,
                           CatalogTableDefinitions.variationUpc)
                    .filter(CatalogTableDefinitions.variationItemId == item.itemId)
                    .filter(CatalogTableDefinitions.variationIsDeleted == false)
                    .limit(1)
                
                var price: Double? = nil
                var currentSku: String? = nil
                var currentBarcode: String? = nil
                
                if let variationRow = try db.pluck(variationQuery) {
                    // Extract price
                    let priceAmount = try? variationRow.get(CatalogTableDefinitions.variationPriceAmount)
                    if let amount = priceAmount, amount > 0 {
                        let convertedPrice = Double(amount) / 100.0
                        if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                            price = convertedPrice
                        }
                    }
                    
                    // Extract SKU and barcode
                    currentSku = try? variationRow.get(CatalogTableDefinitions.variationSku)
                    currentBarcode = try? variationRow.get(CatalogTableDefinitions.variationUpc)
                }
                
                // Check if item has taxes
                let hasTax = checkItemHasTaxFromDataJson(dataJson)
                
                // Get team data (vendor, case info) from team_data table
                let teamQuery = CatalogTableDefinitions.teamData
                    .select(CatalogTableDefinitions.teamVendor,
                           CatalogTableDefinitions.teamCaseUpc,
                           CatalogTableDefinitions.teamCaseCost,
                           CatalogTableDefinitions.teamCaseQuantity)
                    .filter(CatalogTableDefinitions.teamDataItemId == item.itemId)
                    .limit(1)
                
                var vendor: String? = nil
                var caseUpc: String? = nil
                var caseCost: Double? = nil
                var caseQuantity: Int? = nil
                
                if let teamRow = try db.pluck(teamQuery) {
                    vendor = try? teamRow.get(CatalogTableDefinitions.teamVendor)
                    caseUpc = try? teamRow.get(CatalogTableDefinitions.teamCaseUpc)
                    caseCost = try? teamRow.get(CatalogTableDefinitions.teamCaseCost)
                    if let caseQty = try? teamRow.get(CatalogTableDefinitions.teamCaseQuantity) {
                        caseQuantity = Int(caseQty)
                    }
                }
                
                // Get primary image data using centralized SimpleImageService
                let imageUrl = await getPrimaryImageForReorderItem(itemId: item.itemId)
                
                // Update reorder item with fresh data from database
                var updatedItem = item
                
                // Update ALL catalog fields with current database values
                updatedItem.name = currentItemName ?? item.name // Fallback to existing name if database value is nil
                updatedItem.sku = currentSku
                updatedItem.barcode = currentBarcode
                updatedItem.price = price
                if let categoryName = categoryName {
                    updatedItem.categoryName = categoryName
                }
                updatedItem.hasTax = hasTax
                
                // Update team data fields
                updatedItem.vendor = vendor
                updatedItem.caseUpc = caseUpc
                updatedItem.caseCost = caseCost
                updatedItem.caseQuantity = caseQuantity
                
                // Update image data - PRESERVE existing if no new data found
                if let imageUrl = imageUrl {
                    updatedItem.imageUrl = imageUrl
                    // Note: SimpleImageService focuses on URLs, not IDs
                } else {
                    // PRESERVE existing image data if refresh fails to find images
                    // Keep existing imageId and imageUrl unchanged
                }
                
                // Verbose logging removed to reduce console spam
                
                updatedItems.append(updatedItem)
                
            } catch {
                print("❌ [ReorderRefresh] Failed to refresh item \(item.itemId): \(error)")
                updatedItems.append(item)
            }
        }
        
        print("🔄 [ReorderRefresh] Refreshed ALL data for \(updatedItems.count) reorder items using pre-computed columns")
        return updatedItems
    }
    
    // MARK: - Targeted Item Updates (No Full Refresh)
    
    /// Updates specific reorder items that reference the changed catalog item
    func updateReorderItemsReferencingCatalogItem(itemId: String) async {
        guard let viewModel = viewModel else { return }
        
        var reorderItems = viewModel.reorderItems
        var hasChanges = false
        
        // Find all reorder items that reference this catalog item
        for i in 0..<reorderItems.count {
            if reorderItems[i].itemId == itemId {
                // Fetch fresh catalog data for this specific item
                if let freshCatalogData = await fetchCatalogData(itemId: itemId) {
                    // Update catalog-derived properties while preserving reorder metadata
                    reorderItems[i].name = freshCatalogData.name
                    reorderItems[i].sku = freshCatalogData.sku
                    reorderItems[i].barcode = freshCatalogData.barcode
                    reorderItems[i].price = freshCatalogData.price
                    reorderItems[i].categoryName = freshCatalogData.categoryName
                    reorderItems[i].hasTax = freshCatalogData.hasTax
                    reorderItems[i].vendor = freshCatalogData.vendor
                    reorderItems[i].caseUpc = freshCatalogData.caseUpc
                    reorderItems[i].caseCost = freshCatalogData.caseCost
                    reorderItems[i].caseQuantity = freshCatalogData.caseQuantity
                    reorderItems[i].imageUrl = freshCatalogData.imageUrl
                    
                    hasChanges = true
                    print("🔄 Updated reorder item referencing catalog item: \(itemId)")
                }
            }
        }
        
        if hasChanges {
            await MainActor.run {
                viewModel.reorderItems = reorderItems
                saveReorderData(reorderItems)
            }
        }
    }
    
    /// Removes reorder items that reference a deleted catalog item
    func removeReorderItemsReferencingCatalogItem(itemId: String) async {
        guard let viewModel = viewModel else { return }
        
        let originalCount = viewModel.reorderItems.count
        let filteredItems = viewModel.reorderItems.filter { $0.itemId != itemId }
        
        if filteredItems.count < originalCount {
            await MainActor.run {
                viewModel.reorderItems = filteredItems
                saveReorderData(filteredItems)
            }
            print("🗑️ Removed reorder items referencing deleted catalog item: \(itemId)")
        }
    }
    
    // MARK: - DEPRECATED: Full Refresh Methods (will be removed)
    func handleCatalogSyncCompleted() async {
        // DEPRECATED: This method performs full refresh - will be replaced by targeted updates
        guard let viewModel = viewModel else { return }
        
        print("🔄 Catalog sync completed - refreshing reorder items data")
        let refreshedItems = await refreshDynamicDataForReorderItems(viewModel.reorderItems)
        
        await MainActor.run {
            viewModel.reorderItems = refreshedItems
            saveReorderData(refreshedItems)
        }
    }
    
    func handleImageUpdated() async {
        guard let viewModel = viewModel else { return }
        
        print("🔄 Image updated - refreshing reorder items data")
        let refreshedItems = await refreshDynamicDataForReorderItems(viewModel.reorderItems)
        
        await MainActor.run {
            viewModel.reorderItems = refreshedItems
            saveReorderData(refreshedItems)
        }
    }
    
    func handleForceImageRefresh() async {
        guard let viewModel = viewModel else { return }
        
        print("🔄 Force image refresh - refreshing reorder items data")
        let refreshedItems = await refreshDynamicDataForReorderItems(viewModel.reorderItems)
        
        await MainActor.run {
            viewModel.reorderItems = refreshedItems
            saveReorderData(refreshedItems)
        }
    }
    
    // MARK: - Universal Item Data Fetcher
    
    /// Fetches complete catalog data for a single item
    private func fetchCatalogData(itemId: String) async -> CatalogData? {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        guard let db = databaseManager.getConnection() else {
            return nil
        }
        
        do {
            // Query catalog_items table
            let itemQuery = CatalogTableDefinitions.catalogItems
                .select(CatalogTableDefinitions.itemName,
                       CatalogTableDefinitions.itemCategoryName,
                       CatalogTableDefinitions.itemReportingCategoryName,
                       CatalogTableDefinitions.itemDataJson)
                .filter(CatalogTableDefinitions.itemId == itemId)
                .filter(CatalogTableDefinitions.itemIsDeleted == false)
            
            guard let itemRow = try db.pluck(itemQuery) else {
                return nil
            }
            
            // Get item data
            let name = try? itemRow.get(CatalogTableDefinitions.itemName)
            let reportingCategoryName = try? itemRow.get(CatalogTableDefinitions.itemReportingCategoryName)
            let regularCategoryName = try? itemRow.get(CatalogTableDefinitions.itemCategoryName)
            let categoryName = reportingCategoryName ?? regularCategoryName
            let dataJson = try? itemRow.get(CatalogTableDefinitions.itemDataJson)
            
            // Get variation data
            let variationQuery = CatalogTableDefinitions.itemVariations
                .select(CatalogTableDefinitions.variationPriceAmount,
                       CatalogTableDefinitions.variationSku,
                       CatalogTableDefinitions.variationUpc)
                .filter(CatalogTableDefinitions.variationItemId == itemId)
                .filter(CatalogTableDefinitions.variationIsDeleted == false)
                .limit(1)
            
            var price: Double? = nil
            var sku: String? = nil
            var barcode: String? = nil
            
            if let variationRow = try db.pluck(variationQuery) {
                let priceAmount = try? variationRow.get(CatalogTableDefinitions.variationPriceAmount)
                if let amount = priceAmount, amount > 0 {
                    let convertedPrice = Double(amount) / 100.0
                    if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                        price = convertedPrice
                    }
                }
                sku = try? variationRow.get(CatalogTableDefinitions.variationSku)
                barcode = try? variationRow.get(CatalogTableDefinitions.variationUpc)
            }
            
            // Get team data
            let teamQuery = CatalogTableDefinitions.teamData
                .select(CatalogTableDefinitions.teamVendor,
                       CatalogTableDefinitions.teamCaseUpc,
                       CatalogTableDefinitions.teamCaseCost,
                       CatalogTableDefinitions.teamCaseQuantity)
                .filter(CatalogTableDefinitions.teamDataItemId == itemId)
                .limit(1)
            
            var vendor: String? = nil
            var caseUpc: String? = nil
            var caseCost: Double? = nil
            var caseQuantity: Int? = nil
            
            if let teamRow = try db.pluck(teamQuery) {
                vendor = try? teamRow.get(CatalogTableDefinitions.teamVendor)
                caseUpc = try? teamRow.get(CatalogTableDefinitions.teamCaseUpc)
                caseCost = try? teamRow.get(CatalogTableDefinitions.teamCaseCost)
                if let caseQty = try? teamRow.get(CatalogTableDefinitions.teamCaseQuantity) {
                    caseQuantity = Int(caseQty)
                }
            }
            
            // Get tax info
            let hasTax = checkItemHasTaxFromDataJson(dataJson)
            
            // Get image URL
            let imageUrl = await getPrimaryImageForReorderItem(itemId: itemId)
            
            return CatalogData(
                name: name ?? "Unknown Item",
                sku: sku,
                barcode: barcode,
                price: price,
                categoryName: categoryName,
                hasTax: hasTax,
                vendor: vendor,
                caseUpc: caseUpc,
                caseCost: caseCost,
                caseQuantity: caseQuantity,
                imageUrl: imageUrl
            )
            
        } catch {
            print("❌ [ReorderDataManager] Failed to fetch catalog data for item \(itemId): \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Functions
    private func checkItemHasTaxFromDataJson(_ dataJson: String?) -> Bool {
        guard let dataJson = dataJson,
              let data = dataJson.data(using: .utf8) else {
            return false
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taxIds = json["tax_ids"] as? [String] {
                return !taxIds.isEmpty
            }
        } catch {
            print("❌ [ReorderRefresh] Failed to parse tax data: \(error)")
        }
        
        return false
    }
    
    private func getPrimaryImageForReorderItem(itemId: String) async -> String? {
        // Use CatalogLookupService for Single Source of Truth from SwiftData
        return CatalogLookupService.shared.getPrimaryImageUrl(for: itemId)
    }
    
    // MARK: - Statistics Calculation
    func calculateStatistics(for items: [ReorderItem]) -> (total: Int, unpurchased: Int, purchased: Int, totalQuantity: Int) {
        let totalItems = items.count
        let unpurchasedItems = items.filter { $0.status == .added }.count
        let purchasedItems = items.filter { $0.status == .purchased || $0.status == .received }.count
        let totalQuantity = items.reduce(0) { $0 + $1.quantity }
        
        return (total: totalItems, unpurchased: unpurchasedItems, purchased: purchasedItems, totalQuantity: totalQuantity)
    }
}

// MARK: - Supporting Data Structures

/// Represents complete catalog data for a single item
private struct CatalogData {
    let name: String
    let sku: String?
    let barcode: String?
    let price: Double?
    let categoryName: String?
    let hasTax: Bool
    let vendor: String?
    let caseUpc: String?
    let caseCost: Double?
    let caseQuantity: Int?
    let imageUrl: String?
}