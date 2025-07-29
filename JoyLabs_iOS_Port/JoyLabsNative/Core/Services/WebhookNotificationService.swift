import Foundation
import OSLog
import Combine

/// Webhook Notification Service - Manages notifications for webhook events
/// Integrates with the notification bell in ScanView for webhook status updates
@MainActor
class WebhookNotificationService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = WebhookNotificationService()
    
    // MARK: - Published Properties
    @Published var webhookNotifications: [WebhookNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isWebhookActive: Bool = false
    @Published var lastWebhookReceived: Date?
    @Published var webhookStats: WebhookNotificationStats = WebhookNotificationStats()
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookNotificationService")
    private var cancellables = Set<AnyCancellable>()
    private let maxNotifications = 50 // Keep last 50 notifications
    
    // MARK: - Initialization
    private init() {
        setupWebhookObservers()
        logger.info("🔔 WebhookNotificationService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Get unread notification count for badge display
    var hasUnreadNotifications: Bool {
        return unreadCount > 0
    }
    
    /// Mark all notifications as read
    func markAllAsRead() {
        for index in webhookNotifications.indices {
            webhookNotifications[index].isRead = true
        }
        unreadCount = 0
        logger.debug("📖 All webhook notifications marked as read")
    }
    
    /// Mark specific notification as read
    func markAsRead(_ notificationId: String) {
        if let index = webhookNotifications.firstIndex(where: { $0.id == notificationId }) {
            if !webhookNotifications[index].isRead {
                webhookNotifications[index].isRead = true
                unreadCount = max(0, unreadCount - 1)
            }
        }
    }
    
    /// Clear all notifications
    func clearAllNotifications() {
        webhookNotifications.removeAll()
        unreadCount = 0
        logger.info("🗑️ All webhook notifications cleared")
    }
    
    /// Get recent webhook activity for display
    func getRecentActivity() -> [WebhookNotification] {
        return Array(webhookNotifications.prefix(10))
    }
    
    /// Get webhook system status for debugging
    func getWebhookSystemStatus() -> WebhookSystemStatus {
        return WebhookSystemStatus(
            isActive: isWebhookActive,
            lastReceived: lastWebhookReceived,
            totalReceived: webhookStats.totalReceived,
            totalProcessed: webhookStats.totalProcessed,
            totalFailed: webhookStats.totalFailed,
            catalogUpdates: webhookStats.catalogUpdates,
            imageUpdates: webhookStats.imageUpdates
        )
    }
}

// MARK: - Private Implementation
extension WebhookNotificationService {
    
    /// Setup observers for webhook-related notifications
    private func setupWebhookObservers() {
        // Observe webhook status changes (but don't create confusing UI notifications)
        WebhookManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isWebhookActive = isActive
                // Only log status changes, don't create user-visible notifications
                print("🔔 Webhook system \(isActive ? "started" : "stopped")")
            }
            .store(in: &cancellables)
        
        // Observe webhook processing results
        WebhookManager.shared.$lastProcessedWebhook
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processedWebhook in
                self?.handleProcessedWebhook(processedWebhook)
            }
            .store(in: &cancellables)
        
        // Observe image refresh notifications
        NotificationCenter.default.publisher(for: .forceImageRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleImageRefreshNotification(notification)
            }
            .store(in: &cancellables)
        
        // Observe catalog sync notifications
        NotificationCenter.default.publisher(for: .catalogSyncCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCatalogSyncNotification(notification)
            }
            .store(in: &cancellables)
        
        logger.debug("🔗 Webhook notification observers configured")
    }
    
    /// Handle processed webhook events
    private func handleProcessedWebhook(_ processedWebhook: ProcessedWebhook) {
        lastWebhookReceived = processedWebhook.timestamp
        webhookStats.totalReceived += 1
        
        if processedWebhook.success {
            webhookStats.totalProcessed += 1
            addWebhookNotification(
                title: "Webhook Processed",
                message: "Successfully processed \(processedWebhook.eventType) event",
                type: .success,
                eventType: processedWebhook.eventType
            )
        } else {
            webhookStats.totalFailed += 1
            addWebhookNotification(
                title: "Webhook Failed",
                message: processedWebhook.error ?? "Unknown error",
                type: .error,
                eventType: processedWebhook.eventType
            )
        }
    }
    
    /// Handle image refresh notifications triggered by webhooks
    private func handleImageRefreshNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo["reason"] as? String,
              reason.contains("webhook") else {
            return
        }
        
        webhookStats.imageUpdates += 1
        
        if let itemId = userInfo["itemId"] as? String {
            addWebhookNotification(
                title: "Image Updated",
                message: "Image cache refreshed for item \(itemId)",
                type: .info,
                eventType: "image.updated"
            )
        } else {
            addWebhookNotification(
                title: "Images Refreshed",
                message: "Global image cache refresh triggered",
                type: .info,
                eventType: "catalog.version.updated"
            )
        }
    }
    
    /// Handle catalog sync notifications triggered by webhooks
    private func handleCatalogSyncNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo["reason"] as? String,
              reason.contains("webhook") || reason.contains("catalog") else {
            return
        }
        
        webhookStats.catalogUpdates += 1
        
        addWebhookNotification(
            title: "Catalog Updated",
            message: "Catalog synchronized via webhook",
            type: .success,
            eventType: "catalog.sync"
        )
    }
    
    /// Add a webhook-related notification (public for external services)
    func addWebhookNotification(
        title: String,
        message: String,
        type: WebhookNotificationType,
        eventType: String
    ) {
        let notification = WebhookNotification(
            title: title,
            message: message,
            type: type,
            eventType: eventType,
            timestamp: Date()
        )
        
        addNotification(notification)
    }
    
    /// Add a system notification
    private func addSystemNotification(_ message: String, type: WebhookNotificationType) {
        let notification = WebhookNotification(
            title: "Webhook System",
            message: message,
            type: type,
            eventType: "system",
            timestamp: Date()
        )
        
        addNotification(notification)
    }
    
    /// Add notification to the list
    private func addNotification(_ notification: WebhookNotification) {
        webhookNotifications.insert(notification, at: 0)
        
        if !notification.isRead {
            unreadCount += 1
        }
        
        // Keep only the most recent notifications
        if webhookNotifications.count > maxNotifications {
            webhookNotifications.removeLast()
        }
        
        logger.debug("🔔 Added webhook notification: \(notification.title)")
    }
}

