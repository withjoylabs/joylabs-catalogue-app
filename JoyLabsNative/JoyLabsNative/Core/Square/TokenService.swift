import Foundation
import Security
import OSLog

/// Secure token storage and management service using iOS Keychain
/// Handles access tokens, refresh tokens, and automatic token refresh
actor TokenService {
    
    // MARK: - Dependencies
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "TokenService")
    private let keychain: KeychainService
    private let httpClient: AnyObject? // Will be SquareHTTPClient when available
    
    // MARK: - Token State
    
    private var cachedTokens: TokenData?
    private var refreshTask: Task<TokenData, Error>?
    
    // MARK: - Configuration
    
    private let tokenRefreshThreshold: TimeInterval = 300 // 5 minutes before expiry
    
    // MARK: - Initialization
    
    init(keychain: KeychainService = KeychainService(), httpClient: AnyObject? = nil) {
        self.keychain = keychain
        self.httpClient = httpClient
        logger.info("TokenService initialized")
    }
    
    // MARK: - Public Token Management
    
    /// Store tokens securely in keychain
    func storeTokens(_ tokenResponse: [String: Any]) async throws {
        logger.info("Storing tokens in keychain")
        
        let tokenData = TokenData(
            accessToken: tokenResponse["access_token"] as? String ?? "",
            refreshToken: tokenResponse["refresh_token"] as? String,
            expiresAt: calculateExpiryDate(from: tokenResponse["expires_in"] as? Int),
            merchantId: tokenResponse["merchant_id"] as? String,
            businessName: tokenResponse["business_name"] as? String,
            tokenType: tokenResponse["token_type"] as? String ?? "Bearer"
        )
        
        try await keychain.storeTokenData(tokenData)
        cachedTokens = tokenData
        
        logger.info("Tokens stored successfully")
    }
    
    /// Get current access token, refreshing if necessary
    func ensureValidToken() async -> String? {
        do {
            let tokenData = try await getCurrentTokenData()
            
            // Check if token needs refresh
            if await needsRefresh(tokenData) {
                logger.debug("Token needs refresh, attempting refresh")
                let refreshedTokenData = try await refreshTokenIfNeeded(tokenData)
                return refreshedTokenData.accessToken
            }
            
            return tokenData.accessToken
            
        } catch {
            logger.error("Failed to ensure valid token: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get current token data
    func getCurrentTokenData() async throws -> TokenData {
        // Return cached tokens if available and valid
        if let cached = cachedTokens, !(await needsRefresh(cached)) {
            return cached
        }
        
        // Load from keychain
        let tokenData = try await keychain.loadTokenData()
        cachedTokens = tokenData
        
        return tokenData
    }
    
    /// Check if user is authenticated
    func isAuthenticated() async -> Bool {
        do {
            let _ = try await getCurrentTokenData()
            return true
        } catch {
            logger.debug("User not authenticated: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Clear all stored tokens
    func clearTokens() async throws {
        logger.info("Clearing all stored tokens")
        
        try await keychain.clearTokenData()
        cachedTokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        
        logger.info("Tokens cleared successfully")
    }
    
    /// Manually refresh tokens
    func refreshTokens() async throws -> TokenData {
        logger.info("Manually refreshing tokens")
        
        let currentTokenData = try await getCurrentTokenData()
        return try await performTokenRefresh(currentTokenData)
    }
    
    // MARK: - Private Implementation
    
    private func needsRefresh(_ tokenData: TokenData) async -> Bool {
        guard let expiresAt = tokenData.expiresAt else {
            // If no expiry date, assume token is still valid
            return false
        }
        
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow
        let needsRefresh = timeUntilExpiry <= tokenRefreshThreshold
        
        if needsRefresh {
            logger.debug("Token expires in \(timeUntilExpiry)s, needs refresh")
        }
        
        return needsRefresh
    }
    
    private func refreshTokenIfNeeded(_ tokenData: TokenData) async throws -> TokenData {
        // Check if refresh is already in progress
        if let existingTask = refreshTask {
            logger.debug("Token refresh already in progress, waiting for completion")
            return try await existingTask.value
        }
        
        // Start new refresh task
        let task = Task<TokenData, Error> {
            try await performTokenRefresh(tokenData)
        }
        
        refreshTask = task
        
        do {
            let refreshedTokenData = try await task.value
            refreshTask = nil
            return refreshedTokenData
        } catch {
            refreshTask = nil
            throw error
        }
    }
    
    private func performTokenRefresh(_ tokenData: TokenData) async throws -> TokenData {
        guard let refreshToken = tokenData.refreshToken else {
            logger.error("No refresh token available")
            throw TokenError.noRefreshToken
        }
        
        // Temporarily disable token refresh until HTTP client is available
        logger.error("Token refresh not implemented yet")
        throw TokenError.refreshFailed(NSError(domain: "TokenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token refresh not implemented"]))
        
        // This will be implemented when HTTP client is available
        fatalError("Token refresh not implemented")
    }
    
    private func calculateExpiryDate(from expiresIn: Int?) -> Date? {
        guard let expiresIn = expiresIn else { return nil }
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

// MARK: - Token Data Model

struct TokenData: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let merchantId: String?
    let businessName: String?
    let tokenType: String
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
    
    var timeUntilExpiry: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return expiresAt.timeIntervalSinceNow
    }
}

// MARK: - Keychain Service

actor KeychainService {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "KeychainService")
    
    // MARK: - Keychain Configuration
    
    private let service = "com.joylabs.native.square"
    private let accessTokenKey = "square_access_token"
    private let tokenDataKey = "square_token_data"
    
    // MARK: - Token Storage
    
    func storeTokenData(_ tokenData: TokenData) async throws {
        logger.debug("Storing token data in keychain")
        
        let data = try JSONEncoder().encode(tokenData)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenDataKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to store token data: \(status)")
            throw KeychainError.storeFailed(status)
        }
        
        logger.debug("Token data stored successfully")
    }
    
    func loadTokenData() async throws -> TokenData {
        logger.debug("Loading token data from keychain")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenDataKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                logger.debug("No token data found in keychain")
                throw TokenError.noTokensStored
            } else {
                logger.error("Failed to load token data: \(status)")
                throw KeychainError.loadFailed(status)
            }
        }
        
        guard let data = result as? Data else {
            logger.error("Invalid token data format in keychain")
            throw KeychainError.invalidData
        }
        
        do {
            let tokenData = try JSONDecoder().decode(TokenData.self, from: data)
            logger.debug("Token data loaded successfully")
            return tokenData
        } catch {
            logger.error("Failed to decode token data: \(error)")
            throw KeychainError.decodingFailed(error)
        }
    }
    
    func clearTokenData() async throws {
        logger.debug("Clearing token data from keychain")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenDataKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to clear token data: \(status)")
            throw KeychainError.deleteFailed(status)
        }
        
        logger.debug("Token data cleared successfully")
    }
}

// MARK: - Error Types

enum TokenError: LocalizedError {
    case noTokensStored
    case noRefreshToken
    case noHTTPClient
    case refreshFailed(Error)
    case invalidTokenData
    
    var errorDescription: String? {
        switch self {
        case .noTokensStored:
            return "No authentication tokens stored"
        case .noRefreshToken:
            return "No refresh token available"
        case .noHTTPClient:
            return "HTTP client not configured"
        case .refreshFailed(let error):
            return "Token refresh failed: \(error.localizedDescription)"
        case .invalidTokenData:
            return "Invalid token data"
        }
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    case decodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store in keychain: \(status)"
        case .loadFailed(let status):
            return "Failed to load from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .invalidData:
            return "Invalid keychain data format"
        case .decodingFailed(let error):
            return "Failed to decode keychain data: \(error.localizedDescription)"
        }
    }
}
