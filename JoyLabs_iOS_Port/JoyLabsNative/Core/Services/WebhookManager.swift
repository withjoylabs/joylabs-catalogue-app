import Foundation
import OSLog
import Combine

/// Webhook Manager - Coordinates webhook processing with existing services
/// Integrates WebhookService with UnifiedImageService and image cache invalidation
@MainActor
class WebhookManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = WebhookManager()
    
    // MARK: - Dependencies
    private let webhookService: WebhookService
    private let webhookValidator: WebhookSignatureValidator
    private let simpleImageService: SimpleImageService
    // SimpleImageView uses native URLCache - no custom service needed
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookManager")
    
    // MARK: - Published Properties
    @Published var isActive = false
    @Published var webhookStats = WebhookStats()
    @Published var lastProcessedWebhook: ProcessedWebhook?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let retryManager = WebhookRetryManager()
    
    // MARK: - Initialization
    private init() {
        self.webhookService = WebhookService.shared
        self.webhookValidator = WebhookSignatureValidator()
        self.simpleImageService = SimpleImageService.shared
        
        setupWebhookObservers()
        logger.info("[WebhookManager] WebhookManager initialized and ready")
    }
    
    // MARK: - Public Interface
    
    /// Start webhook processing
    func startWebhookProcessing() {
        isActive = true
        logger.info("[WebhookManager] Webhook processing started")
    }
    
    /// Stop webhook processing
    func stopWebhookProcessing() {
        isActive = false
        logger.info("⏹️ Webhook processing stopped")
    }
    
    /// Process incoming webhook from AWS endpoint
    /// This is the main entry point called by your AWS Lambda/API Gateway
    func processIncomingWebhook(
        payload: Data,
        signature: String?,
        headers: [String: String] = [:]
    ) async -> WebhookProcessingResult {
        guard isActive else {
            logger.warning("⚠️ Webhook processing is disabled")
            return WebhookProcessingResult(
                success: false,
                error: "Webhook processing is currently disabled",
                processingTime: 0
            )
        }
        
        let startTime = Date()
        logger.info("📥 Processing incoming webhook")
        
        do {
            // Step 1: Validate webhook signature and structure
            if let signature = signature {
                let validationResult = await webhookValidator.validateWebhookComprehensive(
                    payload: payload,
                    signature: signature,
                    timestamp: headers["X-Square-Timestamp"]
                )
                
                guard validationResult.isValid else {
                    await recordFailedWebhook(
                        reason: "Validation failed: \(validationResult.details)",
                        error: validationResult.error
                    )
                    return WebhookProcessingResult(
                        success: false,
                        error: validationResult.details,
                        processingTime: Date().timeIntervalSince(startTime)
                    )
                }
            }
            
            // Step 2: Process webhook through WebhookService
            try await webhookService.processWebhookPayload(payload, signature: signature, headers: headers)
            
            // Step 3: Update stats and record success
            let processingTime = Date().timeIntervalSince(startTime)
            await recordSuccessfulWebhook(payload: payload, processingTime: processingTime)
            
            logger.info("✅ Webhook processed successfully in \(String(format: "%.2f", processingTime))s")
            
            return WebhookProcessingResult(
                success: true,
                error: nil,
                processingTime: processingTime
            )
            
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            await recordFailedWebhook(reason: "Processing error: \(error.localizedDescription)", error: error)
            
            logger.error("❌ Webhook processing failed: \(error)")
            
            // Attempt retry if appropriate
            if shouldRetryWebhook(error: error) {
                await scheduleWebhookRetry(payload: payload, signature: signature, headers: headers)
            }
            
            return WebhookProcessingResult(
                success: false,
                error: error.localizedDescription,
                processingTime: processingTime
            )
        }
    }
    
    /// Get webhook processing statistics
    func getWebhookStats() -> WebhookStats {
        return webhookStats
    }
    
    /// Reset webhook statistics
    func resetStats() {
        webhookStats = WebhookStats()
        logger.info("📊 Webhook statistics reset")
    }
    
    /// Simulate webhook for testing
    func simulateWebhookForTesting(eventType: String, objectId: String, objectType: String) async {
        logger.info("🧪 Simulating webhook for testing: \(eventType)")
        
        guard let webhookEventType = WebhookEventType(rawValue: eventType) else {
            logger.error("❌ Invalid webhook event type: \(eventType)")
            return
        }
        
        do {
            try await webhookService.simulateWebhookEvent(
                eventType: webhookEventType,
                objectId: objectId,
                objectType: objectType
            )
            logger.info("✅ Webhook simulation completed")
        } catch {
            logger.error("❌ Webhook simulation failed: \(error)")
        }
    }
}

// MARK: - Private Implementation
extension WebhookManager {
    
    /// Setup observers for webhook-related notifications
    private func setupWebhookObservers() {
        logger.info("[WebhookManager] Webhook observers configured")
        // Observe image refresh notifications to update stats
        NotificationCenter.default.publisher(for: .forceImageRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleImageRefreshNotification(notification)
            }
            .store(in: &cancellables)
        
        // Observe image update notifications
        NotificationCenter.default.publisher(for: .imageUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleImageUpdateNotification(notification)
            }
            .store(in: &cancellables)
        
    }
    
    /// Handle image refresh notifications triggered by webhooks
    private func handleImageRefreshNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo["reason"] as? String else {
            return
        }
        
