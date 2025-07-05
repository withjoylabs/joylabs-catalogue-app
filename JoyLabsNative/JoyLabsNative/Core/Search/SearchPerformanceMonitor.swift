import Foundation
import OSLog

/// Comprehensive search performance monitoring with real-time analytics
/// Tracks search latency, cache performance, and user behavior patterns
actor SearchPerformanceMonitor {
    
    // MARK: - Performance Data
    
    private var activeSearches: [String: SearchSession] = [:]
    private var completedSearches: [SearchSession] = []
    private var performanceMetrics = PerformanceMetrics()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SearchPerformanceMonitor")
    
    // MARK: - Configuration
    
    private let maxCompletedSearches = 1000
    private let performanceThresholds = PerformanceThresholds()
    
    // MARK: - Initialization
    
    init() {
        logger.info("SearchPerformanceMonitor initialized")
        
        // Start background performance analysis
        Task {
            await startPerformanceAnalysis()
        }
    }
    
    // MARK: - Search Tracking
    
    func startSearch(id: String, query: String) async {
        let session = SearchSession(
            id: id,
            query: query,
            startTime: Date(),
            queryLength: query.count,
            queryComplexity: calculateQueryComplexity(query)
        )
        
        activeSearches[id] = session
        logger.debug("Started tracking search: \(id)")
    }
    
    func recordCacheHit(searchId: String) async {
        guard var session = activeSearches[searchId] else { return }
        
        session.cacheHit = true
        session.cacheHitTime = Date()
        activeSearches[searchId] = session
        
        performanceMetrics.totalCacheHits += 1
        logger.debug("Cache hit recorded for search: \(searchId)")
    }
    
    func recordSearchComplete(searchId: String, resultCount: Int, duration: TimeInterval) async {
        guard var session = activeSearches.removeValue(forKey: searchId) else { return }
        
        session.endTime = Date()
        session.resultCount = resultCount
        session.totalDuration = duration
        session.isComplete = true
        
        // Add to completed searches
        completedSearches.append(session)
        
        // Maintain max completed searches limit
        if completedSearches.count > maxCompletedSearches {
            completedSearches.removeFirst(completedSearches.count - maxCompletedSearches)
        }
        
        // Update performance metrics
        await updatePerformanceMetrics(session)
        
        // Check for performance issues
        await checkPerformanceThresholds(session)
        
        logger.debug("Search completed: \(searchId) - \(resultCount) results in \(duration)s")
    }
    
    func recordSearchError(searchId: String, error: Error) async {
        guard var session = activeSearches.removeValue(forKey: searchId) else { return }
        
        session.endTime = Date()
        session.error = error
        session.isComplete = true
        
        completedSearches.append(session)
        performanceMetrics.totalErrors += 1
        
        logger.error("Search error recorded: \(searchId) - \(error.localizedDescription)")
    }
    
    // MARK: - Performance Analysis
    
    func generateReport() async -> SearchPerformanceReport {
        let now = Date()
        let last24Hours = now.addingTimeInterval(-86400)
        let recentSearches = completedSearches.filter { $0.startTime >= last24Hours }
        
        let report = SearchPerformanceReport(
            totalSearches: completedSearches.count,
            recentSearches: recentSearches.count,
            averageLatency: calculateAverageLatency(recentSearches),
            cacheHitRate: calculateCacheHitRate(recentSearches),
            errorRate: calculateErrorRate(recentSearches),
            topQueries: getTopQueries(recentSearches),
            performanceDistribution: calculatePerformanceDistribution(recentSearches),
            slowQueries: getSlowQueries(recentSearches),
            generatedAt: now
        )
        
        logger.info("Performance report generated: \(recentSearches.count) recent searches")
        return report
    }
    
    func getPerformanceMetrics() async -> PerformanceMetrics {
        return performanceMetrics
    }
    
    func reset() async {
        activeSearches.removeAll()
        completedSearches.removeAll()
        performanceMetrics = PerformanceMetrics()
        logger.info("Performance monitor reset")
    }
    
    // MARK: - Private Methods
    
    private func updatePerformanceMetrics(_ session: SearchSession) async {
        performanceMetrics.totalSearches += 1
        performanceMetrics.totalLatency += session.totalDuration
        
        if session.cacheHit {
            performanceMetrics.totalCacheHits += 1
        }
        
        if session.error != nil {
            performanceMetrics.totalErrors += 1
        }
        
        // Update latency buckets
        let latencyMs = session.totalDuration * 1000
        switch latencyMs {
        case 0..<100:
            performanceMetrics.latencyBuckets.under100ms += 1
        case 100..<500:
            performanceMetrics.latencyBuckets.under500ms += 1
        case 500..<1000:
            performanceMetrics.latencyBuckets.under1s += 1
        case 1000..<5000:
            performanceMetrics.latencyBuckets.under5s += 1
        default:
            performanceMetrics.latencyBuckets.over5s += 1
        }
    }
    
    private func checkPerformanceThresholds(_ session: SearchSession) async {
        // Check if search exceeded performance thresholds
        if session.totalDuration > performanceThresholds.slowSearchThreshold {
            logger.warning("Slow search detected: \(session.id) took \(session.totalDuration)s")
            performanceMetrics.slowSearchCount += 1
        }
        
        if session.resultCount == 0 && session.error == nil {
            logger.info("No results search: \(session.id) for query '\(session.query)'")
            performanceMetrics.noResultsCount += 1
        }
    }
    
    private func calculateQueryComplexity(_ query: String) -> QueryComplexity {
        let wordCount = query.components(separatedBy: .whitespacesAndNewlines).count
        let hasSpecialChars = query.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
        
        if wordCount > 5 || hasSpecialChars {
            return .complex
        } else if wordCount > 2 {
            return .medium
        } else {
            return .simple
        }
    }
    
    private func calculateAverageLatency(_ searches: [SearchSession]) -> TimeInterval {
        guard !searches.isEmpty else { return 0 }
        let totalLatency = searches.reduce(0) { $0 + $1.totalDuration }
        return totalLatency / Double(searches.count)
    }
    
    private func calculateCacheHitRate(_ searches: [SearchSession]) -> Double {
        guard !searches.isEmpty else { return 0 }
        let cacheHits = searches.filter { $0.cacheHit }.count
        return Double(cacheHits) / Double(searches.count)
    }
    
    private func calculateErrorRate(_ searches: [SearchSession]) -> Double {
        guard !searches.isEmpty else { return 0 }
        let errors = searches.filter { $0.error != nil }.count
        return Double(errors) / Double(searches.count)
    }
    
    private func getTopQueries(_ searches: [SearchSession]) -> [QueryFrequency] {
        let queryGroups = Dictionary(grouping: searches) { $0.query.lowercased() }
        
        return queryGroups.map { query, sessions in
            QueryFrequency(
                query: query,
                count: sessions.count,
                averageLatency: calculateAverageLatency(sessions),
                averageResults: sessions.reduce(0) { $0 + $1.resultCount } / sessions.count
            )
        }.sorted { $0.count > $1.count }.prefix(10).map { $0 }
    }
    
    private func calculatePerformanceDistribution(_ searches: [SearchSession]) -> PerformanceDistribution {
        var latencies = searches.map { $0.totalDuration * 1000 } // Convert to ms
        latencies.sort()
        
        guard !latencies.isEmpty else {
            return PerformanceDistribution(p50: 0, p90: 0, p95: 0, p99: 0)
        }
        
        return PerformanceDistribution(
            p50: percentile(latencies, 0.5),
            p90: percentile(latencies, 0.9),
            p95: percentile(latencies, 0.95),
            p99: percentile(latencies, 0.99)
        )
    }
    
    private func getSlowQueries(_ searches: [SearchSession]) -> [SlowQuery] {
        return searches
            .filter { $0.totalDuration > performanceThresholds.slowSearchThreshold }
            .sorted { $0.totalDuration > $1.totalDuration }
            .prefix(10)
            .map { session in
                SlowQuery(
                    query: session.query,
                    duration: session.totalDuration,
                    resultCount: session.resultCount,
                    timestamp: session.startTime
                )
            }
    }
    
    private func percentile(_ sortedArray: [TimeInterval], _ percentile: Double) -> TimeInterval {
        guard !sortedArray.isEmpty else { return 0 }
        
        let index = Int(Double(sortedArray.count - 1) * percentile)
        return sortedArray[index]
    }
    
    private func startPerformanceAnalysis() async {
        while true {
            // Run performance analysis every 5 minutes
            try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
            
            await analyzePerformanceTrends()
        }
    }
    
    private func analyzePerformanceTrends() async {
        let now = Date()
        let last24Hours = now.addingTimeInterval(-86400)
        let recentSearches = completedSearches.filter { $0.startTime >= last24Hours }
        
        // Analyze trends
        let averageLatency = calculateAverageLatency(recentSearches)
        let cacheHitRate = calculateCacheHitRate(recentSearches)
        let errorRate = calculateErrorRate(recentSearches)
        
        // Log performance insights
        logger.info("Performance Analysis - Avg Latency: \(averageLatency)s, Cache Hit Rate: \(cacheHitRate), Error Rate: \(errorRate)")
        
        // Check for performance degradation
        if averageLatency > performanceThresholds.slowSearchThreshold {
            logger.warning("Performance degradation detected - Average latency: \(averageLatency)s")
        }
        
        if errorRate > 0.05 { // 5% error rate threshold
            logger.warning("High error rate detected: \(errorRate)")
        }
    }
}

