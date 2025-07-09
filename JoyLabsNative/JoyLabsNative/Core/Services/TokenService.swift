import Foundation
import Security

/// TokenService - Handles secure token storage and management
/// Ports the sophisticated token management from React Native
class TokenService {
    // MARK: - Private Properties
    private let keychain = KeychainHelper()
    
    // Token storage keys (port from React Native)
    private enum Keys {
        static let accessToken = "square_access_token"
        static let refreshToken = "square_refresh_token"
        static let merchantId = "square_merchant_id"
        static let businessName = "square_business_name"
        static let tokenExpiry = "square_token_expiry"
        static let codeVerifier = "square_code_verifier"
        static let state = "square_state"
    }
    
    // MARK: - Token Management
    func storeAuthData(
        accessToken: String,
        refreshToken: String?,
        merchantId: String?,
        businessName: String?,
        expiresIn: Int? = nil
    ) async throws {
        Logger.info("TokenService", "Storing authentication data")
        
        // Store access token
        try keychain.store(accessToken, forKey: Keys.accessToken)
        
        // Store refresh token if available
        if let refreshToken = refreshToken {
            try keychain.store(refreshToken, forKey: Keys.refreshToken)
        }
        
        // Store merchant info if available
        if let merchantId = merchantId {
            try keychain.store(merchantId, forKey: Keys.merchantId)
        }
        
        if let businessName = businessName {
            try keychain.store(businessName, forKey: Keys.businessName)
        }
        
        // Calculate and store expiry time
        if let expiresIn = expiresIn {
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            let expiryString = ISO8601DateFormatter().string(from: expiryDate)
            try keychain.store(expiryString, forKey: Keys.tokenExpiry)
        }
        
        Logger.info("TokenService", "Authentication data stored successfully")
    }
    
    func getTokenInfo() async -> TokenInfo {
        let accessToken = try? keychain.retrieve(forKey: Keys.accessToken)
        let refreshToken = try? keychain.retrieve(forKey: Keys.refreshToken)
        let merchantId = try? keychain.retrieve(forKey: Keys.merchantId)
        let businessName = try? keychain.retrieve(forKey: Keys.businessName)
        let expiryString = try? keychain.retrieve(forKey: Keys.tokenExpiry)
        
        let status = checkTokenStatus(accessToken: accessToken, expiryString: expiryString)
        
        return TokenInfo(
            accessToken: accessToken,
            refreshToken: refreshToken,
            merchantId: merchantId,
            businessName: businessName,
            expiresAt: expiryString,
            status: status
        )
    }
    
    func ensureValidToken() async -> String? {
        let tokenInfo = await getTokenInfo()
        
        switch tokenInfo.status {
        case .valid:
            return tokenInfo.accessToken
            
        case .expired:
            // Try to refresh token
            if let refreshToken = tokenInfo.refreshToken {
                return await refreshToken(refreshToken)
            } else {
                Logger.warn("TokenService", "Token expired and no refresh token available")
                return nil
            }
            
        case .missing:
            Logger.info("TokenService", "No token available")
            return nil
            
        case .unknown:
            // Try to use existing token
            return tokenInfo.accessToken
        }
    }
    
    func clearAuthData() async throws {
        Logger.info("TokenService", "Clearing all authentication data")
        
        try keychain.delete(forKey: Keys.accessToken)
        try keychain.delete(forKey: Keys.refreshToken)
        try keychain.delete(forKey: Keys.merchantId)
        try keychain.delete(forKey: Keys.businessName)
        try keychain.delete(forKey: Keys.tokenExpiry)
        
        Logger.info("TokenService", "Authentication data cleared")
    }
    
    // MARK: - PKCE Management
    func storePKCEValues(codeVerifier: String, state: String) async throws {
        try keychain.store(codeVerifier, forKey: Keys.codeVerifier)
        try keychain.store(state, forKey: Keys.state)
        
        Logger.debug("TokenService", "PKCE values stored")
    }
    
