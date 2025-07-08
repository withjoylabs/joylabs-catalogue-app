import Foundation
import AuthenticationServices
import OSLog

/// Complete Square OAuth 2.0 service with PKCE flow
/// Handles authorization, token exchange, and deep link processing
@MainActor
class SquareOAuthService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published var isAuthenticating = false
    @Published var authenticationError: Error?
    @Published var isAuthenticated = false
    @Published var lastTokenResponse: TokenResponse?
    
    // MARK: - Dependencies
    
    private let httpClient: SquareHTTPClient
    private let stateManager = OAuthStateManager()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareOAuthService")
    
    // MARK: - OAuth Session
    
    private var authSession: ASWebAuthenticationSession?
    private var currentOAuthState: OAuthState?
    
    // MARK: - Initialization
    
    init(httpClient: SquareHTTPClient) {
        self.httpClient = httpClient
        super.init()
        logger.info("SquareOAuthService initialized")
    }
    
    // MARK: - Public OAuth Methods
    
    /// Start Square OAuth authorization flow
    func startAuthorization() async throws {
        guard !isAuthenticating else {
            logger.warning("Authorization already in progress")
            return
        }
        
        logger.info("Starting Square OAuth authorization flow")
        isAuthenticating = true
        authenticationError = nil
        
        do {
            // Create OAuth state with PKCE parameters
            let oauthState = await stateManager.createOAuthState()
            currentOAuthState = oauthState
            
            // Skip backend registration for performance - direct token flow doesn't need it
            // try await registerStateWithBackend(oauthState)
            
            // Build authorization URL
            guard let authURL = OAuthURLBuilder.buildAuthorizationURL(oauthState: oauthState) else {
                throw OAuthError.invalidCallback
            }
            
            // Start web authentication session
            try await startWebAuthenticationSession(authURL: authURL)
            
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription)")
            isAuthenticating = false
            authenticationError = error
            throw error
        }
    }
    
    /// Handle deep link callback from Square OAuth
    func handleCallback(url: URL) async throws -> TokenResponse {
        logger.info("Handling OAuth callback: \(url.absoluteString)")
        
        guard let callbackResult = OAuthURLBuilder.parseCallbackURL(url) else {
            throw OAuthError.invalidCallback
        }
        
        switch callbackResult {
        case .success(let code, let state):
            return try await processSuccessfulCallback(code: code, state: state)

        case .directTokens(let accessToken, let refreshToken, let merchantId, let businessName):
            return try await processDirectTokenCallback(
                accessToken: accessToken,
                refreshToken: refreshToken,
                merchantId: merchantId,
                businessName: businessName
            )

        case .error(let error, let description):
            logger.error("OAuth callback error: \(error) - \(description ?? "no description")")
            throw OAuthError.serverError(description ?? error)
        }
    }
    
    /// Cancel ongoing authorization
    func cancelAuthorization() {
        logger.info("Canceling OAuth authorization")
        
        authSession?.cancel()
        authSession = nil
        currentOAuthState = nil
        isAuthenticating = false
        
        Task {
            await stateManager.clearOAuthState()
        }
    }
    
    // MARK: - Private Implementation
    
    private func registerStateWithBackend(_ oauthState: OAuthState) async throws {
        logger.debug("Registering OAuth state with backend")
        
        try await httpClient.registerState(
            state: oauthState.state,
            codeVerifier: oauthState.codeVerifier,
            appCallback: oauthState.appCallback
        )
        
        logger.debug("OAuth state registered successfully")
    }
    
    private func startWebAuthenticationSession(authURL: URL) async throws {
        logger.debug("Starting web authentication session")
        
        return try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: SquareConfiguration.callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.isAuthenticating = false
                    
                    if let error = error {
                        if let authError = error as? ASWebAuthenticationSessionError,
                           authError.code == .canceledLogin {
                            self?.logger.info("User canceled OAuth authorization")
                            continuation.resume(throwing: OAuthError.authorizationDenied)
                        } else {
                            self?.logger.error("Web authentication session error: \(error.localizedDescription)")
                            continuation.resume(throwing: OAuthError.networkError(error))
                        }
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        self?.logger.error("No callback URL received")
                        continuation.resume(throwing: OAuthError.invalidCallback)
                        return
                    }
                    
                    do {
                        _ = try await self?.handleCallback(url: callbackURL)
                        self?.isAuthenticated = true
                        continuation.resume()
                    } catch {
                        self?.logger.error("Callback handling failed: \(error.localizedDescription)")
                        self?.authenticationError = error
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Configure session
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            
            // Start the session
            guard authSession?.start() == true else {
                logger.error("Failed to start web authentication session")
                continuation.resume(throwing: OAuthError.networkError(NSError(domain: "ASWebAuthenticationSession", code: -1)))
                return
            }
            
            logger.debug("Web authentication session started successfully")
        }
    }
    
    private func processSuccessfulCallback(code: String, state: String) async throws -> TokenResponse {
        logger.debug("Processing successful OAuth callback")
        
        // Validate state parameter
        guard let oauthState = await stateManager.validateOAuthState(state) else {
            logger.error("OAuth state validation failed")
            throw OAuthError.invalidState
        }
        
        // Exchange authorization code for tokens
        let tokenResponse = try await httpClient.exchangeCodeForTokens(
            code: code,
            codeVerifier: oauthState.codeVerifier
        )
        
        // Store token response
        lastTokenResponse = tokenResponse
        isAuthenticated = true

        // Clear OAuth state
        await stateManager.clearOAuthState()
        currentOAuthState = nil

        logger.info("OAuth flow completed successfully")
        return tokenResponse
    }

    private func processDirectTokenCallback(
        accessToken: String,
        refreshToken: String?,
        merchantId: String?,
        businessName: String?
    ) async throws -> TokenResponse {
        logger.debug("Processing direct token callback")

        // Create token response from direct tokens
        let tokenResponse = TokenResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: nil, // Not provided in direct callback
            merchantId: merchantId,
            businessName: businessName,
            tokenType: "Bearer"
        )

        // Store token response and update authentication state
        lastTokenResponse = tokenResponse
        isAuthenticated = true

        // Store tokens securely
        // TODO: Implement token storage when TokenService is ready

        // Clear OAuth state
        await stateManager.clearOAuthState()
        currentOAuthState = nil

        logger.info("Direct token callback processed successfully")
        return tokenResponse
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SquareOAuthService: ASWebAuthenticationPresentationContextProviding {
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window for presentation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            logger.warning("No window available for OAuth presentation")
            return ASPresentationAnchor()
        }
        
        return window
    }
}

