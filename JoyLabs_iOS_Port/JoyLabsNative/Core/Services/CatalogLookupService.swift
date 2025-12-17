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
    private var variationCache: [String: ItemVariationModel] = [:]
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
        // Clear full cache when catalog sync completes
        NotificationCenter.default.addObserver(
            forName: .catalogSyncCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearCache()
            }
        }

        // Clear image cache when images are specifically updated
        NotificationCenter.default.addObserver(
            forName: .imageUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.clearImageCache()
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
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { item in
                item.id == id && !item.isDeleted
            }
        )
        // NOTE: No need to prefetch images - using ImageURLCache instead

        guard let item = try? catalogContext.fetch(descriptor).first else {
            return nil
        }

        // Cache the result
        cacheItem(item)
        return item
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
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    missingIds.contains(item.id) && !item.isDeleted
                }
            )
            // NOTE: No need to prefetch images - using ImageURLCache instead

            if let results = try? catalogContext.fetch(descriptor) {
                fetchedItems = results
                // Cache fetched items
                fetchedItems.forEach { cacheItem($0) }
            } else {
                logger.error("[CatalogLookup] Failed to batch fetch items for IDs: \(missingIds)")
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
        // Check cache first
        if let cachedVariation = getCachedVariation(itemId: itemId) {
            guard let priceAmount = cachedVariation.priceAmount, priceAmount > 0 else {
                return nil
            }
            let convertedPrice = Double(priceAmount) / 100.0
            return convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
        }
        
        // Fetch from database
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            if let variation = try catalogContext.fetch(descriptor).first {
                // Cache the variation for future lookups
                cacheVariation(variation, forItemId: itemId)
                
                guard let priceAmount = variation.priceAmount, priceAmount > 0 else {
                    return nil
                }
                
                let convertedPrice = Double(priceAmount) / 100.0
                return convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
            }
            return nil
        } catch {
            logger.error("[CatalogLookup] Failed to fetch price for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get SKU for item (from primary variation)
    func getSku(for itemId: String) -> String? {
        // Check cache first
        if let cachedVariation = getCachedVariation(itemId: itemId) {
            return cachedVariation.sku
        }
        
        // Fetch from database
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            if let variation = try catalogContext.fetch(descriptor).first {
                // Cache the variation for future lookups
                cacheVariation(variation, forItemId: itemId)
                return variation.sku
            }
            return nil
        } catch {
            logger.error("[CatalogLookup] Failed to fetch SKU for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get barcode/UPC for item (from primary variation)
    func getBarcode(for itemId: String) -> String? {
        // Check cache first
        if let cachedVariation = getCachedVariation(itemId: itemId) {
            return cachedVariation.upc
        }
        
        // Fetch from database
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            if let variation = try catalogContext.fetch(descriptor).first {
                // Cache the variation for future lookups
                cacheVariation(variation, forItemId: itemId)
                return variation.upc
            }
            return nil
        } catch {
            logger.error("[CatalogLookup] Failed to fetch barcode for item \(itemId): \(error)")
            return nil
        }
    }
    
    /// Get variation name for item (from primary variation)
    func getVariationName(for itemId: String) -> String? {
        // Check cache first
        if let cachedVariation = getCachedVariation(itemId: itemId) {
            return cachedVariation.name
        }
        
        // Fetch from database
        do {
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            if let variation = try catalogContext.fetch(descriptor).first {
                // Cache the variation for future lookups
                cacheVariation(variation, forItemId: itemId)
                return variation.name
            }
            return nil
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
        let itemCount = itemCache.count
        let variationCount = variationCache.count
        itemCache.removeAll()
        variationCache.removeAll()
        cacheTimestamp = Date()
        logger.info("[CatalogLookup] Cache cleared - had \(itemCount) items, \(variationCount) variations cached")
    }

    /// Get catalog item by ID with fresh database lookup (bypasses cache)
    /// Use this for image URLs to ensure they're always fresh
    func getItemFresh(id: String) -> CatalogItemModel? {
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { item in
                item.id == id && !item.isDeleted
            }
        )
        // NOTE: No need to prefetch images - using ImageURLCache instead

        guard let item = try? catalogContext.fetch(descriptor).first else {
            return nil
        }

        // Update cache with fresh data
        cacheItem(item)
        return item
    }

    /// Get primary image URL with guaranteed fresh database lookup
    func getPrimaryImageURLFresh(for itemId: String) -> String? {
        let item = getItemFresh(id: itemId)
        return item?.primaryImageUrl
    }

    /// Clear cache specifically for image-related data
    func clearImageCache() {
        // Clear item cache to force fresh image relationship loading
        itemCache.removeAll()
        cacheTimestamp = Date()
        logger.info("[CatalogLookup] Image cache cleared - forcing fresh image relationship lookups")
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
    
    private func getCachedVariation(itemId: String) -> ItemVariationModel? {
        // Check cache validity
        if Date().timeIntervalSince(cacheTimestamp) > cacheTimeout {
            clearCache()
            return nil
        }
        return variationCache[itemId]
    }
    
    private func cacheVariation(_ variation: ItemVariationModel, forItemId itemId: String) {
        variationCache[itemId] = variation
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