    func getStoredCodeVerifier() async throws -> String {
        guard let codeVerifier = try? keychain.retrieve(forKey: Keys.codeVerifier) else {
            throw TokenError.missingCodeVerifier
        }
        return codeVerifier
    }
    
    func getStoredState() async throws -> String {
        guard let state = try? keychain.retrieve(forKey: Keys.state) else {
            throw TokenError.missingState
        }
        return state
    }
    
    func clearPKCEValues() async throws {
        try keychain.delete(forKey: Keys.codeVerifier)
        try keychain.delete(forKey: Keys.state)
        
        Logger.debug("TokenService", "PKCE values cleared")
    }
    
    // MARK: - Private Methods
    private func checkTokenStatus(accessToken: String?, expiryString: String?) -> TokenStatus {
        guard let accessToken = accessToken, !accessToken.isEmpty else {
            return .missing
        }
        
        guard let expiryString = expiryString,
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            return .unknown
        }
        
        // Check if token will expire in the next 5 minutes
        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
        
        if expiryDate < fiveMinutesFromNow {
            return .expired
        }
        
        return .valid
    }
    
    private func refreshToken(_ refreshToken: String) async -> String? {
        Logger.info("TokenService", "Attempting to refresh access token")
        
        do {
            // Call refresh endpoint (port from React Native)
            let url = URL(string: "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/refresh")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["refresh_token": refreshToken]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.error("TokenService", "Token refresh failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            
            let refreshResponse = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
            
            // Store new token data
            try await storeAuthData(
                accessToken: refreshResponse.accessToken,
                refreshToken: refreshResponse.refreshToken,
                merchantId: refreshResponse.merchantId,
                businessName: refreshResponse.businessName,
                expiresIn: refreshResponse.expiresIn
            )
            
            Logger.info("TokenService", "Token refreshed successfully")
            return refreshResponse.accessToken
            
        } catch {
            Logger.error("TokenService", "Token refresh failed: \(error)")
            return nil
        }
    }
}

// MARK: - Supporting Types
struct TokenInfo {
    let accessToken: String?
    let refreshToken: String?
    let merchantId: String?
    let businessName: String?
    let expiresAt: String?
    let status: TokenStatus
}

enum TokenStatus {
    case valid
    case expired
    case missing
    case unknown
}

enum TokenError: LocalizedError {
    case missingCodeVerifier
    case missingState
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .missingCodeVerifier:
            return "Code verifier not found"
        case .missingState:
            return "OAuth state not found"
        case .storageError:
            return "Token storage error"
        }
    }
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let merchantId: String?
    let businessName: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case merchantId = "merchant_id"
        case businessName = "business_name"
        case expiresIn = "expires_in"
    }
}

// MARK: - Keychain Helper
private class KeychainHelper {
    func store(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Use more persistent accessibility for development
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            // Add service identifier for better isolation
            kSecAttrService as String: "com.joylabs.native.tokens"
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            Logger.error("TokenService", "Failed to store keychain item: \(status)")
            throw TokenError.storageError
        }

        Logger.debug("TokenService", "Successfully stored keychain item for key: \(key)")
    }
    
    func retrieve(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.joylabs.native.tokens",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                Logger.debug("TokenService", "No keychain item found for key: \(key)")
                return nil
            }
            Logger.error("TokenService", "Failed to retrieve keychain item: \(status)")
            throw TokenError.storageError
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            Logger.error("TokenService", "Failed to decode keychain data for key: \(key)")
            throw TokenError.storageError
        }

        Logger.debug("TokenService", "Successfully retrieved keychain item for key: \(key)")
        return string
    }
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.joylabs.native.tokens"
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Don't throw error if item doesn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.error("TokenService", "Failed to delete keychain item: \(status)")
            throw TokenError.storageError
        }

        Logger.debug("TokenService", "Successfully deleted keychain item for key: \(key)")
    }
}
