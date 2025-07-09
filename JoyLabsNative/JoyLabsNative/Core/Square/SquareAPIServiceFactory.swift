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

    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareAPIServiceFactory")

    private init() {
        logger.info("SquareAPIServiceFactory initialized - SINGLE INSTANCE FACTORY")
    }

    /// Create or return cached SquareAPIService instance
    static func createService() -> SquareAPIService {
        return shared.getOrCreateSquareAPIService()
    }

    /// Get or create the SquareAPIService instance
    private func getOrCreateSquareAPIService() -> SquareAPIService {
        if let cachedService = cachedSquareAPIService {
            logger.debug("Returning cached SquareAPIService instance")
            return cachedService
        }

        logger.info("Creating NEW SquareAPIService instance")
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
            logger.debug("Returning cached SQLiteSwiftCatalogManager instance")
            return cachedManager
        }

        logger.info("Creating NEW SQLiteSwiftCatalogManager instance")
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
            logger.debug("Returning cached SQLiteSwiftSyncCoordinator instance")
            return cachedCoordinator
        }

        logger.info("Creating NEW SQLiteSwiftSyncCoordinator instance")
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
            logger.debug("Returning cached SQLiteSwiftCatalogSyncService instance")
            return cachedService
        }

        logger.info("Creating NEW SQLiteSwiftCatalogSyncService instance")
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
            logger.debug("Returning cached TokenService instance")
            return cachedService
        }

        logger.info("Creating NEW TokenService instance")
        let service = TokenService()
        cachedTokenService = service
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
    }

    /// Get service status for debugging
    static func getServiceStatus() -> [String: Bool] {
        return [
            "SquareAPIService": shared.cachedSquareAPIService != nil,
            "SQLiteSwiftCatalogManager": shared.cachedDatabaseManager != nil,
            "SQLiteSwiftSyncCoordinator": shared.cachedSyncCoordinator != nil,
            "SQLiteSwiftCatalogSyncService": shared.cachedCatalogSyncService != nil,
            "TokenService": shared.cachedTokenService != nil
        ]
    }
}
