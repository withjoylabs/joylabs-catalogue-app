import Foundation
import SwiftData

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
        print(" [ReorderService] Model context has been set successfully")
    }
    
    
    // MARK: - CRUD Operations
    
    func addOrUpdateItem(from searchResult: SearchResultItem, quantity: Int) {
        guard let context = modelContext else {
            print("[ReorderService] addOrUpdateItem failed - modelContext is nil")
            return
        }
        
        // Capture the search result ID for predicate
        let searchResultId = searchResult.id
        
        // Check if item already exists
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.catalogItemId == searchResultId }
        )
        
        do {
            let existingItems = try context.fetch(descriptor)
            
            if let existingItem = existingItems.first {
                // Update quantity only (catalog data is computed automatically)
                existingItem.quantity = quantity
                existingItem.lastUpdated = Date()
                print("[ReorderService] Updated existing reorder item quantity to \(quantity)")
            } else {
                // Create new item with minimal data (catalog data computed automatically)
                let newItem = ReorderItemModel(
                    catalogItemId: searchResult.id,
                    quantity: quantity
                )
                
                context.insert(newItem)
                print("[ReorderService] Added new item to reorder list: \(newItem.name)")
            }
            
            try context.save()
        } catch {
            print("[ReorderService] Failed to add/update reorder item: \(error)")
        }
    }
    
    func updateItemStatus(_ itemId: String, status: ReorderItemStatus) {
        guard let context = modelContext else {
            print(" [ReorderService] updateItemStatus failed - modelContext is nil")
            return
        }
        
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
            print(" Failed to update item status: \(error)")
        }
    }
    
    func updateItemQuantity(_ itemId: String, quantity: Int) {
        guard let context = modelContext else {
            print(" [ReorderService] updateItemQuantity failed - modelContext is nil")
            return
        }
        
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
            print(" Failed to update item quantity: \(error)")
        }
    }
    
    func removeItem(_ itemId: String) {
        guard let context = modelContext else {
            print(" [ReorderService] removeItem failed - modelContext is nil")
            return
        }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.id == itemId }
        )
        
        do {
            if let item = try context.fetch(descriptor).first {
                context.delete(item)
                try context.save()
                print(" Removed item from reorder list")
            }
        } catch {
            print(" Failed to remove item: \(error)")
        }
    }
    
    func clearAllItems() {
        guard let context = modelContext else {
            print(" [ReorderService] clearAllItems failed - modelContext is nil")
            return
        }
        
        do {
            try context.delete(model: ReorderItemModel.self)
            try context.save()
            print(" Cleared all reorder items")
        } catch {
            print(" Failed to clear items: \(error)")
        }
    }
    
    // MARK: - Badge Count Support
    func getUnpurchasedCount() async -> Int {
        guard let context = modelContext else {
            print(" [ReorderService] getUnpurchasedCount failed - modelContext is nil")
            return 0
        }
        
        let descriptor = FetchDescriptor<ReorderItemModel>(
            predicate: #Predicate { item in item.status == "added" }
        )
        
        do {
            let items = try context.fetch(descriptor)
            return items.count
        } catch {
            print(" Failed to get unpurchased count: \(error)")
            return 0
        }
    }
    
    func markAllAsReceived() {
        guard let context = modelContext else {
            print(" [ReorderService] markAllAsReceived failed - modelContext is nil")
            return
        }
        
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
            print(" Failed to mark all as received: \(error)")
        }
    }
    
    // MARK: - Catalog Integration
    
    /// Clear cache when catalog data changes (computed properties will fetch fresh data automatically)
    func refreshCatalogCache() {
        CatalogLookupService.shared.clearCache()
        print("[ReorderService] Catalog cache cleared - computed properties will fetch fresh data")
    }
    
    func removeItemsForDeletedCatalogItem(itemId: String) async {
        guard let context = modelContext else { return }
        
        do {
            try context.delete(model: ReorderItemModel.self, where: #Predicate { item in item.catalogItemId == itemId })
            try context.save()
            print("[ReorderService] Removed reorder items for deleted catalog item: \(itemId)")
        } catch {
            print(" Failed to remove items for deleted catalog: \(error)")
        }
    }
    
}