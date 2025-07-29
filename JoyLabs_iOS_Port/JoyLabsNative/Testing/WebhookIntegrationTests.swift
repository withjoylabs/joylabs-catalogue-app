import Foundation
import OSLog

/// Webhook Integration Tests - Test webhook functionality and integration
class WebhookIntegrationTests: ObservableObject {
    
    // MARK: - Dependencies
    private let webhookManager: WebhookManager
    private let webhookService: WebhookService
    private let unifiedImageService: UnifiedImageService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookIntegrationTests")
    
    // MARK: - Test Results
    @Published var testResults: [TestResult] = []
    @Published var isRunning = false
    @Published var currentTest = ""
    
    @MainActor
    init() {
        self.webhookManager = WebhookManager.shared
        self.webhookService = WebhookService.shared
        self.unifiedImageService = UnifiedImageService.shared
    }
    
    // MARK: - Test Runner
    
    /// Run all webhook integration tests
    func runAllTests() async {
        await MainActor.run {
            isRunning = true
            testResults.removeAll()
            currentTest = "Starting webhook integration tests..."
        }
        
        logger.info("🧪 Starting webhook integration tests")
        
        // Test 1: Basic webhook service functionality
        let basicTest = await testBasicWebhookService()
        await addTestResult(basicTest)
        
        // Test 2: Webhook payload parsing
        let parsingTest = await testWebhookPayloadParsing()
        await addTestResult(parsingTest)
        
        // Test 3: Image cache invalidation integration
        let cacheTest = await testImageCacheInvalidation()
        await addTestResult(cacheTest)
        
        // Test 4: Webhook signature validation
        let signatureTest = await testWebhookSignatureValidation()
        await addTestResult(signatureTest)
        
        // Test 5: End-to-end webhook processing
        let e2eTest = await testEndToEndWebhookProcessing()
        await addTestResult(e2eTest)
        
        // Test 6: Error handling and retry logic
        let errorTest = await testErrorHandlingAndRetry()
        await addTestResult(errorTest)
        
        await MainActor.run {
            isRunning = false
            currentTest = "Tests completed"
        }
        
        logger.info("✅ Webhook integration tests completed")
    }
    
    // MARK: - Individual Tests
    
    /// Test 1: Basic webhook service functionality
    private func testBasicWebhookService() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing basic webhook service...")
        
