import Foundation
import OSLog

/// Singleton handler for Square OAuth callbacks at the app level
/// Coordinates between app URL handling and OAuth services
@MainActor
class SquareOAuthCallbackHandler: ObservableObject {
    
    static let shared = SquareOAuthCallbackHandler()
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareOAuthCallbackHandler")
    
    // Reference to the active OAuth service
    private weak var activeOAuthService: SquareOAuthService?
    
    private init() {
        logger.info("SquareOAuthCallbackHandler initialized")
    }
    
    /// Register an OAuth service to receive callbacks
    func registerOAuthService(_ service: SquareOAuthService) {
        logger.info("Registering OAuth service for callbacks")
        activeOAuthService = service
    }
    
    /// Unregister the OAuth service
    func unregisterOAuthService() {
        logger.info("Unregistering OAuth service")
        activeOAuthService = nil
    }
    
    /// Handle incoming OAuth callback URL
    func handleCallback(url: URL) async {
        logger.info("Handling OAuth callback: \(url.absoluteString)")
        
        guard let oauthService = activeOAuthService else {
            logger.error("No active OAuth service registered to handle callback")
            return
        }
        
        do {
            let tokenResponse = try await oauthService.handleCallback(url: url)
            logger.info("OAuth callback processed successfully")
            
            // Notify any observers that authentication completed
            NotificationCenter.default.post(
                name: .squareAuthenticationCompleted,
                object: tokenResponse
            )
            
        } catch {
            logger.error("OAuth callback processing failed: \(error.localizedDescription)")
            
            // Notify any observers that authentication failed
            NotificationCenter.default.post(
                name: .squareAuthenticationFailed,
                object: error
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let squareAuthenticationCompleted = Notification.Name("squareAuthenticationCompleted")
    static let squareAuthenticationFailed = Notification.Name("squareAuthenticationFailed")
}
