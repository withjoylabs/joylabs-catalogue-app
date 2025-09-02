import Foundation
import SwiftData
import SQLite

// MARK: - Reorder Service (Single Source of Truth)
// Manages all reorder operations through SwiftData
@MainActor
final class ReorderService: ObservableObject {
    static let shared = ReorderService()
    
    private var modelContext: ModelContext?
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
    
    private init() {}
    
    // MARK: - Setup
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    
    // MARK: - CRUD Operations
    
    func addOrUpdateItem(from searchResult: SearchResultItem, quantity: Int) {
        guard let context = modelContext else { return }
        
        // Capture the search result ID for predicate
        let searchResultId = searchResult.id
        
        // Check if item already exists
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.itemId == searchResultId }
        )
        
        do {
            let existingItems = try context.fetch(descriptor)
            
            if let existingItem = existingItems.first {
                // Update quantity
                existingItem.quantity = quantity
                existingItem.lastUpdated = Date()
                print("✅ Updated existing reorder item quantity to \(quantity)")
            } else {
                // Create new item
                let newItem = ReorderItemModel(
                    itemId: searchResult.id,
                    name: searchResult.name ?? "Unknown Item",
                    sku: searchResult.sku,
                    barcode: searchResult.barcode,
                    variationName: searchResult.variationName,
                    quantity: quantity
                )
                
                // Set catalog fields
                newItem.categoryName = searchResult.categoryName
                newItem.price = searchResult.price
                newItem.hasTax = searchResult.hasTax
                
                if let images = searchResult.images, let firstImage = images.first {
                    newItem.imageId = firstImage.id
                    newItem.imageUrl = firstImage.imageData?.url
                }
                
                context.insert(newItem)
                print("✅ Added new item to reorder list: \(newItem.name)")
            }
            
            try context.save()
        } catch {
            print("❌ Failed to add/update reorder item: \(error)")
        }
    }
    
    func updateItemStatus(_ itemId: String, status: ReorderItemStatus) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.id == itemId }
        )
        
        do {
            if let item = try context.fetch(descriptor).first {
                item.statusEnum = status
                
                switch status {
                case .purchased:
                    item.purchasedDate = Date()
                case .received:
                    item.receivedDate = Date()
                case .added:
                    item.purchasedDate = nil
                    item.receivedDate = nil
                }
                
                item.lastUpdated = Date()
                try context.save()
                
                // Remove if received
                if status == .received {
                    context.delete(item)
                    try context.save()
                }
            }
        } catch {
            print("❌ Failed to update item status: \(error)")
        }
    }
    
    func updateItemQuantity(_ itemId: String, quantity: Int) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.id == itemId }
        )
        
        do {
            if let item = try context.fetch(descriptor).first {
                item.quantity = max(1, quantity)
                item.lastUpdated = Date()
                try context.save()
            }
        } catch {
            print("❌ Failed to update item quantity: \(error)")
        }
    }
    
    func removeItem(_ itemId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.id == itemId }
        )
        
        do {
            if let item = try context.fetch(descriptor).first {
                context.delete(item)
                try context.save()
                print("🗑️ Removed item from reorder list")
            }
        } catch {
            print("❌ Failed to remove item: \(error)")
        }
    }
    
    func clearAllItems() {
        guard let context = modelContext else { return }
        
        do {
            try context.delete(model: ReorderItemModel.self)
            try context.save()
            print("🗑️ Cleared all reorder items")
        } catch {
            print("❌ Failed to clear items: \(error)")
        }
    }
    
    // MARK: - Badge Count Support
    func getUnpurchasedCount() async -> Int {
        guard let context = modelContext else { return 0 }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.status == "added" }
        )
        
        do {
            let items = try context.fetch(descriptor)
            return items.count
        } catch {
            print("❌ Failed to get unpurchased count: \(error)")
            return 0
        }
    }
    
    func markAllAsReceived() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.status == "added" }
        )
        
        do {
            let items = try context.fetch(descriptor)
            for item in items {
                item.statusEnum = .received
                item.receivedDate = Date()
                item.lastUpdated = Date()
            }
            try context.save()
            
            // Then delete all received items
            try context.delete(model: ReorderItemModel.self, where: #Predicate { item in item.status == "received" })
            try context.save()
        } catch {
            print("❌ Failed to mark all as received: \(error)")
        }
    }
    
    // MARK: - Catalog Updates (Called by CentralItemUpdateManager)
    
    func updateItemsFromCatalog(itemId: String) async {
        guard let context = modelContext else { return }
        guard let db = databaseManager.getConnection() else { return }
        
        // Find all reorder items referencing this catalog item
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.itemId == itemId }
        )
        
        do {
            let items = try context.fetch(descriptor)
            guard !items.isEmpty else { return }
            
            // Fetch fresh catalog data
            if let catalogData = await fetchCatalogData(itemId: itemId, db: db) {
                for item in items {
                    item.updateFromCatalog(
                        name: catalogData.name,
                        sku: catalogData.sku,
                        barcode: catalogData.barcode,
                        price: catalogData.price,
                        categoryName: catalogData.categoryName,
                        hasTax: catalogData.hasTax,
                        vendor: catalogData.vendor,
                        caseUpc: catalogData.caseUpc,
                        caseCost: catalogData.caseCost,
                        caseQuantity: catalogData.caseQuantity,
                        imageUrl: catalogData.imageUrl
                    )
                }
                
                try context.save()
                print("✅ Updated \(items.count) reorder items from catalog")
            }
        } catch {
            print("❌ Failed to update items from catalog: \(error)")
        }
    }
    
    func removeItemsForDeletedCatalogItem(itemId: String) async {
        guard let context = modelContext else { return }
        
        do {
            try context.delete(model: ReorderItemModel.self, where: #Predicate { item in item.itemId == itemId })
            try context.save()
            print("🗑️ Removed reorder items for deleted catalog item: \(itemId)")
        } catch {
            print("❌ Failed to remove items for deleted catalog: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchCatalogData(itemId: String, db: Connection) async -> CatalogData? {
        do {
            // Query catalog_items using SwiftData
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            guard let catalogItem = try db.fetch(itemDescriptor).first else {
                return nil
            }
            
            // Get item data
            let name = catalogItem.name
            let reportingCategoryName = catalogItem.reportingCategoryName
            let regularCategoryName = catalogItem.categoryName
            let categoryName = reportingCategoryName ?? regularCategoryName
            let dataJson = catalogItem.dataJson
            
            // Get variation data using SwiftData
            let variationDescriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            var price: Double? = nil
            var sku: String? = nil
            var barcode: String? = nil
            
            if let variation = try db.fetch(variationDescriptor).first {
                let priceAmount = variation.priceAmount
                if let amount = priceAmount, amount > 0 {
                    let convertedPrice = Double(amount) / 100.0
                    if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                        price = convertedPrice
                    }
                }
                sku = variation.sku
                barcode = variation.upc
            }
            
            // Get tax info
            let hasTax = checkItemHasTaxFromDataJson(dataJson)
            
            // Get image URL
            let imageUrl = await SimpleImageService.shared.getPrimaryImageURL(for: itemId)
            
            return CatalogData(
                name: name ?? "Unknown Item",
                sku: sku,
                barcode: barcode,
                price: price,
                categoryName: categoryName,
                hasTax: hasTax,
                vendor: nil,  // Team data would go here
                caseUpc: nil,
                caseCost: nil,
                caseQuantity: nil,
                imageUrl: imageUrl
            )
            
        } catch {
            print("❌ Failed to fetch catalog data: \(error)")
            return nil
        }
    }
    
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
            print("❌ Failed to parse tax data: \(error)")
        }
        
        return false
    }
}

// MARK: - Supporting Data Structure
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