import Foundation
import Combine
import OSLog

/// Service for managing user notification preferences
@MainActor
public class NotificationSettingsService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = NotificationSettingsService()
    
    // MARK: - Published Properties
    @Published var appLaunchSyncNotifications = true
    @Published var webhookSyncNotifications = true
    @Published var catalogUpdateNotifications = true
    @Published var systemBadgeNotifications = true
    @Published var imageUpdateNotifications = true
    @Published var syncErrorNotifications = true
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.joylabs.native", category: "NotificationSettings")
    
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let appLaunchSyncNotifications = "notification_app_launch_sync"
        static let webhookSyncNotifications = "notification_webhook_sync"
        static let catalogUpdateNotifications = "notification_catalog_update"
        static let systemBadgeNotifications = "notification_system_badge"
        static let imageUpdateNotifications = "notification_image_update"
        static let syncErrorNotifications = "notification_sync_error"
    }
    
    // MARK: - Initialization
    private init() {
        loadSettings()
        logger.info("🔔 NotificationSettingsService initialized")
    }
    
    // MARK: - Public Methods
    
    /// Load settings from UserDefaults
    func loadSettings() {
        appLaunchSyncNotifications = userDefaults.bool(forKey: Keys.appLaunchSyncNotifications, defaultValue: true)
        webhookSyncNotifications = userDefaults.bool(forKey: Keys.webhookSyncNotifications, defaultValue: true)
        catalogUpdateNotifications = userDefaults.bool(forKey: Keys.catalogUpdateNotifications, defaultValue: true)
        systemBadgeNotifications = userDefaults.bool(forKey: Keys.systemBadgeNotifications, defaultValue: true)
        imageUpdateNotifications = userDefaults.bool(forKey: Keys.imageUpdateNotifications, defaultValue: true)
        syncErrorNotifications = userDefaults.bool(forKey: Keys.syncErrorNotifications, defaultValue: true)
        
        logger.info("📱 Notification settings loaded")
    }
    
    /// Save settings to UserDefaults
    func saveSettings() {
        userDefaults.set(appLaunchSyncNotifications, forKey: Keys.appLaunchSyncNotifications)
        userDefaults.set(webhookSyncNotifications, forKey: Keys.webhookSyncNotifications)
        userDefaults.set(catalogUpdateNotifications, forKey: Keys.catalogUpdateNotifications)
        userDefaults.set(systemBadgeNotifications, forKey: Keys.systemBadgeNotifications)
        userDefaults.set(imageUpdateNotifications, forKey: Keys.imageUpdateNotifications)
        userDefaults.set(syncErrorNotifications, forKey: Keys.syncErrorNotifications)
        
        logger.info("💾 Notification settings saved")
    }
    
    /// Check if a specific notification type is enabled
    func isEnabled(for type: NotificationType) -> Bool {
        switch type {
        case .appLaunchSync:
            return appLaunchSyncNotifications
        case .webhookSync:
            return webhookSyncNotifications
        case .catalogUpdate:
            return catalogUpdateNotifications
        case .systemBadge:
            return systemBadgeNotifications
        case .imageUpdate:
            return imageUpdateNotifications
        case .syncError:
            return syncErrorNotifications
        }
    }
    
    /// Toggle a specific notification type
    func toggle(_ type: NotificationType) {
        switch type {
        case .appLaunchSync:
            appLaunchSyncNotifications.toggle()
        case .webhookSync:
            webhookSyncNotifications.toggle()
        case .catalogUpdate:
            catalogUpdateNotifications.toggle()
        case .systemBadge:
            systemBadgeNotifications.toggle()
        case .imageUpdate:
            imageUpdateNotifications.toggle()
        case .syncError:
            syncErrorNotifications.toggle()
        }
        saveSettings()
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        appLaunchSyncNotifications = true
        webhookSyncNotifications = true
        catalogUpdateNotifications = true
        systemBadgeNotifications = true
        imageUpdateNotifications = true
        syncErrorNotifications = true
        saveSettings()
        
        logger.info("🔄 Notification settings reset to defaults")
    }
}

// MARK: - Notification Types

public enum NotificationType {
    case appLaunchSync
    case webhookSync
    case catalogUpdate
    case systemBadge
    case imageUpdate
    case syncError
    
    var title: String {
        switch self {
        case .appLaunchSync:
            return "App Launch Sync"
        case .webhookSync:
            return "Webhook Sync"
        case .catalogUpdate:
            return "Catalog Updates"
        case .systemBadge:
            return "Badge Notifications"
        case .imageUpdate:
            return "Image Updates"
        case .syncError:
            return "Sync Errors"
        }
    }
    
    var description: String {
        switch self {
        case .appLaunchSync:
            return "Notifications when app syncs on launch"
        case .webhookSync:
            return "Notifications from real-time webhook updates"
        case .catalogUpdate:
            return "General catalog update notifications"
        case .systemBadge:
            return "App icon badge count"
        case .imageUpdate:
            return "Product image update notifications"
        case .syncError:
            return "Notifications when sync fails"
        }
    }
    
    var icon: String {
        switch self {
        case .appLaunchSync:
            return "arrow.clockwise.circle"
        case .webhookSync:
            return "bolt.circle"
        case .catalogUpdate:
            return "square.grid.3x3"
        case .systemBadge:
            return "app.badge"
        case .imageUpdate:
            return "photo.circle"
        case .syncError:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - UserDefaults Extension

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}