import Foundation
import OSLog

/// Multi-level cache manager with L1 (memory), L2 (disk), and L3 (database) caching
/// Implements intelligent cache eviction and performance optimization
actor MultiLevelCacheManager {
    
    // MARK: - Cache Levels
    
    private let memoryCache: MemoryCache
    private let diskCache: DiskCache
    private let databaseCache: DatabaseCache
    private let logger = Logger(subsystem: "com.joylabs.native", category: "MultiLevelCacheManager")
    
    // MARK: - Configuration
    
    private let memoryCacheTTL: TimeInterval = 300 // 5 minutes
    private let diskCacheTTL: TimeInterval = 3600 // 1 hour
    private let databaseCacheTTL: TimeInterval = 86400 // 24 hours
    
    private let maxMemoryCacheSize = 100
    private let maxDiskCacheSize = 1000
    private let maxDatabaseCacheSize = 10000
    
    // MARK: - Performance Tracking
    
    private var cacheStats = CacheStatistics()
    
    // MARK: - Initialization
    
    init() {
        self.memoryCache = MemoryCache(maxSize: maxMemoryCacheSize, ttl: memoryCacheTTL)
        self.diskCache = DiskCache(maxSize: maxDiskCacheSize, ttl: diskCacheTTL)
        self.databaseCache = DatabaseCache(maxSize: maxDatabaseCacheSize, ttl: databaseCacheTTL)
        logger.info("MultiLevelCacheManager initialized")
    }
    
    // MARK: - Search Results Caching
    
    func getCachedResults(for query: String) async -> CachedSearchResult? {
        let cacheKey = generateCacheKey(for: query)
        
        // L1: Check memory cache first (fastest)
        if let result = await memoryCache.get(key: cacheKey) {
            logger.debug("L1 cache hit for query: '\(query)'")
            cacheStats.recordHit(level: .memory)
            return result
        }
        
        // L2: Check disk cache
        if let result = await diskCache.get(key: cacheKey) {
            logger.debug("L2 cache hit for query: '\(query)'")
            cacheStats.recordHit(level: .disk)
            
            // Promote to L1 cache
            await memoryCache.set(key: cacheKey, value: result)
            return result
        }
        
        // L3: Check database cache
        if let result = await databaseCache.get(key: cacheKey) {
            logger.debug("L3 cache hit for query: '\(query)'")
            cacheStats.recordHit(level: .database)
            
            // Promote to L2 and L1 caches
            await diskCache.set(key: cacheKey, value: result)
            await memoryCache.set(key: cacheKey, value: result)
            return result
        }
        
        logger.debug("Cache miss for query: '\(query)'")
        cacheStats.recordMiss()
        return nil
    }
    
    func cacheResults(query: String, results: [SearchResultItem], metrics: SearchMetrics) async {
        let cacheKey = generateCacheKey(for: query)
        let cachedResult = CachedSearchResult(
            results: results,
            metrics: metrics,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(memoryCacheTTL)
        )
        
        logger.debug("Caching results for query: '\(query)' (\(results.count) results)")
        
        // Store in all cache levels
        await memoryCache.set(key: cacheKey, value: cachedResult)
        await diskCache.set(key: cacheKey, value: cachedResult)
        await databaseCache.set(key: cacheKey, value: cachedResult)
        
        // Track query frequency
        await trackQueryFrequency(query)
        
        cacheStats.recordStore()
    }
    
    // MARK: - Search Suggestions Caching
    
    func getCachedSuggestions(for query: String) async -> [SearchSuggestion]? {
        let cacheKey = "suggestions:\(generateCacheKey(for: query))"
        
        // Check memory cache only for suggestions (they're lightweight)
        if let suggestions = await memoryCache.getSuggestions(key: cacheKey) {
            logger.debug("Suggestions cache hit for query: '\(query)'")
            return suggestions
        }
        
        return nil
    }
    
    func cacheSuggestions(query: String, suggestions: [SearchSuggestion]) async {
        let cacheKey = "suggestions:\(generateCacheKey(for: query))"
        
        await memoryCache.setSuggestions(key: cacheKey, value: suggestions)
        logger.debug("Cached \(suggestions.count) suggestions for query: '\(query)'")
    }
    
    // MARK: - Recent Searches
    
    func getRecentSearches() async -> [String] {
        return await memoryCache.getRecentSearches()
    }
    
    func addRecentSearch(_ query: String) async {
        await memoryCache.addRecentSearch(query)
    }
    
    // MARK: - Frequent Queries
    
    func getFrequentQueries() async -> [String] {
        return await databaseCache.getFrequentQueries()
    }
    
    private func trackQueryFrequency(_ query: String) async {
        await databaseCache.incrementQueryCount(query)
    }
    
    // MARK: - Cache Management
    
    func clearAll() async {
        await memoryCache.clear()
        await diskCache.clear()
        await databaseCache.clear()
        cacheStats = CacheStatistics()
        logger.info("All caches cleared")
    }
    
    func clearExpired() async {
        await memoryCache.clearExpired()
        await diskCache.clearExpired()
        await databaseCache.clearExpired()
        logger.debug("Expired cache entries cleared")
    }
    
    func getCacheStatistics() async -> CacheStatistics {
        return cacheStats
    }
    
    // MARK: - Cache Optimization
    
    func optimizeCaches() async {
        logger.info("Starting cache optimization")
        
        // Clear expired entries
        await clearExpired()
        
        // Optimize memory cache
        await memoryCache.optimize()
        
        // Optimize disk cache
        await diskCache.optimize()
        
        // Optimize database cache
        await databaseCache.optimize()
        
        logger.info("Cache optimization completed")
    }
    
    // MARK: - Private Helpers
    
    private func generateCacheKey(for query: String) -> String {
        // Normalize query for consistent caching
        let normalized = query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return "search:\(normalized.hash)"
    }
}

