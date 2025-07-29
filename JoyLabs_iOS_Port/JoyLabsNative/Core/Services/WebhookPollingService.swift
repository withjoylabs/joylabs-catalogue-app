import Foundation
import OSLog
import Combine

/// Webhook Polling Service - Polls AWS backend for webhook events to show user feedback
/// This bridges the gap between AWS Lambda webhook processing and iOS user notifications
@MainActor
class WebhookPollingService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = WebhookPollingService()
    
    // MARK: - Configuration  
    // AWS backend integration for multi-tenant webhook polling
    private let baseURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api"
    private let pollingInterval: TimeInterval = 30 // Poll every 30 seconds
    
    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookPollingService")
    private let webhookNotificationService = WebhookNotificationService.shared
    
    // MARK: - Published Properties
    @Published var isPolling = false
    @Published var lastPollTime: Date?
    @Published var pollError: String?
    
    // MARK: - Private Properties
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastProcessedEventId: String?
    
    // MARK: - Initialization
    private init() {
        logger.info("🔄 WebhookPollingService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start polling for webhook events from AWS backend
    func startPolling() {
        guard !isPolling else {
            logger.debug("🔄 Polling already active")
            return
        }
        
        isPolling = true
        logger.info("🚀 Starting webhook polling every \(pollingInterval)s")
        
        // Start timer for regular polling
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForWebhookEvents()
            }
        }
        
        // Do initial poll
        Task {
            await pollForWebhookEvents()
        }
    }
    
    /// Stop polling for webhook events
    func stopPolling() {
        guard isPolling else { return }
        
        isPolling = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        logger.info("⏹️ Webhook polling stopped")
    }
    
    /// Manually trigger a poll for testing
    func manualPoll() async {
        logger.info("👆 Manual webhook poll triggered")
        await pollForWebhookEvents()
    }
}

// MARK: - Private Implementation
extension WebhookPollingService {
    
