import Foundation
import UserNotifications
import UIKit
import OSLog

/// Push Notification Service - Handles push notifications from AWS backend
/// Replaces webhook polling with real-time push notifications for better efficiency
@MainActor
public class PushNotificationService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = PushNotificationService()
    
    // MARK: - Published Properties
    @Published var isAuthorized = false
    @Published var pushToken: String?
    @Published var lastNotificationReceived: Date?
    @Published var notificationError: String?
    
    // MARK: - Private Properties
    private var isSetupComplete = false
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "PushNotificationService")
    private let webhookNotificationService = WebhookNotificationService.shared
    private let baseURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api"
    
    // MARK: - Initialization
    private override init() {
        super.init()
        logger.info("🔔 PushNotificationService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Setup push notifications and request permissions
    func setupPushNotifications() async {
        // Prevent duplicate setup calls
        guard !isSetupComplete else {
            logger.debug("🔧 Push notifications already set up, skipping duplicate call")
            return
        }
        
        logger.info("🔧 Setting up push notifications...")
        
        // Request authorization
        await requestAuthorization()
        
        // Register for remote notifications if authorized
        if isAuthorized {
            await registerForRemoteNotifications()
        }
        
        isSetupComplete = true
        logger.info("✅ Push notification setup completed")
    }
    
    /// Handle received push notification
    func handleNotification(_ userInfo: [AnyHashable: Any]) async {
        logger.info("📥 Received push notification")
        lastNotificationReceived = Date()
        
        // Extract webhook data from notification (matches Square webhook format)
        guard let data = userInfo["data"] as? [String: Any],
              let type = data["type"] as? String,
              type == "catalog_updated" else {
            logger.warning("⚠️ Received non-catalog push notification. Expected 'catalog_updated', got: \(userInfo)")
            
            // Log the full notification for debugging
            logger.info("📋 Full notification payload: \(userInfo)")
            return
        }
        
        let eventId = data["eventId"] as? String ?? "unknown"
        let merchantId = data["merchantId"] as? String ?? "unknown"
        let updatedAt = data["updatedAt"] as? String ?? ""
        
        logger.info("🔄 Processing catalog update notification for merchant \(merchantId)")
        
        // Create user notification
        await createNotificationForCatalogUpdate(
            eventId: eventId,
            merchantId: merchantId,
            updatedAt: updatedAt
        )
        
        // Trigger image cache refresh
        await triggerImageCacheRefresh()
        
        // Trigger catalog sync to get latest changes from Square
        await triggerCatalogSync(eventId: eventId, merchantId: merchantId)
        
        // Clear badge count since we've processed the notification (if badges are enabled)
        let notificationSettings = NotificationSettingsService.shared
        if notificationSettings.isEnabled(for: .systemBadge) {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                logger.error("Failed to clear badge count: \(error)")
            }
        }
    }
    
    /// Send push token to AWS backend
    func sendTokenToBackend(_ token: String) async {
        logger.info("📤 Push token received: \(String(token.prefix(10)))...")
        
        guard let merchantId = await getMerchantId() else {
            logger.warning("⚠️ No merchant ID available for token registration")
            return
        }
        
        // Use webhooks API push token registration endpoint (consolidated in webhooks function)
        let url = "\(baseURL)/webhooks/merchants/\(merchantId)/push-token"
        logger.info("📍 Registering push token for merchant \(merchantId) at \(url)")
        
        do {
            guard let requestURL = URL(string: url) else {
                logger.error("❌ Invalid URL: \(url)")
                throw PushNotificationError.registrationFailed("Invalid URL")
            }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let tokenData = [
                "pushToken": token,
                "platform": "ios"
            ]
            
            logger.info("📤 Request payload: \(tokenData)")
            
            request.httpBody = try JSONSerialization.data(withJSONObject: tokenData)
            
            logger.info("🌐 Making HTTP PUT request to: \(url)")
            logger.info("📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")
            logger.info("📄 Request body size: \(request.httpBody?.count ?? 0) bytes")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            logger.info("📥 Response received - Data size: \(data.count) bytes")
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("📊 HTTP Response Status: \(httpResponse.statusCode)")
                logger.info("📋 Response Headers: \(httpResponse.allHeaderFields)")
                
                // Log response body for debugging
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.info("📄 Response Body: \(responseBody)")
                } else {
                    logger.warning("⚠️ Could not decode response body as UTF-8")
                }
                
                if httpResponse.statusCode == 200 {
                    logger.info("✅ Push token registered successfully with AWS backend")
                    pushToken = token
                    notificationError = nil
                } else {
                    let statusCode = httpResponse.statusCode
                    logger.error("❌ HTTP error \(statusCode) registering push token")
                    
                    // Try to extract error message from response
                    var errorMessage = "HTTP error \(statusCode)"
                    if let _ = String(data: data, encoding: .utf8),
                       let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = errorData["message"] as? String ?? errorData["error"] as? String {
                        errorMessage = "\(errorMessage): \(message)"
                    }
                    
                    throw PushNotificationError.registrationFailed(errorMessage)
                }
            } else {
                logger.error("❌ No HTTP response received")
                throw PushNotificationError.registrationFailed("No HTTP response")
            }
            
        } catch {
            logger.error("❌ Failed to register push token: \(error)")
            logger.error("🔍 Error details - Type: \(type(of: error)), LocalizedDescription: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                logger.error("🌐 URLError details - Code: \(urlError.code.rawValue), Description: \(urlError.localizedDescription)")
            }
            notificationError = error.localizedDescription
        }
    }
}

// MARK: - Private Implementation
extension PushNotificationService {
    
    /// Request push notification authorization
    private func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            isAuthorized = granted
            
