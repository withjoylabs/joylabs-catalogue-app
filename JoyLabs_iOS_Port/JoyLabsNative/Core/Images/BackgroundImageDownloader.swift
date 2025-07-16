import Foundation
import UIKit
import os.log
import Network

/// Industry-standard background image downloader with URLSession background configuration
/// Enables downloads to continue when app is backgrounded or terminated
class BackgroundImageDownloader: NSObject, ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = BackgroundImageDownloader()
    
    // MARK: - Published Properties
    @Published var activeDownloads: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var networkStatus: NetworkStatus = .unknown
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "BackgroundImageDownloader")
    private let fileManager = FileManager.default
    private let networkMonitor = NWPathMonitor()
    
    // MARK: - Configuration
    private let maxConcurrentDownloads = 6
    private let downloadTimeout: TimeInterval = 60.0
    private let retryAttempts = 3
    
    // MARK: - Cache Configuration
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    
    // MARK: - Background Session
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.joylabs.native.image-downloads")
        
        // Configure for optimal background performance
        config.isDiscretionary = false // Don't wait for optimal conditions
        config.sessionSendsLaunchEvents = true // Launch app when downloads complete
        config.allowsCellularAccess = true // Allow cellular downloads
        config.timeoutIntervalForRequest = downloadTimeout
        config.timeoutIntervalForResource = downloadTimeout * 2
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        
        // Configure caching
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024, // 10MB memory
            diskCapacity: 50 * 1024 * 1024,   // 50MB disk
            diskPath: "background_image_cache"
        )
        
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Download Management
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadCompletions: [String: (Result<URL, Error>) -> Void] = [:]
    private var downloadRetryCount: [String: Int] = [:]
    
    // MARK: - Network Status
    enum NetworkStatus {
        case unknown
        case wifi
        case cellular
        case offline
        
        var allowsLargeDownloads: Bool {
            switch self {
            case .wifi: return true
            case .cellular, .unknown: return false
            case .offline: return false
            }
        }
        
        var maxConcurrentDownloads: Int {
            switch self {
            case .wifi: return 6
            case .cellular, .unknown: return 3
            case .offline: return 0
            }
        }
    }
    
    // MARK: - Initialization
    override init() {
        // Create cache directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("BackgroundImageCache")
        
        super.init()
        
        setupCacheDirectory()
        startNetworkMonitoring()
        
        logger.info("🌐 BackgroundImageDownloader initialized with cache: \(cacheDirectory.path)")
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Download image with background capability and network awareness
    func downloadImage(
        from urlString: String,
        cacheKey: String,
        priority: DownloadPriority = .normal,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(ImageDownloadError.invalidURL))
            return
        }
        
        // Check if already downloading
        if downloadTasks[cacheKey] != nil {
            logger.debug("⏳ Image already downloading: \(cacheKey)")
            // Store additional completion handler
            let existingCompletion = downloadCompletions[cacheKey]
            downloadCompletions[cacheKey] = { result in
                existingCompletion?(result)
                completion(result)
            }
            return
        }
        
        // Check network conditions
        guard networkStatus != .offline else {
            completion(.failure(ImageDownloadError.networkUnavailable))
            return
        }
        
        // Respect concurrent download limits based on network
        guard activeDownloads.count < networkStatus.maxConcurrentDownloads else {
            // Queue for later or reject based on priority
            if priority == .high {
                // Cancel lowest priority download to make room
                cancelLowestPriorityDownload()
            } else {
                completion(.failure(ImageDownloadError.tooManyDownloads))
                return
            }
        }
        
        startDownload(url: url, cacheKey: cacheKey, priority: priority, completion: completion)
    }
    
    /// Cancel specific download
    func cancelDownload(cacheKey: String) {
        guard let task = downloadTasks[cacheKey] else { return }
        
        task.cancel()
        cleanupDownload(cacheKey: cacheKey)
        
        logger.debug("🛑 Cancelled download: \(cacheKey)")
    }
    
    /// Cancel all downloads
    func cancelAllDownloads() {
        for cacheKey in downloadTasks.keys {
            cancelDownload(cacheKey: cacheKey)
        }
        
        logger.info("🛑 Cancelled all downloads")
    }
    
    /// Get cached file URL if exists
    func getCachedFileURL(for cacheKey: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    // MARK: - Private Methods
    
    private func setupCacheDirectory() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("❌ Failed to create cache directory: \(error)")
        }
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path)
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        let newStatus: NetworkStatus
        
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                newStatus = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newStatus = .cellular
            } else {
                newStatus = .unknown
            }
        } else {
            newStatus = .offline
        }
        
        if networkStatus != newStatus {
            networkStatus = newStatus
            logger.info("📶 Network status changed to: \(newStatus)")
            
            // Adjust downloads based on new network conditions
            adjustDownloadsForNetworkChange()
        }
    }
    
    private func adjustDownloadsForNetworkChange() {
        let maxAllowed = networkStatus.maxConcurrentDownloads
        
        if activeDownloads.count > maxAllowed {
            // Cancel excess downloads, keeping highest priority
            let excessCount = activeDownloads.count - maxAllowed
            let tasksToCancel = Array(downloadTasks.keys.prefix(excessCount))
            
            for cacheKey in tasksToCancel {
                cancelDownload(cacheKey: cacheKey)
            }
            
            logger.info("📶 Adjusted downloads for network change: cancelled \(excessCount) downloads")
        }
    }
}

