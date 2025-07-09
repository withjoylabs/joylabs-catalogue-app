import Foundation
import OSLog

/// Single Code Path ProductService - Unified service for scan and reorder pages
/// Uses 2025 industry standards: protocol-based dependency injection, structured concurrency, comprehensive caching
@MainActor
class ProductService: ObservableObject {
    
    // MARK: - Dependencies (Protocol-based DI)
    
    private let repository: ProductRepository
    private let cache: CacheService
    private let validator: DataValidationService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ProductService")
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var searchResults: [SearchResultItem] = []
    @Published var recentProducts: [SearchResultItem] = []
    @Published var error: ProductServiceError?
    
    // MARK: - Performance Tracking
    
    private var performanceMetrics = ProductServiceMetrics()
    
    // MARK: - Initialization
    
    init(
        repository: ProductRepository = DatabaseProductRepository(),
        cache: CacheService = InMemoryCacheService(),
        validator: DataValidationService = DataValidationServiceImpl()
    ) {
        self.repository = repository
        self.cache = cache
        self.validator = validator
        logger.info("ProductService initialized with dependency injection")
    }
    
    // MARK: - Single Code Path Methods (Used by both Scan & Reorder)
    
    /// Get product by ID - Single method used by both scan and reorder pages
    func getProduct(id: String) async throws -> SearchResultItem? {
        let startTime = Date()
        logger.debug("Getting product: \(id)")
        
        do {
            // Validate input
            guard !id.isEmpty else {
                throw ProductServiceError.invalidInput("Product ID cannot be empty")
            }
            
            // Check cache first (L1 cache)
            if let cachedProduct = await cache.getProduct(id: id) {
                logger.debug("Product found in cache: \(id)")
                performanceMetrics.recordCacheHit(duration: Date().timeIntervalSince(startTime))
                return cachedProduct
            }
            
            // Fetch from repository
            let product = try await repository.getProduct(id: id)
            
            // Cache the result
            if let product = product {
                await cache.setProduct(product)
            }
            
            performanceMetrics.recordRepositoryFetch(duration: Date().timeIntervalSince(startTime))
            logger.debug("Product fetched from repository: \(id)")
            
            return product
            
        } catch {
            logger.error("Failed to get product \(id): \(error.localizedDescription)")
            throw ProductServiceError.fetchFailed(error)
        }
    }
    
    /// Search products - Single method used by both scan and reorder pages
    func searchProducts(_ query: String) async throws -> [SearchResultItem] {
        let startTime = Date()
        logger.debug("Searching products: \(query)")
        
        do {
            isLoading = true
            error = nil
            
            // Validate and sanitize input
            let sanitizedQuery = try validator.validateSearchInput(query)
            
            // Check search cache (L2 cache)
            let cacheKey = "search:\(sanitizedQuery)"
            if let cachedResults = await cache.getSearchResults(key: cacheKey) {
                logger.debug("Search results found in cache: \(sanitizedQuery)")
                performanceMetrics.recordSearchCacheHit(duration: Date().timeIntervalSince(startTime))
                
                DispatchQueue.main.async {
                    self.searchResults = cachedResults
                    self.isLoading = false
                }
                return cachedResults
            }
            
            // Perform search
            let results = try await repository.searchProducts(sanitizedQuery)
            
            // Cache search results
            await cache.setSearchResults(key: cacheKey, results: results)
            
            // Update UI
            DispatchQueue.main.async {
                self.searchResults = results
                self.isLoading = false
            }
            
            performanceMetrics.recordSearch(
                query: sanitizedQuery,
                resultCount: results.count,
                duration: Date().timeIntervalSince(startTime)
            )
            
            logger.debug("Search completed: \(results.count) results for '\(sanitizedQuery)'")
            return results
            
        } catch {
            DispatchQueue.main.async {
                self.error = ProductServiceError.searchFailed(error)
                self.isLoading = false
            }
            
            logger.error("Search failed for '\(query)': \(error.localizedDescription)")
            throw ProductServiceError.searchFailed(error)
        }
    }
    
    /// Get product by barcode - Used by scan page
    func getProductByBarcode(_ barcode: String) async throws -> SearchResultItem? {
        logger.debug("Getting product by barcode: \(barcode)")
        
        do {
            // Validate barcode format
            guard validator.validateBarcode(barcode) else {
                throw ProductServiceError.invalidBarcode(barcode)
            }
            
            // Use repository to find by barcode
            let product = try await repository.getProductByBarcode(barcode)
            
            // Cache if found
            if let product = product {
                await cache.setProduct(product)
            }
            
            return product
            
        } catch {
            logger.error("Failed to get product by barcode \(barcode): \(error.localizedDescription)")
            throw ProductServiceError.barcodeLookupFailed(error)
        }
    }
    
    /// Get recent products - Used by reorder page
    func getRecentProducts(limit: Int = 20) async throws -> [SearchResultItem] {
        logger.debug("Getting recent products (limit: \(limit))")
        
        do {
            let products = try await repository.getRecentProducts(limit: limit)
            
            DispatchQueue.main.async {
                self.recentProducts = products
            }
            
            return products
            
        } catch {
            logger.error("Failed to get recent products: \(error.localizedDescription)")
            throw ProductServiceError.fetchFailed(error)
        }
    }
    