        if reason.contains("webhook") {
            webhookStats.imageRefreshesTriggered += 1
            logger.debug("📸 Webhook triggered image refresh: \(reason)")
        }
    }
    
    /// Handle image update notifications triggered by webhooks
    private func handleImageUpdateNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let action = userInfo["action"] as? String else {
            return
        }
        
        if action.contains("webhook") {
            webhookStats.imageUpdatesProcessed += 1
            logger.debug("🖼️ Webhook triggered image update: \(action)")
        }
    }
    
    /// Record successful webhook processing
    private func recordSuccessfulWebhook(payload: Data, processingTime: TimeInterval) async {
        webhookStats.totalWebhooksReceived += 1
        webhookStats.successfulWebhooks += 1
        webhookStats.averageProcessingTime = calculateAverageProcessingTime(newTime: processingTime)
        webhookStats.lastSuccessfulWebhook = Date()
        
        // Parse webhook to get event type for stats
        if let eventType = extractEventType(from: payload) {
            webhookStats.eventTypeCounts[eventType, default: 0] += 1
        }
        
        // Record in recent history
        let processedWebhook = ProcessedWebhook(
            timestamp: Date(),
            eventType: extractEventType(from: payload) ?? "unknown",
            success: true,
            processingTime: processingTime,
            error: nil
        )
        
        lastProcessedWebhook = processedWebhook
        addToRecentHistory(processedWebhook)
    }
    
    /// Record failed webhook processing
    private func recordFailedWebhook(reason: String, error: Error?) async {
        webhookStats.totalWebhooksReceived += 1
        webhookStats.failedWebhooks += 1
        webhookStats.lastFailure = Date()
        webhookStats.lastFailureReason = reason
        
        // Record in recent history
        let processedWebhook = ProcessedWebhook(
            timestamp: Date(),
            eventType: "unknown",
            success: false,
            processingTime: 0,
            error: reason
        )
        
        lastProcessedWebhook = processedWebhook
        addToRecentHistory(processedWebhook)
    }
    
    /// Extract event type from webhook payload for statistics
    private func extractEventType(from payload: Data) -> String? {
        do {
            let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            return json?["event_type"] as? String
        } catch {
            return nil
        }
    }
    
    /// Calculate rolling average processing time
    private func calculateAverageProcessingTime(newTime: TimeInterval) -> TimeInterval {
        let currentAverage = webhookStats.averageProcessingTime
        let totalSuccessful = Double(webhookStats.successfulWebhooks)
        
        if totalSuccessful <= 1 {
            return newTime
        } else {
            return ((currentAverage * (totalSuccessful - 1)) + newTime) / totalSuccessful
        }
    }
    
    /// Add webhook to recent history (keep last 20)
    private func addToRecentHistory(_ webhook: ProcessedWebhook) {
        webhookStats.recentWebhooks.append(webhook)
        if webhookStats.recentWebhooks.count > 20 {
            webhookStats.recentWebhooks.removeFirst()
        }
    }
    
    /// Determine if webhook should be retried based on error type
    private func shouldRetryWebhook(error: Error) -> Bool {
        // Don't retry validation errors or malformed payloads
        if error is WebhookValidationError {
            return false
        }
        
        // Don't retry parsing errors
        if error.localizedDescription.contains("parse") || error.localizedDescription.contains("JSON") {
            return false
        }
        
        // Retry network errors, temporary failures, etc.
        return true
    }
    
    /// Schedule webhook retry with exponential backoff
    private func scheduleWebhookRetry(payload: Data, signature: String?, headers: [String: String]) async {
        await retryManager.scheduleRetry(
            payload: payload,
            signature: signature,
            headers: headers
        ) { [weak self] retryPayload, retrySignature, retryHeaders in
            await self?.processIncomingWebhook(
                payload: retryPayload,
                signature: retrySignature,
                headers: retryHeaders
            )
        }
    }
}

// MARK: - Supporting Types

/// Webhook processing statistics
struct WebhookStats {
    var totalWebhooksReceived: Int = 0
    var successfulWebhooks: Int = 0
    var failedWebhooks: Int = 0
    var averageProcessingTime: TimeInterval = 0
    var imageRefreshesTriggered: Int = 0
    var imageUpdatesProcessed: Int = 0
    var lastSuccessfulWebhook: Date?
    var lastFailure: Date?
    var lastFailureReason: String?
    var eventTypeCounts: [String: Int] = [:]
    var recentWebhooks: [ProcessedWebhook] = []
    
    var successRate: Double {
        guard totalWebhooksReceived > 0 else { return 0 }
        return Double(successfulWebhooks) / Double(totalWebhooksReceived)
    }
}

/// Individual processed webhook record
struct ProcessedWebhook {
    let timestamp: Date
    let eventType: String
    let success: Bool
    let processingTime: TimeInterval
    let error: String?
}

/// Webhook processing result
struct WebhookProcessingResult {
    let success: Bool
    let error: String?
    let processingTime: TimeInterval
}

/// Webhook retry manager with exponential backoff
class WebhookRetryManager {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookRetryManager")
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0
    
    func scheduleRetry(
        payload: Data,
        signature: String?,
        headers: [String: String],
        retryHandler: @escaping (Data, String?, [String: String]) async -> WebhookProcessingResult?
    ) async {
        for attempt in 1...maxRetries {
            let delay = baseDelay * pow(2.0, Double(attempt - 1)) // Exponential backoff
            
            logger.info("🔄 Scheduling webhook retry \(attempt)/\(self.maxRetries) in \(delay)s")
            
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            let result = await retryHandler(payload, signature, headers)
            if result?.success == true {
                logger.info("✅ Webhook retry \(attempt) successful")
                return
            }
        }
        
        logger.error("❌ All webhook retry attempts failed")
    }
}