import Foundation
import OSLog

/// Comprehensive resilience service that integrates error recovery, circuit breakers, and graceful degradation
/// Provides a unified interface for building resilient operations
@MainActor
class ResilienceService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let errorRecoveryManager: ErrorRecoveryManager
    private let degradationManager: GracefulDegradationManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ResilienceService")
    
    // MARK: - Published State
    
    @Published var systemHealth: SystemHealth = SystemHealth()
    @Published var isMonitoring = false
    
    // MARK: - Configuration
    
    private let healthCheckInterval: TimeInterval = 30.0 // 30 seconds
    private var healthCheckTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(
        errorRecoveryManager: ErrorRecoveryManager = ErrorRecoveryManager(),
        degradationManager: GracefulDegradationManager = GracefulDegradationManager()
    ) {
        self.errorRecoveryManager = errorRecoveryManager
        self.degradationManager = degradationManager
        logger.info("ResilienceService initialized")
    }
    
    deinit {
        healthCheckTask?.cancel()
    }
    
    // MARK: - Public Interface
    
    /// Execute operation with full resilience features
    func executeResilient<T>(
        operationId: String,
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil,
        degradationStrategy: DegradationStrategy? = nil
    ) async throws -> T {
        logger.debug("Executing resilient operation: \(operationId)")
        
        do {
            // Execute with error recovery (includes circuit breaker and retry logic)
            return try await errorRecoveryManager.executeWithRecovery(
                operationId: operationId,
                operation: operation,
                fallback: fallback
            )
            
        } catch {
            logger.warning("Operation failed after all recovery attempts: \(operationId)")
            
            // Try graceful degradation if strategy is provided
            if let strategy = degradationStrategy,
               let fallback = fallback {
                logger.info("Attempting graceful degradation for operation: \(operationId)")
                
                await degradationManager.registerStrategy(strategy, for: operationId)
                return await degradationManager.executeDegraded(
                    serviceId: operationId,
                    fallbackValue: await fallback()
                )
            }
            
            // Re-throw the error if no degradation strategy
            throw error
        }
    }
    
    /// Execute operation with timeout and resilience
    func executeWithTimeout<T>(
        operationId: String,
        timeout: TimeInterval,
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil
    ) async throws -> T {
        logger.debug("Executing operation with timeout: \(operationId) (\(timeout)s)")
        
        return try await executeResilient(
            operationId: operationId,
            operation: {
                try await withThrowingTaskGroup(of: T.self) { group in
                    // Add the main operation
                    group.addTask {
                        try await operation()
                    }
                    
                    // Add timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        throw ErrorRecoveryError.operationTimeout(operationId)
                    }
                    
                    // Return the first result (either success or timeout)
                    guard let result = try await group.next() else {
                        throw ErrorRecoveryError.operationTimeout(operationId)
                    }
                    
                    group.cancelAll()
                    return result
                }
            },
            fallback: fallback,
            degradationStrategy: .returnDefault
        )
    }
    
    /// Start system health monitoring
    func startHealthMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        logger.info("Starting system health monitoring")
        
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateSystemHealth()
                
                try? await Task.sleep(nanoseconds: UInt64(self?.healthCheckInterval ?? 30.0 * 1_000_000_000))
            }
        }
    }
    
    /// Stop system health monitoring
    func stopHealthMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        healthCheckTask?.cancel()
        healthCheckTask = nil
        
        logger.info("Stopped system health monitoring")
    }
    
    /// Get comprehensive system statistics
    func getSystemStatistics() async -> SystemStatistics {
        let errorStats = await errorRecoveryManager.getErrorStatistics()
        
        return SystemStatistics(
            systemHealth: systemHealth,
            errorStatistics: errorStats,
            timestamp: Date()
        )
    }
    
    /// Reset all error states
    func resetAllErrorStates() async {
        logger.info("Resetting all error states")
        
        // This would need to be implemented to reset all operation states
        // For now, we'll just update the system health
        await updateSystemHealth()
    }
    
    // MARK: - Health Monitoring
    
    private func updateSystemHealth() async {
        logger.debug("Updating system health")
        
        let errorStats = await errorRecoveryManager.getErrorStatistics()
        
        let overallHealth = calculateOverallHealth(errorStats: errorStats)
        let criticalServices = identifyCriticalServices(errorStats: errorStats)
        
        let newHealth = SystemHealth(
            overallStatus: overallHealth,
            criticalServices: criticalServices,
            lastUpdated: Date(),
            errorRate: 1.0 - errorStats.successRate,
            circuitBreakerStatus: summarizeCircuitBreakers(errorStats.circuitBreakerStates)
        )
        
        // Update on main actor
        Task { @MainActor in
            self.systemHealth = newHealth
        }
    }
    
    private func calculateOverallHealth(errorStats: ErrorStatistics) -> HealthStatus {
        let successRate = errorStats.successRate
        let openCircuitBreakers = errorStats.circuitBreakerStates.values.filter { $0 == .open }.count
        
        if successRate >= 0.95 && openCircuitBreakers == 0 {
            return .healthy
        } else if successRate >= 0.8 && openCircuitBreakers <= 2 {
            return .degraded
        } else {
            return .unhealthy
        }
    }
    
    private func identifyCriticalServices(errorStats: ErrorStatistics) -> [String] {
        return errorStats.circuitBreakerStates.compactMap { operationId, state in
            state == .open ? operationId : nil
        }
    }
    
    private func summarizeCircuitBreakers(_ states: [String: CircuitBreakerState]) -> CircuitBreakerSummary {
        let closed = states.values.filter { $0 == .closed }.count
        let open = states.values.filter { $0 == .open }.count
        let halfOpen = states.values.filter { $0 == .halfOpen }.count
        
        return CircuitBreakerSummary(
            closed: closed,
            open: open,
            halfOpen: halfOpen,
            total: states.count
        )
    }
}

