import UIKit
import os.log

/// AppDelegate for handling background tasks and URL session events
class AppDelegate: NSObject, UIApplicationDelegate {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "AppDelegate")
    
    // Background download completion handler
    var backgroundDownloadCompletionHandler: (() -> Void)?
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logger.info("🚀 Application did finish launching")
        
        // Configure background app refresh
        if application.backgroundRefreshStatus == .available {
            logger.info("📱 Background app refresh is available")
        } else {
            logger.warning("⚠️ Background app refresh is not available")
        }
        
        return true
    }
    
    // MARK: - Background URL Session Handling
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        logger.info("🌐 Handling events for background URL session: \(identifier)")
        
        // Store completion handler for background downloads
        if identifier == "com.joylabs.native.image-downloads" {
            backgroundDownloadCompletionHandler = completionHandler
            logger.info("📥 Stored background download completion handler")
        } else {
            // Call completion handler immediately for unknown sessions
            completionHandler()
        }
    }
    
    // MARK: - Background Task Management
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("📱 Application entered background")
        
        // Background tasks will be managed by individual services
        // This is just for logging and monitoring
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("📱 Application will enter foreground")
        
        // Refresh any stale data or resume paused operations
        NotificationCenter.default.post(name: .applicationWillEnterForeground, object: nil)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        logger.info("📱 Application became active")
        
        // Resume normal operations
        NotificationCenter.default.post(name: .applicationDidBecomeActive, object: nil)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        logger.info("📱 Application will resign active")
        
        // Prepare for background or inactive state
        NotificationCenter.default.post(name: .applicationWillResignActive, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let applicationWillEnterForeground = Notification.Name("applicationWillEnterForeground")
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
    static let applicationWillResignActive = Notification.Name("applicationWillResignActive")
}
