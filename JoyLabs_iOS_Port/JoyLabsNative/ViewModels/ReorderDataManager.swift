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
                // Query catalog_items table directly to get pre-computed category names
                let itemQuery = CatalogTableDefinitions.catalogItems
                    .select(CatalogTableDefinitions.itemCategoryName,
                           CatalogTableDefinitions.itemReportingCategoryName,
                           CatalogTableDefinitions.itemDataJson)
                    .filter(CatalogTableDefinitions.itemId == item.itemId)
                    .filter(CatalogTableDefinitions.itemIsDeleted == false)
                
                guard let itemRow = try db.pluck(itemQuery) else {
                    print("⚠️ [ReorderRefresh] Item not found in database: \(item.itemId)")
                    updatedItems.append(item)
                    continue
                }
                
                // Get pre-computed category names
                let reportingCategoryName = try? itemRow.get(CatalogTableDefinitions.itemReportingCategoryName)
                let regularCategoryName = try? itemRow.get(CatalogTableDefinitions.itemCategoryName)
                let categoryName = reportingCategoryName ?? regularCategoryName
                
                let dataJson = try? itemRow.get(CatalogTableDefinitions.itemDataJson)
                
                // Get first variation data for price
                let variationQuery = CatalogTableDefinitions.itemVariations
                    .select(CatalogTableDefinitions.variationPriceAmount)
                    .filter(CatalogTableDefinitions.variationItemId == item.itemId)
                    .filter(CatalogTableDefinitions.variationIsDeleted == false)
                    .limit(1)
                
                var price: Double? = nil
                if let variationRow = try db.pluck(variationQuery) {
                    let priceAmount = try? variationRow.get(CatalogTableDefinitions.variationPriceAmount)
                    if let amount = priceAmount, amount > 0 {
                        let convertedPrice = Double(amount) / 100.0
                        if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                            price = convertedPrice
                        }
                    }
                }
                
                // Check if item has taxes
                let hasTax = checkItemHasTaxFromDataJson(dataJson)
                
                // Get primary image data using centralized SimpleImageService
                let imageUrl = await getPrimaryImageForReorderItem(itemId: item.itemId)
                
                // Update reorder item with fresh data
                var updatedItem = item
                updatedItem.price = price
                if let categoryName = categoryName {
                    updatedItem.categoryName = categoryName
                }
                updatedItem.hasTax = hasTax
                
                // Update image data - PRESERVE existing if no new data found
                if let imageUrl = imageUrl {
                    updatedItem.imageUrl = imageUrl
                    // Note: SimpleImageService focuses on URLs, not IDs
                } else {
                    // PRESERVE existing image data if refresh fails to find images
                    // Keep existing imageId and imageUrl unchanged
                }
                
                print("🔄 [ReorderRefresh] Updated ALL data for '\(item.name)'")
                print("   - Price: \(updatedItem.price?.description ?? "nil")")
                print("   - Category: \(updatedItem.categoryName ?? "nil")")
                print("   - Image URL: \(updatedItem.imageUrl ?? "nil")")
                print("   - Has Tax: \(updatedItem.hasTax)")
                
                updatedItems.append(updatedItem)
                
            } catch {
                print("❌ [ReorderRefresh] Failed to refresh item \(item.itemId): \(error)")
                updatedItems.append(item)
            }
        }
        
        print("🔄 [ReorderRefresh] Refreshed ALL data for \(updatedItems.count) reorder items using pre-computed columns")
        return updatedItems
    }
    
    // MARK: - Notification-Triggered Refresh
    func handleCatalogSyncCompleted() async {
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
        // Use centralized SimpleImageService instead of parsing JSON directly
        let imageService = SimpleImageService.shared
        return await imageService.getPrimaryImageURL(for: itemId)
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