import Foundation

/// Factory for creating SquareAPIService instances with proper dependency injection
/// Provides centralized creation and configuration of Square API services
@MainActor
class SquareAPIServiceFactory {
    
    /// Shared instance for singleton access
    static let shared = SquareAPIServiceFactory()
    
    /// Cached service instance
    private var cachedService: SquareAPIService?
    
    private init() {}
    
    /// Create or return cached SquareAPIService instance
    static func createService() -> SquareAPIService {
        return shared.getOrCreateService()
    }
    
    /// Get or create the service instance
    private func getOrCreateService() -> SquareAPIService {
        if let cachedService = cachedService {
            return cachedService
        }
        
        let service = SquareAPIService()
        cachedService = service
        return service
    }
    
    /// Reset the cached service (useful for testing or logout)
    static func resetService() {
        shared.cachedService = nil
    }
}
