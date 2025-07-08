import Foundation
import OSLog

/// Comprehensive error recovery manager for Square API operations
/// Provides intelligent error classification, recovery strategies, and graceful degradation
actor SquareErrorRecoveryManager {
    
    // MARK: - Dependencies
    
    private let resilienceService: ResilienceService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareErrorRecoveryManager")
    
    // MARK: - Recovery State
    
    private var recoveryAttempts: [String: Int] = [:]
    private var lastRecoveryTime: [String: Date] = [:]
    private var circuitBreakerStates: [String: CircuitBreakerState] = [:]
    
    // MARK: - Configuration
    
    private let maxRecoveryAttempts = 3
    private let recoveryBackoffBase: TimeInterval = 2.0
    private let circuitBreakerThreshold = 5
    private let circuitBreakerTimeout: TimeInterval = 60.0
    
    // MARK: - Initialization
    
    init(resilienceService: ResilienceService) {
        self.resilienceService = resilienceService
        logger.info("SquareErrorRecoveryManager initialized")
    }
    
    // MARK: - Error Recovery
    
    /// Attempt to recover from a Square API error
    func recoverFromError(_ error: Error, operationId: String) async throws {
        logger.info("Attempting recovery from error: \(error.localizedDescription)")
        
        // Classify the error
        let squareError = classifyError(error)
        
        // Check circuit breaker state
        if await isCircuitBreakerOpen(for: operationId) {
            logger.warning("Circuit breaker open for operation: \(operationId)")
            throw SquareAPIError.circuitBreakerOpen
        }
        
        // Determine recovery strategy
        let strategy = determineRecoveryStrategy(for: squareError, operationId: operationId)
        
        // Execute recovery strategy
        try await executeRecoveryStrategy(strategy, for: operationId, originalError: squareError)
    }
    
    /// Classify an error into a SquareAPIError
    private func classifyError(_ error: Error) -> SquareAPIError {
        // If already a SquareAPIError, return as-is
        if let squareError = error as? SquareAPIError {
            return squareError
        }
        
        // Classify based on error characteristics
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("network") || errorDescription.contains("connection") {
            return .networkUnavailable
        } else if errorDescription.contains("timeout") {
            return .requestTimeout
        } else if errorDescription.contains("unauthorized") || errorDescription.contains("authentication") {
            return .authenticationRequired
        } else if errorDescription.contains("rate limit") {
            return .rateLimitExceeded
        } else if errorDescription.contains("server error") {
            return .serverError(500)
        } else {
            return .internalError(error.localizedDescription)
        }
    }
    
    /// Determine the appropriate recovery strategy
    private func determineRecoveryStrategy(for error: SquareAPIError, operationId: String) -> RecoveryStrategy {
        let attemptCount = recoveryAttempts[operationId] ?? 0
        
        switch error {
        case .networkUnavailable, .requestTimeout:
            return attemptCount < maxRecoveryAttempts ? .retryWithBackoff : .useCachedData
            
        case .rateLimitExceeded, .quotaExceeded:
            return .retryWithExponentialBackoff
            
        case .authenticationRequired, .authenticationFailed, .tokenExpired:
            return .reauthenticate
            
        case .serverError(let code) where code >= 500:
            return attemptCount < maxRecoveryAttempts ? .retryWithBackoff : .useCachedData
            
        case .invalidRequest, .resourceNotFound, .permissionDenied:
            return .skipOperation
            
        case .invalidData, .serializationError, .validationError:
            return .skipOperation
            
        case .serviceUnavailable:
            return .useAlternativeService
            
        case .circuitBreakerOpen:
            return .useCachedData
            
        case .internalError:
            return attemptCount < maxRecoveryAttempts ? .retryWithBackoff : .skipOperation
            
        default:
            return .skipOperation
        }
    }
    
    /// Execute the recovery strategy
    private func executeRecoveryStrategy(_ strategy: RecoveryStrategy, for operationId: String, originalError: SquareAPIError) async throws {
        logger.info("Executing recovery strategy: \(strategy) for operation: \(operationId)")
        
        switch strategy {
        case .retryWithBackoff:
            try await retryWithBackoff(operationId: operationId)
            
        case .retryWithExponentialBackoff:
            try await retryWithExponentialBackoff(operationId: operationId)
            
        case .reauthenticate:
            try await reauthenticate()
            
        case .useCachedData:
            logger.info("Using cached data as recovery strategy")
            // This would be handled by the calling service
            
        case .useAlternativeService:
            logger.info("Using alternative service as recovery strategy")
            // This would be handled by the calling service
            
        case .skipOperation:
            logger.info("Skipping operation as recovery strategy")
            throw originalError
        }
    }
    
    /// Retry with linear backoff
    private func retryWithBackoff(operationId: String) async throws {
        let attemptCount = recoveryAttempts[operationId] ?? 0
        
        guard attemptCount < maxRecoveryAttempts else {
            logger.error("Max recovery attempts reached for operation: \(operationId)")
            await recordCircuitBreakerFailure(for: operationId)
            throw SquareAPIError.internalError("Max recovery attempts exceeded")
        }
        
        let backoffTime = recoveryBackoffBase * Double(attemptCount + 1)
        logger.info("Retrying operation \(operationId) after \(backoffTime)s backoff")
        
        try await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
        
        recoveryAttempts[operationId] = attemptCount + 1
        lastRecoveryTime[operationId] = Date()
    }
    
    /// Retry with exponential backoff
    private func retryWithExponentialBackoff(operationId: String) async throws {
        let attemptCount = recoveryAttempts[operationId] ?? 0
        
        guard attemptCount < maxRecoveryAttempts else {
            logger.error("Max recovery attempts reached for operation: \(operationId)")
            await recordCircuitBreakerFailure(for: operationId)
            throw SquareAPIError.internalError("Max recovery attempts exceeded")
        }
        
        let backoffTime = recoveryBackoffBase * pow(2.0, Double(attemptCount))
        logger.info("Retrying operation \(operationId) after \(backoffTime)s exponential backoff")
        
        try await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
        
        recoveryAttempts[operationId] = attemptCount + 1
        lastRecoveryTime[operationId] = Date()
    }
    
    /// Attempt reauthentication
    private func reauthenticate() async throws {
        logger.info("Attempting reauthentication")
        // This would integrate with the authentication service
        throw SquareAPIError.authenticationFailed("Reauthentication not implemented")
    }
    
    // MARK: - Circuit Breaker Management
    
    /// Check if circuit breaker is open for an operation
    private func isCircuitBreakerOpen(for operationId: String) async -> Bool {
        guard let state = circuitBreakerStates[operationId] else {
            return false
        }
        
        switch state {
        case .open(let timestamp):
            let timeElapsed = Date().timeIntervalSince(timestamp)
            if timeElapsed > circuitBreakerTimeout {
                // Reset to half-open
                circuitBreakerStates[operationId] = .halfOpen
                logger.info("Circuit breaker reset to half-open for operation: \(operationId)")
                return false
            }
            return true
            
        case .halfOpen, .closed:
            return false
        }
    }
    
    /// Record a circuit breaker failure
    private func recordCircuitBreakerFailure(for operationId: String) async {
        let currentState = circuitBreakerStates[operationId] ?? .closed
        
        switch currentState {
        case .closed:
            let failureCount = (recoveryAttempts[operationId] ?? 0) + 1
            if failureCount >= circuitBreakerThreshold {
                circuitBreakerStates[operationId] = .open(Date())
                logger.warning("Circuit breaker opened for operation: \(operationId)")
            }
            
        case .halfOpen:
            circuitBreakerStates[operationId] = .open(Date())
            logger.warning("Circuit breaker reopened for operation: \(operationId)")
            
        case .open:
            // Already open, no action needed
            break
        }
    }
    
    /// Record a successful operation (for circuit breaker recovery)
    func recordSuccess(for operationId: String) async {
        recoveryAttempts[operationId] = 0
        lastRecoveryTime[operationId] = nil
        
        if let state = circuitBreakerStates[operationId] {
            switch state {
            case .halfOpen:
                circuitBreakerStates[operationId] = .closed
                logger.info("Circuit breaker closed for operation: \(operationId)")
                
            case .open, .closed:
                break
            }
        }
    }
    
    // MARK: - Recovery Statistics
    
    /// Get recovery statistics for monitoring
    func getRecoveryStatistics() async -> RecoveryStatistics {
        let totalOperations = recoveryAttempts.count
        let failedOperations = recoveryAttempts.filter { $0.value > 0 }.count
        let openCircuitBreakers = circuitBreakerStates.filter { 
            if case .open = $0.value { return true }
            return false
        }.count
        
        return RecoveryStatistics(
            totalOperations: totalOperations,
            failedOperations: failedOperations,
            openCircuitBreakers: openCircuitBreakers,
            averageRecoveryAttempts: totalOperations > 0 ? Double(recoveryAttempts.values.reduce(0, +)) / Double(totalOperations) : 0
        )
    }
}

// MARK: - Supporting Types

enum RecoveryStrategy {
    case retryWithBackoff
    case retryWithExponentialBackoff
    case reauthenticate
    case useCachedData
    case useAlternativeService
    case skipOperation
}

enum CircuitBreakerState {
    case closed
    case open(Date)
    case halfOpen
}

struct RecoveryStatistics {
    let totalOperations: Int
    let failedOperations: Int
    let openCircuitBreakers: Int
    let averageRecoveryAttempts: Double
}
