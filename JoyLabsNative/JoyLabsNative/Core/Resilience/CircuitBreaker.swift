import Foundation
import OSLog

/// Circuit breaker implementation with three states: Closed, Open, Half-Open
/// Prevents cascading failures by temporarily blocking operations when failure rate is high
actor CircuitBreaker {
    
    // MARK: - Properties
    
    private let operationId: String
    private let config: CircuitBreakerConfig
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CircuitBreaker")
    
    // MARK: - State Management
    
    private var state: CircuitBreakerState = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?
    private var halfOpenCallCount: Int = 0
    
    // MARK: - Initialization
    
    init(operationId: String, config: CircuitBreakerConfig) {
        self.operationId = operationId
        self.config = config
        logger.debug("CircuitBreaker initialized for operation: \(operationId)")
    }
    
    // MARK: - Public Interface
    
    /// Check if operation can be executed
    func canExecute() async -> Bool {
        await updateStateIfNeeded()
        
        switch state {
        case .closed:
            return true
        case .open:
            return false
        case .halfOpen:
            return halfOpenCallCount < config.halfOpenMaxCalls
        }
    }
    
    /// Record successful operation
    func recordSuccess() async {
        logger.debug("Recording success for operation: \(self.operationId)")
        
        switch state {
        case .closed:
            // Reset failure count on success
            failureCount = 0
            
        case .halfOpen:
            successCount += 1
            halfOpenCallCount += 1
            
            // If we've had enough successful calls, close the circuit
            if successCount >= config.halfOpenMaxCalls {
                await transitionTo(.closed)
                logger.info("Circuit breaker closed after successful recovery: \(self.operationId)")
            }
            
        case .open:
            // This shouldn't happen, but handle gracefully
            logger.warning("Received success while circuit breaker is open: \(self.operationId)")
        }
    }
    
    /// Record failed operation
    func recordFailure() async {
        logger.debug("Recording failure for operation: \(self.operationId)")
        
        switch state {
        case .closed:
            failureCount += 1
            lastFailureTime = Date()
            
            // Check if we should open the circuit
            if failureCount >= config.failureThreshold {
                await transitionTo(.open)
                logger.warning("Circuit breaker opened due to failures: \(self.operationId)")
            }
            
        case .halfOpen:
            halfOpenCallCount += 1
            
            // Any failure in half-open state should open the circuit
            await transitionTo(.open)
            logger.warning("Circuit breaker reopened after failure in half-open state: \(self.operationId)")
            
        case .open:
            // Update last failure time
            lastFailureTime = Date()
        }
    }
    
    /// Reset circuit breaker to closed state
    func reset() async {
        logger.info("Resetting circuit breaker: \(self.operationId)")
        await transitionTo(.closed)
    }
    
    /// Get current state information
    func getCurrentState() async -> CircuitBreakerState {
        await updateStateIfNeeded()
        return state
    }
    
    /// Get detailed circuit breaker metrics
    func getMetrics() async -> CircuitBreakerMetrics {
        await updateStateIfNeeded()
        
        return CircuitBreakerMetrics(
            operationId: operationId,
            state: state,
            failureCount: failureCount,
            successCount: successCount,
            lastFailureTime: lastFailureTime,
            halfOpenCallCount: halfOpenCallCount,
            config: config
        )
    }
    
    // MARK: - Private Implementation
    
    private func updateStateIfNeeded() async {
        // Only check for state transitions from open to half-open
        guard state == .open else { return }
        
        guard let lastFailure = lastFailureTime else { return }
        
        let timeSinceLastFailure = Date().timeIntervalSince(lastFailure)
        
        if timeSinceLastFailure >= config.recoveryTimeout {
            await transitionTo(.halfOpen)
            logger.info("Circuit breaker transitioned to half-open: \(self.operationId)")
        }
    }
    
    private func transitionTo(_ newState: CircuitBreakerState) async {
        let oldState = state
        state = newState
        
        // Reset counters based on new state
        switch newState {
        case .closed:
            failureCount = 0
            successCount = 0
            halfOpenCallCount = 0
            lastFailureTime = nil
            
        case .open:
            successCount = 0
            halfOpenCallCount = 0
            lastFailureTime = Date()
            
        case .halfOpen:
            successCount = 0
            halfOpenCallCount = 0
        }
        
        logger.info("Circuit breaker state transition: \(oldState.rawValue) → \(newState.rawValue) for operation: \(self.operationId)")
    }
}

// MARK: - Circuit Breaker State

enum CircuitBreakerState: String, CaseIterable {
    case closed = "closed"
    case open = "open"
    case halfOpen = "half-open"
    