// MARK: - OAuth Service Extensions

extension SquareOAuthService {
    
    /// Check if user is currently authenticated
    var hasValidAuthentication: Bool {
        // This will be implemented when we add token storage
        return isAuthenticated
    }
    
    /// Get current OAuth state for debugging
    func getCurrentOAuthState() async -> OAuthState? {
        return await stateManager.getCurrentState()
    }
    
    /// Validate OAuth configuration
    func validateConfiguration() -> Bool {
        return SquareConfiguration.validateConfiguration()
    }
}

// MARK: - Deep Link Handler

/// Handles deep link URLs for Square OAuth callbacks
class SquareDeepLinkHandler {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareDeepLinkHandler")
    private weak var oauthService: SquareOAuthService?
    
    init(oauthService: SquareOAuthService) {
        self.oauthService = oauthService
    }
    
    /// Handle incoming deep link URL
    func handleDeepLink(_ url: URL) -> Bool {
        logger.info("Handling deep link: \(url.absoluteString)")
        
        // Check if this is a Square callback URL
        guard url.scheme == SquareConfiguration.callbackScheme,
              url.host == SquareConfiguration.callbackPath else {
            logger.debug("URL is not a Square callback")
            return false
        }
        
        // Process the callback asynchronously
        Task { @MainActor in
            do {
                _ = try await oauthService?.handleCallback(url: url)
                logger.info("Deep link callback processed successfully")
            } catch {
                logger.error("Deep link callback processing failed: \(error.localizedDescription)")
            }
        }
        
        return true
    }
}

// MARK: - OAuth Flow Manager

/// High-level manager for the complete OAuth flow
@MainActor
class SquareOAuthFlowManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var flowState: OAuthFlowState = .idle
    @Published var error: Error?
    @Published var tokenResponse: TokenResponse?
    
    // MARK: - Dependencies
    
    private let oauthService: SquareOAuthService
    private let deepLinkHandler: SquareDeepLinkHandler
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareOAuthFlowManager")
    
    // MARK: - Initialization
    
    init(httpClient: SquareHTTPClient) {
        self.oauthService = SquareOAuthService(httpClient: httpClient)
        self.deepLinkHandler = SquareDeepLinkHandler(oauthService: oauthService)
        
        logger.info("SquareOAuthFlowManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Start the complete OAuth flow
    func startOAuthFlow() async {
        logger.info("Starting complete OAuth flow")
        
        flowState = .authenticating
        error = nil
        
        do {
            try await oauthService.startAuthorization()
            // Flow will continue via deep link callback
        } catch {
            logger.error("OAuth flow failed: \(error.localizedDescription)")
            self.error = error
            flowState = .failed
        }
    }
    
    /// Handle deep link callback
    func handleDeepLink(_ url: URL) -> Bool {
        let handled = deepLinkHandler.handleDeepLink(url)
        
        if handled {
            flowState = .exchangingToken
        }
        
        return handled
    }
    
    /// Cancel the OAuth flow
    func cancelFlow() {
        logger.info("Canceling OAuth flow")
        
        oauthService.cancelAuthorization()
        flowState = .idle
        error = nil
    }
    
    /// Complete the OAuth flow with token response
    func completeFlow(with tokenResponse: TokenResponse) {
        logger.info("OAuth flow completed successfully")
        
        self.tokenResponse = tokenResponse
        flowState = .completed
    }
    
    /// Handle OAuth flow error
    func handleError(_ error: Error) {
        logger.error("OAuth flow error: \(error.localizedDescription)")
        
        self.error = error
        flowState = .failed
    }
}

// MARK: - OAuth Flow State

enum OAuthFlowState {
    case idle
    case authenticating
    case exchangingToken
    case completed
    case failed
    
    var description: String {
        switch self {
        case .idle:
            return "Ready to start"
        case .authenticating:
            return "Authenticating with Square"
        case .exchangingToken:
            return "Exchanging authorization code"
        case .completed:
            return "Authentication completed"
        case .failed:
            return "Authentication failed"
        }
    }
    
    var isInProgress: Bool {
        switch self {
        case .authenticating, .exchangingToken:
            return true
        default:
            return false
        }
    }
}