            if granted {
                logger.info("✅ Push notification authorization granted")
            } else {
                logger.warning("⚠️ Push notification authorization denied")
                notificationError = "Push notifications not authorized"
            }
            
        } catch {
            logger.error("❌ Failed to request push authorization: \(error)")
            isAuthorized = false
            notificationError = error.localizedDescription
        }
    }
    
    /// Register for remote notifications
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
            logger.info("📱 Registered for remote notifications")
        }
    }
    
    /// Create notification for catalog update
    private func createNotificationForCatalogUpdate(
        eventId: String,
        merchantId: String,
        updatedAt: String
    ) async {
        let notification = WebhookNotification(
            title: "Catalog Updated",
            message: "Your Square catalog has been updated",
            type: .success,
            eventType: "catalog.version.updated",
            timestamp: Date()
        )
        
        // Add notification to WebhookNotificationService so it appears in UI
        await MainActor.run {
            webhookNotificationService.addWebhookNotification(
                title: notification.title,
                message: notification.message,
                type: notification.type,
                eventType: notification.eventType
            )
        }
        
        logger.info("📝 Catalog update notification: \(notification.title) - \(notification.message)")
        logger.info("🔔 Added catalog update notification to UI")
    }
    
    /// Trigger image cache refresh
    private func triggerImageCacheRefresh() async {
        NotificationCenter.default.post(
            name: .forceImageRefresh,
            object: nil,
            userInfo: [
                "reason": "catalog_updated_via_push_notification",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        )
        
        logger.info("🖼️ Triggered image cache refresh via push notification")
    }
    
    /// Trigger catalog sync to get latest changes from Square
    private func triggerCatalogSync(eventId: String, merchantId: String) async {
        logger.info("🚀 Starting catalog sync for webhook event \(eventId)")
        
        do {
            // Get database manager to count items before sync using existing getItemCount method
            let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
            let itemCountBefore = try await databaseManager.getItemCount()
            
            // Get the sync coordinator from the factory
            let syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
            
            // Perform incremental sync to get latest catalog changes
            await syncCoordinator.performIncrementalSync()
            
            // Count items after sync to see what changed
            let itemCountAfter = try await databaseManager.getItemCount()
            let itemsUpdated = abs(itemCountAfter - itemCountBefore)
            
            logger.info("✅ Catalog sync completed successfully for webhook event \(eventId) - \(itemsUpdated) items updated")
            
            // Create user-visible notification about sync results
            if itemsUpdated > 0 {
                await createUserNotificationForWebhookSync(itemsUpdated: itemsUpdated, eventId: eventId)
            }
            
            // Post notification to update UI with detailed sync results
            NotificationCenter.default.post(
                name: .catalogSyncCompleted,
                object: nil,
                userInfo: [
                    "reason": "catalog_updated_via_push_notification",
                    "eventId": eventId,
                    "merchantId": merchantId,
                    "itemsUpdated": itemsUpdated,
                    "itemCountBefore": itemCountBefore,
                    "itemCountAfter": itemCountAfter,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            )
            
        } catch {
            logger.error("❌ Catalog sync failed for webhook event \(eventId): \(error)")
            
            // Post notification about sync failure
            NotificationCenter.default.post(
                name: NSNotification.Name("catalogSyncFailed"),
                object: nil,
                userInfo: [
                    "error": error.localizedDescription,
                    "eventId": eventId,
                    "merchantId": merchantId
                ]
            )
        }
    }
    
    /// Creates a user-visible notification about webhook sync results
    private func createUserNotificationForWebhookSync(itemsUpdated: Int, eventId: String) async {
        // Check user preferences before creating notifications
        let notificationSettings = NotificationSettingsService.shared
        
        guard notificationSettings.isEnabled(for: .webhookSync) else {
            logger.info("⏭️ Webhook sync notifications disabled by user")
            return
        }
        
        let title = "Catalog Updated"
        let message: String
        
        if itemsUpdated == 1 {
            message = "1 item was updated from Square webhook"
        } else {
            message = "\(itemsUpdated) items were updated from Square webhook"
        }
        
        // Add to WebhookNotificationService so it appears in the webhook notifications view
        await MainActor.run {
            webhookNotificationService.addWebhookNotification(
                title: title,
                message: message,
                type: .success,
                eventType: "catalog.version.updated"
            )
        }
        
        logger.info("📱 Added webhook sync notification to UI: \(message)")
    }
    
    /// Get merchant ID from authentication
    private func getMerchantId() async -> String? {
        let tokenService = TokenService()
        do {
            let tokenData = try await tokenService.getCurrentTokenData()
            return tokenData.merchantId
        } catch {
            logger.error("Failed to get merchant ID: \(error)")
            return nil
        }
    }
}

// MARK: - Push Notification Delegate
extension PushNotificationService: UNUserNotificationCenterDelegate {
    
    /// Handle notification when app is in foreground
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            logger.info("📱 Received notification while app in foreground")
            await handleNotification(notification.request.content.userInfo)
        }
        
        // Show banner and sound
        completionHandler([.banner, .sound])
    }
    
    /// Handle notification tap
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            logger.info("👆 User tapped notification")
            await handleNotification(response.notification.request.content.userInfo)
        }
        
        completionHandler()
    }
}

// MARK: - Error Types
enum PushNotificationError: LocalizedError {
    case authorizationDenied
    case registrationFailed(String)
    case tokenSendFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Push notification authorization was denied"
        case .registrationFailed(let reason):
            return "Failed to register for push notifications: \(reason)"
        case .tokenSendFailed(let reason):
            return "Failed to send push token to backend: \(reason)"
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    /// Posted when a catalog update push notification is received
    static let catalogUpdatedViaPush = Notification.Name("catalogUpdatedViaPush")
}