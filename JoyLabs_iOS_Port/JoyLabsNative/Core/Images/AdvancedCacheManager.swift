import Foundation
import UIKit
import os.log

/// Advanced cache management with intelligent eviction, warming, and performance analytics
/// Implements industry-standard cache optimization strategies
@MainActor
class AdvancedCacheManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = AdvancedCacheManager()
    
    // MARK: - Published Properties
    @Published var cacheStatistics: CacheStatistics = CacheStatistics()
    @Published var cacheHealth: CacheHealth = .good
    @Published var isOptimizing: Bool = false
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "AdvancedCacheManager")
    private let fileManager = FileManager.default
    
    // MARK: - Cache Configuration
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let lowWaterMark: Double = 0.8 // Start cleanup at 80%
    private let highWaterMark: Double = 0.9 // Aggressive cleanup at 90%
    
    // MARK: - Cache Directories
    private let cacheDirectory: URL
    private let thumbnailDirectory: URL
    private let fullImageDirectory: URL
    private let metadataDirectory: URL
    
    // MARK: - Performance Tracking
    private var accessLog: [String: CacheAccessRecord] = [:]
    private var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    private var optimizationTimer: Timer?
    
    // MARK: - Cache Warming
    private var warmingQueue: [String] = []
    private var isWarming: Bool = false
    
    // MARK: - Initialization
    private init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("AdvancedImageCache")
        self.thumbnailDirectory = cacheDirectory.appendingPathComponent("Thumbnails")
        self.fullImageDirectory = cacheDirectory.appendingPathComponent("FullImages")
        self.metadataDirectory = cacheDirectory.appendingPathComponent("Metadata")
        
        setupDirectories()
        loadCacheMetadata()
        startPerformanceMonitoring()
        
        logger.info("🧠 AdvancedCacheManager initialized")
    }
    
    deinit {
        optimizationTimer?.invalidate()
        saveCacheMetadata()
    }
    
    // MARK: - Public Methods
    
    /// Record cache access for analytics
    func recordAccess(cacheKey: String, accessType: CacheAccessType, hitTime: TimeInterval? = nil) {
        let record = CacheAccessRecord(
            cacheKey: cacheKey,
            accessType: accessType,
            timestamp: Date(),
            hitTime: hitTime
        )
        
        accessLog[cacheKey] = record
        updatePerformanceMetrics(record)
        
        // Update cache statistics
        updateCacheStatistics()
    }
    
    /// Get cache priority for a key based on access patterns
    func getCachePriority(for cacheKey: String) -> CachePriority {
        guard let record = accessLog[cacheKey] else {
            return .normal
        }
        
        let daysSinceAccess = Date().timeIntervalSince(record.timestamp) / (24 * 60 * 60)
        let accessFrequency = getAccessFrequency(for: cacheKey)
        
        if daysSinceAccess < 1 && accessFrequency > 5 {
            return .high
        } else if daysSinceAccess < 7 && accessFrequency > 2 {
            return .normal
        } else {
            return .low
        }
    }
    
    /// Perform intelligent cache optimization
    func optimizeCache() async {
        guard !isOptimizing else { return }
        
        isOptimizing = true
        defer { isOptimizing = false }
        
        logger.info("🔧 Starting cache optimization")
        
        // Update cache statistics
        await updateCacheStatistics()
        
        // Determine optimization strategy
        let strategy = determineOptimizationStrategy()
        
        switch strategy {
        case .none:
            logger.info("✅ Cache is healthy, no optimization needed")
            
        case .gentle:
            await performGentleCleanup()
            
        case .aggressive:
            await performAggressiveCleanup()
            
        case .emergency:
            await performEmergencyCleanup()
        }
        
        // Update statistics after optimization
        await updateCacheStatistics()
        updateCacheHealth()
        
        logger.info("✅ Cache optimization completed")
    }
    
    /// Warm cache with predicted items
    func warmCache(with cacheKeys: [String]) async {
        guard !isWarming else { return }
        
        isWarming = true
        defer { isWarming = false }
        
        logger.info("🔥 Starting cache warming with \(cacheKeys.count) items")
        
        warmingQueue = cacheKeys.filter { !isCached($0) }
        
        // Prioritize based on access patterns
        warmingQueue.sort { key1, key2 in
            let priority1 = getCachePriority(for: key1)
            let priority2 = getCachePriority(for: key2)
            return priority1.rawValue > priority2.rawValue
        }
        
        // Warm cache in background
        for cacheKey in warmingQueue {
            // This would trigger download if not cached
            // Implementation depends on integration with download manager
            logger.debug("🔥 Warming cache for: \(cacheKey)")
        }
        
        logger.info("✅ Cache warming completed")
    }
    
    /// Get cache recommendations
    func getCacheRecommendations() -> [CacheRecommendation] {
        var recommendations: [CacheRecommendation] = []
        
        // Check cache size
        let usageRatio = Double(cacheStatistics.totalSize) / Double(maxCacheSize)
        if usageRatio > highWaterMark {
            recommendations.append(.reduceCacheSize)
        }
        
        // Check hit rate
        if cacheStatistics.hitRate < 0.7 {
            recommendations.append(.improveHitRate)
        }
        
        // Check old items
        let oldItemsCount = getOldItemsCount()
        if oldItemsCount > 100 {
            recommendations.append(.cleanupOldItems)
        }
        
        // Check fragmentation
        if cacheStatistics.fragmentationRatio > 0.3 {
            recommendations.append(.defragmentCache)
        }
        
        return recommendations
    }
    
    /// Clear cache intelligently
    func clearCache(strategy: ClearStrategy = .smart) async {
        logger.info("🧹 Clearing cache with strategy: \(strategy)")
        
        switch strategy {
        case .all:
            await clearAllCache()
            
        case .old:
            await clearOldItems()
            
        case .lowPriority:
            await clearLowPriorityItems()
            
        case .smart:
            await performSmartClear()
        }
        
        await updateCacheStatistics()
        updateCacheHealth()
    }
    
    // MARK: - Private Methods
    
    private func setupDirectories() {
        let directories = [cacheDirectory, thumbnailDirectory, fullImageDirectory, metadataDirectory]
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("❌ Failed to create directory \(directory.path): \(error)")
            }
        }
    }
    
    private func startPerformanceMonitoring() {
        optimizationTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPeriodicOptimization()
            }
        }
    }
    
    private func performPeriodicOptimization() async {
        // Only optimize if cache is getting full or performance is degrading
        await updateCacheStatistics()
        
        let usageRatio = Double(cacheStatistics.totalSize) / Double(maxCacheSize)
        
        if usageRatio > lowWaterMark || cacheStatistics.hitRate < 0.6 {
            await optimizeCache()
        }
    }
    
    private func updateCacheStatistics() async {
        let thumbnailSize = await getDirectorySize(thumbnailDirectory)
        let fullImageSize = await getDirectorySize(fullImageDirectory)
        let metadataSize = await getDirectorySize(metadataDirectory)
        
        let totalSize = thumbnailSize + fullImageSize + metadataSize
        let itemCount = await getItemCount()
        
        let hitRate = calculateHitRate()
        let averageAccessTime = calculateAverageAccessTime()
        let fragmentationRatio = calculateFragmentationRatio()
        
        cacheStatistics = CacheStatistics(
            totalSize: totalSize,
            thumbnailSize: thumbnailSize,
            fullImageSize: fullImageSize,
            itemCount: itemCount,
            hitRate: hitRate,
            averageAccessTime: averageAccessTime,
            fragmentationRatio: fragmentationRatio
        )
    }
    
    private func getDirectorySize(_ directory: URL) async -> Int64 {
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            
            var totalSize: Int64 = 0
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(attributes.fileSize ?? 0)
            }
            
            return totalSize
        } catch {
            return 0
        }
    }
    
    private func getItemCount() async -> Int {
        do {
            let thumbnailFiles = try fileManager.contentsOfDirectory(at: thumbnailDirectory, includingPropertiesForKeys: nil)
            return thumbnailFiles.count
        } catch {
            return 0
        }
    }
    
    private func calculateHitRate() -> Double {
        let totalAccesses = accessLog.count
        guard totalAccesses > 0 else { return 0.0 }
        
        let hits = accessLog.values.filter { $0.accessType == .hit }.count
        return Double(hits) / Double(totalAccesses)
    }
    
    private func calculateAverageAccessTime() -> TimeInterval {
        let hitTimes = accessLog.values.compactMap { $0.hitTime }
        guard !hitTimes.isEmpty else { return 0.0 }
        
        return hitTimes.reduce(0, +) / Double(hitTimes.count)
    }
    
    private func calculateFragmentationRatio() -> Double {
        // Simplified fragmentation calculation
        // In practice, this would analyze file system fragmentation
        return 0.1 // Placeholder
    }
    
    private func getAccessFrequency(for cacheKey: String) -> Int {
        // Count accesses in the last 7 days
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        return accessLog.values.filter { record in
            record.cacheKey == cacheKey && record.timestamp > weekAgo
        }.count
    }
    
    private func isCached(_ cacheKey: String) -> Bool {
        let thumbnailPath = thumbnailDirectory.appendingPathComponent(cacheKey).path
        return fileManager.fileExists(atPath: thumbnailPath)
    }
    
    private func determineOptimizationStrategy() -> OptimizationStrategy {
        let usageRatio = Double(cacheStatistics.totalSize) / Double(maxCacheSize)
        
        if usageRatio > 0.95 {
            return .emergency
        } else if usageRatio > highWaterMark {
            return .aggressive
        } else if usageRatio > lowWaterMark {
            return .gentle
        } else {
            return .none
        }
    }
    
    private func performGentleCleanup() async {
        logger.info("🧹 Performing gentle cleanup")
        
        // Remove items older than 30 days
        await removeItemsOlderThan(maxCacheAge)
        
        // Remove low-priority items if still over threshold
        let usageRatio = Double(cacheStatistics.totalSize) / Double(maxCacheSize)
        if usageRatio > lowWaterMark {
            await removeLowPriorityItems(targetReduction: 0.1)
        }
    }
    
    private func performAggressiveCleanup() async {
        logger.info("🧹 Performing aggressive cleanup")
        
        // Remove old items
        await removeItemsOlderThan(maxCacheAge / 2) // 15 days
        
        // Remove low-priority items
        await removeLowPriorityItems(targetReduction: 0.2)
        
        // Remove least recently used items
        await removeLRUItems(targetReduction: 0.1)
    }
    
    private func performEmergencyCleanup() async {
        logger.warning("🚨 Performing emergency cleanup")
        
        // Aggressive removal to get under high water mark
        await removeLowPriorityItems(targetReduction: 0.3)
        await removeLRUItems(targetReduction: 0.2)
        
        // Remove items older than 7 days
        await removeItemsOlderThan(7 * 24 * 60 * 60)
    }
    
    private func removeItemsOlderThan(_ maxAge: TimeInterval) async {
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        
        do {
            let files = try fileManager.contentsOfDirectory(at: thumbnailDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modificationDate = attributes.contentModificationDate,
                   modificationDate < cutoffDate {
                    
                    let cacheKey = file.lastPathComponent
                    await removeItem(cacheKey: cacheKey)
                }
            }
        } catch {
            logger.error("❌ Failed to remove old items: \(error)")
        }
    }
    
    private func removeLowPriorityItems(targetReduction: Double) async {
        let lowPriorityItems = accessLog.filter { _, record in
            getCachePriority(for: record.cacheKey) == .low
        }.map { $0.key }
        
        let targetCount = Int(Double(lowPriorityItems.count) * targetReduction)
        let itemsToRemove = Array(lowPriorityItems.prefix(targetCount))
        
        for cacheKey in itemsToRemove {
            await removeItem(cacheKey: cacheKey)
        }
        
        logger.info("🗑️ Removed \(itemsToRemove.count) low-priority items")
    }
    
    private func removeLRUItems(targetReduction: Double) async {
        let sortedByAccess = accessLog.sorted { $0.value.timestamp < $1.value.timestamp }
        let targetCount = Int(Double(sortedByAccess.count) * targetReduction)
        let itemsToRemove = Array(sortedByAccess.prefix(targetCount).map { $0.key })
        
        for cacheKey in itemsToRemove {
            await removeItem(cacheKey: cacheKey)
        }
        
        logger.info("🗑️ Removed \(itemsToRemove.count) LRU items")
    }
    
    private func removeItem(cacheKey: String) async {
        let thumbnailPath = thumbnailDirectory.appendingPathComponent(cacheKey)
        let fullImagePath = fullImageDirectory.appendingPathComponent(cacheKey)
        
        do {
            if fileManager.fileExists(atPath: thumbnailPath.path) {
                try fileManager.removeItem(at: thumbnailPath)
            }
            
            if fileManager.fileExists(atPath: fullImagePath.path) {
                try fileManager.removeItem(at: fullImagePath)
            }
            
            accessLog.removeValue(forKey: cacheKey)
            
        } catch {
            logger.error("❌ Failed to remove item \(cacheKey): \(error)")
        }
    }
    
    private func clearAllCache() async {
        do {
            try fileManager.removeItem(at: cacheDirectory)
            setupDirectories()
            accessLog.removeAll()
            
            logger.info("🧹 Cleared all cache")
        } catch {
            logger.error("❌ Failed to clear all cache: \(error)")
        }
    }
    
    private func clearOldItems() async {
        await removeItemsOlderThan(maxCacheAge)
    }
    
    private func clearLowPriorityItems() async {
        await removeLowPriorityItems(targetReduction: 1.0)
    }
    
    private func performSmartClear() async {
        // Intelligent clearing based on usage patterns
        await performGentleCleanup()
    }
    
    private func getOldItemsCount() -> Int {
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        
        return accessLog.values.filter { record in
            record.timestamp < cutoffDate
        }.count
    }
    
    private func updatePerformanceMetrics(_ record: CacheAccessRecord) {
        performanceMetrics.totalAccesses += 1
        
        if record.accessType == .hit {
            performanceMetrics.hits += 1
            
            if let hitTime = record.hitTime {
                performanceMetrics.totalHitTime += hitTime
                performanceMetrics.hitCount += 1
            }
        } else {
            performanceMetrics.misses += 1
        }
    }
    
    private func updateCacheHealth() {
        let usageRatio = Double(cacheStatistics.totalSize) / Double(maxCacheSize)
        
        if usageRatio > 0.9 || cacheStatistics.hitRate < 0.5 {
            cacheHealth = .poor
        } else if usageRatio > 0.7 || cacheStatistics.hitRate < 0.7 {
            cacheHealth = .fair
        } else {
            cacheHealth = .good
        }
    }
    
    private func loadCacheMetadata() {
        // Load access log and performance metrics from disk
        // Implementation would deserialize from metadata directory
    }
    
    private func saveCacheMetadata() {
        // Save access log and performance metrics to disk
        // Implementation would serialize to metadata directory
    }
}