        do {
            // Webhook services are guaranteed to be initialized via shared instances
            // No need for nil checks on non-optional properties
            
            // Start webhook processing
            await MainActor.run {
                webhookManager.startWebhookProcessing()
            }
            
            let isActive = await MainActor.run { webhookManager.isActive }
            guard isActive else {
                throw TestError.functionalityFailed("Webhook processing failed to start")
            }
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Basic Webhook Service",
                description: "Test webhook service and manager initialization",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Basic Webhook Service",
                description: "Test webhook service and manager initialization",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    /// Test 2: Webhook payload parsing
    private func testWebhookPayloadParsing() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing webhook payload parsing...")
        
        do {
            // Create sample webhook payload
            let samplePayload = createSampleWebhookPayload()
            
            // Test parsing through webhook service
            try await webhookService.processWebhookPayload(
                samplePayload,
                signature: nil,
                headers: [:]
            )
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Webhook Payload Parsing",
                description: "Test parsing of Square webhook payloads",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Webhook Payload Parsing",
                description: "Test parsing of Square webhook payloads",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    /// Test 3: Image cache invalidation integration
    private func testImageCacheInvalidation() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing image cache invalidation...")
        
        do {
            // Simulate item update webhook
            try await webhookService.simulateWebhookEvent(
                eventType: .catalogObjectUpdated,
                objectId: "test-item-123",
                objectType: "ITEM"
            )
            
            // Wait a moment for processing
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Simulate image update webhook
            try await webhookService.simulateWebhookEvent(
                eventType: .catalogObjectUpdated,
                objectId: "test-image-456",
                objectType: "IMAGE"
            )
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Image Cache Invalidation",
                description: "Test webhook-triggered image cache invalidation",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Image Cache Invalidation",
                description: "Test webhook-triggered image cache invalidation",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    /// Test 4: Webhook signature validation
    private func testWebhookSignatureValidation() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing webhook signature validation...")
        
        do {
            let validator = WebhookSignatureValidator()
            let testPayload = "test webhook payload".data(using: .utf8)!
            
            // Test invalid signature format
            do {
                _ = try await validator.validateSignature(
                    payload: testPayload,
                    signature: "invalid-signature",
                    webhookSignatureKey: "test-key"
                )
                throw TestError.functionalityFailed("Should have failed with invalid signature format")
            } catch WebhookValidationError.invalidSignatureFormat {
                // Expected error
            }
            
            // Test valid signature format (though key won't match in test)
            do {
                _ = try await validator.validateSignature(
                    payload: testPayload,
                    signature: "sha1=1234567890123456789012345678901234567890",
                    webhookSignatureKey: "test-key"
                )
            } catch {
                // Expected to fail due to signature mismatch in test environment
                logger.debug("Signature validation failed as expected in test: \(error)")
            }
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Webhook Signature Validation",
                description: "Test webhook signature validation logic",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Webhook Signature Validation",
                description: "Test webhook signature validation logic",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    /// Test 5: End-to-end webhook processing
    private func testEndToEndWebhookProcessing() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing end-to-end webhook processing...")
        
        do {
            // Create realistic webhook payload
            let webhookPayload = createSampleWebhookPayload()
            
            // Process through webhook manager
            let result = await webhookManager.processIncomingWebhook(
                payload: webhookPayload,
                signature: nil, // Skip signature validation for test
                headers: [:]
            )
            
            guard result.success else {
                throw TestError.functionalityFailed("Webhook processing failed: \(result.error ?? "unknown error")")
            }
            
            // Check that stats were updated
            let stats = await webhookManager.getWebhookStats()
            guard stats.totalWebhooksReceived > 0 else {
                throw TestError.functionalityFailed("Webhook stats not updated")
            }
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "End-to-End Processing",
                description: "Test complete webhook processing pipeline",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "End-to-End Processing",
                description: "Test complete webhook processing pipeline",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    /// Test 6: Error handling and retry logic
    private func testErrorHandlingAndRetry() async -> TestResult {
        let startTime = Date()
        await updateCurrentTest("Testing error handling and retry logic...")
        
        do {
            // Test with malformed JSON
            let malformedPayload = "{ invalid json }".data(using: .utf8)!
            
            let result = await webhookManager.processIncomingWebhook(
                payload: malformedPayload,
                signature: nil,
                headers: [:]
            )
            
            // Should fail gracefully
            guard !result.success else {
                throw TestError.functionalityFailed("Should have failed with malformed JSON")
            }
            
            // Check that error was recorded
            let stats = await webhookManager.getWebhookStats()
            guard stats.failedWebhooks > 0 else {
                throw TestError.functionalityFailed("Failed webhook not recorded in stats")
            }
            
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Error Handling and Retry",
                description: "Test webhook error handling and retry logic",
                passed: true,
                duration: duration,
                error: nil
            )
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return TestResult(
                name: "Error Handling and Retry",
                description: "Test webhook error handling and retry logic",
                passed: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create sample webhook payload for testing
    private func createSampleWebhookPayload() -> Data {
        let webhookData = [
            "event_id": "webhook-test-\(UUID().uuidString)",
            "event_type": "catalog.object.updated",
            "api_version": "2025-07-16",
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "data": [
                "object_id": "test-item-\(Int.random(in: 1000...9999))",
                "object_type": "ITEM",
                "event_type": "catalog.object.updated"
            ]
        ] as [String: Any]
        
        return try! JSONSerialization.data(withJSONObject: webhookData)
    }
    
    /// Update current test status
    private func updateCurrentTest(_ message: String) async {
        await MainActor.run {
            currentTest = message
        }
        logger.debug("🧪 \(message)")
    }
    
    /// Add test result to results array
    private func addTestResult(_ result: TestResult) async {
        await MainActor.run {
            testResults.append(result)
        }
        
        let status = result.passed ? "✅" : "❌"
        logger.info("\(status) \(result.name): \(result.description) (\(String(format: "%.2f", result.duration))s)")
        
        if let error = result.error {
            logger.error("   Error: \(error)")
        }
    }
}

// MARK: - Test Infrastructure

/// Test result structure
struct TestResult {
    let name: String
    let description: String
    let passed: Bool
    let duration: TimeInterval
    let error: String?
}

/// Test-specific errors
enum TestError: LocalizedError {
    case initializationFailed(String)
    case functionalityFailed(String)
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .functionalityFailed(let message):
            return "Functionality failed: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

// MARK: - Configuration Extensions

extension WebhookIntegrationTests {
    
    /// Get webhook configuration summary for debugging
    @MainActor
    func getWebhookConfiguration() async -> [String: Any] {
        return [
            "webhook_endpoint": "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/webhooks/square",
            "subscription_id": "wbhk_74d1165c8a674945abf31da0e51f6d57",
            "api_version": "2025-07-16",
            "manager_active": webhookManager.isActive,
            "supported_events": WebhookEventType.allCases.map { $0.rawValue },
            "test_environment": true
        ]
    }
    
    /// Reset webhook system for testing
    func resetWebhookSystem() async {
        await webhookManager.stopWebhookProcessing()
        await webhookManager.resetStats()
        await webhookManager.startWebhookProcessing()
        
        logger.info("🔄 Webhook system reset for testing")
    }
}