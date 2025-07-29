import Foundation
import OSLog
import Combine

/// Direct Webhook Service - Processes webhooks directly without AWS
/// Uses webhook.site or similar service to receive webhooks and process them locally
@MainActor
class DirectWebhookService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = DirectWebhookService()
    
    // MARK: - Configuration
    // Option 1: Use webhook.site (free, temporary URLs)
    // Option 2: Use ngrok (requires installation)
    // Option 3: Use a simple webhook relay service
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DirectWebhookService")
    
    // MARK: - Dependencies
    private let webhookService = WebhookService.shared
    private let webhookNotificationService = WebhookNotificationService.shared
    
    // MARK: - Published Properties
    @Published var isActive = false
    @Published var webhookURL: String?
    @Published var lastWebhookReceived: Date?
    
    // MARK: - Private Properties
    private var pollingTimer: Timer?
    private var webhookSiteToken: String?
    
    private init() {
        logger.info("🚀 DirectWebhookService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Set up webhook URL and start processing
    func setupWebhookProcessing() async {
        logger.info("🔧 Setting up direct webhook processing...")
        
        // For demo purposes, we'll simulate webhook events
        // In production, you'd use one of these options:
        
        // Option 1: Use webhook.site
        await setupWebhookSite()
        
        // Option 2: Use ngrok (requires ngrok installation)
        // await setupNgrok()
        
        // Option 3: Manual webhook simulation for testing
        setupManualTesting()
        
        isActive = true
        logger.info("✅ Direct webhook processing active")
    }
    
    /// Process webhook directly (called by webhook relay)
    func processDirectWebhook(payload: Data, signature: String?, headers: [String: String] = [:]) async {
        logger.info("📥 Processing direct webhook")
        
        do {
            // Use existing webhook service to process
            try await webhookService.processWebhookPayload(payload, signature: signature, headers: headers)
            
            lastWebhookReceived = Date()
            
            // Create user notification
            await createWebhookNotification(from: payload)
            
            logger.info("✅ Direct webhook processed successfully")
            
        } catch {
            logger.error("❌ Direct webhook processing failed: \(error)")
        }
    }
    
    /// Simulate webhook for testing (removes need for external services)
    func simulateSquareWebhook(eventType: String, objectType: String, objectId: String? = nil) async {
        logger.info("🧪 Simulating Square webhook: \(eventType)")
        
        let testObjectId = objectId ?? "test-\(objectType.lowercased())-\(Int.random(in: 1000...9999))"
        
        let webhookPayload: [String: Any] = [
            "event_id": UUID().uuidString,
            "event_type": eventType,
            "api_version": "2025-07-16",
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "object_id": testObjectId,
                "object_type": objectType,
                "event_type": eventType
            ]
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: webhookPayload) else {
            logger.error("❌ Failed to create webhook payload")
            return
        }
        
        await processDirectWebhook(payload: payloadData, signature: nil)
    }
}

// MARK: - Private Implementation
extension DirectWebhookService {
    
    /// Set up webhook.site for receiving webhooks (free option)
    private func setupWebhookSite() async {
        // webhook.site provides free webhook URLs that we can poll
        // This is perfect for development and testing
        
        do {
            // Create a webhook.site endpoint
            let url = URL(string: "https://webhook.site/token")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let uuid = json["uuid"] as? String {
                
                webhookSiteToken = uuid
                webhookURL = "https://webhook.site/\(uuid)"
                
                logger.info("✅ Webhook.site URL created: \(self.webhookURL!)")
                logger.info("🔗 Update your Square webhook subscription to: \(self.webhookURL!)")
                
                // Start polling webhook.site for incoming webhooks
                startWebhookSitePolling()
            }
            
        } catch {
            logger.error("❌ Failed to setup webhook.site: \(error)")
            // Fall back to manual testing
            setupManualTesting()
        }
    }
    