// MARK: - Supporting Types

struct CacheStatistics {
    let totalSize: Int64
    let thumbnailSize: Int64
    let fullImageSize: Int64
    let itemCount: Int
    let hitRate: Double
    let averageAccessTime: TimeInterval
    let fragmentationRatio: Double

    init() {
        self.totalSize = 0
        self.thumbnailSize = 0
        self.fullImageSize = 0
        self.itemCount = 0
        self.hitRate = 0.0
        self.averageAccessTime = 0.0
        self.fragmentationRatio = 0.0
    }

    init(totalSize: Int64, thumbnailSize: Int64, fullImageSize: Int64, itemCount: Int, hitRate: Double, averageAccessTime: TimeInterval, fragmentationRatio: Double) {
        self.totalSize = totalSize
        self.thumbnailSize = thumbnailSize
        self.fullImageSize = fullImageSize
        self.itemCount = itemCount
        self.hitRate = hitRate
        self.averageAccessTime = averageAccessTime
        self.fragmentationRatio = fragmentationRatio
    }

    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedHitRate: String {
        return String(format: "%.1f%%", hitRate * 100)
    }
}

enum CacheHealth: String, CaseIterable {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: UIColor {
        switch self {
        case .good: return .systemGreen
        case .fair: return .systemOrange
        case .poor: return .systemRed
        }
    }
}

