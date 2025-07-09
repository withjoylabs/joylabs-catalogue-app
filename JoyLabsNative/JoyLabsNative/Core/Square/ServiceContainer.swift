import Foundation
import OSLog

/// Service container for managing Square API integration dependencies
/// Provides proper dependency injection and service lifecycle management
@MainActor
class ServiceContainer: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ServiceContainer()
    
    // MARK: - Services
    
    private var _dataValidationService: DataValidationService?
    private var _dataTransformationService: DataTransformationService?
    private var _squareAPIService: SquareAPIService?
    private var _databaseManager: ResilientDatabaseManager?
    private var _catalogDatabaseManager: CatalogDatabaseManager?
    private var _catalogSyncService: CatalogSyncService?
    private var _squareSyncCoordinator: SquareSyncCoordinator?
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ServiceContainer")
    
    // MARK: - Initialization
    
    private init() {
        logger.info("ServiceContainer initialized")
    }
    
    // MARK: - Service Accessors
    
    /// Get or create DataValidationService
    func dataValidationService() async -> DataValidationService {
        if let service = _dataValidationService {
            return service
        }
        
        logger.info("Creating DataValidationService")
        let service = DataValidationService()
        _dataValidationService = service
        return service
    }
    
    /// Get or create DataTransformationService
    func dataTransformationService() async -> DataTransformationService {
        if let service = _dataTransformationService {
            return service
        }
        
        logger.info("Creating DataTransformationService")
        let validationService = await dataValidationService()
        let service = DataTransformationService(dataValidator: validationService)
        _dataTransformationService = service
        return service
    }
    
    /// Get or create SquareAPIService
    func squareAPIService() async -> SquareAPIService {
        if let service = _squareAPIService {
            return service
        }
        
        logger.info("Creating SquareAPIService")
        let service = SquareAPIService()
        _squareAPIService = service
        return service
    }
    
    /// Get or create ResilientDatabaseManager
    func databaseManager() async -> ResilientDatabaseManager {
        if let manager = _databaseManager {
            return manager
        }

        logger.info("Creating ResilientDatabaseManager")
        let manager = ResilientDatabaseManager()
        _databaseManager = manager
        return manager
    }

    /// Get or create shared CatalogDatabaseManager
    /// CRITICAL: This prevents multiple database connections to the same file
    func catalogDatabaseManager() async -> CatalogDatabaseManager {
        if let manager = _catalogDatabaseManager {
            return manager
        }

        logger.info("Creating shared CatalogDatabaseManager")
        let manager = CatalogDatabaseManager()
        _catalogDatabaseManager = manager
        return manager
    }
    
    /// Get or create CatalogSyncService with shared database manager
    func catalogSyncService() async -> CatalogSyncService {
        if let service = _catalogSyncService {
            return service
        }

        logger.info("Creating CatalogSyncService with shared dependencies")
        let apiService = await squareAPIService()
        let dbManager = await catalogDatabaseManager()

        let service = CatalogSyncService(
            squareAPIService: apiService,
            databaseManager: dbManager
        )
        _catalogSyncService = service
        return service
    }
    
    /// Get or create SquareSyncCoordinator
    func squareSyncCoordinator() async -> SquareSyncCoordinator {
        if let coordinator = _squareSyncCoordinator {
            return coordinator
        }

        logger.info("Creating SquareSyncCoordinator with shared dependencies")
        let dbManager = await databaseManager()
        let apiService = await squareAPIService()
        let catalogService = await catalogSyncService() // Use shared instance

        let coordinator = SquareSyncCoordinator.createCoordinator(
            databaseManager: dbManager,
            squareAPIService: apiService,
            catalogSyncService: catalogService
        )
        _squareSyncCoordinator = coordinator
        return coordinator
    }
    
    // MARK: - Service Management
    
    /// Reset all services (useful for testing or configuration changes)
    func resetServices() async {
        logger.info("Resetting all services")
        
        _squareSyncCoordinator = nil
        _catalogSyncService = nil
        _dataTransformationService = nil
        _dataValidationService = nil
        _squareAPIService = nil
        _databaseManager = nil
        
        logger.info("All services reset")
    }
    
    /// Get service status for debugging
    func getServiceStatus() async -> ServiceStatus {
        return ServiceStatus(
            dataValidationServiceCreated: _dataValidationService != nil,
            dataTransformationServiceCreated: _dataTransformationService != nil,
            squareAPIServiceCreated: _squareAPIService != nil,
            databaseManagerCreated: _databaseManager != nil,
            catalogSyncServiceCreated: _catalogSyncService != nil,
            squareSyncCoordinatorCreated: _squareSyncCoordinator != nil
        )
    }
    
    /// Initialize all core services
    func initializeCoreServices() async {
        logger.info("Initializing core services")
        
        // Initialize services in dependency order
        _ = await dataValidationService()
        _ = await dataTransformationService()
        _ = await squareAPIService()
        _ = await databaseManager()
        _ = await catalogSyncService()
        _ = await squareSyncCoordinator()
        
        logger.info("Core services initialization completed")
    }
    
    // MARK: - Service Health Check
    
    /// Perform health check on all services
    func performHealthCheck() async -> HealthCheckResult {
        logger.info("Performing service health check")
        
        var results: [String: Bool] = [:]
        var errors: [String] = []
        
        // Check DataValidationService
        do {
            let validationService = await dataValidationService()
            let stats = await validationService.getValidationStatistics()
            results["DataValidationService"] = true
            logger.debug("DataValidationService: \(stats.totalValidations) validations performed")
        } catch {
            results["DataValidationService"] = false
            errors.append("DataValidationService: \(error.localizedDescription)")
        }
        
        // Check DataTransformationService
        do {
            let transformationService = await dataTransformationService()
            let stats = await transformationService.getTransformationStatistics()
            results["DataTransformationService"] = true
            logger.debug("DataTransformationService: \(stats.totalTransformations) transformations performed")
        } catch {
            results["DataTransformationService"] = false
            errors.append("DataTransformationService: \(error.localizedDescription)")
        }
        
        // Check SquareAPIService
        do {
            let apiService = await squareAPIService()
            results["SquareAPIService"] = apiService.isAuthenticated
            logger.debug("SquareAPIService: authenticated = \(apiService.isAuthenticated)")
        } catch {
            results["SquareAPIService"] = false
            errors.append("SquareAPIService: \(error.localizedDescription)")
        }
        
        // Check DatabaseManager
        do {
            let dbManager = await databaseManager()
            let isReady = await dbManager.isDatabaseReady()
            results["ResilientDatabaseManager"] = isReady
            logger.debug("ResilientDatabaseManager: ready = \(isReady)")
        } catch {
            results["ResilientDatabaseManager"] = false
            errors.append("ResilientDatabaseManager: \(error.localizedDescription)")
        }
        
        let allHealthy = results.values.allSatisfy { $0 }
        
        logger.info("Health check completed: \(allHealthy ? "All services healthy" : "Some services unhealthy")")
        
        return HealthCheckResult(
            allHealthy: allHealthy,
            serviceResults: results,
            errors: errors,
            timestamp: Date()
        )
    }
}

