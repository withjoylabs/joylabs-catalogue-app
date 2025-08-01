import Foundation
import OSLog
import Combine

/// Webhook Service - Handles Square webhook events for real-time catalog synchronization
/// Integrates with existing UnifiedImageService and image cache invalidation
@MainActor
class WebhookService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = WebhookService()
    
    // MARK: - Dependencies
    // SimpleImageView uses native URLCache - no custom service needed
    private let simpleImageService: SimpleImageService
    private let databaseManager: SQLiteSwiftCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookService")
    
    // MARK: - Published Properties
    @Published var isProcessingWebhook = false
    @Published var lastWebhookProcessed: Date?
    @Published var webhookProcessingErrors: [WebhookError] = []
    
    // MARK: - Configuration
    private let webhookEndpoint = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/webhooks/square"
    private let subscriptionId = "wbhk_74d1165c8a674945abf31da0e51f6d57"
    private let expectedApiVersion = "2025-07-16"
    
    // MARK: - Initialization
    private init() {
        self.simpleImageService = SimpleImageService.shared
        self.databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        
        logger.info("[Webhook] WebhookService initialized")
        logger.info("[Webhook] Webhook endpoint: \(self.webhookEndpoint)")
        logger.info("[Webhook] Subscription ID: \(self.subscriptionId)")
    }
    
    // MARK: - Public Interface
    
    /// Process incoming webhook payload from AWS endpoint
    func processWebhookPayload(_ payload: Data, signature: String?, headers: [String: String]) async throws {
        logger.info("🔄 Processing webhook payload")
        
        isProcessingWebhook = true
        defer { isProcessingWebhook = false }
        
        do {
            // Step 1: Validate webhook signature (if provided)
            if let signature = signature {
                try validateWebhookSignature(payload: payload, signature: signature)
            } else {
                logger.warning("⚠️ No webhook signature provided - proceeding without validation")
            }
            
            // Step 2: Parse webhook payload
            let webhookEvent = try parseWebhookPayload(payload)
            
            // Step 3: Validate API version compatibility
            try validateApiVersion(webhookEvent.apiVersion)
            
            // Step 4: Process the webhook event
            try await processWebhookEvent(webhookEvent)
            
            // Step 5: Update processing status
            lastWebhookProcessed = Date()
            logger.info("✅ Webhook processed successfully")
            
        } catch {
            logger.error("❌ Webhook processing failed: \(error)")
            await recordWebhookError(error)
            throw error
        }
    }
    
    /// Simulate webhook processing for testing
    func simulateWebhookEvent(eventType: WebhookEventType, objectId: String, objectType: String) async throws {
        logger.info("🧪 Simulating webhook event: \(String(describing: eventType)) for \(objectType) \(objectId)")
        
        let simulatedEvent = WebhookEvent(
            eventId: UUID().uuidString,
            eventType: eventType,
            apiVersion: expectedApiVersion,
            createdAt: Date(),
            data: WebhookEventData(
                objectId: objectId,
                objectType: objectType,
                eventType: eventType.rawValue
            )
        )
        
        try await processWebhookEvent(simulatedEvent)
    }
}

// MARK: - Private Implementation
extension WebhookService {
    
    /// Validate webhook signature using Square's validation method
    private func validateWebhookSignature(payload: Data, signature: String) throws {
        // TODO: Implement Square webhook signature validation
        // This would typically involve:
        // 1. Get webhook signature key from AWS Secrets Manager
        // 2. Compute HMAC-SHA1 of payload using the key
        // 3. Compare with provided signature
        
        logger.debug("🔐 Webhook signature validation (TODO: implement)")
        
        // For now, we'll validate the signature format
        guard signature.hasPrefix("sha1=") else {
            throw WebhookError.invalidSignature("Signature must start with 'sha1='")
        }
        
        // Extract the hash portion
        let hashString = String(signature.dropFirst(5))
        guard hashString.count == 40 else { // SHA1 produces 40 character hex string
            throw WebhookError.invalidSignature("Invalid signature hash length")
        }
    }
    