// MARK: - System Health Models

struct SystemHealth {
    let overallStatus: HealthStatus
    let criticalServices: [String]
    let lastUpdated: Date
    let errorRate: Double
    let circuitBreakerStatus: CircuitBreakerSummary
    
    init(
        overallStatus: HealthStatus = .healthy,
        criticalServices: [String] = [],
        lastUpdated: Date = Date(),
        errorRate: Double = 0.0,
        circuitBreakerStatus: CircuitBreakerSummary = CircuitBreakerSummary()
    ) {
        self.overallStatus = overallStatus
        self.criticalServices = criticalServices
        self.lastUpdated = lastUpdated
        self.errorRate = errorRate
        self.circuitBreakerStatus = circuitBreakerStatus
    }
    
    var isHealthy: Bool {
        overallStatus == .healthy
    }
    
    var hasCriticalIssues: Bool {
        !criticalServices.isEmpty || overallStatus == .unhealthy
    }
}

enum HealthStatus: String, CaseIterable {
    case healthy = "healthy"
    case degraded = "degraded"
    case unhealthy = "unhealthy"
    
    var description: String {
        switch self {
        case .healthy:
            return "All systems operational"
        case .degraded:
            return "Some services experiencing issues"
        case .unhealthy:
            return "Critical system issues detected"
        }
    }
    
    var color: String {
        switch self {
        case .healthy:
            return "green"
        case .degraded:
            return "yellow"
        case .unhealthy:
            return "red"
        }
    }
}

struct CircuitBreakerSummary {
    let closed: Int
    let open: Int
    let halfOpen: Int
    let total: Int
    
    init(closed: Int = 0, open: Int = 0, halfOpen: Int = 0, total: Int = 0) {
        self.closed = closed
        self.open = open
        self.halfOpen = halfOpen
        self.total = total
    }
    
    var healthyPercentage: Double {
        total > 0 ? Double(closed) / Double(total) : 1.0
    }
}

struct SystemStatistics {
    let systemHealth: SystemHealth
    let errorStatistics: ErrorStatistics
    let timestamp: Date
    
    var summary: String {
        """
        System Health: \(systemHealth.overallStatus.description)
        Error Rate: \(String(format: "%.1f", systemHealth.errorRate * 100))%
        Circuit Breakers: \(systemHealth.circuitBreakerStatus.closed) closed, \(systemHealth.circuitBreakerStatus.open) open
        Critical Services: \(systemHealth.criticalServices.count)
        """
    }
}

// MARK: - Resilience Extensions

extension ResilienceService {
    
    /// Convenience method for database operations
    func executeDatabaseOperation<T>(
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil
    ) async throws -> T {
        return try await executeResilient(
            operationId: "database_operation",
            operation: operation,
            fallback: fallback,
            degradationStrategy: .returnCached
        )
    }
    
    /// Convenience method for network operations
    func executeNetworkOperation<T>(
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil
    ) async throws -> T {
        return try await executeWithTimeout(
            operationId: "network_operation",
            timeout: 10.0, // 10 second timeout for network operations
            operation: operation,
            fallback: fallback
        )
    }
    
    /// Convenience method for search operations
    func executeSearchOperation<T>(
        query: String,
        operation: @escaping () async throws -> T,
        fallback: (() async -> T)? = nil
    ) async throws -> T {
        return try await executeResilient(
            operationId: "search_\(query.hash)",
            operation: operation,
            fallback: fallback,
            degradationStrategy: .returnCached
        )
    }
}
