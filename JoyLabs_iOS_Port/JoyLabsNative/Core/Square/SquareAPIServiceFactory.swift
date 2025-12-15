import Foundation
import SwiftData
import OSLog

/// SINGLE SERVICE FACTORY - Eliminates ALL duplicate service instances
/// Provides centralized creation and configuration of ALL Square services
/// CRITICAL: This prevents multiple keychain access and database connections
@MainActor
class SquareAPIServiceFactory {

    /// Shared instance for singleton access
    static let shared = SquareAPIServiceFactory()

    /// Shared catalog container (from app)
    private var sharedCatalogContainer: ModelContainer?

    /// Cached service instances - SINGLE INSTANCES ONLY
    private var cachedSquareAPIService: SquareAPIService?
    private var cachedDatabaseManager: SwiftDataCatalogManager?  // SwiftData only
    private var cachedSyncCoordinator: SwiftDataSyncCoordinator?  // SwiftData only
    private var cachedCatalogSyncService: SwiftDataCatalogSyncService?  // SwiftData only
    private var cachedTokenService: TokenService?
    private var cachedHTTPClient: SquareHTTPClient?
    // ImageURLManager removed - using pure SwiftData for images
    private var cachedCRUDService: SquareCRUDService?
    private var cachedInventoryService: SquareInventoryService?

    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareAPIServiceFactory")

    private init() {
        logger.info("[Factory] SquareAPIServiceFactory initialized - SINGLE INSTANCE FACTORY")
    }

    /// Initialize factory with shared catalog container from app
    static func initialize(with catalogContainer: ModelContainer) {
        shared.sharedCatalogContainer = catalogContainer
        shared.logger.info("[Factory] Initialized with shared catalog container")
    }

    /// Create or return cached SquareAPIService instance
    static func createService() -> SquareAPIService {
        return shared.getOrCreateSquareAPIService()
    }

