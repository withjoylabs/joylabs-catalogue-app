import Foundation
import SwiftUI
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
        loadPersistedNotifications()
        setupWebhookObservers()
        logger.info("[WebhookNotification] WebhookNotificationService initialized")
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
        saveNotificationsToPersistence()
        logger.debug("[WebhookNotification] All webhook notifications marked as read")
    }
    
    /// Mark specific notification as read
    func markAsRead(_ notificationId: String) {
        if let index = webhookNotifications.firstIndex(where: { $0.id == notificationId }) {
            if !webhookNotifications[index].isRead {
                webhookNotifications[index].isRead = true
                unreadCount = max(0, unreadCount - 1)
                saveNotificationsToPersistence()
            }
        }
    }
    
    /// Clear all notifications
    func clearAllNotifications() {
        webhookNotifications.removeAll()
        unreadCount = 0
        saveNotificationsToPersistence()
        logger.info("[WebhookNotification] All webhook notifications cleared")
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
            .dropFirst() // Skip initial false value to avoid "stopped" message on startup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isWebhookActive = isActive
                // Only log actual state changes, not initial states
                self?.logger.debug("[WebhookNotification] Webhook system \(isActive ? "started" : "stopped")")
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
        
        logger.debug("[WebhookNotification] Webhook notification observers configured")
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
    
    /// Handle catalog sync notifications triggered by webhooks (DISABLED - preventing duplicates)
    private func handleCatalogSyncNotification(_ notification: Notification) {
        // DISABLED: This was creating duplicate notifications 
        // Webhook sync notifications are now handled directly by PushNotificationService
        
        // Still update stats for tracking
        if let userInfo = notification.userInfo,
           let reason = userInfo["reason"] as? String,
           reason.contains("webhook") || reason.contains("catalog") {
            webhookStats.catalogUpdates += 1
            logger.trace("[WebhookNotification] Catalog sync stats updated")
        }
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
    
    /// Add authentication failure notification
    func addAuthenticationFailureNotification() {
        let notification = WebhookNotification(
            title: "Authentication Failed",
            message: "Square authentication expired. Please reconnect in Profile.",
            type: .error,
            eventType: "auth.failed",
            timestamp: Date()
        )
        
        addNotification(notification)
        logger.error("[WebhookNotification] Authentication failure notification added")
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
        
        logger.trace("[WebhookNotification] Added webhook notification: \(notification.title)")
        
        // Save to persistence after adding
        saveNotificationsToPersistence()
    }
    
    // MARK: - Persistence
    
    private func loadPersistedNotifications() {
        if let data = UserDefaults.standard.data(forKey: "WebhookNotifications"),
           let decoded = try? JSONDecoder().decode([WebhookNotificationData].self, from: data) {
            
            webhookNotifications = decoded.map { data in
                WebhookNotification(
                    title: data.title,
                    message: data.message,
                    type: data.type,
                    eventType: data.eventType,
                    timestamp: data.timestamp,
                    isRead: data.isRead
                )
            }
            
            // Recalculate unread count
            unreadCount = self.webhookNotifications.filter { !$0.isRead }.count
            
            logger.debug("[WebhookNotification] Loaded \(self.webhookNotifications.count) persisted notifications")
        }
    }
    
    private func saveNotificationsToPersistence() {
        let notificationData = webhookNotifications.map { notification in
            WebhookNotificationData(
                title: notification.title,
                message: notification.message,
                type: notification.type,
                eventType: notification.eventType,
                timestamp: notification.timestamp,
                isRead: notification.isRead
            )
        }
        
        if let encoded = try? JSONEncoder().encode(notificationData) {
            UserDefaults.standard.set(encoded, forKey: "WebhookNotifications")
            logger.trace("[WebhookNotification] Saved \(notificationData.count) notifications to persistence")
        }
    }
}

// MARK: - Supporting Types

/// Codable version of WebhookNotification for persistence
private struct WebhookNotificationData: Codable {
    let title: String
    let message: String
    let type: WebhookNotificationType
    let eventType: String
    let timestamp: Date
    let isRead: Bool
}

/// Webhook notification model
struct WebhookNotification: Identifiable {
    let id = UUID().uuidString
    let title: String
    let message: String
    let type: WebhookNotificationType
    let eventType: String
    let timestamp: Date
    var isRead: Bool = false
    
    // Custom initializer for persistence loading
    init(title: String, message: String, type: WebhookNotificationType, eventType: String, timestamp: Date, isRead: Bool = false) {
        self.title = title
        self.message = message
        self.type = type
        self.eventType = eventType
        self.timestamp = timestamp
        self.isRead = isRead
    }
    
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
    
    var color: Color {
        switch type {
        case .success:
            return .green
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        case .system:
            return .secondary
        }
    }
}

/// Webhook notification types
enum WebhookNotificationType: Codable {
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