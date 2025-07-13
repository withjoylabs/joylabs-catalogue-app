import Foundation
import OSLog

// MARK: - Database Product Repository Implementation

/// Concrete implementation of ProductRepository using the new SQLite.swift database
class DatabaseProductRepository: ProductRepository {

    private var sqliteDB: SQLiteSwiftCatalogManager?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DatabaseProductRepository")

    init() {
        logger.info("DatabaseProductRepository initialized with SQLite.swift")
    }

    @MainActor
    private func getSQLiteDB() -> SQLiteSwiftCatalogManager {
        if let existingDB = sqliteDB {
            return existingDB
        }

        let newDB = SquareAPIServiceFactory.createDatabaseManager()
        sqliteDB = newDB
        return newDB
    }
    
    func getProduct(id: String) async throws -> SearchResultItem? {
        logger.debug("Repository: Getting product \(id) using SQLite.swift")

        let db = await getSQLiteDB()
        // TODO: Implement actual SQLite.swift product lookup
        logger.warning("Product lookup with SQLite.swift not yet implemented - returning nil")
        return nil
    }

    func searchProducts(_ query: String) async throws -> [SearchResultItem] {
        logger.debug("Repository: Searching products '\(query)' using native SearchManager")

        let searchManager = SearchManager(databaseManager: await getSQLiteDB())
        let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)

        return await searchManager.performSearch(searchTerm: query, filters: filters)
    }
    
    func getProductByBarcode(_ barcode: String) async throws -> SearchResultItem? {
        logger.debug("Repository: Getting product by barcode \(barcode)")

        let searchManager = SearchManager(databaseManager: await getSQLiteDB())
        let filters = SearchFilters(name: false, sku: false, barcode: true, category: false)

        let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)
        return results.first // Return the first (best) match
    }
    
    func getRecentProducts(limit: Int) async throws -> [SearchResultItem] {
        logger.debug("Repository: Getting recent products (limit: \(limit))")
        
        // Implementation will query recent scans/orders
        // For now, return empty array (will be implemented when we connect to actual database)
        return []
    }
    
    func getFrequentProducts(limit: Int) async throws -> [SearchResultItem] {
        logger.debug("Repository: Getting frequent products (limit: \(limit))")
        
        // Implementation will query most frequently accessed products
        // For now, return empty array (will be implemented when we connect to actual database)
        return []
    }
    
    func getTeamData(itemId: String) async throws -> TeamData? {
        logger.debug("Repository: Getting team data for item \(itemId)")
        
        // Implementation will query team_data table
        // For now, return nil (will be implemented when we connect to actual database)
        return nil
    }
}

// MARK: - In-Memory Cache Service Implementation

/// High-performance in-memory cache with TTL and LRU eviction
actor InMemoryCacheService: CacheService {
    
    private var productCache: [String: CachedProduct] = [:]
    private var searchCache: [String: CachedSearchResults] = [:]
    private let maxProductCacheSize = 1000
    private let maxSearchCacheSize = 100
    private let productTTL: TimeInterval = 300 // 5 minutes
    private let searchTTL: TimeInterval = 60   // 1 minute
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "InMemoryCacheService")
    
    // MARK: - Product Cache
    
    func getProduct(id: String) async -> SearchResultItem? {
        // Check if cached and not expired
        if let cached = productCache[id],
           !cached.isExpired {
            logger.debug("Cache hit for product: \(id)")
            cached.updateAccessTime() // Update for LRU
            return cached.product
        }
        
        // Remove expired entry
        productCache.removeValue(forKey: id)
        logger.debug("Cache miss for product: \(id)")
        return nil
    }
    
    func setProduct(_ product: SearchResultItem) async {
        logger.debug("Caching product: \(product.id)")
        
        // Evict oldest entries if cache is full
        if productCache.count >= maxProductCacheSize {
            evictOldestProducts()
        }
        
        productCache[product.id] = CachedProduct(
            product: product,
            cachedAt: Date(),
            ttl: productTTL
        )
    }
    
    // MARK: - Search Cache
    
    func getSearchResults(key: String) async -> [SearchResultItem]? {
        // Check if cached and not expired
        if let cached = searchCache[key],
           !cached.isExpired {
            logger.debug("Cache hit for search: \(key)")
            cached.updateAccessTime() // Update for LRU
            return cached.results
        }
        
        // Remove expired entry
        searchCache.removeValue(forKey: key)
        logger.debug("Cache miss for search: \(key)")
        return nil
    }
    
    func setSearchResults(key: String, results: [SearchResultItem]) async {
        logger.debug("Caching search results: \(key) (\(results.count) results)")
        
        // Evict oldest entries if cache is full
        if searchCache.count >= maxSearchCacheSize {
            evictOldestSearchResults()
        }
        
        searchCache[key] = CachedSearchResults(
            results: results,
            cachedAt: Date(),
            ttl: searchTTL
        )
    }
    
    // MARK: - Cache Management
    
    func clearAll() async {
        productCache.removeAll()
        searchCache.removeAll()
        logger.info("All caches cleared")
    }
    
    // MARK: - Private Methods
    
    private func evictOldestProducts() {
        // Find oldest accessed product
        let oldestKey = productCache.min { a, b in
            a.value.lastAccessTime < b.value.lastAccessTime
        }?.key
        
        if let key = oldestKey {
            productCache.removeValue(forKey: key)
            logger.debug("Evicted oldest product from cache: \(key)")
        }
    }
    
    private func evictOldestSearchResults() {
        // Find oldest accessed search results
        let oldestKey = searchCache.min { a, b in
            a.value.lastAccessTime < b.value.lastAccessTime
        }?.key
        
        if let key = oldestKey {
            searchCache.removeValue(forKey: key)
            logger.debug("Evicted oldest search results from cache: \(key)")
        }
    }
}