// MARK: - Cache Level Implementations

/// L1 Memory Cache - Fastest access, smallest capacity
private actor MemoryCache {
    private var cache: [String: CachedSearchResult] = [:]
    private var suggestions: [String: [SearchSuggestion]] = [:]
    private var recentSearches: [String] = []
    private let maxSize: Int
    private let ttl: TimeInterval
    
    init(maxSize: Int, ttl: TimeInterval) {
        self.maxSize = maxSize
        self.ttl = ttl
    }
    
    func get(key: String) async -> CachedSearchResult? {
        guard let result = cache[key], !result.isExpired else {
            cache.removeValue(forKey: key)
            return nil
        }
        return result
    }
    
    func set(key: String, value: CachedSearchResult) async {
        if cache.count >= maxSize {
            evictOldest()
        }
        cache[key] = value
    }
    
    func getSuggestions(key: String) async -> [SearchSuggestion]? {
        return suggestions[key]
    }
    
    func setSuggestions(key: String, value: [SearchSuggestion]) async {
        suggestions[key] = value
    }
    
    func getRecentSearches() async -> [String] {
        return Array(recentSearches.prefix(10))
    }
    
    func addRecentSearch(_ query: String) async {
        recentSearches.removeAll { $0 == query }
        recentSearches.insert(query, at: 0)
        if recentSearches.count > 20 {
            recentSearches = Array(recentSearches.prefix(20))
        }
    }
    
    func clear() async {
        cache.removeAll()
        suggestions.removeAll()
        recentSearches.removeAll()
    }
    
    func clearExpired() async {
        let expiredKeys = cache.compactMap { key, value in
            value.isExpired ? key : nil
        }
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
    }
    
    func optimize() async {
        await clearExpired()
        
        // Keep only most recently accessed items if over capacity
        if cache.count > maxSize {
            let sortedEntries = cache.sorted { $0.value.cachedAt > $1.value.cachedAt }
            cache = Dictionary(uniqueKeysWithValues: Array(sortedEntries.prefix(maxSize)))
        }
    }
    
    private func evictOldest() {
        guard let oldestKey = cache.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key else {
            return
        }
        cache.removeValue(forKey: oldestKey)
    }
}