    /// Start polling webhook.site for incoming webhooks
    private func startWebhookSitePolling() {
        guard let token = webhookSiteToken else { return }
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollWebhookSite(token: token)
            }
        }
    }
    
    /// Poll webhook.site for new webhooks
    private func pollWebhookSite(token: String) async {
        do {
            let url = URL(string: "https://webhook.site/token/\(token)/requests")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let requests = json["data"] as? [[String: Any]] {
                
                // Process new webhook requests
                for request in requests {
                    if let content = request["content"] as? String,
                       let contentData = content.data(using: .utf8) {
                        
                        // Check if this is a Square webhook
                        if content.contains("catalog.") {
                            logger.info("📥 Received Square webhook from webhook.site")
                            await processDirectWebhook(payload: contentData, signature: nil)
                        }
                    }
                }
            }
            
        } catch {
            logger.debug("Webhook.site polling error: \(error)")
        }
    }
    
    /// Set up manual testing (fallback option)
    private func setupManualTesting() {
        webhookURL = "Manual Testing Mode"
        logger.info("🧪 Manual testing mode enabled - use simulator buttons to test webhooks")
        
        // Start a timer that simulates occasional webhook events for demo
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Simulate random webhook events for demo
                let eventTypes = ["catalog.object.updated", "catalog.version.updated"]
                let objectTypes = ["ITEM", "IMAGE", "CATEGORY"]
                
                let randomEvent = eventTypes.randomElement()!
                let randomObject = objectTypes.randomElement()!
                
                await self?.simulateSquareWebhook(
                    eventType: randomEvent,
                    objectType: randomObject
                )
            }
        }
    }
    
    /// Create user notification from webhook payload
    private func createWebhookNotification(from payload: Data) async {
        do {
            let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            let eventType = json?["event_type"] as? String ?? "unknown"
            let data = json?["data"] as? [String: Any]
            let objectType = data?["object_type"] as? String ?? "unknown"
            let objectId = data?["object_id"] as? String ?? "unknown"
            
            let title: String
            let message: String
            let type: WebhookNotificationType
            
            switch eventType {
            case "catalog.version.updated":
                title = "Catalog Updated"
                message = "Your Square catalog has been synchronized"
                type = .success
                
            case "catalog.object.created":
                title = "New Item Created"
                message = "Created \(objectType.lowercased()): \(objectId)"
                type = .info
                
            case "catalog.object.updated":
                title = "Item Updated"
                message = "Updated \(objectType.lowercased()): \(objectId)"
                type = .success
                
            case "catalog.object.deleted":
                title = "Item Deleted"
                message = "Deleted \(objectType.lowercased()): \(objectId)"
                type = .warning
                
            default:
                title = "Webhook Event"
                message = "Received \(eventType)"
                type = .info
            }
            
            let notification = WebhookNotification(
                title: title,
                message: message,
                type: type,
                eventType: eventType,
                timestamp: Date()
            )
            
            webhookNotificationService.addPolledNotification(notification)
            
        } catch {
            logger.error("❌ Failed to create notification from webhook: \(error)")
        }
    }
    
    /// Stop webhook processing
    func stopWebhookProcessing() {
        isActive = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        logger.info("⏹️ Direct webhook processing stopped")
    }
}

// MARK: - Webhook URL Instructions
extension DirectWebhookService {
    
    /// Get instructions for updating Square webhook subscription
    func getSquareWebhookInstructions() -> String {
        guard let url = webhookURL else {
            return "Webhook URL not yet generated. Please set up webhook processing first."
        }
        
        return """
        📋 Square Webhook Setup Instructions:
        
        1. Go to Square Developer Dashboard
        2. Navigate to your application's Webhooks section
        3. Update webhook subscription: wbhk_74d1165c8a674945abf31da0e51f6d57
        4. Change URL from:
           https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/webhooks/square
           
           To: \(url)
        
        5. Save the changes
        6. Test with a catalog update in Square Dashboard
        
        ✅ This will eliminate AWS usage and process webhooks directly in your iOS app!
        """
    }
}