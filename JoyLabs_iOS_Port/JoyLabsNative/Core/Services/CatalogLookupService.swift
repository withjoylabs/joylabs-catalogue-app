import Foundation
import SwiftData
import OSLog

/// Efficient cross-container catalog lookup service
/// Provides computed access to catalog data from any container
@MainActor
class CatalogLookupService {
    static let shared = CatalogLookupService()
    
    private let catalogContext: ModelContext
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogLookupService")
    
    // In-memory cache for frequently accessed items
    private var itemCache: [String: CatalogItemModel] = [:]
    private var cacheTimestamp: Date = Date()
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Get shared catalog database context
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
            self?.clearCache()
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
    
    /// Get primary image URL for item
    func getPrimaryImageURL(for itemId: String) async -> String? {
        return await SimpleImageService.shared.getPrimaryImageURL(for: itemId)
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