// MARK: - Supporting Types

/// Webhook notification model
struct WebhookNotification: Identifiable {
    let id = UUID().uuidString
    let title: String
    let message: String
    let type: WebhookNotificationType
    let eventType: String
    let timestamp: Date
    var isRead: Bool = false
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var icon: String {
        switch type {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .system:
            return "gear.circle.fill"
        }
    }
    
    var color: String {
        switch type {
        case .success:
            return "green"
        case .error:
            return "red"
        case .warning:
            return "orange"
        case .info:
            return "blue"
        case .system:
            return "secondary"
        }
    }
}

/// Webhook notification types
enum WebhookNotificationType {
    case success
    case error
    case warning
    case info
    case system
}

/// Webhook notification statistics
struct WebhookNotificationStats {
    var totalReceived: Int = 0
    var totalProcessed: Int = 0
    var totalFailed: Int = 0
    var catalogUpdates: Int = 0
    var imageUpdates: Int = 0
    
    var successRate: Double {
        guard totalReceived > 0 else { return 0 }
        return Double(totalProcessed) / Double(totalReceived)
    }
}

/// Webhook system status for debugging
struct WebhookSystemStatus {
    let isActive: Bool
    let lastReceived: Date?
    let totalReceived: Int
    let totalProcessed: Int
    let totalFailed: Int
    let catalogUpdates: Int
    let imageUpdates: Int
    
    var statusText: String {
        if isActive {
            return "Active • \(totalReceived) received"
        } else {
            return "Inactive"
        }
    }
}