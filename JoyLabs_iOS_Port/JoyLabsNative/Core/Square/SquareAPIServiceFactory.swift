import Foundation
import OSLog

/// SINGLE SERVICE FACTORY - Eliminates ALL duplicate service instances
/// Provides centralized creation and configuration of ALL Square services
/// CRITICAL: This prevents multiple keychain access and database connections
@MainActor
class SquareAPIServiceFactory {

    /// Shared instance for singleton access
    static let shared = SquareAPIServiceFactory()

    /// Cached service instances - SINGLE INSTANCES ONLY
    private var cachedSquareAPIService: SquareAPIService?
    private var cachedDatabaseManager: SQLiteSwiftCatalogManager?
    private var cachedSyncCoordinator: SQLiteSwiftSyncCoordinator?
    private var cachedCatalogSyncService: SQLiteSwiftCatalogSyncService?
    private var cachedTokenService: TokenService?
    private var cachedHTTPClient: SquareHTTPClient?
    private var cachedImageURLManager: ImageURLManager?
    private var cachedCRUDService: SquareCRUDService?

    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareAPIServiceFactory")

    private init() {
        logger.info("[Factory] SquareAPIServiceFactory initialized - SINGLE INSTANCE FACTORY")
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

    /// Get or create the database manager instance
    static func createDatabaseManager() -> SQLiteSwiftCatalogManager {
        return shared.getOrCreateDatabaseManager()
    }

    private func getOrCreateDatabaseManager() -> SQLiteSwiftCatalogManager {
        if let cachedManager = cachedDatabaseManager {
            // Remove this debug log to reduce console noise
            return cachedManager
        }

        logger.debug("[Factory] Creating NEW SQLiteSwiftCatalogManager instance")
        let manager = SQLiteSwiftCatalogManager()
        cachedDatabaseManager = manager
        return manager
    }

    /// Get or create the sync coordinator instance
    static func createSyncCoordinator() -> SQLiteSwiftSyncCoordinator {
        return shared.getOrCreateSyncCoordinator()
    }

    private func getOrCreateSyncCoordinator() -> SQLiteSwiftSyncCoordinator {
        if let cachedCoordinator = cachedSyncCoordinator {
            logger.debug("[Factory] Returning cached SQLiteSwiftSyncCoordinator instance")
            return cachedCoordinator
        }

        logger.debug("[Factory] Creating NEW SQLiteSwiftSyncCoordinator instance")
        let squareService = getOrCreateSquareAPIService()
        let coordinator = SQLiteSwiftSyncCoordinator(squareAPIService: squareService)
        cachedSyncCoordinator = coordinator
        return coordinator
    }

    /// Get or create the catalog sync service instance
    static func createCatalogSyncService() -> SQLiteSwiftCatalogSyncService {
        return shared.getOrCreateCatalogSyncService()
    }

    private func getOrCreateCatalogSyncService() -> SQLiteSwiftCatalogSyncService {
        if let cachedService = cachedCatalogSyncService {
            logger.debug("[Factory] Returning cached SQLiteSwiftCatalogSyncService instance")
            return cachedService
        }

        logger.debug("[Factory] Creating NEW SQLiteSwiftCatalogSyncService instance")
        let squareService = getOrCreateSquareAPIService()
        let service = SQLiteSwiftCatalogSyncService(squareAPIService: squareService)
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
    static func createImageURLManager() -> ImageURLManager {
        return shared.getOrCreateImageURLManager()
    }

    private func getOrCreateImageURLManager() -> ImageURLManager {
        if let cachedManager = cachedImageURLManager {
            return cachedManager
        }

        logger.debug("[Factory] Creating NEW ImageURLManager instance")
        let databaseManager = getOrCreateDatabaseManager()
        let manager = ImageURLManager(databaseManager: databaseManager)
        cachedImageURLManager = manager
        return manager
    }

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

    /// Reset ALL cached services (for testing or re-authentication)
    static func resetAllServices() {
        shared.logger.info("Resetting ALL cached services")
        shared.cachedSquareAPIService = nil
        shared.cachedDatabaseManager = nil
        shared.cachedSyncCoordinator = nil
        shared.cachedCatalogSyncService = nil
        shared.cachedTokenService = nil
        shared.cachedHTTPClient = nil
        shared.cachedImageURLManager = nil
        shared.cachedCRUDService = nil
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
            "ImageURLManager": shared.cachedImageURLManager != nil,
            "SquareCRUDService": shared.cachedCRUDService != nil
        ]
    }
}
