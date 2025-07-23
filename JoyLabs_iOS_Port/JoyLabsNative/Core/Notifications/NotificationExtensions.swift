import Foundation

// MARK: - Shared Notification Extensions
extension Notification.Name {
    /// Posted when an item's image is updated (uploaded, deleted, or modified)
    static let imageUpdated = Notification.Name("imageUpdated")
}