    /// Parse webhook payload into structured event
    private func parseWebhookPayload(_ payload: Data) throws -> WebhookEvent {
        logger.debug("📝 Parsing webhook payload")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let webhookEvent = try decoder.decode(WebhookEvent.self, from: payload)
            logger.debug("✅ Parsed webhook event: \(String(describing: webhookEvent.eventType)) for \(webhookEvent.data.objectType)")
            return webhookEvent
        } catch {
            logger.error("❌ Failed to parse webhook payload: \(error)")
            throw WebhookError.invalidPayload("Failed to parse webhook JSON: \(error.localizedDescription)")
        }
    }
    
    /// Validate API version compatibility
    private func validateApiVersion(_ apiVersion: String?) throws {
        guard let apiVersion = apiVersion else {
            logger.warning("⚠️ No API version in webhook payload")
            return
        }
        
        guard apiVersion == expectedApiVersion else {
            logger.warning("⚠️ API version mismatch: webhook=\(apiVersion), expected=\(self.expectedApiVersion)")
            // Don't throw error for version mismatch, just log warning
            return
        }
        
        logger.debug("✅ API version validated: \(apiVersion)")
    }
    
    /// Process the webhook event based on type
    private func processWebhookEvent(_ event: WebhookEvent) async throws {
        logger.info("🔄 Processing \(String(describing: event.eventType)) event for \(event.data.objectType) \(event.data.objectId)")
        
        switch event.eventType {
        case .catalogVersionUpdated:
            try await handleCatalogVersionUpdated(event)
        case .catalogObjectCreated:
            try await handleCatalogObjectCreated(event)
        case .catalogObjectUpdated:
            try await handleCatalogObjectUpdated(event)
        case .catalogObjectDeleted:
            try await handleCatalogObjectDeleted(event)
        }
    }
    
    /// Handle catalog.version.updated events
    private func handleCatalogVersionUpdated(_ event: WebhookEvent) async throws {
        logger.info("🔄 Handling catalog version updated event")
        
        // For version updates, we should invalidate all caches and trigger incremental sync
        // This is a broad event that indicates changes occurred
        
        // Step 1: Clear image cache for all items to force refresh
        // Native URLCache handles cleanup automatically
        
        // Step 2: Post global notification for UI refresh
        NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
            "reason": "catalog_version_updated",
            "eventId": event.eventId
        ])
        
        logger.info("✅ Catalog version updated event processed")
    }
    
    /// Handle catalog.object.created events
    private func handleCatalogObjectCreated(_ event: WebhookEvent) async throws {
        logger.info("🔄 Handling catalog object created: \(event.data.objectType) \(event.data.objectId)")
        
        // For new objects, we don't need to invalidate images since they're new
        // But we should trigger a database refresh if it's an item
        
        if event.data.objectType == "ITEM" {
            // Post notification for potential UI updates
            NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil, userInfo: [
                "reason": "item_created",
                "itemId": event.data.objectId,
                "eventId": event.eventId
            ])
        }
        
        logger.info("✅ Catalog object created event processed")
    }
    
    /// Handle catalog.object.updated events
    private func handleCatalogObjectUpdated(_ event: WebhookEvent) async throws {
        logger.info("🔄 Handling catalog object updated: \(event.data.objectType) \(event.data.objectId)")
        
        switch event.data.objectType {
        case "ITEM":
            try await handleItemUpdated(event.data.objectId)
        case "CATEGORY":
            try await handleCategoryUpdated(event.data.objectId)
        case "IMAGE":
            try await handleImageUpdated(event.data.objectId)
        default:
            logger.debug("📝 Ignoring update for object type: \(event.data.objectType)")
        }
        
        logger.info("✅ Catalog object updated event processed")
    }
    
    /// Handle catalog.object.deleted events
    private func handleCatalogObjectDeleted(_ event: WebhookEvent) async throws {
        logger.info("🔄 Handling catalog object deleted: \(event.data.objectType) \(event.data.objectId)")
        
        switch event.data.objectType {
        case "ITEM":
            try await handleItemDeleted(event.data.objectId)
        case "IMAGE":
            try await handleImageDeleted(event.data.objectId)
        default:
            logger.debug("📝 Ignoring deletion for object type: \(event.data.objectType)")
        }
        
        logger.info("✅ Catalog object deleted event processed")
    }
    
    // MARK: - Object-Specific Handlers
    
    /// Handle item updates with image cache invalidation
    private func handleItemUpdated(_ itemId: String) async throws {
        logger.info("🔄 Invalidating images for updated item: \(itemId)")
        
        // Invalidate cached images for this item
        // Native URLCache handles cache invalidation automatically
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
            "itemId": itemId,
            "action": "item_updated_via_webhook"
        ])
    }
    
    /// Handle category updates
    private func handleCategoryUpdated(_ categoryId: String) async throws {
        logger.info("🔄 Handling category update: \(categoryId)")
        
        // Invalidate cached images for this category
        // Native URLCache handles cache invalidation automatically
        
        // Post notification for potential UI updates
        NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil, userInfo: [
            "reason": "category_updated",
            "categoryId": categoryId
        ])
    }
    
    /// Handle image updates with cache invalidation
    private func handleImageUpdated(_ imageId: String) async throws {
        logger.info("🔄 Invalidating cache for updated image: \(imageId)")
        
        // Remove from memory cache
        // Native URLCache handles memory management automatically
        
        // Post global image refresh notification
        NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
            "imageId": imageId,
            "action": "image_updated_via_webhook"
        ])
    }
    
    /// Handle item deletions
    private func handleItemDeleted(_ itemId: String) async throws {
        logger.info("🔄 Cleaning up deleted item: \(itemId)")
        
        // Clean up cached images for deleted item
        // Native URLCache handles cache invalidation automatically
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil, userInfo: [
            "reason": "item_deleted",
            "itemId": itemId
        ])
    }
    
    /// Handle image deletions
    private func handleImageDeleted(_ imageId: String) async throws {
        logger.info("🔄 Cleaning up deleted image: \(imageId)")
        
        // Remove from memory cache
        // Native URLCache handles memory management automatically
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
            "imageId": imageId,
            "action": "image_deleted_via_webhook"
        ])
    }
    
    /// Record webhook processing error
    private func recordWebhookError(_ error: Error) async {
        let webhookError = WebhookError.processingFailed(error.localizedDescription)
        webhookProcessingErrors.append(webhookError)
        
        // Keep only the last 10 errors to prevent memory issues
        if webhookProcessingErrors.count > 10 {
            webhookProcessingErrors.removeFirst()
        }
    }
}

