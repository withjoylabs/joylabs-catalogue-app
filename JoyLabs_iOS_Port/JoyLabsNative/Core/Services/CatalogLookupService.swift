import Foundation
import SwiftData
import OSLog

/// Efficient cross-container catalog lookup service
/// Provides computed access to catalog data from any container
/// Thread-safe for use in computed properties
@MainActor
class CatalogLookupService {
    static let shared = CatalogLookupService()
    
    private let catalogContext: ModelContext
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogLookupService")
    
    // Simple MainActor cache (no concurrent access needed for lookup service)
    private var itemCache: [String: CatalogItemModel] = [:]
    private var cacheTimestamp: Date = Date()
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Initialize with MainActor context - ModelContext requires MainActor
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        self.catalogContext = databaseManager.getContext()
        
        // Setup automatic cache clearing when catalog syncs complete
        setupCatalogSyncObserver()
        
        logger.info("[CatalogLookup] CatalogLookupService initialized")
    }
    
    private func setupCatalogSyncObserver() {
        NotificationCenter.default.addObserver(
            forName: .catalogSyncCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearCache()
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Get single catalog item by ID
    func getItem(id: String) -> CatalogItemModel? {
        // Check cache first
        if let cachedItem = getCachedItem(id: id) {
            return cachedItem
        }
        
        // Fetch from database
        do {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == id && !item.isDeleted
                }
            )
            
            let item = try catalogContext.fetch(descriptor).first
            
            // Cache the result
            if let item = item {
                cacheItem(item)
            }
            
            return item
        } catch {
            logger.error("[CatalogLookup] Failed to fetch item \(id): \(error)")
            return nil
        }
    }
    
    /// Get multiple catalog items by IDs (batch lookup for efficiency)
    func getItems(ids: [String]) -> [CatalogItemModel] {
        guard !ids.isEmpty else { return [] }
        
        // Check cache for all items first
        var cachedItems: [CatalogItemModel] = []
        var missingIds: [String] = []
        
        for id in ids {
            if let cachedItem = getCachedItem(id: id) {
                cachedItems.append(cachedItem)
            } else {
                missingIds.append(id)
            }
        }
        
        // Fetch missing items from database
        var fetchedItems: [CatalogItemModel] = []
        if !missingIds.isEmpty {
            do {
                let descriptor = FetchDescriptor<CatalogItemModel>(
                    predicate: #Predicate { item in
                        missingIds.contains(item.id) && !item.isDeleted
                    }
                )
                
                fetchedItems = try catalogContext.fetch(descriptor)
                
                // Cache fetched items
                fetchedItems.forEach { cacheItem($0) }
                
            } catch {
                logger.error("[CatalogLookup] Failed to batch fetch items: \(error)")
            }
        }
        
        return cachedItems + fetchedItems
    }
    
    /// Get primary image URL for item (synchronous, from SwiftData)
    func getPrimaryImageUrl(for itemId: String) -> String? {
        let item = getItem(id: itemId)
        return item?.primaryImageUrl  // Uses CatalogItemModel's computed property
    }
    
    /// Get primary image URL for item (async, for compatibility)
    func getPrimaryImageURL(for itemId: String) async -> String? {
        return getPrimaryImageUrl(for: itemId)
    }
    
    /// Get current price for item (from variation data)
    func getCurrentPrice(for itemId: String) -> Double? {
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            guard let variation = try catalogContext.fetch(descriptor).first,
                  let priceAmount = variation.priceAmount,
                  priceAmount > 0 else {
                return nil
            }
            
            let convertedPrice = Double(priceAmount) / 100.0
            return convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
            
        } catch {
            logger.error("[CatalogLookup] Failed to fetch price for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get SKU for item (from primary variation)
    func getSku(for itemId: String) -> String? {
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            return try catalogContext.fetch(descriptor).first?.sku
        } catch {
            logger.error("[CatalogLookup] Failed to fetch SKU for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get barcode/UPC for item (from primary variation)
    func getBarcode(for itemId: String) -> String? {
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            return try catalogContext.fetch(descriptor).first?.upc
        } catch {
            logger.error("[CatalogLookup] Failed to fetch barcode for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get variation name for item (from primary variation)
    func getVariationName(for itemId: String) -> String? {
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            return try catalogContext.fetch(descriptor).first?.name
        } catch {
            logger.error("[CatalogLookup] Failed to fetch variation name for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Check if item has tax (from tax relationships or dataJson)
    func getHasTax(for itemId: String) -> Bool {
        guard let item = getItem(id: itemId) else { return false }
        
        // Check tax relationships first
        if let taxes = item.taxes, !taxes.isEmpty {
            return true
        }
        
        // Fallback to parsing dataJson for tax_ids
        guard let dataJson = item.dataJson,
              let data = dataJson.data(using: .utf8) else {
            return false
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taxIds = json["tax_ids"] as? [String] {
                return !taxIds.isEmpty
            }
        } catch {
            logger.error("[CatalogLookup] Failed to parse tax data for item \(itemId): \(error)")
        }
        
        return false
    }
    
    /// Clear cache (call when catalog sync completes)
    func clearCache() {
        itemCache.removeAll()
        cacheTimestamp = Date()
        logger.debug("[CatalogLookup] Cache cleared")
    }
    
    // MARK: - Private Methods
    
    private func getCachedItem(id: String) -> CatalogItemModel? {
        // Check cache validity
        if Date().timeIntervalSince(cacheTimestamp) > cacheTimeout {
            clearCache()
            return nil
        }
        return itemCache[id]
    }
    
    private func cacheItem(_ item: CatalogItemModel) {
        itemCache[item.id] = item
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Computed Property Extensions

extension CatalogLookupService {
    /// Get item data for display purposes
    func getItemDisplayData(for itemId: String) -> CatalogItemDisplayData? {
        guard let item = getItem(id: itemId) else { return nil }
        
        return CatalogItemDisplayData(
            id: item.id,
            name: item.name,
            categoryName: item.reportingCategoryName ?? item.categoryName,
            currentPrice: getCurrentPrice(for: itemId)
        )
    }
}

// MARK: - Supporting Types

struct CatalogItemDisplayData {
    let id: String
    let name: String?
    let categoryName: String?
    let currentPrice: Double?
}