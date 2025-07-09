import Foundation
import CryptoKit
import OSLog

/// PKCE (Proof Key for Code Exchange) generator for OAuth 2.0 security
/// Implements RFC 7636 with S256 challenge method for secure authorization
struct PKCEGenerator {
    
    private static let logger = Logger(subsystem: "com.joylabs.native", category: "PKCEGenerator")
    
    // MARK: - PKCE Generation
    
    /// Generate PKCE code verifier and challenge pair
    /// Returns tuple of (codeVerifier, codeChallenge) for OAuth flow
    static func generatePKCEPair() -> (codeVerifier: String, codeChallenge: String) {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        logger.debug("Generated PKCE pair - verifier length: \(codeVerifier.count), challenge length: \(codeChallenge.count)")
        
        return (codeVerifier: codeVerifier, codeChallenge: codeChallenge)
    }
    
    /// Generate cryptographically secure code verifier
    /// RFC 7636: 43-128 characters, URL-safe base64 encoded
    private static func generateCodeVerifier() -> String {
        // Generate 32 random bytes (256 bits) for high entropy
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let data = Data(randomBytes)
        
        // Base64 URL-safe encoding without padding
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Generate code challenge from verifier using S256 method
    /// RFC 7636: SHA256 hash of verifier, base64 URL-safe encoded
    private static func generateCodeChallenge(from verifier: String) -> String {
        guard let verifierData = verifier.data(using: .utf8) else {
            logger.error("Failed to convert code verifier to data")
            fatalError("Invalid code verifier encoding")
        }
        
        // SHA256 hash of the verifier
        let hash = SHA256.hash(data: verifierData)
        let hashData = Data(hash)
        
        // Base64 URL-safe encoding without padding
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Generate cryptographically secure state parameter
    /// Used to prevent CSRF attacks in OAuth flow
    static func generateState() -> String {
        // Generate 16 random bytes (128 bits) for state
        let randomBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let data = Data(randomBytes)
        
        // Hex encoding for simplicity and URL safety
        return data.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Validate PKCE parameters
    static func validatePKCEParameters(codeVerifier: String, codeChallenge: String) -> Bool {
        // Validate code verifier length (43-128 characters per RFC 7636)
        guard codeVerifier.count >= 43 && codeVerifier.count <= 128 else {
            logger.error("Invalid code verifier length: \(codeVerifier.count)")
            return false
        }
        
        // Validate code challenge length (should be 43 characters for S256)
        guard codeChallenge.count == 43 else {
            logger.error("Invalid code challenge length: \(codeChallenge.count)")
            return false
        }
        
        // Validate that challenge matches verifier
        let expectedChallenge = generateCodeChallenge(from: codeVerifier)
        guard codeChallenge == expectedChallenge else {
            logger.error("Code challenge does not match verifier")
            return false
        }
        
        logger.debug("PKCE parameters validated successfully")
        return true
    }
}

// MARK: - OAuth State Management

/// Manages OAuth state and PKCE parameters during authorization flow
actor OAuthStateManager {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "OAuthStateManager")
    
    // MARK: - State Storage
    
    private var currentState: OAuthState?
    private let stateTimeout: TimeInterval = 600 // 10 minutes
    
    // MARK: - State Management
    
    /// Create new OAuth state with PKCE parameters
    func createOAuthState() -> OAuthState {
        let pkcePair = PKCEGenerator.generatePKCEPair()
        let state = PKCEGenerator.generateState()
        
        let oauthState = OAuthState(
            state: state,
            codeVerifier: pkcePair.codeVerifier,
            codeChallenge: pkcePair.codeChallenge,
            createdAt: Date(),
            appCallback: "joylabs://square-callback"
        )
        
        currentState = oauthState
        
        logger.info("Created OAuth state with ID: \(state)")
        return oauthState
    }
    
    /// Validate and retrieve OAuth state
    func validateOAuthState(_ stateId: String) -> OAuthState? {
        guard let state = currentState,
              state.state == stateId else {
            logger.warning("OAuth state validation failed - state not found or mismatch")
            return nil
        }
        
        // Check if state has expired
        let elapsed = Date().timeIntervalSince(state.createdAt)
        guard elapsed < stateTimeout else {
            logger.warning("OAuth state expired - elapsed: \(elapsed)s")
            currentState = nil
            return nil
        }
        
        logger.debug("OAuth state validated successfully")
        return state
    }
    
    /// Clear current OAuth state
    func clearOAuthState() {
        logger.debug("Clearing OAuth state")
        currentState = nil
    }
    
    /// Get current OAuth state (for debugging)
    func getCurrentState() -> OAuthState? {
        return currentState
    }
}

// MARK: - OAuth State Model

struct OAuthState {
    let state: String
    let codeVerifier: String
    let codeChallenge: String
    let createdAt: Date
    let appCallback: String
    
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 600 // 10 minutes
    }
    
    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }
}

