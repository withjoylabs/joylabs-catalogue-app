import Foundation

// MARK: - Shared Notification Extensions
extension Notification.Name {
    /// Posted when an item's image is updated (uploaded, deleted, or modified)
    static let imageUpdated = Notification.Name("imageUpdated")

    /// Posted to force immediate image refresh across all views
    static let forceImageRefresh = Notification.Name("forceImageRefresh")
    
    /// Posted when catalog sync completes
    static let catalogSyncCompleted = Notification.Name("catalogSyncCompleted")
    
    /// Posted to navigate to notification settings in profile
    static let navigateToNotificationSettings = Notification.Name("navigateToNotificationSettings")
}
