import Foundation
import UserNotifications
import UIKit

/// NotificationManager - Handles push notifications and local notifications
/// Ports the notification system from React Native
@MainActor
class NotificationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isRegistered: Bool = false
    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    init() {
        notificationCenter.delegate = self
        
        Task {
            await checkNotificationPermissionStatus()
        }
    }
    
    // MARK: - Public Methods
    func registerForPushNotifications() async throws {
        Logger.info("Notifications", "Registering for push notifications")
        
        // Request permission
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        
        guard granted else {
            throw NotificationError.permissionDenied
        }
        
        // Register for remote notifications on main thread
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        isRegistered = true
        Logger.info("Notifications", "Successfully registered for push notifications")
    }
    
    func handlePushNotification(_ userInfo: [AnyHashable: Any]) {
        Logger.info("Notifications", "Handling push notification: \(userInfo)")
        
        // Port the push notification handling logic from React Native
        if let notificationData = userInfo["data"] as? [String: Any],
           let type = notificationData["type"] as? String {
            
            switch type {
            case "catalog_updated":
                handleCatalogUpdateNotification(notificationData)
            default:
                Logger.debug("Notifications", "Unknown notification type: \(type)")
            }
        }
    }
    
    func scheduleLocalNotification(
        title: String,
        body: String,
        identifier: String,
        delay: TimeInterval = 0
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try await notificationCenter.add(request)
        Logger.debug("Notifications", "Scheduled local notification: \(title)")
    }
    
    func clearAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        
        // Clear badge count
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        Logger.info("Notifications", "Cleared all notifications")
    }
    
    // MARK: - Private Methods
    private func checkNotificationPermissionStatus() async {
        let settings = await notificationCenter.notificationSettings()
        notificationPermissionStatus = settings.authorizationStatus
        isRegistered = settings.authorizationStatus == .authorized
    }
    
    private func handleCatalogUpdateNotification(_ data: [String: Any]) {
        Logger.info("Notifications", "Handling catalog update notification")
        
        // Trigger catalog sync
        Task {
            do {
                try await CatalogSyncService.shared.runIncrementalSync()
                Logger.info("Notifications", "Catalog sync triggered by push notification")
            } catch {
                Logger.error("Notifications", "Failed to sync catalog from notification: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        handlePushNotification(userInfo)
        
        completionHandler()
    }
}

// MARK: - Supporting Types
enum NotificationError: LocalizedError {
    case permissionDenied
    case registrationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied"
        case .registrationFailed:
            return "Failed to register for notifications"
        }
    }
}