    /// Poll AWS backend for recent webhook events
    private func pollForWebhookEvents() async {
        lastPollTime = Date()
        
        do {
            logger.debug("📡 Polling for webhook events...")
            
            // Get merchant ID from authentication (you'll need to implement this)
            guard let merchantId = await getMerchantId() else {
                logger.warning("⚠️ No merchant ID available for webhook polling")
                pollError = "No merchant authentication"
                return
            }
            
            // Create request to get recent webhook events
            var components = URLComponents(string: "\(baseURL)/webhooks/events")!
            var queryItems = [URLQueryItem(name: "merchantId", value: merchantId)]
            
            // Add last processed event ID as query parameter if available
            if let lastEventId = lastProcessedEventId {
                queryItems.append(URLQueryItem(name: "after", value: lastEventId))
            }
            
            components.queryItems = queryItems
            
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add merchant ID header as backup
            request.setValue(merchantId, forHTTPHeaderField: "X-Merchant-ID")
            
            // Make request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PollingError.invalidResponse("Not an HTTP response")
            }
            
            guard httpResponse.statusCode == 200 else {
                throw PollingError.httpError(httpResponse.statusCode)
            }
            
            // Parse response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let webhookEvents = try decoder.decode(WebhookEventsResponse.self, from: data)
            
            // Process new events
            if !webhookEvents.events.isEmpty {
                logger.info("📥 Received \(webhookEvents.events.count) new webhook events")
                await processNewWebhookEvents(webhookEvents.events)
            } else {
                logger.debug("📭 No new webhook events")
            }
            
            pollError = nil
            
        } catch {
            logger.error("❌ Polling failed: \(error)")
            pollError = error.localizedDescription
        }
    }
    
    /// Process new webhook events received from AWS
    private func processNewWebhookEvents(_ events: [WebhookEventInfo]) async {
        for event in events {
            logger.info("🔄 Processing webhook event: \(event.eventType) for \(event.objectType)")
            
            // Update last processed event ID
            lastProcessedEventId = event.eventId
            
            // Create notification based on event type
            await createNotificationForWebhookEvent(event)
            
            // Trigger appropriate cache invalidation if needed
            await triggerCacheInvalidation(for: event)
        }
        
        // Update webhook manager stats to reflect polling activity
        await updateWebhookStats(eventCount: events.count)
    }
    
    /// Create user notification for webhook event
    private func createNotificationForWebhookEvent(_ event: WebhookEventInfo) async {
        let title: String
        let message: String
        let type: WebhookNotificationType
        
        switch event.eventType {
        case "catalog.version.updated":
            title = "Catalog Updated"
            message = "Your catalog has been updated from Square"
            type = .success
            
        case "catalog.object.created":
            title = "Item Created"
            message = "New \(event.objectType.lowercased()) created: \(event.objectId)"
            type = .info
            
        case "catalog.object.updated":
            title = "Item Updated"
            message = "\(event.objectType.capitalized) updated: \(event.objectId)"
            type = .success
            
        case "catalog.object.deleted":
            title = "Item Deleted"
            message = "\(event.objectType.capitalized) deleted: \(event.objectId)"
            type = .warning
            
        default:
            title = "Webhook Event"
            message = "Received \(event.eventType) for \(event.objectType)"
            type = .info
        }
        
        // Add notification to the notification service
        let notification = WebhookNotification(
            title: title,
            message: message,
            type: type,
            eventType: event.eventType,
            timestamp: event.timestamp
        )
        
        // This will trigger UI updates in the notification bell
        await MainActor.run {
            webhookNotificationService.addPolledNotification(notification)
        }
    }
    
    /// Trigger cache invalidation based on webhook event
    private func triggerCacheInvalidation(for event: WebhookEventInfo) async {
        switch event.eventType {
        case "catalog.version.updated":
            // Global cache refresh
            NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
                "reason": "catalog_version_updated_via_webhook",
                "eventId": event.eventId
            ])
            
        case "catalog.object.updated" where event.objectType == "ITEM":
            // Item-specific cache refresh
            NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
                "itemId": event.objectId,
                "action": "item_updated_via_webhook_polling"
            ])
            
        case "catalog.object.updated" where event.objectType == "IMAGE":
            // Image-specific cache refresh
            NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
                "imageId": event.objectId,
                "action": "image_updated_via_webhook_polling"
            ])
            
        default:
            break
        }
    }
    
    /// Update webhook manager stats to reflect polling activity
    private func updateWebhookStats(eventCount: Int) async {
        let webhookManager = WebhookManager.shared
        
        // Simulate webhook processing stats for the polled events
        for _ in 0..<eventCount {
            // This will update the webhook manager's stats
            await webhookManager.recordPolledWebhookEvent()
        }
    }
    
    /// Get merchant ID from Square OAuth configuration
    private func getMerchantId() async -> String? {
        // Get merchant ID from Square OAuth service
        // This should match how you handle merchant authentication in your app
        return await SquareOAuthService.shared.getCurrentMerchantId()
    }
}

// MARK: - API Models

/// Response from AWS backend webhook events endpoint
struct WebhookEventsResponse: Codable {
    let events: [WebhookEventInfo]
    let hasMore: Bool
}

/// Individual webhook event from AWS backend
struct WebhookEventInfo: Codable {
    let eventId: String
    let eventType: String
    let objectId: String
    let objectType: String
    let timestamp: Date
    let processed: Bool
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case objectId = "object_id"
        case objectType = "object_type"
        case timestamp
        case processed
    }
}

// MARK: - Error Types

enum PollingError: LocalizedError {
    case invalidResponse(String)
    case httpError(Int)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

// MARK: - Extensions

extension WebhookNotificationService {
    /// Add notification from polling service
    func addPolledNotification(_ notification: WebhookNotification) {
        // Insert at the beginning of the notifications array
        webhookNotifications.insert(notification, at: 0)
        
        if !notification.isRead {
            unreadCount += 1
        }
        
        // Keep only the most recent notifications
        if webhookNotifications.count > 50 {
            webhookNotifications.removeLast()
        }
        
        logger.debug("🔔 Added polled webhook notification: \(notification.title)")
    }
}

extension WebhookManager {
    /// Record webhook event discovered through polling
    func recordPolledWebhookEvent() async {
        webhookStats.totalWebhooksReceived += 1
        webhookStats.successfulWebhooks += 1
        webhookStats.lastSuccessfulWebhook = Date()
    }
}