// MARK: - Supporting Types

struct ServiceStatus {
    let dataValidationServiceCreated: Bool
    let dataTransformationServiceCreated: Bool
    let squareAPIServiceCreated: Bool
    let databaseManagerCreated: Bool
    let catalogSyncServiceCreated: Bool
    let squareSyncCoordinatorCreated: Bool
    
    var allServicesCreated: Bool {
        return dataValidationServiceCreated &&
               dataTransformationServiceCreated &&
               squareAPIServiceCreated &&
               databaseManagerCreated &&
               catalogSyncServiceCreated &&
               squareSyncCoordinatorCreated
    }
    
    var createdServicesCount: Int {
        return [dataValidationServiceCreated, dataTransformationServiceCreated, squareAPIServiceCreated, 
                databaseManagerCreated, catalogSyncServiceCreated, squareSyncCoordinatorCreated]
            .filter { $0 }.count
    }
}

struct HealthCheckResult {
    let allHealthy: Bool
    let serviceResults: [String: Bool]
    let errors: [String]
    let timestamp: Date
    
    var healthyServicesCount: Int {
        return serviceResults.values.filter { $0 }.count
    }
    
    var totalServicesCount: Int {
        return serviceResults.count
    }
    
    var summary: String {
        return "Health Check: \(healthyServicesCount)/\(totalServicesCount) services healthy"
    }
}
