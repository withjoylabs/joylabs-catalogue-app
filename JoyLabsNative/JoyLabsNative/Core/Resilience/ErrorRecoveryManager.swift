import Foundation
import OSLog

/// Comprehensive error recovery manager with exponential backoff and graceful degradation
/// Implements 2025 industry standards for resilient system design
actor ErrorRecoveryManager {
    
    // MARK: - Configuration
    
    private let config: ErrorRecoveryConfig
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ErrorRecoveryManager")
    
    // MARK: - State Tracking
    
    private var operationStates: [String: OperationState] = [:]
    private var circuitBreakers: [String: CircuitBreaker] = [:]
    private var retryCounters: [String: RetryCounter] = [:]
    
    // MARK: - Initialization
    
    init(config: ErrorRecoveryConfig = ErrorRecoveryConfig.default) {
        self.config = config
        logger.info("ErrorRecoveryManager initialized with config: \(config.description)")
    }
    
    // MARK: - Public Interface
    
    /// Execute operation with comprehensive error recovery
    func executeWithRecovery<T>(
        operationId: String,
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil
    ) async throws -> T {
        logger.debug("Starting operation with recovery: \(operationId)")
        
        // Check circuit breaker
        let circuitBreaker = getOrCreateCircuitBreaker(operationId)
        
        guard await circuitBreaker.canExecute() else {
            logger.warning("Circuit breaker open for operation: \(operationId)")
            
            if let fallback = fallback {
                logger.info("Using fallback for operation: \(operationId)")
                return await fallback()
            } else {
                throw ErrorRecoveryError.circuitBreakerOpen(operationId)
            }
        }
        
        // Get or create retry counter
        let retryCounter = getOrCreateRetryCounter(operationId)
        
        // Execute with retry logic
        return try await executeWithRetry(
            operationId: operationId,
            operation: operation,
            fallback: fallback,
            circuitBreaker: circuitBreaker,
            retryCounter: retryCounter
        )
    }
    
    /// Reset error state for operation
    func resetErrorState(operationId: String) async {
        logger.info("Resetting error state for operation: \(operationId)")
        
        operationStates.removeValue(forKey: operationId)
        retryCounters.removeValue(forKey: operationId)
        
        if let circuitBreaker = circuitBreakers[operationId] {
            await circuitBreaker.reset()
        }
    }
    
    /// Get current error statistics
    func getErrorStatistics() async -> ErrorStatistics {
        let totalOperations = operationStates.count
        let failedOperations = operationStates.values.filter { $0.lastResult == .failure }.count
        let circuitBreakerStates = await getCircuitBreakerStates()
        
        let retryStats = await getRetryStatistics()

        return ErrorStatistics(
            totalOperations: totalOperations,
            failedOperations: failedOperations,
            successRate: totalOperations > 0 ? Double(totalOperations - failedOperations) / Double(totalOperations) : 1.0,
            circuitBreakerStates: circuitBreakerStates,
            retryStatistics: retryStats
        )
    }
    
    // MARK: - Private Implementation
    
    private func executeWithRetry<T>(
        operationId: String,
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)?,
        circuitBreaker: CircuitBreaker,
        retryCounter: RetryCounter
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...config.maxRetryAttempts {
            do {
                logger.debug("Attempt \(attempt) for operation: \(operationId)")
                
                let result = try await operation()
                
                // Success - record and return
                await recordSuccess(operationId: operationId, circuitBreaker: circuitBreaker, retryCounter: retryCounter)
                logger.debug("Operation succeeded on attempt \(attempt): \(operationId)")
                
                return result
                
            } catch {
                lastError = error
                logger.warning("Operation failed on attempt \(attempt): \(operationId) - \(error.localizedDescription)")
                
                // Record failure
                await recordFailure(operationId: operationId, error: error, circuitBreaker: circuitBreaker, retryCounter: retryCounter)
                
                // Check if we should retry
                if attempt < config.maxRetryAttempts && shouldRetry(error: error) {
                    let delay = calculateBackoffDelay(attempt: attempt, baseDelay: config.baseRetryDelay)
                    logger.debug("Retrying operation \(operationId) after \(delay)s delay")
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    break
                }
            }
        }
        
        // All retries failed
        logger.error("All retries failed for operation: \(operationId)")
        
        // Try fallback if available
        if let fallback = fallback {
            logger.info("Using fallback after all retries failed: \(operationId)")
            return await fallback()
        }
        
        // Throw the last error
        throw lastError ?? ErrorRecoveryError.allRetriesFailed(operationId)
    }
    
    private func recordSuccess(
        operationId: String,
        circuitBreaker: CircuitBreaker,
        retryCounter: RetryCounter
    ) async {
        operationStates[operationId] = OperationState(
            operationId: operationId,
            lastResult: .success,
            lastExecutionTime: Date(),
            totalExecutions: (operationStates[operationId]?.totalExecutions ?? 0) + 1
        )
        
        await circuitBreaker.recordSuccess()
        await retryCounter.recordSuccess()
    }
    
    private func recordFailure(
        operationId: String,
        error: Error,
        circuitBreaker: CircuitBreaker,
        retryCounter: RetryCounter
    ) async {
        operationStates[operationId] = OperationState(
            operationId: operationId,
            lastResult: .failure,
            lastError: error,
            lastExecutionTime: Date(),
            totalExecutions: (operationStates[operationId]?.totalExecutions ?? 0) + 1,
            totalFailures: (operationStates[operationId]?.totalFailures ?? 0) + 1
        )
        
        await circuitBreaker.recordFailure()
        await retryCounter.recordFailure()
    }
    
    private func shouldRetry(error: Error) -> Bool {
        // Don't retry certain types of errors
        if let recoveryError = error as? ErrorRecoveryError {
            switch recoveryError {
            case .circuitBreakerOpen, .allRetriesFailed:
                return false
            default:
                return true
            }
        }
        
        // Don't retry validation errors (using qualified name to avoid conflict)
        let errorString = error.localizedDescription
        if errorString.contains("validation") || errorString.contains("invalid") {
            return false
        }
        
        // Don't retry authentication errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return false
            default:
                return true
            }
        }
        
        return true
    }
    
    private func calculateBackoffDelay(attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.1) * exponentialDelay
        let finalDelay = min(exponentialDelay + jitter, config.maxRetryDelay)
        
        return finalDelay
    }
    
    private func getOrCreateCircuitBreaker(_ operationId: String) -> CircuitBreaker {
        if let existing = circuitBreakers[operationId] {
            return existing
        }
        
        let circuitBreaker = CircuitBreaker(
            operationId: operationId,
            config: config.circuitBreakerConfig
        )
        circuitBreakers[operationId] = circuitBreaker
        return circuitBreaker
    }
    
    private func getOrCreateRetryCounter(_ operationId: String) -> RetryCounter {
        if let existing = retryCounters[operationId] {
            return existing
        }
        
        let retryCounter = RetryCounter(operationId: operationId)
        retryCounters[operationId] = retryCounter
        return retryCounter
    }
    
    private func getCircuitBreakerStates() async -> [String: CircuitBreakerState] {
        var states: [String: CircuitBreakerState] = [:]
        
        for (operationId, circuitBreaker) in circuitBreakers {
            states[operationId] = await circuitBreaker.getCurrentState()
        }
        
        return states
    }
    
    private func getRetryStatistics() async -> [String: RetryStatistics] {
        var statistics: [String: RetryStatistics] = [:]

        for (operationId, retryCounter) in retryCounters {
            statistics[operationId] = await retryCounter.getStatistics()
        }

        return statistics
    }
}

