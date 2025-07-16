import Foundation
import OSLog

/// Performance monitoring for image cache system
/// Tracks metrics like cache hit rates, loading times, and memory usage
class ImagePerformanceMonitor: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ImagePerformanceMonitor()
    
    // MARK: - Performance Metrics
    @Published var cacheHitRate: Double = 0.0
    @Published var averageLoadTime: TimeInterval = 0.0
    @Published var totalImagesLoaded: Int = 0
    @Published var memoryUsage: Int64 = 0
    @Published var diskUsage: Int64 = 0
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImagePerformanceMonitor")
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var totalLoadTime: TimeInterval = 0.0
    private var loadTimeCount: Int = 0
    
    // MARK: - Performance Tracking
    
    /// Record a cache hit
    func recordCacheHit() {
        cacheHits += 1
        updateCacheHitRate()
        logger.debug("📊 Cache hit recorded. Hit rate: \(String(format: "%.1f", cacheHitRate * 100))%")
    }
    
    /// Record a cache miss
    func recordCacheMiss() {
        cacheMisses += 1
        updateCacheHitRate()
        logger.debug("📊 Cache miss recorded. Hit rate: \(String(format: "%.1f", cacheHitRate * 100))%")
    }
    
    /// Record image load time
    func recordLoadTime(_ duration: TimeInterval) {
        totalLoadTime += duration
        loadTimeCount += 1
        
        DispatchQueue.main.async {
            self.averageLoadTime = self.totalLoadTime / Double(self.loadTimeCount)
            self.totalImagesLoaded = self.loadTimeCount
        }
        
        logger.debug("📊 Load time recorded: \(String(format: "%.3f", duration))s. Average: \(String(format: "%.3f", averageLoadTime))s")
    }
    
    /// Update memory usage statistics
    func updateMemoryUsage(_ bytes: Int64) {
        DispatchQueue.main.async {
            self.memoryUsage = bytes
        }
        logger.debug("📊 Memory usage updated: \(formatBytes(bytes))")
    }
    
    /// Update disk usage statistics
    func updateDiskUsage(_ bytes: Int64) {
        DispatchQueue.main.async {
            self.diskUsage = bytes
        }
        logger.debug("📊 Disk usage updated: \(formatBytes(bytes))")
    }
    
    /// Reset all performance metrics
    func resetMetrics() {
        cacheHits = 0
        cacheMisses = 0
        totalLoadTime = 0.0
        loadTimeCount = 0
        
        DispatchQueue.main.async {
            self.cacheHitRate = 0.0
            self.averageLoadTime = 0.0
            self.totalImagesLoaded = 0
            self.memoryUsage = 0
            self.diskUsage = 0
        }
        
        logger.info("📊 Performance metrics reset")
    }
    
    /// Get performance summary
    func getPerformanceSummary() -> PerformanceSummary {
        return PerformanceSummary(
            cacheHitRate: cacheHitRate,
            averageLoadTime: averageLoadTime,
            totalImagesLoaded: totalImagesLoaded,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses
        )
    }
    
    // MARK: - Private Methods
    
    private func updateCacheHitRate() {
        let totalRequests = cacheHits + cacheMisses
        guard totalRequests > 0 else { return }
        
        DispatchQueue.main.async {
            self.cacheHitRate = Double(self.cacheHits) / Double(totalRequests)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Performance Summary

struct PerformanceSummary {
    let cacheHitRate: Double
    let averageLoadTime: TimeInterval
    let totalImagesLoaded: Int
    let memoryUsage: Int64
    let diskUsage: Int64
    let cacheHits: Int
    let cacheMisses: Int
    
    var formattedCacheHitRate: String {
        return String(format: "%.1f%%", cacheHitRate * 100)
    }
    
    var formattedAverageLoadTime: String {
        return String(format: "%.3fs", averageLoadTime)
    }
    
    var formattedMemoryUsage: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: memoryUsage)
    }
    
    var formattedDiskUsage: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskUsage)
    }
}

// MARK: - Performance Monitoring Extensions
// Note: Performance monitoring is now integrated directly into CachedImageView
// to avoid SwiftUI property wrapper issues

// MARK: - Performance Monitoring View

import SwiftUI

struct ImagePerformanceView: View {
    @StateObject private var monitor = ImagePerformanceMonitor.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Image Cache Performance")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cache Hit Rate:")
                    Spacer()
                    Text(monitor.getPerformanceSummary().formattedCacheHitRate)
                        .foregroundColor(monitor.cacheHitRate > 0.8 ? .green : monitor.cacheHitRate > 0.5 ? .orange : .red)
                }
                
                HStack {
                    Text("Average Load Time:")
                    Spacer()
                    Text(monitor.getPerformanceSummary().formattedAverageLoadTime)
                        .foregroundColor(monitor.averageLoadTime < 0.5 ? .green : monitor.averageLoadTime < 1.0 ? .orange : .red)
                }
                
                HStack {
                    Text("Images Loaded:")
                    Spacer()
                    Text("\(monitor.totalImagesLoaded)")
                }
                
                HStack {
                    Text("Memory Usage:")
                    Spacer()
                    Text(monitor.getPerformanceSummary().formattedMemoryUsage)
                }
                
                HStack {
                    Text("Disk Usage:")
                    Spacer()
                    Text(monitor.getPerformanceSummary().formattedDiskUsage)
                }
            }
            .font(.subheadline)
            
            Button("Reset Metrics") {
                monitor.resetMetrics()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ImagePerformanceView()
}