// MARK: - Supporting Models

struct SearchSession {
    let id: String
    let query: String
    let startTime: Date
    let queryLength: Int
    let queryComplexity: QueryComplexity
    
    var endTime: Date?
    var resultCount: Int = 0
    var totalDuration: TimeInterval = 0
    var cacheHit: Bool = false
    var cacheHitTime: Date?
    var error: Error?
    var isComplete: Bool = false
}

enum QueryComplexity {
    case simple
    case medium
    case complex
}

struct PerformanceMetrics {
    var totalSearches: Int = 0
    var totalLatency: TimeInterval = 0
    var totalCacheHits: Int = 0
    var totalErrors: Int = 0
    var slowSearchCount: Int = 0
    var noResultsCount: Int = 0
    var latencyBuckets = LatencyBuckets()
    
    var averageLatency: TimeInterval {
        totalSearches > 0 ? totalLatency / Double(totalSearches) : 0
    }
    
    var cacheHitRate: Double {
        totalSearches > 0 ? Double(totalCacheHits) / Double(totalSearches) : 0
    }
    
    var errorRate: Double {
        totalSearches > 0 ? Double(totalErrors) / Double(totalSearches) : 0
    }
}

struct LatencyBuckets {
    var under100ms: Int = 0
    var under500ms: Int = 0
    var under1s: Int = 0
    var under5s: Int = 0
    var over5s: Int = 0
}

struct PerformanceThresholds {
    let slowSearchThreshold: TimeInterval = 2.0 // 2 seconds
    let cacheHitRateThreshold: Double = 0.7 // 70%
    let errorRateThreshold: Double = 0.05 // 5%
}

struct SearchPerformanceReport {
    let totalSearches: Int
    let recentSearches: Int
    let averageLatency: TimeInterval
    let cacheHitRate: Double
    let errorRate: Double
    let topQueries: [QueryFrequency]
    let performanceDistribution: PerformanceDistribution
    let slowQueries: [SlowQuery]
    let generatedAt: Date
}

struct QueryFrequency {
    let query: String
    let count: Int
    let averageLatency: TimeInterval
    let averageResults: Int
}

struct PerformanceDistribution {
    let p50: TimeInterval // Median
    let p90: TimeInterval
    let p95: TimeInterval
    let p99: TimeInterval
}

struct SlowQuery {
    let query: String
    let duration: TimeInterval
    let resultCount: Int
    let timestamp: Date
}