    var description: String {
        switch self {
        case .closed:
            return "Closed - Normal operation"
        case .open:
            return "Open - Blocking requests"
        case .halfOpen:
            return "Half-Open - Testing recovery"
        }
    }
}

// MARK: - Circuit Breaker Metrics

struct CircuitBreakerMetrics {
    let operationId: String
    let state: CircuitBreakerState
    let failureCount: Int
    let successCount: Int
    let lastFailureTime: Date?
    let halfOpenCallCount: Int
    let config: CircuitBreakerConfig
    
    var failureRate: Double {
        let totalCalls = failureCount + successCount
        return totalCalls > 0 ? Double(failureCount) / Double(totalCalls) : 0.0
    }
    
    var timeSinceLastFailure: TimeInterval? {
        guard let lastFailure = lastFailureTime else { return nil }
        return Date().timeIntervalSince(lastFailure)
    }
    
    var isHealthy: Bool {
        switch state {
        case .closed:
            return failureRate < 0.1 // Less than 10% failure rate
        case .open:
            return false
        case .halfOpen:
            return successCount > 0 && failureCount == 0
        }
    }
}

// MARK: - Retry Counter

/// Tracks retry statistics for operations
actor RetryCounter {
    
    private let operationId: String
    private let logger = Logger(subsystem: "com.joylabs.native", category: "RetryCounter")
    
    private var totalOperations: Int = 0
    private var totalRetries: Int = 0
    private var successfulRetries: Int = 0
    private var failedRetries: Int = 0
    private var currentOperationRetries: Int = 0
    
    init(operationId: String) {
        self.operationId = operationId
    }
    
    func recordSuccess() async {
        if currentOperationRetries > 0 {
            successfulRetries += 1
            logger.debug("Successful retry for operation: \(self.operationId) (attempt: \(self.currentOperationRetries + 1))")
        }
        
        totalOperations += 1
        currentOperationRetries = 0
    }
    
    func recordFailure() async {
        currentOperationRetries += 1
        totalRetries += 1
        
        logger.debug("Retry \(self.currentOperationRetries) for operation: \(self.operationId)")
    }
    
    func recordFinalFailure() async {
        if currentOperationRetries > 0 {
            failedRetries += 1
        }
        
        totalOperations += 1
        currentOperationRetries = 0
    }
    
    func getStatistics() async -> RetryStatistics {
        return RetryStatistics(
            totalRetries: totalRetries,
            successfulRetries: successfulRetries,
            failedRetries: failedRetries,
            averageRetriesPerOperation: totalOperations > 0 ? Double(totalRetries) / Double(totalOperations) : 0.0
        )
    }
    
    func reset() async {
        totalOperations = 0
        totalRetries = 0
        successfulRetries = 0
        failedRetries = 0
        currentOperationRetries = 0
        
        logger.info("Retry counter reset for operation: \(self.operationId)")
    }
}

// MARK: - Graceful Degradation Manager

/// Manages graceful degradation strategies when services are unavailable
actor GracefulDegradationManager {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "GracefulDegradationManager")
    private var degradationStrategies: [String: DegradationStrategy] = [:]
    
    /// Register a degradation strategy for a service
    func registerStrategy(_ strategy: DegradationStrategy, for serviceId: String) async {
        degradationStrategies[serviceId] = strategy
        logger.info("Registered degradation strategy for service: \(serviceId)")
    }
    
    /// Execute degraded operation
    func executeDegraded<T>(serviceId: String, fallbackValue: T) async -> T {
        guard let strategy = degradationStrategies[serviceId] else {
            logger.warning("No degradation strategy found for service: \(serviceId)")
            return fallbackValue
        }
        
        logger.info("Executing degraded operation for service: \(serviceId)")
        
        switch strategy {
        case .returnCached:
            // Return cached value if available
            return fallbackValue
            
        case .returnDefault:
            // Return default value
            return fallbackValue
            
        case .skipOperation:
            // Skip the operation entirely
            return fallbackValue
            
        case .useAlternativeService:
            // Use alternative service (would need implementation)
            return fallbackValue
        }
    }
}

// MARK: - Degradation Strategy

enum DegradationStrategy {
    case returnCached
    case returnDefault
    case skipOperation
    case useAlternativeService
    
    var description: String {
        switch self {
        case .returnCached:
            return "Return cached data"
        case .returnDefault:
            return "Return default values"
        case .skipOperation:
            return "Skip operation"
        case .useAlternativeService:
            return "Use alternative service"
        }
    }
}
