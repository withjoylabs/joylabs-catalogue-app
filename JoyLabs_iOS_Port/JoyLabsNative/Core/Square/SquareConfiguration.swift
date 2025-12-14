import Foundation
import OSLog

/// Square API configuration and constants
/// Ports the configuration from React Native config files
struct SquareConfiguration {
    
    // MARK: - Square API Configuration
    
    /// Square Application ID (Production)
    static let appId = "sq0idp-WFTYv3An7NPv6ovGFLld1Q"
    
    /// Square API Version (Latest as of 2025)
    static let apiVersion = "2025-10-16"
    
    /// Square API Base URL
    static let apiBaseURL = "https://connect.squareup.com"
    
    /// Square OAuth Scopes
    static let scopes = ["MERCHANT_PROFILE_READ", "ITEMS_READ", "ITEMS_WRITE"]
    
    // MARK: - Backend Configuration
    
    /// AWS Lambda Backend Base URL
    static let backendBaseURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production"
    
    /// Backend API Endpoints (OAuth only - catalog operations use direct Square API)
    struct Endpoints {
        static let registerState = "/api/auth/register-state"
        static let squareCallback = "/api/auth/square/callback"
        static let tokenExchange = "/api/auth/square/token"
        static let storeVerifier = "/api/auth/store-verifier"
        static let retrieveVerifier = "/api/auth/retrieve-verifier"
    }
    
    // MARK: - OAuth Configuration
    
    /// Deep link callback scheme
    static let callbackScheme = "joylabs"
    
    /// Deep link callback path
    static let callbackPath = "square-callback"
    
    /// Full callback URL for the app
    static let appCallbackURL = "\(callbackScheme)://\(callbackPath)"
    
    /// Square redirect URI (backend endpoint)
    static let squareRedirectURI = "\(backendBaseURL)\(Endpoints.squareCallback)"
    
    /// PKCE configuration
    static let codeChallengeMethod = "S256"
    
    // MARK: - AWS Configuration
    
    /// AWS Secrets Manager secret name
    static let secretName = "square-credentials-production"
    
    /// AWS Region
    static let awsRegion = "us-west-1"
    
    // MARK: - Request Configuration

    /// Default timeout for API requests (fast timeout for connection issues)
    static let requestTimeout: TimeInterval = 10.0

    /// Token exchange timeout (fast timeout for connection issues)
    static let tokenExchangeTimeout: TimeInterval = 10.0
    
    /// User Agent for API requests
    static let userAgent = "JoyLabsApp/1.0.0"
    
    // MARK: - Catalog Sync Configuration
    
    /// Object types to sync from Square
    static let catalogObjectTypes = "ITEM,CATEGORY,ITEM_VARIATION,MODIFIER,MODIFIER_LIST,TAX,DISCOUNT,IMAGE"
    
    /// Default page size for catalog sync
    static let defaultPageSize = 1000
    
    /// Maximum retry attempts for API calls
    static let maxRetryAttempts = 3
    
    /// Base delay for exponential backoff (seconds)
    static let baseRetryDelay: TimeInterval = 1.0
    
    /// Maximum delay for exponential backoff (seconds)
    static let maxRetryDelay: TimeInterval = 30.0
    
    // MARK: - Helper Methods
    
    /// Build Square authorization URL
    static func buildAuthorizationURL(
        codeChallenge: String,
        state: String,
        appCallback: String
    ) -> URL? {
        var components = URLComponents(string: "\(apiBaseURL)/oauth2/authorize")
        
        var queryItems = [
            URLQueryItem(name: "client_id", value: appId),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: squareRedirectURI)
        ]
        
        // Add app callback as parameter for backend to use
        queryItems.append(URLQueryItem(name: "app_callback", value: appCallback))
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    /// Get standard Square API headers
    static func getStandardHeaders(accessToken: String? = nil) -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": userAgent,
            "Square-Version": apiVersion
        ]
        
        if let token = accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        return headers
    }
    
    /// Get backend API headers
    static func getBackendHeaders() -> [String: String] {
        return [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": userAgent
        ]
    }
    
    /// Validate configuration
    static func validateConfiguration() -> Bool {
        // Ensure all required configuration is present
        guard !appId.isEmpty,
              !apiVersion.isEmpty,
              !backendBaseURL.isEmpty,
              !scopes.isEmpty else {
            Logger(subsystem: "com.joylabs.native", category: "SquareConfig").error("Missing required Square configuration")
            return false
        }
        
        // Validate URLs
        guard URL(string: apiBaseURL) != nil,
              URL(string: backendBaseURL) != nil else {
            Logger(subsystem: "com.joylabs.native", category: "SquareConfig").error("Invalid URLs in Square configuration")
            return false
        }
        
        Logger(subsystem: "com.joylabs.native", category: "SquareConfig").info("Square configuration validated successfully")
        return true
    }
}

// MARK: - Square API Error Types

enum SquareAPIError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case noAccessToken
    case invalidResponse
    case authenticationFailed
    case rateLimitExceeded
    case serverError(Int)
    case clientError(Int)
    case apiError(Int, String)
    case networkError(Error)
    case decodingError(Error)
    case unknownError
    case objectNotFound(String)
    case upsertFailed(String)
    case deleteFailed(String)
    case versionConflict(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Square API configuration is invalid"
        case .invalidURL:
            return "Invalid URL for Square API request"
        case .noAccessToken:
            return "No valid access token available"
        case .invalidResponse:
            return "Invalid response from Square API"
        case .authenticationFailed:
            return "Square API authentication failed"
        case .rateLimitExceeded:
            return "Square API rate limit exceeded"
        case .serverError(let code):
            return "Square API server error: \(code)"
        case .clientError(let code):
            return "Square API client error: \(code)"
        case .apiError(let code, let message):
            return "Square API error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unknownError:
            return "Unknown Square API error"
        case .objectNotFound(let objectId):
            return "Catalog object not found: \(objectId)"
        case .upsertFailed(let reason):
            return "Failed to create or update catalog object: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete catalog object: \(reason)"
        case .versionConflict(let objectId):
            return "Version conflict for catalog object: \(objectId)"
        }
    }
}

// MARK: - Square API Response Models

struct SquareAPIResponse<T: Codable>: Codable {
    let data: T?
    let errors: [SquareError]?
    let cursor: String?
    
    var isSuccess: Bool {
        return errors?.isEmpty ?? true
    }
}

struct SquareError: Codable {
    let category: String
    let code: String
    let detail: String?
    let field: String?
}

struct SquareErrorResponse: Codable {
    let errors: [SquareError]
}

// MARK: - OAuth Response Models

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let merchantId: String?
    let businessName: String?
    let tokenType: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case merchantId = "merchant_id"
        case businessName = "business_name"
        case tokenType = "token_type"
    }
}

struct StateRegistrationRequest: Codable {
    let state: String
    let codeVerifier: String
    let appCallback: String
    
    enum CodingKeys: String, CodingKey {
        case state
        case codeVerifier = "code_verifier"
        case appCallback = "app_callback"
    }
}

struct TokenExchangeRequest: Codable {
    let code: String
    let codeVerifier: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier = "code_verifier"
    }
}