// MARK: - Webhook Models

/// Square webhook event structure
struct WebhookEvent: Codable {
    let eventId: String
    let eventType: WebhookEventType
    let apiVersion: String?
    let createdAt: Date
    let data: WebhookEventData
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case apiVersion = "api_version"
        case createdAt = "created_at"
        case data
    }
}

/// Webhook event data payload
struct WebhookEventData: Codable {
    let objectId: String
    let objectType: String
    let eventType: String
    
    enum CodingKeys: String, CodingKey {
        case objectId = "object_id"
        case objectType = "object_type"
        case eventType = "event_type"
    }
}

/// Supported webhook event types
enum WebhookEventType: String, Codable, CaseIterable {
    case catalogVersionUpdated = "catalog.version.updated"
    case catalogObjectCreated = "catalog.object.created"
    case catalogObjectUpdated = "catalog.object.updated"
    case catalogObjectDeleted = "catalog.object.deleted"
}

/// Webhook processing errors
enum WebhookError: LocalizedError {
    case invalidSignature(String)
    case invalidPayload(String)
    case unsupportedEventType(String)
    case processingFailed(String)
    case apiVersionMismatch(String, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidSignature(let message):
            return "Invalid webhook signature: \(message)"
        case .invalidPayload(let message):
            return "Invalid webhook payload: \(message)"
        case .unsupportedEventType(let eventType):
            return "Unsupported webhook event type: \(eventType)"
        case .processingFailed(let message):
            return "Webhook processing failed: \(message)"
        case .apiVersionMismatch(let received, let expected):
            return "API version mismatch: received \(received), expected \(expected)"
        }
    }
}

// MARK: - Notification Extensions

