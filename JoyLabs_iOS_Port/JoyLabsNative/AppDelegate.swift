import UIKit
import UserNotifications
import OSLog

/// AppDelegate for handling background tasks, URL session events, and push notifications
class AppDelegate: NSObject, UIApplicationDelegate {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "AppDelegate")
    
    // Background download completion handler
    var backgroundDownloadCompletionHandler: (() -> Void)?
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logger.info("🚀 Application did finish launching")
        
        // Set up push notification delegate
        UNUserNotificationCenter.current().delegate = PushNotificationService.shared
        
        // Push notifications are set up in JoyLabsNativeApp.swift after database initialization
        
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
    
    // MARK: - Push Notification Handling
    
    /// Called when device successfully registers for push notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        logger.info("✅ Successfully registered for remote notifications")
        
        // Convert token to string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.debug("📱 Push token: \(tokenString.prefix(10))...")
        
        // Send token to backend
        Task { @MainActor in
            await PushNotificationService.shared.sendTokenToBackend(tokenString)
        }
    }
    
    /// Called when device fails to register for push notifications
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("❌ Failed to register for remote notifications: \(error)")
        
        Task { @MainActor in
            PushNotificationService.shared.notificationError = error.localizedDescription
        }
    }
    
    /// Handle background push notifications
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.info("📥 Received background push notification")
        
        // Process the notification
        Task {
            await PushNotificationService.shared.handleNotification(userInfo)
            
            // Call completion handler on main thread
            await MainActor.run {
                completionHandler(.newData)
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let applicationWillEnterForeground = Notification.Name("applicationWillEnterForeground")
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
    static let applicationWillResignActive = Notification.Name("applicationWillResignActive")
}
