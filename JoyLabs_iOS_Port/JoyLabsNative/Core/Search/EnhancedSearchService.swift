import Foundation
import OSLog
import Combine

/// Enhanced Search Service with multi-level caching and streaming results
/// Uses AsyncSequence for streaming search results and comprehensive performance monitoring
@MainActor
class EnhancedSearchService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let productService: ProductService
    private let cacheManager: MultiLevelCacheManager
    private let performanceMonitor: SearchPerformanceMonitor
    private let logger = Logger(subsystem: "com.joylabs.native", category: "EnhancedSearchService")
    
    // MARK: - Published State
    
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching = false
    @Published var searchError: SearchError?
    @Published var searchMetrics: SearchMetrics?
    
    // MARK: - Private State
    
    private var currentSearchTask: Task<Void, Never>?
    private var searchDebounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.3
    
    // MARK: - Initialization
    
    init(
        productService: ProductService? = nil,
        cacheManager: MultiLevelCacheManager? = nil,
        performanceMonitor: SearchPerformanceMonitor? = nil
    ) {
        self.productService = productService ?? ProductService()
        self.cacheManager = cacheManager ?? MultiLevelCacheManager()
        self.performanceMonitor = performanceMonitor ?? SearchPerformanceMonitor()
        logger.info("EnhancedSearchService initialized")
    }
    
    // MARK: - Public Search Methods
    
    /// Perform streaming search with debouncing and caching
    func search(_ query: String) {
        logger.debug("Search requested: '\(query)'")
        
        // Cancel previous search
        currentSearchTask?.cancel()
        searchDebounceTimer?.invalidate()
        
        // Clear results if query is empty
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            searchError = nil
            return
        }
        
        // Debounce search
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performSearch(query)
            }
        }
    }
    
    /// Get search suggestions with streaming
    func getSearchSuggestions(_ query: String) -> AsyncStream<[SearchSuggestion]> {
        return AsyncStream { continuation in
            Task {
                do {
                    let suggestions = try await generateSearchSuggestions(query)
                    continuation.yield(suggestions)
                    continuation.finish()
                } catch {
                    logger.error("Failed to get search suggestions: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
    
    /// Stream search results as they become available
    func streamSearchResults(_ query: String) -> AsyncStream<SearchResultBatch> {
        return AsyncStream { continuation in
            Task {
                await performStreamingSearch(query, continuation: continuation)
            }
        }
    }
    
    // MARK: - Private Search Implementation
    
    private func performSearch(_ query: String) async {
        let searchId = UUID().uuidString
        let startTime = Date()
        
        logger.debug("Starting search: \(searchId) for '\(query)'")
        
        isSearching = true
        searchError = nil
        
        currentSearchTask = Task {
            do {
                // Start performance monitoring
                await performanceMonitor.startSearch(id: searchId, query: query)
                
                // Check multi-level cache first
                if let cachedResults = await cacheManager.getCachedResults(for: query) {
                    logger.debug("Cache hit for query: '\(query)'")
                    await performanceMonitor.recordCacheHit(searchId: searchId)
                    
                    if !Task.isCancelled {
                        searchResults = cachedResults.results
                        searchMetrics = cachedResults.metrics
                        isSearching = false
                    }
                    return
                }
                
                // Perform actual search
                let results = try await productService.searchProducts(query)
                
                if !Task.isCancelled {
                    // Cache results
                    let metrics = SearchMetrics(
                        query: query,
                        resultCount: results.count,
                        duration: Date().timeIntervalSince(startTime),
                        cacheHit: false,
                        searchId: searchId,
                        timestamp: Date()
                    )
                    
                    await cacheManager.cacheResults(
                        query: query,
                        results: results,
                        metrics: metrics
                    )
                    
                    // Update UI
                    searchResults = results
                    searchMetrics = metrics
                    isSearching = false
                    
                    // Record performance metrics
                    await performanceMonitor.recordSearchComplete(
                        searchId: searchId,
                        resultCount: results.count,
                        duration: Date().timeIntervalSince(startTime)
                    )
                    
                    logger.debug("Search completed: \(searchId) - \(results.count) results")
                }
                
            } catch {
                if !Task.isCancelled {
                    logger.error("Search failed: \(searchId) - \(error.localizedDescription)")
                    searchError = SearchError.searchFailed(error)
                    isSearching = false
                    
                    await performanceMonitor.recordSearchError(
                        searchId: searchId,
                        error: error
                    )
                }
            }
        }
    }
    
    private func performStreamingSearch(_ query: String, continuation: AsyncStream<SearchResultBatch>.Continuation) async {
        let searchId = UUID().uuidString
        logger.debug("Starting streaming search: \(searchId)")
        
        do {
            // Start with cached results if available
            if let cachedResults = await cacheManager.getCachedResults(for: query) {
                let batch = SearchResultBatch(
                    results: cachedResults.results,
                    isComplete: true,
                    batchIndex: 0,
                    totalBatches: 1,
                    searchId: searchId
                )
                continuation.yield(batch)
                continuation.finish()
                return
            }
            
            // Stream results in batches
            let allResults = try await productService.searchProducts(query)
            let batchSize = 10
            let totalBatches = (allResults.count + batchSize - 1) / batchSize
            
            for (index, batch) in allResults.chunked(into: batchSize).enumerated() {
                let resultBatch = SearchResultBatch(
                    results: Array(batch),
                    isComplete: index == totalBatches - 1,
                    batchIndex: index,
                    totalBatches: totalBatches,
                    searchId: searchId
                )
                
                continuation.yield(resultBatch)
                
                // Small delay between batches for smooth streaming
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            
            continuation.finish()
            
        } catch {
            logger.error("Streaming search failed: \(error.localizedDescription)")
            continuation.finish()
        }
    }
    
    private func generateSearchSuggestions(_ query: String) async throws -> [SearchSuggestion] {
        // Check suggestion cache first
        if let cachedSuggestions = await cacheManager.getCachedSuggestions(for: query) {
            return cachedSuggestions
        }
        
        // Generate suggestions based on query
        var suggestions: [SearchSuggestion] = []
        
        // Add category suggestions
        if query.count >= 2 {
            let categoryMatches = await findMatchingCategories(query)
            suggestions.append(contentsOf: categoryMatches.map { category in
                SearchSuggestion(
                    text: category,
                    type: .category,
                    confidence: 0.8
                )
            })
        }
        
        // Add recent search suggestions
        let recentSearches = await cacheManager.getRecentSearches()
        let recentMatches = recentSearches.filter { $0.lowercased().contains(query.lowercased()) }
        suggestions.append(contentsOf: recentMatches.map { recent in
            SearchSuggestion(
                text: recent,
                type: .recentSearch,
                confidence: 0.6
            )
        })
        
        // Cache suggestions
        await cacheManager.cacheSuggestions(query: query, suggestions: suggestions)
        
        return suggestions.sorted { $0.confidence > $1.confidence }
    }
    
    private func findMatchingCategories(_ query: String) async -> [String] {
        // This would typically query the database for matching categories
        // For now, return mock categories
        let categories = ["Beverages", "Snacks", "Dairy", "Produce", "Bakery", "Meat", "Frozen"]
        return categories.filter { $0.lowercased().contains(query.lowercased()) }
    }
    
    // MARK: - Cache Management
    
    func clearSearchCache() async {
        await cacheManager.clearAll()
        logger.info("Search cache cleared")
    }
    
    func preloadFrequentSearches() async {
        logger.info("Preloading frequent searches")
        
        let frequentQueries = await cacheManager.getFrequentQueries()
        
        for query in frequentQueries {
            do {
                let results = try await productService.searchProducts(query)
                let metrics = SearchMetrics(
                    query: query,
                    resultCount: results.count,
                    duration: 0,
                    cacheHit: false,
                    searchId: "preload-\(UUID().uuidString)",
                    timestamp: Date()
                )
                
                await cacheManager.cacheResults(
                    query: query,
                    results: results,
                    metrics: metrics
                )
                
            } catch {
                logger.error("Failed to preload search for '\(query)': \(error.localizedDescription)")
            }
        }
        
        logger.info("Preloading completed for \(frequentQueries.count) queries")
    }
    
    // MARK: - Performance Monitoring
    
    func getSearchPerformanceMetrics() async -> SearchPerformanceReport {
        return await performanceMonitor.generateReport()
    }
    
    func resetPerformanceMetrics() async {
        await performanceMonitor.reset()
        logger.info("Search performance metrics reset")
    }
}

// MARK: - Supporting Models

struct SearchResultBatch {
    let results: [SearchResultItem]
    let isComplete: Bool
    let batchIndex: Int
    let totalBatches: Int
    let searchId: String
}

struct SearchSuggestion: Codable {
    let text: String
    let type: SuggestionType
    let confidence: Double

    enum SuggestionType: Codable {
        case category
        case recentSearch
        case popularSearch
        case productName
    }
}

struct SearchMetrics: Codable {
    let query: String
    let resultCount: Int
    let duration: TimeInterval
    let cacheHit: Bool
    let searchId: String
    let timestamp: Date
}

struct CachedSearchResult: Codable {
    let results: [SearchResultItem]
    let metrics: SearchMetrics
    let cachedAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

enum SearchError: LocalizedError {
    case searchFailed(Error)
    case invalidQuery(String)
    case cacheError(Error)
    case performanceMonitoringError(Error)
    
    var errorDescription: String? {
        switch self {
        case .searchFailed(let error):
            return "Search failed: \(error.localizedDescription)"
        case .invalidQuery(let query):
            return "Invalid search query: \(query)"
        case .cacheError(let error):
            return "Cache error: \(error.localizedDescription)"
        case .performanceMonitoringError(let error):
            return "Performance monitoring error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