// MARK: - Download Priority
enum DownloadPriority: Int, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    
    var taskPriority: URLSessionTask.Priority {
        switch self {
        case .low: return .low
        case .normal: return .default
        case .high: return .high
        }
    }
}

// MARK: - Errors
enum ImageDownloadError: LocalizedError {
    case invalidURL
    case networkUnavailable
    case tooManyDownloads
    case downloadFailed(Error)
    case fileSystemError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .networkUnavailable:
            return "Network unavailable"
        case .tooManyDownloads:
            return "Too many concurrent downloads"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "File system error: \(error.localizedDescription)"
        }
    }
}

// MARK: - BackgroundImageDownloader Private Methods Extension
extension BackgroundImageDownloader {

    private func startDownload(
        url: URL,
        cacheKey: String,
        priority: DownloadPriority,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let task = backgroundSession.downloadTask(with: url)
        task.priority = priority.taskPriority

        // Store task and completion
        downloadTasks[cacheKey] = task
        downloadCompletions[cacheKey] = completion
        downloadRetryCount[cacheKey] = 0

        // Update state
        DispatchQueue.main.async {
            self.activeDownloads.insert(cacheKey)
            self.downloadProgress[cacheKey] = 0.0
        }

        task.resume()

        logger.info("⬇️ Started background download: \(cacheKey) from \(url.absoluteString)")
    }

    private func cancelLowestPriorityDownload() {
        // Find and cancel the lowest priority download
        // For now, cancel the first one (could be enhanced with actual priority tracking)
        if let firstKey = downloadTasks.keys.first {
            cancelDownload(cacheKey: firstKey)
        }
    }

    private func cleanupDownload(cacheKey: String) {
        downloadTasks.removeValue(forKey: cacheKey)
        downloadCompletions.removeValue(forKey: cacheKey)
        downloadRetryCount.removeValue(forKey: cacheKey)

        DispatchQueue.main.async {
            self.activeDownloads.remove(cacheKey)
            self.downloadProgress.removeValue(forKey: cacheKey)
        }
    }

    private func retryDownload(cacheKey: String, url: URL, priority: DownloadPriority) {
        let retryCount = downloadRetryCount[cacheKey] ?? 0

        guard retryCount < retryAttempts else {
            // Max retries reached, fail the download
            if let completion = downloadCompletions[cacheKey] {
                completion(.failure(ImageDownloadError.downloadFailed(NSError(domain: "MaxRetriesReached", code: -1))))
            }
            cleanupDownload(cacheKey: cacheKey)
            return
        }

        downloadRetryCount[cacheKey] = retryCount + 1

        // Exponential backoff
        let delay = pow(2.0, Double(retryCount))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  let completion = self.downloadCompletions[cacheKey] else { return }

            self.logger.info("🔄 Retrying download (\(retryCount + 1)/\(self.retryAttempts)): \(cacheKey)")
            self.startDownload(url: url, cacheKey: cacheKey, priority: priority, completion: completion)
        }
    }

    private func moveDownloadedFile(from tempURL: URL, to cacheKey: String) -> Result<URL, Error> {
        let destinationURL = cacheDirectory.appendingPathComponent(cacheKey)

        do {
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Move downloaded file to cache
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            // Update file modification date for LRU
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)

            logger.info("✅ Image cached successfully: \(cacheKey)")
            return .success(destinationURL)

        } catch {
            logger.error("❌ Failed to move downloaded file: \(error)")
            return .failure(ImageDownloadError.fileSystemError(error))
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension BackgroundImageDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalURL = downloadTask.originalRequest?.url,
              let cacheKey = findCacheKey(for: downloadTask) else {
            logger.error("❌ Could not find cache key for completed download")
            return
        }

        logger.info("📥 Download completed: \(cacheKey)")

        let result = moveDownloadedFile(from: location, to: cacheKey)

        DispatchQueue.main.async {
            if let completion = self.downloadCompletions[cacheKey] {
                completion(result)
            }
            self.cleanupDownload(cacheKey: cacheKey)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let cacheKey = findCacheKey(for: downloadTask) else { return }

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0

        DispatchQueue.main.async {
            self.downloadProgress[cacheKey] = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let cacheKey = findCacheKey(for: downloadTask) else { return }

        if let error = error {
            logger.error("❌ Download failed: \(cacheKey) - \(error.localizedDescription)")

            // Check if we should retry
            if let originalURL = downloadTask.originalRequest?.url,
               (error as NSError).code != NSURLErrorCancelled {
                retryDownload(cacheKey: cacheKey, url: originalURL, priority: .normal)
            } else {
                DispatchQueue.main.async {
                    if let completion = self.downloadCompletions[cacheKey] {
                        completion(.failure(ImageDownloadError.downloadFailed(error)))
                    }
                    self.cleanupDownload(cacheKey: cacheKey)
                }
            }
        }
    }

    private func findCacheKey(for task: URLSessionDownloadTask) -> String? {
        return downloadTasks.first { $0.value == task }?.key
    }
}

// MARK: - URLSessionDelegate
extension BackgroundImageDownloader: URLSessionDelegate {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        logger.info("🎉 Background URL session finished all events")

        DispatchQueue.main.async {
            // Notify app delegate that background downloads completed
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.backgroundDownloadCompletionHandler?()
                appDelegate.backgroundDownloadCompletionHandler = nil
            }
        }
    }
}