enum CachePriority: Int, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
}

enum CacheAccessType: String, CaseIterable {
    case hit = "Hit"
    case miss = "Miss"
    case write = "Write"
    case eviction = "Eviction"
}

struct CacheAccessRecord {
    let cacheKey: String
    let accessType: CacheAccessType
    let timestamp: Date
    let hitTime: TimeInterval?
}

struct PerformanceMetrics {
    var totalAccesses: Int = 0
    var hits: Int = 0
    var misses: Int = 0
    var totalHitTime: TimeInterval = 0
    var hitCount: Int = 0

    var hitRate: Double {
        guard totalAccesses > 0 else { return 0.0 }
        return Double(hits) / Double(totalAccesses)
    }

    var averageHitTime: TimeInterval {
        guard hitCount > 0 else { return 0.0 }
        return totalHitTime / Double(hitCount)
    }
}

enum OptimizationStrategy {
    case none
    case gentle
    case aggressive
    case emergency
}

enum ClearStrategy: String, CaseIterable {
    case all = "Clear All"
    case old = "Clear Old Items"
    case lowPriority = "Clear Low Priority"
    case smart = "Smart Clear"
}

enum CacheRecommendation: String, CaseIterable {
    case reduceCacheSize = "Reduce Cache Size"
    case improveHitRate = "Improve Hit Rate"
    case cleanupOldItems = "Cleanup Old Items"
    case defragmentCache = "Defragment Cache"

    var description: String {
        switch self {
        case .reduceCacheSize:
            return "Cache is getting full. Consider clearing old or low-priority items."
        case .improveHitRate:
            return "Cache hit rate is low. Consider cache warming or adjusting cache strategy."
        case .cleanupOldItems:
            return "Many old items in cache. Consider removing items older than 30 days."
        case .defragmentCache:
            return "Cache is fragmented. Consider rebuilding cache for better performance."
        }
    }
}
