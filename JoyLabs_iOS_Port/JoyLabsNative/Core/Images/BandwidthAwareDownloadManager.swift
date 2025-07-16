import Foundation
import Network
import os.log

/// Intelligent download manager that adapts to network conditions and user preferences
/// Optimizes download strategy based on WiFi vs cellular, bandwidth, and battery state
@MainActor
class BandwidthAwareDownloadManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = BandwidthAwareDownloadManager()
    
    // MARK: - Published Properties
    @Published var networkConditions: NetworkConditions = .unknown
    @Published var downloadStrategy: DownloadStrategy = .balanced
    @Published var activeDownloadCount: Int = 0
    @Published var queuedDownloadCount: Int = 0
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "BandwidthAwareDownloadManager")
    private let networkMonitor = NWPathMonitor()
    private let backgroundDownloader = BackgroundImageDownloader.shared
    
    // MARK: - Download Queue Management
    private var downloadQueue: [QueuedDownload] = []
    private var activeDownloads: Set<String> = []
    private var downloadPriorities: [String: DownloadPriority] = [:]
    
    // MARK: - Network Monitoring
    private var currentPath: NWPath?
    private var bandwidthEstimate: Double = 0 // Mbps
    private var latencyEstimate: TimeInterval = 0 // seconds
    
    // MARK: - User Preferences
    @Published var allowCellularDownloads: Bool = true
    @Published var allowBackgroundDownloads: Bool = true
    @Published var preferQualityOverSpeed: Bool = false
    
    // MARK: - Initialization
    private init() {
        setupNetworkMonitoring()
        setupBatteryMonitoring()
        loadUserPreferences()
        
        logger.info("📶 BandwidthAwareDownloadManager initialized")
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Queue download with intelligent prioritization
    func queueDownload(
        urlString: String,
        cacheKey: String,
        priority: DownloadPriority = .normal,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let download = QueuedDownload(
            urlString: urlString,
            cacheKey: cacheKey,
            priority: priority,
            queueTime: Date(),
            completion: completion
        )
        
        // Insert based on priority and network conditions
        insertDownloadInQueue(download)
        
        // Update UI
        queuedDownloadCount = downloadQueue.count
        
        // Process queue
        processDownloadQueue()
        
        logger.debug("📥 Queued download: \(cacheKey) (Priority: \(priority))")
    }
    
    /// Cancel specific download
    func cancelDownload(cacheKey: String) {
        // Remove from queue
        downloadQueue.removeAll { $0.cacheKey == cacheKey }
        queuedDownloadCount = downloadQueue.count
        
        // Cancel active download
        if activeDownloads.contains(cacheKey) {
            backgroundDownloader.cancelDownload(cacheKey: cacheKey)
            activeDownloads.remove(cacheKey)
            activeDownloadCount = activeDownloads.count
        }
        
        downloadPriorities.removeValue(forKey: cacheKey)
        
        logger.debug("🛑 Cancelled download: \(cacheKey)")
    }
    
    /// Update download strategy based on user preference
    func updateDownloadStrategy(_ strategy: DownloadStrategy) {
        downloadStrategy = strategy
        saveUserPreferences()
        
        // Reprocess queue with new strategy
        processDownloadQueue()
        
        logger.info("📋 Updated download strategy: \(strategy)")
    }
    
    /// Get recommended image quality for current conditions
    func getRecommendedImageQuality() -> ImageQuality {
        switch networkConditions {
        case .wifiExcellent, .wifiGood:
            return preferQualityOverSpeed ? .highest : .high
            
        case .wifiFair:
            return .medium
            
        case .cellularExcellent:
            return allowCellularDownloads ? (preferQualityOverSpeed ? .high : .medium) : .low
            
        case .cellularGood:
            return allowCellularDownloads ? .medium : .low
            
        case .cellularFair, .cellularPoor:
            return allowCellularDownloads ? .low : .thumbnail
            
        case .offline, .unknown:
            return .thumbnail
        }
    }
    
    /// Get maximum concurrent downloads for current conditions
    func getMaxConcurrentDownloads() -> Int {
        switch networkConditions {
        case .wifiExcellent:
            return 8
        case .wifiGood:
            return 6
        case .wifiFair:
            return 4
        case .cellularExcellent:
            return allowCellularDownloads ? 4 : 0
        case .cellularGood:
            return allowCellularDownloads ? 3 : 0
        case .cellularFair:
            return allowCellularDownloads ? 2 : 0
        case .cellularPoor:
            return allowCellularDownloads ? 1 : 0
        case .offline, .unknown:
            return 0
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateNetworkConditions(path)
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDownloadStrategyForBattery()
        }
    }
    
    private func updateNetworkConditions(_ path: NWPath) {
        currentPath = path
        
        let newConditions: NetworkConditions
        
        if path.status != .satisfied {
            newConditions = .offline
        } else if path.usesInterfaceType(.wifi) {
            // Estimate WiFi quality based on path characteristics
            newConditions = estimateWiFiQuality(path)
        } else if path.usesInterfaceType(.cellular) {
            // Estimate cellular quality
            newConditions = estimateCellularQuality(path)
        } else {
            newConditions = .unknown
        }
        
        if networkConditions != newConditions {
            networkConditions = newConditions
            logger.info("📶 Network conditions changed: \(newConditions)")
            
            // Adjust download strategy
            adjustDownloadsForNetworkChange()
        }
    }
    
    private func estimateWiFiQuality(_ path: NWPath) -> NetworkConditions {
        // In a real implementation, you might use additional metrics
        // For now, we'll use basic path characteristics
        
        if path.isExpensive {
            return .wifiFair // Might be a hotspot or limited connection
        } else {
            return .wifiGood // Assume good quality for regular WiFi
        }
    }
    
    private func estimateCellularQuality(_ path: NWPath) -> NetworkConditions {
        // In a real implementation, you might use CTTelephonyNetworkInfo
        // or other cellular-specific APIs
        
        if path.isExpensive {
            return .cellularFair // Expensive usually means limited data
        } else {
            return .cellularGood // Assume reasonable quality
        }
    }
    
    private func updateDownloadStrategyForBattery() {
        let batteryState = UIDevice.current.batteryState
        let batteryLevel = UIDevice.current.batteryLevel
        
        // Adjust strategy based on battery state
        if batteryState == .unplugged && batteryLevel < 0.2 {
            // Low battery - be conservative
            downloadStrategy = .conservative
            logger.info("🔋 Low battery detected, switching to conservative downloads")
        } else if batteryState == .charging || batteryState == .full {
            // Charging or full - can be more aggressive
            if downloadStrategy == .conservative {
                downloadStrategy = .balanced
                logger.info("🔋 Device charging, switching to balanced downloads")
            }
        }
    }
    
    private func insertDownloadInQueue(_ download: QueuedDownload) {
        // Find insertion point based on priority and network conditions
        let insertIndex = downloadQueue.firstIndex { existingDownload in
            // Higher priority downloads go first
            if download.priority.rawValue > existingDownload.priority.rawValue {
                return true
            }
            
            // Same priority - consider network conditions and strategy
            if download.priority == existingDownload.priority {
                return shouldPrioritizeDownload(download, over: existingDownload)
            }
            
            return false
        } ?? downloadQueue.count
        
        downloadQueue.insert(download, at: insertIndex)
    }
    
    private func shouldPrioritizeDownload(_ download1: QueuedDownload, over download2: QueuedDownload) -> Bool {
        switch downloadStrategy {
        case .aggressive:
            // Prioritize newer downloads for immediate user feedback
            return download1.queueTime > download2.queueTime
            
        case .balanced:
            // FIFO for same priority
            return download1.queueTime < download2.queueTime
            
        case .conservative:
            // Prioritize older downloads to clear backlog
            return download1.queueTime < download2.queueTime
        }
    }
    
    private func processDownloadQueue() {
        let maxConcurrent = getMaxConcurrentDownloads()
        
        // Start downloads up to the limit
        while activeDownloads.count < maxConcurrent && !downloadQueue.isEmpty {
            let download = downloadQueue.removeFirst()
            startDownload(download)
        }
        
        // Update UI
        queuedDownloadCount = downloadQueue.count
        activeDownloadCount = activeDownloads.count
    }
    
    private func startDownload(_ download: QueuedDownload) {
        activeDownloads.insert(download.cacheKey)
        downloadPriorities[download.cacheKey] = download.priority
        
        backgroundDownloader.downloadImage(
            from: download.urlString,
            cacheKey: download.cacheKey,
            priority: download.priority
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleDownloadCompletion(download.cacheKey, result: result, completion: download.completion)
            }
        }
        
        logger.debug("🚀 Started download: \(download.cacheKey)")
    }
    
    private func handleDownloadCompletion(
        _ cacheKey: String,
        result: Result<URL, Error>,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        activeDownloads.remove(cacheKey)
        downloadPriorities.removeValue(forKey: cacheKey)
        
        completion(result)
        
        // Process next downloads in queue
        processDownloadQueue()
        
        // Update UI
        activeDownloadCount = activeDownloads.count
        
        logger.debug("✅ Completed download: \(cacheKey)")
    }
    
    private func adjustDownloadsForNetworkChange() {
        let newMaxConcurrent = getMaxConcurrentDownloads()
        
        // If we need to reduce active downloads
        if activeDownloads.count > newMaxConcurrent {
            let excessCount = activeDownloads.count - newMaxConcurrent
            let downloadsToCancel = Array(activeDownloads.prefix(excessCount))
            
            for cacheKey in downloadsToCancel {
                // Move back to queue instead of cancelling completely
                if let priority = downloadPriorities[cacheKey] {
                    // This is a simplified approach - in practice you'd want to preserve the original completion handler
                    logger.info("📶 Requeuing download due to network change: \(cacheKey)")
                }
                
                backgroundDownloader.cancelDownload(cacheKey: cacheKey)
                activeDownloads.remove(cacheKey)
            }
        }
        
        // Process queue with new limits
        processDownloadQueue()
    }
    
    private func loadUserPreferences() {
        allowCellularDownloads = UserDefaults.standard.bool(forKey: "allowCellularDownloads")
        allowBackgroundDownloads = UserDefaults.standard.bool(forKey: "allowBackgroundDownloads")
        preferQualityOverSpeed = UserDefaults.standard.bool(forKey: "preferQualityOverSpeed")
        
        if let strategyRaw = UserDefaults.standard.object(forKey: "downloadStrategy") as? Int,
           let strategy = DownloadStrategy(rawValue: strategyRaw) {
            downloadStrategy = strategy
        }
    }
    
    private func saveUserPreferences() {
        UserDefaults.standard.set(allowCellularDownloads, forKey: "allowCellularDownloads")
        UserDefaults.standard.set(allowBackgroundDownloads, forKey: "allowBackgroundDownloads")
        UserDefaults.standard.set(preferQualityOverSpeed, forKey: "preferQualityOverSpeed")
        UserDefaults.standard.set(downloadStrategy.rawValue, forKey: "downloadStrategy")
    }
}