// MARK: - Data Validation Service Implementation

/// Concrete implementation of DataValidationService
struct DataValidationServiceImpl: DataValidationService {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DataValidationService")
    
    func validateSearchInput(_ input: String) throws -> String {
        logger.debug("Validating search input")
        
        // Use the existing DataValidator
        return try DataValidator.validateSearchInput(input).get()
    }
    
    func validateBarcode(_ barcode: String) -> Bool {
        logger.debug("Validating barcode: \(barcode)")
        
        // Validate common barcode formats
        let patterns = [
            "^\\d{12}$",        // UPC-A (12 digits)
            "^\\d{13}$",        // EAN-13 (13 digits)
            "^\\d{8}$",         // EAN-8 (8 digits)
            "^[A-Za-z0-9]{1,20}$" // Generic alphanumeric (up to 20 chars)
        ]
        
        return patterns.contains { pattern in
            barcode.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

// MARK: - Cache Models

/// Cached product with TTL and LRU tracking
private class CachedProduct {
    let product: SearchResultItem
    let cachedAt: Date
    let ttl: TimeInterval
    private(set) var lastAccessTime: Date
    
    init(product: SearchResultItem, cachedAt: Date, ttl: TimeInterval) {
        self.product = product
        self.cachedAt = cachedAt
        self.ttl = ttl
        self.lastAccessTime = cachedAt
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }
    
    func updateAccessTime() {
        lastAccessTime = Date()
    }
}

/// Cached search results with TTL and LRU tracking
private class CachedSearchResults {
    let results: [SearchResultItem]
    let cachedAt: Date
    let ttl: TimeInterval
    private(set) var lastAccessTime: Date
    
    init(results: [SearchResultItem], cachedAt: Date, ttl: TimeInterval) {
        self.results = results
        self.cachedAt = cachedAt
        self.ttl = ttl
        self.lastAccessTime = cachedAt
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }
    
    func updateAccessTime() {
        lastAccessTime = Date()
    }
}

// MARK: - Mock Implementation for Testing

/// Mock implementation for testing and development
class MockProductRepository: ProductRepository {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "MockProductRepository")
    
    func getProduct(id: String) async throws -> SearchResultItem? {
        logger.debug("Mock: Getting product \(id)")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Return mock product
        return SearchResultItem(
            id: id,
            name: "Mock Product \(id)",
            sku: "MOCK-\(id)",
            price: 9.99,
            barcode: "123456789012",
            categoryId: "mock-category"
        )
    }
    
    func searchProducts(_ query: String) async throws -> [SearchResultItem] {
        logger.debug("Mock: Searching products '\(query)'")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Return mock search results
        return (1...5).map { index in
            SearchResultItem(
                id: "search-\(index)",
                name: "\(query) Product \(index)",
                sku: "SEARCH-\(index)",
                price: Double(index * 2) + 0.99,
                barcode: "12345678901\(index)",
                categoryId: "search-category"
            )
        }
    }
    
    func getProductByBarcode(_ barcode: String) async throws -> SearchResultItem? {
        logger.debug("Mock: Getting product by barcode \(barcode)")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Return mock product
        return SearchResultItem(
            id: "barcode-product",
            name: "Barcode Product",
            sku: "BARCODE-001",
            price: 12.99,
            barcode: barcode,
            categoryId: "barcode-category"
        )
    }
    
    func getRecentProducts(limit: Int) async throws -> [SearchResultItem] {
        logger.debug("Mock: Getting recent products (limit: \(limit))")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Return mock recent products
        return (1...min(limit, 10)).map { index in
            SearchResultItem(
                id: "recent-\(index)",
                name: "Recent Product \(index)",
                sku: "RECENT-\(index)",
                price: Double(index + 5) + 0.99,
                barcode: "98765432101\(index)",
                categoryId: "recent-category"
            )
        }
    }
    
    func getFrequentProducts(limit: Int) async throws -> [SearchResultItem] {
        logger.debug("Mock: Getting frequent products (limit: \(limit))")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Return mock frequent products
        return (1...min(limit, 20)).map { index in
            SearchResultItem(
                id: "frequent-\(index)",
                name: "Frequent Product \(index)",
                sku: "FREQ-\(index)",
                price: Double(index + 10) + 0.99,
                barcode: "11223344556\(index)",
                categoryId: "frequent-category"
            )
        }
    }
    
    func getTeamData(itemId: String) async throws -> TeamData? {
        logger.debug("Mock: Getting team data for item \(itemId)")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Return mock team data
        return TeamData(
            itemId: itemId,
            caseUpc: "123456789012",
            caseCost: 24.99,
            caseQuantity: 12,
            vendor: "Mock Vendor",
            discontinued: false,
            notes: "Mock team data for testing",
            createdAt: "2025-07-05T10:00:00Z",
            updatedAt: "2025-07-05T11:00:00Z",
            lastSyncAt: "2025-07-05T11:00:00Z",
            owner: "test-user"
        )
    }
}