    /// Get or create the SquareAPIService instance
    private func getOrCreateSquareAPIService() -> SquareAPIService {
        if let cachedService = cachedSquareAPIService {
            logger.debug("[Factory] Returning cached SquareAPIService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW SquareAPIService instance")
        let service = SquareAPIService()
        cachedSquareAPIService = service
        return service
    }

    /// Get or create the database manager instance (SwiftData)
    static func createDatabaseManager() -> SwiftDataCatalogManager {
        return shared.getOrCreateDatabaseManager()
    }
    
    private func getOrCreateDatabaseManager() -> SwiftDataCatalogManager {
        if let cachedManager = cachedDatabaseManager {
            logger.debug("[Factory] Returning cached SwiftDataCatalogManager instance")
            return cachedManager
        }
        
        do {
            logger.debug("[Factory] Creating NEW SwiftDataCatalogManager instance with shared container")
            guard let container = sharedCatalogContainer else {
                fatalError("[Factory] Shared catalog container not initialized. Call SquareAPIServiceFactory.initialize(with:) first.")
            }
            let manager = try SwiftDataCatalogManager(existingContainer: container)
            cachedDatabaseManager = manager
            return manager
        } catch {
            logger.error("[Factory] Failed to create SwiftDataCatalogManager: \(error)")
            fatalError("Failed to create SwiftDataCatalogManager: \(error)")
        }
    }

    /// Get or create the sync coordinator instance (SwiftData)
    static func createSyncCoordinator() -> SwiftDataSyncCoordinator {
        return shared.getOrCreateSyncCoordinator()
    }

    private func getOrCreateSyncCoordinator() -> SwiftDataSyncCoordinator {
        if let cachedCoordinator = cachedSyncCoordinator {
            logger.debug("[Factory] Returning cached SwiftDataSyncCoordinator instance")
            return cachedCoordinator
        }

        logger.debug("[Factory] Creating NEW SwiftDataSyncCoordinator instance")
        let squareService = getOrCreateSquareAPIService()
        let coordinator = SwiftDataSyncCoordinator(squareAPIService: squareService)
        cachedSyncCoordinator = coordinator
        return coordinator
    }

    /// Get or create the catalog sync service instance (SwiftData)
    static func createCatalogSyncService() -> SwiftDataCatalogSyncService {
        return shared.getOrCreateCatalogSyncService()
    }

    private func getOrCreateCatalogSyncService() -> SwiftDataCatalogSyncService {
        if let cachedService = cachedCatalogSyncService {
            logger.debug("[Factory] Returning cached SwiftDataCatalogSyncService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW SwiftDataCatalogSyncService instance")
        let squareService = getOrCreateSquareAPIService()
        let service = SwiftDataCatalogSyncService(squareAPIService: squareService)
        cachedCatalogSyncService = service
        return service
    }

    /// Get or create the token service instance
    static func createTokenService() -> TokenService {
        return shared.getOrCreateTokenService()
    }

    private func getOrCreateTokenService() -> TokenService {
        if let cachedService = cachedTokenService {
            logger.debug("[Factory] Returning cached TokenService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW TokenService instance")
        let service = TokenService()
        cachedTokenService = service
        return service
    }

    /// Get or create the HTTP client instance
    static func createHTTPClient() -> SquareHTTPClient {
        return shared.getOrCreateHTTPClient()
    }

    private func getOrCreateHTTPClient() -> SquareHTTPClient {
        if let cachedClient = cachedHTTPClient {
            logger.debug("[Factory] Returning cached SquareHTTPClient instance")
            return cachedClient
        }

        logger.debug("[Factory] Creating NEW SquareHTTPClient instance")
        let tokenService = getOrCreateTokenService()
        let client = SquareHTTPClient(tokenService: tokenService, resilienceService: BasicResilienceService())
        cachedHTTPClient = client
        return client
    }

    /// Get or create the image URL manager instance
    // ImageURLManager factory methods removed - using pure SwiftData for images

    /// Get or create the CRUD service instance
    static func createCRUDService() -> SquareCRUDService {
        return shared.getOrCreateCRUDService()
    }

    private func getOrCreateCRUDService() -> SquareCRUDService {
        if let cachedService = cachedCRUDService {
            logger.debug("[Factory] Returning cached SquareCRUDService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW SquareCRUDService instance")
        let squareAPIService = getOrCreateSquareAPIService()
        let databaseManager = getOrCreateDatabaseManager()
        let dataConverter = SquareDataConverter(databaseManager: databaseManager)

        let service = SquareCRUDService(
            squareAPIService: squareAPIService,
            databaseManager: databaseManager,
            dataConverter: dataConverter
        )
        cachedCRUDService = service
        return service
    }

    /// Get or create the inventory service instance
    static func createInventoryService() -> SquareInventoryService {
        return shared.getOrCreateInventoryService()
    }

    private func getOrCreateInventoryService() -> SquareInventoryService {
        if let cachedService = cachedInventoryService {
            logger.debug("[Factory] Returning cached SquareInventoryService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW SquareInventoryService instance")
        let httpClient = getOrCreateHTTPClient()
        let service = SquareInventoryService(httpClient: httpClient)
        cachedInventoryService = service
        return service
    }

    /// Reset ALL cached services (for testing or re-authentication)
    static func resetAllServices() {
        shared.logger.info("Resetting ALL cached services")
        shared.cachedSquareAPIService = nil
        shared.cachedDatabaseManager = nil
        shared.cachedSyncCoordinator = nil
        shared.cachedCatalogSyncService = nil
        shared.cachedTokenService = nil
        shared.cachedHTTPClient = nil
        // cachedImageURLManager removed
        shared.cachedCRUDService = nil
        shared.cachedInventoryService = nil
    }

    /// Get service status for debugging
    static func getServiceStatus() -> [String: Bool] {
        return [
            "SquareAPIService": shared.cachedSquareAPIService != nil,
            "SQLiteSwiftCatalogManager": shared.cachedDatabaseManager != nil,
            "SQLiteSwiftSyncCoordinator": shared.cachedSyncCoordinator != nil,
            "SQLiteSwiftCatalogSyncService": shared.cachedCatalogSyncService != nil,
            "TokenService": shared.cachedTokenService != nil,
            "SquareHTTPClient": shared.cachedHTTPClient != nil,
            // "ImageURLManager": removed,
            "SquareCRUDService": shared.cachedCRUDService != nil,
            "SquareInventoryService": shared.cachedInventoryService != nil
        ]
    }
}