/// L2 Disk Cache - Medium access speed, medium capacity
private actor DiskCache {
    private let maxSize: Int
    private let ttl: TimeInterval
    private let cacheDirectory: URL
    
    init(maxSize: Int, ttl: TimeInterval) {
        self.maxSize = maxSize
        self.ttl = ttl
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("SearchCache")
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func get(key: String) async -> CachedSearchResult? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let result = try? JSONDecoder().decode(CachedSearchResult.self, from: data) else {
            return nil
        }
        
        guard !result.isExpired else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        
        return result
    }
    
    func set(key: String, value: CachedSearchResult) async {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL)
        } catch {
            // Silently fail disk cache writes
        }
    }
    
    func clear() async {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func clearExpired() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files {
            if let data = try? Data(contentsOf: file),
               let result = try? JSONDecoder().decode(CachedSearchResult.self, from: data),
               result.isExpired {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    func optimize() async {
        await clearExpired()
        
        // Remove oldest files if over capacity
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        if files.count > maxSize {
            let sortedFiles = files.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }
            
            let filesToRemove = Array(sortedFiles.prefix(files.count - maxSize))
            for file in filesToRemove {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

/// L3 Database Cache - Slowest access, largest capacity
private actor DatabaseCache {
    private let maxSize: Int
    private let ttl: TimeInterval
    private var queryFrequency: [String: Int] = [:]
    
    init(maxSize: Int, ttl: TimeInterval) {
        self.maxSize = maxSize
        self.ttl = ttl
    }
    
    func get(key: String) async -> CachedSearchResult? {
        // This would integrate with the actual database
        // For now, return nil (will be implemented when database is connected)
        return nil
    }
    
    func set(key: String, value: CachedSearchResult) async {
        // This would store in the actual database
        // For now, do nothing (will be implemented when database is connected)
    }
    
    func getFrequentQueries() async -> [String] {
        return queryFrequency.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
    
    func incrementQueryCount(_ query: String) async {
        queryFrequency[query, default: 0] += 1
    }
    
    func clear() async {
        queryFrequency.removeAll()
    }
    
    func clearExpired() async {
        // Database cache expiration would be handled by database triggers
    }
    
    func optimize() async {
        // Keep only top frequent queries
        if queryFrequency.count > 1000 {
            let topQueries = queryFrequency.sorted { $0.value > $1.value }.prefix(500)
            queryFrequency = Dictionary(uniqueKeysWithValues: Array(topQueries))
        }
    }
}

// MARK: - Cache Statistics

struct CacheStatistics {
    private(set) var memoryHits = 0
    private(set) var diskHits = 0
    private(set) var databaseHits = 0
    private(set) var misses = 0
    private(set) var stores = 0
    
    mutating func recordHit(level: CacheLevel) {
        switch level {
        case .memory:
            memoryHits += 1
        case .disk:
            diskHits += 1
        case .database:
            databaseHits += 1
        }
    }
    
    mutating func recordMiss() {
        misses += 1
    }
    
    mutating func recordStore() {
        stores += 1
    }
    
    var totalHits: Int {
        memoryHits + diskHits + databaseHits
    }
    
    var totalRequests: Int {
        totalHits + misses
    }
    
    var hitRate: Double {
        totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0
    }
    
    var memoryHitRate: Double {
        totalRequests > 0 ? Double(memoryHits) / Double(totalRequests) : 0
    }
}

enum CacheLevel {
    case memory
    case disk
    case database
}

// MARK: - Codable Extensions
// Note: Codable conformance is declared in the original struct definitions