// MARK: - Configuration

struct ErrorRecoveryConfig {
    let maxRetryAttempts: Int
    let baseRetryDelay: TimeInterval
    let maxRetryDelay: TimeInterval
    let circuitBreakerConfig: CircuitBreakerConfig
    
    static let `default` = ErrorRecoveryConfig(
        maxRetryAttempts: 3,
        baseRetryDelay: 1.0,
        maxRetryDelay: 30.0,
        circuitBreakerConfig: CircuitBreakerConfig.default
    )
    
    var description: String {
        "maxRetries: \(maxRetryAttempts), baseDelay: \(baseRetryDelay)s, maxDelay: \(maxRetryDelay)s"
    }
}

struct CircuitBreakerConfig {
    let failureThreshold: Int
    let recoveryTimeout: TimeInterval
    let halfOpenMaxCalls: Int
    
    static let `default` = CircuitBreakerConfig(
        failureThreshold: 5,
        recoveryTimeout: 60.0,
        halfOpenMaxCalls: 3
    )
}

// MARK: - Supporting Types

struct OperationState {
    let operationId: String
    let lastResult: OperationResult
    var lastError: Error?
    let lastExecutionTime: Date
    let totalExecutions: Int
    let totalFailures: Int
    
    init(
        operationId: String,
        lastResult: OperationResult,
        lastError: Error? = nil,
        lastExecutionTime: Date,
        totalExecutions: Int,
        totalFailures: Int = 0
    ) {
        self.operationId = operationId
        self.lastResult = lastResult
        self.lastError = lastError
        self.lastExecutionTime = lastExecutionTime
        self.totalExecutions = totalExecutions
        self.totalFailures = totalFailures
    }
}

enum OperationResult {
    case success
    case failure
}

struct ErrorStatistics {
    let totalOperations: Int
    let failedOperations: Int
    let successRate: Double
    let circuitBreakerStates: [String: CircuitBreakerState]
    let retryStatistics: [String: RetryStatistics]
}

struct RetryStatistics {
    let totalRetries: Int
    let successfulRetries: Int
    let failedRetries: Int
    let averageRetriesPerOperation: Double
}

// MARK: - Errors

enum ErrorRecoveryError: LocalizedError {
    case circuitBreakerOpen(String)
    case allRetriesFailed(String)
    case configurationError(String)
    case operationTimeout(String)
    
    var errorDescription: String? {
        switch self {
        case .circuitBreakerOpen(let operationId):
            return "Circuit breaker is open for operation: \(operationId)"
        case .allRetriesFailed(let operationId):
            return "All retry attempts failed for operation: \(operationId)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .operationTimeout(let operationId):
            return "Operation timed out: \(operationId)"
        }
    }
}

// ValidationError removed to avoid conflict with DataValidation.swift