    /// Get product details with team data - Enhanced method for both pages
    func getProductWithTeamData(id: String) async throws -> ProductWithTeamData? {
        logger.debug("Getting product with team data: \(id)")
        
        do {
            // Get base product
            guard let product = try await getProduct(id: id) else {
                return nil
            }
            
            // Get team data
            let teamData = try await repository.getTeamData(itemId: id)
            
            return ProductWithTeamData(
                product: product,
                teamData: teamData
            )
            
        } catch {
            logger.error("Failed to get product with team data \(id): \(error.localizedDescription)")
            throw ProductServiceError.fetchFailed(error)
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches
    func clearCache() async {
        await cache.clearAll()
        logger.info("All caches cleared")
    }
    
    /// Preload frequently used products
    func preloadFrequentProducts() async {
        logger.info("Preloading frequent products")
        
        do {
            let frequentProducts = try await repository.getFrequentProducts(limit: 50)
            
            for product in frequentProducts {
                await cache.setProduct(product)
            }
            
            logger.info("Preloaded \(frequentProducts.count) frequent products")
            
        } catch {
            logger.error("Failed to preload frequent products: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Performance Monitoring
    
    /// Get performance metrics for monitoring
    func getPerformanceMetrics() -> ProductServiceMetrics {
        return performanceMetrics
    }
    
    /// Reset performance metrics
    func resetMetrics() {
        performanceMetrics = ProductServiceMetrics()
        logger.info("Performance metrics reset")
    }
}

// MARK: - Protocol Definitions

/// Product repository protocol for dependency injection
protocol ProductRepository {
    func getProduct(id: String) async throws -> SearchResultItem?
    func searchProducts(_ query: String) async throws -> [SearchResultItem]
    func getProductByBarcode(_ barcode: String) async throws -> SearchResultItem?
    func getRecentProducts(limit: Int) async throws -> [SearchResultItem]
    func getFrequentProducts(limit: Int) async throws -> [SearchResultItem]
    func getTeamData(itemId: String) async throws -> TeamData?
}

/// Cache service protocol for dependency injection
protocol CacheService {
    func getProduct(id: String) async -> SearchResultItem?
    func setProduct(_ product: SearchResultItem) async
    func getSearchResults(key: String) async -> [SearchResultItem]?
    func setSearchResults(key: String, results: [SearchResultItem]) async
    func clearAll() async
}

/// Data validation service protocol for dependency injection
protocol DataValidationService {
    func validateSearchInput(_ input: String) throws -> String
    func validateBarcode(_ barcode: String) -> Bool
}

// MARK: - Enhanced Models

/// Product with team data for comprehensive display
struct ProductWithTeamData {
    let product: SearchResultItem
    let teamData: TeamData?
    
    var hasTeamData: Bool {
        teamData != nil
    }
    
    var displayName: String {
        product.name ?? "Unknown Product"
    }
    
    var caseInfo: String? {
        guard let teamData = teamData,
              let caseUpc = teamData.caseUpc,
              let caseQuantity = teamData.caseQuantity else {
            return nil
        }
        return "Case UPC: \(caseUpc) (Qty: \(caseQuantity))"
    }
}

// MARK: - Performance Metrics

/// Performance metrics for monitoring and optimization
class ProductServiceMetrics {
    private(set) var cacheHits = 0
    private(set) var cacheMisses = 0
    private(set) var repositoryFetches = 0
    private(set) var searchQueries = 0
    private(set) var totalCacheTime: TimeInterval = 0
    private(set) var totalRepositoryTime: TimeInterval = 0
    private(set) var totalSearchTime: TimeInterval = 0
    
    func recordCacheHit(duration: TimeInterval) {
        cacheHits += 1
        totalCacheTime += duration
    }
    
    func recordCacheMiss() {
        cacheMisses += 1
    }
    
    func recordRepositoryFetch(duration: TimeInterval) {
        repositoryFetches += 1
        totalRepositoryTime += duration
    }
    
    func recordSearch(query: String, resultCount: Int, duration: TimeInterval) {
        searchQueries += 1
        totalSearchTime += duration
    }
    
    func recordSearchCacheHit(duration: TimeInterval) {
        cacheHits += 1
        totalCacheTime += duration
    }
    
    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0
    }
    
    var averageCacheTime: TimeInterval {
        cacheHits > 0 ? totalCacheTime / Double(cacheHits) : 0
    }
    
    var averageRepositoryTime: TimeInterval {
        repositoryFetches > 0 ? totalRepositoryTime / Double(repositoryFetches) : 0
    }
    
    var averageSearchTime: TimeInterval {
        searchQueries > 0 ? totalSearchTime / Double(searchQueries) : 0
    }
}

// MARK: - Service Errors

enum ProductServiceError: LocalizedError {
    case invalidInput(String)
    case invalidBarcode(String)
    case fetchFailed(Error)
    case searchFailed(Error)
    case barcodeLookupFailed(Error)
    case cacheError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .invalidBarcode(let barcode):
            return "Invalid barcode format: \(barcode)"
        case .fetchFailed(let error):
            return "Failed to fetch product: \(error.localizedDescription)"
        case .searchFailed(let error):
            return "Search failed: \(error.localizedDescription)"
        case .barcodeLookupFailed(let error):
            return "Barcode lookup failed: \(error.localizedDescription)"
        case .cacheError(let error):
            return "Cache error: \(error.localizedDescription)"
        }
    }
}