// MARK: - OAuth URL Builder

struct OAuthURLBuilder {
    
    private static let logger = Logger(subsystem: "com.joylabs.native", category: "OAuthURLBuilder")
    
    /// Build complete Square authorization URL with all parameters
    static func buildAuthorizationURL(oauthState: OAuthState) -> URL? {
        // Temporarily hardcode URL building until SquareConfiguration is added
        var components = URLComponents(string: "https://connect.squareup.com/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: "sq0idp-WFTYv3An7NPv6ovGFLld1Q"),
            URLQueryItem(name: "scope", value: "MERCHANT_PROFILE_READ ITEMS_READ ITEMS_WRITE"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: oauthState.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: oauthState.state),
            URLQueryItem(name: "redirect_uri", value: "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/square/callback"),
            URLQueryItem(name: "app_callback", value: oauthState.appCallback)
        ]

        guard let url = components?.url else {
            logger.error("Failed to build authorization URL")
            return nil
        }
        
        logger.info("Built authorization URL with state: \(oauthState.state)")
        logger.debug("Authorization URL: \(url.absoluteString)")
        
        return url
    }
    
    /// Parse callback URL and extract authorization code and state
    static func parseCallbackURL(_ url: URL) -> CallbackResult? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("Failed to parse callback URL components")
            return nil
        }
        
        // Extract parameters from query items
        var code: String?
        var state: String?
        var error: String?
        var errorDescription: String?
        var accessToken: String?
        var refreshToken: String?
        var merchantId: String?
        var businessName: String?

        for item in queryItems {
            switch item.name {
            case "code":
                code = item.value
            case "state":
                state = item.value
            case "error":
                error = item.value
            case "error_description":
                errorDescription = item.value
            case "access_token":
                accessToken = item.value
            case "refresh_token":
                refreshToken = item.value
            case "merchant_id":
                merchantId = item.value
            case "business_name":
                businessName = item.value?.removingPercentEncoding
            default:
                break
            }
        }
        
        // Check for error response
        if let error = error {
            logger.error("OAuth callback error: \(error)")
            return .error(error, errorDescription)
        }

        // Check for direct token callback (new flow)
        if let accessToken = accessToken {
            logger.info("Direct token callback detected")
            return .directTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                merchantId: merchantId,
                businessName: businessName
            )
        }

        // Check for authorization code callback (original flow)
        if let authCode = code, let stateParam = state {
            logger.info("Authorization code callback detected - state: \(stateParam)")
            return .success(code: authCode, state: stateParam)
        }

        logger.error("Missing required parameters in callback URL")
        return .error("invalid_request", "Missing code/state or access_token parameters")
    }
}

// MARK: - Callback Result

enum CallbackResult {
    case success(code: String, state: String)
    case directTokens(accessToken: String, refreshToken: String?, merchantId: String?, businessName: String?)
    case error(String, String?)

    var isSuccess: Bool {
        switch self {
        case .success, .directTokens:
            return true
        case .error:
            return false
        }
    }
}

// MARK: - OAuth Errors

enum OAuthError: LocalizedError {
    case invalidState
    case stateExpired
    case missingParameters
    case authorizationDenied
    case invalidCallback
    case networkError(Error)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidState:
            return "Invalid OAuth state parameter"
        case .stateExpired:
            return "OAuth state has expired"
        case .missingParameters:
            return "Missing required OAuth parameters"
        case .authorizationDenied:
            return "User denied authorization"
        case .invalidCallback:
            return "Invalid callback URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