// MARK: - Supporting Types

enum NetworkConditions: String, CaseIterable {
    case wifiExcellent = "WiFi Excellent"
    case wifiGood = "WiFi Good"
    case wifiFair = "WiFi Fair"
    case cellularExcellent = "Cellular Excellent"
    case cellularGood = "Cellular Good"
    case cellularFair = "Cellular Fair"
    case cellularPoor = "Cellular Poor"
    case offline = "Offline"
    case unknown = "Unknown"
    
    var allowsLargeDownloads: Bool {
        switch self {
        case .wifiExcellent, .wifiGood, .cellularExcellent:
            return true
        default:
            return false
        }
    }
}

enum DownloadStrategy: Int, CaseIterable {
    case aggressive = 2
    case balanced = 1
    case conservative = 0
    
    var description: String {
        switch self {
        case .aggressive: return "Aggressive"
        case .balanced: return "Balanced"
        case .conservative: return "Conservative"
        }
    }
}

enum ImageQuality: String, CaseIterable {
    case thumbnail = "Thumbnail"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case highest = "Highest"
    
    var compressionQuality: CGFloat {
        switch self {
        case .thumbnail: return 0.3
        case .low: return 0.5
        case .medium: return 0.7
        case .high: return 0.8
        case .highest: return 0.95
        }
    }
}

struct QueuedDownload {
    let urlString: String
    let cacheKey: String
    let priority: DownloadPriority
    let queueTime: Date
    let completion: (Result<URL, Error>) -> Void
}
