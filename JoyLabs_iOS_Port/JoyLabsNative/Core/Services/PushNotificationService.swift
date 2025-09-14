import Foundation
import UserNotifications
import UIKit
import OSLog
import Combine

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
    
    // MARK: - Deduplication Properties
    private var processedEventIds = Set<String>()
    private var recentLocalOperations: [String: Date] = [:]
    private let eventIdCleanupInterval: TimeInterval = 3600 // 1 hour
    private let localOperationWindow: TimeInterval = 30 // 30 seconds
    private var lastEventCleanup = Date()
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "PushNotificationService")
    private let baseURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api"
    
    // MARK: - Initialization
    private override init() {
        super.init()
        logger.info("[PushNotification] PushNotificationService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Setup push notifications and request permissions
    func setupPushNotifications() async {
        // Prevent duplicate setup calls
        guard !isSetupComplete else {
            logger.debug("[PushNotification] Push notifications already set up, skipping duplicate call")
            return
        }
        
        logger.info("[PushNotification] Setting up push notifications...")
        
        // Request authorization
        await requestAuthorization()
        
        // Always register for remote notifications (silent notifications work even without permission)
        await registerForRemoteNotifications()
        
        if !isAuthorized {
            logger.info("[PushNotification] Silent notifications will still work for background catalog sync even without permission")
        }
        
        isSetupComplete = true
        logger.info("[PushNotification] Push notification setup completed")
    }
    
    /// Handle received push notification (both silent and visible)
    func handleNotification(_ userInfo: [AnyHashable: Any]) async {
        lastNotificationReceived = Date()
        logger.info("[PushNotification] Webhook notification received at \(Date())")
        
        // Check if this is a silent notification (content-available: 1)
        let isSilentNotification = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1
        
        logger.info("[PushNotification] Processing \(isSilentNotification ? "SILENT" : "VISIBLE") notification")
        logger.debug("[PushNotification] Full notification payload: \(userInfo)")
        
        // Extract webhook data from notification (matches Square webhook format)
        guard let data = userInfo["data"] as? [String: Any],
              let type = data["type"] as? String,
              type == "catalog_updated" else {
            let receivedType = (userInfo["data"] as? [String: Any])?["type"] as? String ?? "unknown"
            logger.warning("[PushNotification] Received non-catalog push notification. Expected 'catalog_updated', got type: \(receivedType)")
            
            // Log the full notification for debugging
            logger.debug("[PushNotification] Non-catalog notification payload: \(userInfo)")
            return
        }
        
        logger.info("[PushNotification] Confirmed catalog_updated webhook notification")
        
        let eventId = data["eventId"] as? String ?? "unknown"
        let merchantId = data["merchantId"] as? String ?? "unknown"
        let updatedAt = data["updatedAt"] as? String ?? ""
        
        // DEDUPLICATION: Check if we've already processed this event
        if await isDuplicateEvent(eventId: eventId) {
            logger.info("🔄 Skipping duplicate webhook event: \(eventId)")
            return
        }
        
        // DEDUPLICATION: Check if this is for a recent local operation
        if await isRecentLocalOperation(updatedAt: updatedAt) {
            logger.info("🔄 Skipping webhook for recent local operation (Event: \(eventId))")
            await markEventAsProcessed(eventId: eventId) // Still mark as processed to prevent retries
            return
        }
        
        logger.info("[PushNotification] Webhook \(eventId) - processing catalog update")
        
        // Mark event as being processed to prevent duplicates
        await markEventAsProcessed(eventId: eventId)
        
        // Trigger image cache refresh
        await triggerImageCacheRefresh()
        
        // Trigger catalog sync to get latest changes from Square (this will create the in-app notification with sync results)
        await triggerCatalogSync(eventId: eventId, merchantId: merchantId, isSilent: isSilentNotification)
        
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
            logger.debug("[PushNotification] Request headers: \(request.allHTTPHeaderFields ?? [:])")
            logger.debug("[PushNotification] Request body size: \(request.httpBody?.count ?? 0) bytes")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            logger.debug("[PushNotification] Response received - Data size: \(data.count) bytes")
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("[PushNotification] HTTP Response Status: \(httpResponse.statusCode)")
                logger.debug("[PushNotification] Response Headers: \(httpResponse.allHeaderFields)")
                
                // Log response body for debugging
                if let responseBody = String(data: data, encoding: .utf8) {
                    logger.debug("[PushNotification] Response Body: \(responseBody)")
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
                logger.info("[PushNotification] Push notification authorization granted - real-time catalog sync enabled")
            } else {
                logger.warning("⚠️ Push notification authorization denied - app will still sync when opened")
                notificationError = "Push notifications not authorized - catalog will sync when app is opened"
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
            logger.info("[PushNotification] Registered for remote notifications")
        }
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
        
        logger.debug("[PushNotification] Triggered image cache refresh")
    }
    
    /// Trigger catalog sync to get latest changes from Square
    private func triggerCatalogSync(eventId: String, merchantId: String, isSilent: Bool) async {
        logger.info("[PushNotification] Starting catalog sync for webhook \(eventId)")
        
        do {
            // Get database manager to count items before sync using existing getItemCount method
            let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
            // RACE CONDITION FIX: Ensure database connection is established before accessing
            try databaseManager.connect()
            let itemCountBefore = try await databaseManager.getItemCount()
            logger.debug("[PushNotification] Database item count before sync: \(itemCountBefore)")
            
            // Get the sync coordinator from the factory
            let syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
            logger.debug("[PushNotification] Sync coordinator obtained, current state: \(String(describing: syncCoordinator.syncState))")
            
            // Check if sync coordinator has previous results
            if let previousResult = syncCoordinator.lastSyncResult {
                logger.debug("[PushNotification] Previous sync result exists: \(previousResult.summary)")
            } else {
                logger.debug("[PushNotification] No previous sync result found")
            }
            
            // Perform incremental sync to get latest catalog changes
            logger.info("[PushNotification] Starting incremental sync...")
            await syncCoordinator.performIncrementalSync()
            logger.info("[PushNotification] performIncrementalSync() completed")
            
            // Wait for sync to actually complete using Combine publisher
            logger.debug("[PushNotification] Waiting for sync state to change from .syncing...")
            await withCheckedContinuation { continuation in
                var cancellable: AnyCancellable?
                cancellable = syncCoordinator.$syncState
                    .filter { $0 != .syncing }
                    .first()
                    .sink { state in
                        self.logger.debug("[PushNotification] Sync state changed to: \(String(describing: state))")
                        cancellable?.cancel()
                        continuation.resume()
                    }
            }
            logger.info("[PushNotification] Sync state completion detected")
            
            // Count items after sync to see what changed
            // Database connection should already be established, but ensure it's connected
            try databaseManager.connect()
            let itemCountAfter = try await databaseManager.getItemCount()
            let itemsUpdated = Int(abs(Int32(itemCountAfter - itemCountBefore)))
            logger.debug("[PushNotification] Database item count after sync: \(itemCountAfter)")
            logger.info("[PushNotification] Item count difference: \(itemsUpdated) items")
            
            // Create in-app notification about sync results - use sync coordinator data instead of item count
            let syncResult = syncCoordinator.lastSyncResult
            if let result = syncResult {
                logger.info("[PushNotification] Sync result available: \(result.summary)")
                logger.debug("[PushNotification] Sync result details - Objects: \(result.totalProcessed), Items: \(result.itemsProcessed), Duration: \(result.duration)s")
            } else {
                logger.warning("[PushNotification] No sync result available from coordinator!")
            }
            
            logger.info("[PushNotification] Creating webhook notification...")
            await createInAppNotificationForWebhookSync(syncResult: syncResult, eventId: eventId, isSilent: isSilent)
            
        } catch {
            logger.error("❌ Catalog sync failed for webhook event \(eventId): \(error)")
            
            // Handle authentication failures specifically
            if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
                logger.error("[PushNotification] Authentication failed during webhook sync - clearing tokens and notifying user")
                
                // Clear invalid tokens
                let tokenService = SquareAPIServiceFactory.createTokenService()
                try? await tokenService.clearAuthData()
                
                // Update auth state
                let apiService = SquareAPIServiceFactory.createService()
                apiService.setAuthenticated(false)
                
                // Notify user
                await MainActor.run {
                    WebhookNotificationService.shared.addAuthenticationFailureNotification()
                    ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")
                }
            } else {
                // For non-auth errors, still create a notification
                await MainActor.run {
                    WebhookNotificationService.shared.addWebhookNotification(
                        title: "Sync Failed",
                        message: "Failed to sync catalog: \(error.localizedDescription)",
                        type: .error,
                        eventType: "webhook.sync.failed"
                    )
                }
            }
            
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
    
    /// Creates an in-app notification about webhook sync results using actual sync data
    private func createInAppNotificationForWebhookSync(syncResult: SyncResult?, eventId: String, isSilent: Bool) async {
        logger.info("[PushNotification] Creating webhook notification for event \(eventId) (silent: \(isSilent))")
        
        let title: String
        let message: String
        
        if let result = syncResult {
            let objectsProcessed = result.totalProcessed
            let itemsProcessed = result.itemsProcessed
            logger.info("[PushNotification] Using sync result - Objects: \(objectsProcessed), Items: \(itemsProcessed)")
            
            if objectsProcessed == 0 {
                title = "Catalog Sync"
                message = "No changes found - catalog is up to date (webhook)"
                logger.debug("[PushNotification] No changes notification created")
            } else if objectsProcessed == 1 {
                title = "Catalog Updated"
                if itemsProcessed == 1 {
                    message = "1 item updated from Square (webhook)"
                } else {
                    message = "1 catalog object updated from Square (webhook)"
                }
                logger.debug("[PushNotification] Single object update notification created")
            } else {
                title = "Catalog Updated"
                if itemsProcessed > 0 && itemsProcessed != objectsProcessed {
                    message = "\(itemsProcessed) items updated, \(objectsProcessed) total objects (webhook)"
                } else {
                    message = "\(objectsProcessed) catalog objects updated from Square (webhook)"
                }
                logger.debug("[PushNotification] Multiple objects update notification created")
            }
        } else {
            // Fallback if sync result is not available
            title = "Catalog Sync"
            message = "Sync completed but result data unavailable (webhook)"
            logger.warning("[PushNotification] Using fallback notification - no sync result available")
        }
        
        logger.info("[PushNotification] Final notification: '\(title)' - '\(message)'")
        
        // Always add to in-app notification center (regardless of silent/visible)
        logger.debug("[PushNotification] Adding notification to WebhookNotificationService...")
        await MainActor.run {
            WebhookNotificationService.shared.addWebhookNotification(
                title: title,
                message: message,
                type: .success,
                eventType: "webhook.catalog.sync"
            )
            self.logger.info("[PushNotification] Notification added to WebhookNotificationService")
        }
        
        logger.info("[PushNotification] Webhook sync notification complete: \(message)")
    }
    
    /// Get merchant ID from authentication
    private func getMerchantId() async -> String? {
        let tokenService = SquareAPIServiceFactory.createTokenService()
        do {
            let tokenData = try await tokenService.getCurrentTokenData()
            return tokenData.merchantId
        } catch {
            logger.error("Failed to get merchant ID: \(error)")
            return nil
        }
    }
    
    // MARK: - Deduplication Methods
    
    /// Check if this event has already been processed
    private func isDuplicateEvent(eventId: String) async -> Bool {
        // Clean up old events periodically
        await cleanupOldEvents()
        
        return processedEventIds.contains(eventId)
    }
    
    /// Mark an event as processed to prevent duplicate processing
    private func markEventAsProcessed(eventId: String) async {
        processedEventIds.insert(eventId)
        logger.trace("[PushNotification] Marked event as processed: \(eventId)")
    }
    
    /// Check if this webhook corresponds to a recent local operation
    private func isRecentLocalOperation(updatedAt: String) async -> Bool {
        guard !updatedAt.isEmpty else { return false }
        
        // Parse the Square webhook timestamp (ISO 8601)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let webhookTime = formatter.date(from: updatedAt) else {
            logger.warning("⚠️ Failed to parse webhook timestamp: \(updatedAt)")
            return false
        }
        
        // Clean up old local operations
        cleanupOldLocalOperations()
        
        // Check if any recent local operation falls within the time window
        for (_, localOpTime) in recentLocalOperations {
            let timeDifference = abs(webhookTime.timeIntervalSince(localOpTime))
            if timeDifference <= localOperationWindow {
                logger.debug("🔍 Found recent local operation within \(timeDifference)s of webhook")
                return true
            }
        }
        
        return false
    }
    
    /// Record a local operation to prevent processing webhooks for our own changes
    func recordLocalOperation(itemId: String) {
        let operationTime = Date()
        recentLocalOperations[itemId] = operationTime
        logger.debug("📝 Recorded local operation for item: \(itemId) at \(operationTime)")
        
        // Clean up old operations to prevent memory growth
        cleanupOldLocalOperations()
    }
    
    /// Clean up old processed event IDs to prevent memory growth
    private func cleanupOldEvents() async {
        let now = Date()
        
        // Only clean up if it's been more than an hour since last cleanup
        guard now.timeIntervalSince(lastEventCleanup) > eventIdCleanupInterval else { return }
        
        // For now, we'll keep a simple approach and clear all after cleanup interval
        // In production, you might want to implement a more sophisticated LRU cache
        let eventCount = processedEventIds.count
        if eventCount > 1000 { // Arbitrary limit to prevent excessive memory usage
            processedEventIds.removeAll()
            logger.info("🧹 Cleared \(eventCount) processed event IDs to prevent memory growth")
        }
        
        lastEventCleanup = now
    }
    
    /// Clean up old local operations to prevent memory growth
    private func cleanupOldLocalOperations() {
        let cutoffTime = Date().addingTimeInterval(-localOperationWindow * 2) // Keep records for 2x the window
        
        let oldCount = recentLocalOperations.count
        recentLocalOperations = recentLocalOperations.filter { $0.value > cutoffTime }
        let cleanedCount = oldCount - recentLocalOperations.count
        
        if cleanedCount > 0 {
            logger.debug("🧹 Cleaned up \(cleanedCount) old local operation records")
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
    
    /// Handle notification tap - just log, don't process again
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            logger.info("👆 User tapped notification - UI interaction only, sync already processed")
            // Don't call handleNotification again - sync was already processed when notification arrived
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