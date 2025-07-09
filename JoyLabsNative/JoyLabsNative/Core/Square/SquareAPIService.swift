import Foundation
import OSLog

// Import TokenService from Core/Services
// Note: TokenService and TokenData are defined in Core/Services/TokenService.swift

// MARK: - Token Service Types
// Temporary forward declarations until import issues are resolved
// TODO: These should be imported from Core/Services/TokenService.swift

// Simple KeychainHelper for temporary use
class KeychainHelper {
    func store(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainError", code: Int(status), userInfo: nil)
        }
    }

    func retrieve(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw NSError(domain: "KeychainError", code: Int(status), userInfo: nil)
        }

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

class TokenService {
    private let keychain = KeychainHelper()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "TokenService")

    func ensureValidToken() async -> String? {
        // This will be implemented by the real TokenService
        do {
            let tokenData = try await getCurrentTokenData()
            if let accessToken = tokenData.accessToken, !accessToken.isEmpty {
                return accessToken
            }
        } catch {
            logger.error("Failed to get token data: \(error)")
        }
        return nil
    }

    func getCurrentTokenData() async throws -> TokenData {
        let accessToken = try? keychain.retrieve(forKey: "square_access_token")
        let refreshToken = try? keychain.retrieve(forKey: "square_refresh_token")
        let merchantId = try? keychain.retrieve(forKey: "square_merchant_id")
        let businessName = try? keychain.retrieve(forKey: "square_business_name")

        return TokenData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            merchantId: merchantId,
            businessName: businessName,
            expiresAt: nil
        )
    }

    func storeAuthData(accessToken: String, refreshToken: String?, merchantId: String, businessName: String?, expiresAt: Date?) async throws {
        try keychain.store(accessToken, forKey: "square_access_token")
        if let refreshToken = refreshToken {
            try keychain.store(refreshToken, forKey: "square_refresh_token")
        }
        try keychain.store(merchantId, forKey: "square_merchant_id")
        if let businessName = businessName {
            try keychain.store(businessName, forKey: "square_business_name")
        }
    }

    func clearTokens() async throws {
        // Clear all stored tokens
        let keys = ["square_access_token", "square_refresh_token", "square_merchant_id", "square_business_name", "square_token_expiry"]
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

struct TokenData {
    let accessToken: String?
    let refreshToken: String?
    let merchantId: String?
    let businessName: String?
    let expiresAt: Date?
}

// MARK: - Authentication State

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated
    case failed

    var isInProgress: Bool {
        return self == .authenticating
    }
}

// MARK: - Square API Response Models

/// Response type for /v2/catalog/list endpoint (per Square API documentation)
/// Reference: https://developer.squareup.com/reference/square/catalog-api/list-catalog
struct ListCatalogResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let errors: [SquareError]?

    enum CodingKeys: String, CodingKey {
        case objects
        case cursor
        case errors
    }
}

struct SquareCatalogSearchResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let relatedObjects: [CatalogObject]?
}

/// Comprehensive Square API service integrating OAuth, token management, and catalog operations
/// Provides high-level interface for all Square API interactions
@MainActor
class SquareAPIService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isAuthenticated = false
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var currentMerchant: MerchantInfo?
    @Published var lastSyncDate: Date?
    @Published var error: Error?
    
    // MARK: - Dependencies

    private let httpClient: SquareHTTPClient
    private let tokenService: TokenService
    private let oauthService: SquareOAuthService
    private let resilienceService: any ResilienceService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareAPIService")
    
    // MARK: - Initialization

    init() {
        self.resilienceService = BasicResilienceService()
        self.tokenService = SquareAPIServiceFactory.createTokenService()
        self.httpClient = SquareHTTPClient(tokenService: self.tokenService, resilienceService: BasicResilienceService())
        self.oauthService = SquareOAuthService(httpClient: self.httpClient, tokenService: self.tokenService)

        logger.info("SquareAPIService initialized with resilience integration")

        // Check initial authentication state
        Task {
            await checkAuthenticationState()
        }

        // Set up authentication state monitoring
        setupAuthenticationMonitoring()
        setupNotificationObservers()
    }

    private func setupAuthenticationMonitoring() {
        // Set up a simple callback-based approach instead of polling
        // This will be triggered when OAuth completes
    }

    private func setupNotificationObservers() {
        // Listen for OAuth completion notifications
        NotificationCenter.default.addObserver(
            forName: .squareAuthenticationCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.logger.info("Received OAuth completion notification")
                self?.isAuthenticated = true
                self?.authenticationState = .authenticated
                await self?.fetchMerchantInfo()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .squareAuthenticationFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.logger.error("Received OAuth failure notification")
                self?.isAuthenticated = false
                self?.authenticationState = .unauthenticated
                self?.currentMerchant = nil
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Authentication Methods

    private func fetchMerchantInfo() async {
        // Get merchant info from the OAuth service's last token response
        if let tokenResponse = oauthService.lastTokenResponse {
            currentMerchant = MerchantInfo(
                id: tokenResponse.merchantId ?? "unknown_merchant",
                businessName: tokenResponse.businessName ?? "Square Account"
            )
            logger.info("Merchant info fetched from OAuth response: \(tokenResponse.merchantId ?? "unknown")")
        } else {
            // Fallback if no token response available
            currentMerchant = MerchantInfo(
                id: "unknown_merchant",
                businessName: "Square Account"
            )
            logger.warning("No token response available, using fallback merchant info")
        }
    }

    /// Start Square OAuth authentication flow with resilience
    func authenticate() async throws {
        logger.info("Starting Square authentication with resilience")

        authenticationState = .authenticating
        error = nil

        do {
            let _: Void = try await resilienceService.executeResilient(
                operationId: "square_oauth_authentication",
                operation: {
                    // Start the actual OAuth flow
                    try await self.oauthService.startAuthorization()
                },
                fallback: (), // No fallback value for Void
                degradationStrategy: .returnCached
            )

            // Update authentication state based on OAuth result
            if oauthService.isAuthenticated {
                authenticationState = .authenticated
                isAuthenticated = true
                await fetchMerchantInfo()
            }
        } catch {
            logger.error("Authentication failed: \(error.localizedDescription)")
            authenticationState = .failed
            self.error = error
            throw error
        }
    }

    /// Check for cached authentication credentials
    private func checkCachedAuthentication() async {
        logger.info("Checking cached authentication")

        do {
            _ = try await tokenService.getCurrentTokenData()
            authenticationState = .authenticated
            isAuthenticated = true
            logger.info("Found valid cached authentication")
        } catch {
            logger.error("Error checking cached authentication: \(error.localizedDescription)")
            authenticationState = .unauthenticated
            isAuthenticated = false
            logger.info("No valid cached authentication found")
        }
    }

    /// Public method to check authentication state
    func checkAuthenticationState() async {
        await checkCachedAuthentication()
    }
    
    /// Handle deep link callback from OAuth flow
    func handleDeepLink(_ url: URL) -> Bool {
        logger.info("Handling OAuth deep link")

        // Temporarily return false until OAuth flow is implemented
        return false
    }
    
    /// Sign out and clear all stored data
    func signOut() async throws {
        logger.info("Signing out user")
        
        try await tokenService.clearTokens()
        
        isAuthenticated = false
        authenticationState = .unauthenticated
        currentMerchant = nil
        lastSyncDate = nil
        error = nil
        
        logger.info("User signed out successfully")
    }



    
    // MARK: - Catalog API Methods
    
    /// Fetch complete catalog from Square with resilience
    func fetchCatalog() async throws -> [CatalogObject] {
        logger.info("Fetching complete catalog from Square with resilience")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        return try await resilienceService.executeResilient(
            operationId: "square_catalog_fetch",
            operation: {
                return try await self.performCatalogFetch()
            },
            fallback: [], // Empty array as fallback
            degradationStrategy: .returnCached
        )
    }

    /// Perform the actual catalog fetch operation
    private func performCatalogFetch() async throws -> [CatalogObject] {
        var allObjects: [CatalogObject] = []
        var cursor: String?

        repeat {
            // Build query parameters
            var queryItems = [URLQueryItem]()

            // Add object types (comprehensive list covering all Square catalog objects)
            let objectTypes = SquareConfiguration.catalogObjectTypes
            queryItems.append(URLQueryItem(name: "types", value: objectTypes))

            // Add cursor for pagination
            if let cursor = cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }

            // Add limit for pagination (Square API default is 100, max is 1000)
            queryItems.append(URLQueryItem(name: "limit", value: String(SquareConfiguration.defaultPageSize)))

            // Build endpoint with query parameters
            let endpoint = buildEndpointWithQuery(
                base: "/v2/catalog/list",
                queryItems: queryItems
            )

            logger.debug("Making Square API request: GET \(endpoint)")

            let response = try await httpClient.makeSquareAPIRequest(
                endpoint: endpoint,
                method: .GET,
                body: nil,
                responseType: ListCatalogResponse.self
            )

            if let objects = response.objects {
                allObjects.append(contentsOf: objects)
                logger.debug("Fetched \(objects.count) objects in this page, total: \(allObjects.count)")
            }

            cursor = response.cursor

        } while cursor != nil

        logger.info("Fetched \(allObjects.count) catalog objects")
        lastSyncDate = Date()

        return allObjects
    }

    /// Build endpoint URL with query parameters
    private func buildEndpointWithQuery(base: String, queryItems: [URLQueryItem]) -> String {
        guard !queryItems.isEmpty else { return base }

        var components = URLComponents()
        components.queryItems = queryItems

        if let queryString = components.query {
            return "\(base)?\(queryString)"
        }

        return base
    }

    /// Get cached catalog data as fallback
    private func getCachedCatalog() async -> [CatalogObject] {
        logger.info("Using cached catalog data as fallback")
        // This would integrate with the database manager to get cached data
        return []
    }
    
    /// Search catalog objects with timestamp filter
    func searchCatalog(beginTime: String? = nil) async throws -> [CatalogObject] {
        logger.info("Searching catalog with beginTime: \(beginTime ?? "none")")
        
        guard isAuthenticated else {
            throw NSError(domain: "SquareAPIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }

        // Temporarily return empty response until HTTP client is implemented
        let response = SquareCatalogSearchResponse(objects: [], cursor: nil, relatedObjects: [])
        
        let objects = response.objects ?? []
        logger.info("Found \(objects.count) catalog objects")
        
        return objects
    }
    
    /// Sync catalog changes since last sync
    func syncCatalogChanges() async throws -> [CatalogObject] {
        logger.info("Syncing catalog changes since last sync")
        
        let beginTime = lastSyncDate?.iso8601String
        let objects = try await searchCatalog(beginTime: beginTime)
        
        if !objects.isEmpty {
            lastSyncDate = Date()
        }
        
        return objects
    }
    
    // MARK: - Merchant Information
    
    /// Get current merchant information
    func getMerchantInfo() async throws -> MerchantInfo {
        logger.info("Fetching merchant information")
        
        guard isAuthenticated else {
            throw NSError(domain: "SquareAPIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        
        // This would be implemented with actual Square API call
        // For now, return cached merchant info from token data
        if let merchant = currentMerchant {
            return merchant
        }
        
        let tokenData = try await tokenService.getCurrentTokenData()
        let merchantInfo = MerchantInfo(
            id: tokenData.merchantId ?? "unknown",
            businessName: tokenData.businessName ?? "Unknown Business"
        )
        
        currentMerchant = merchantInfo
        return merchantInfo
    }
    
    // MARK: - Private Implementation
    
    private func processOAuthCompletion() async {
        logger.debug("Processing OAuth completion")

        // Temporarily do nothing until OAuth flow is implemented
        logger.info("OAuth completion processing not implemented yet")
    }
    
    private func updateAuthenticatedState(_ tokenData: TokenData) async {
        isAuthenticated = true
        authenticationState = .authenticated
        
        currentMerchant = MerchantInfo(
            id: tokenData.merchantId ?? "unknown",
            businessName: tokenData.businessName ?? "Unknown Business"
        )
        
        logger.info("Updated authenticated state for merchant: \(self.currentMerchant?.businessName ?? "unknown")")
    }
}

// MARK: - Authentication State



// MARK: - Merchant Info Model

struct MerchantInfo: Codable, Identifiable {
    let id: String
    let businessName: String
    
    var displayName: String {
        return businessName.isEmpty ? "Unknown Business" : businessName
    }
}

// MARK: - Date Extensions

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}



// MARK: - Square API Service Extensions

extension SquareAPIService {
    
    /// Get authentication status summary
    var authenticationSummary: String {
        switch authenticationState {
        case .authenticated:
            return "Authenticated as \(self.currentMerchant?.displayName ?? "Unknown")"
        case .authenticating:
            return "Authenticating with Square..."
        case .failed:
            return "Authentication failed: \(error?.localizedDescription ?? "Unknown error")"
        case .unauthenticated:
            return "Not authenticated"
        }
    }
    
    /// Check if catalog sync is needed
    var needsCatalogSync: Bool {
        guard isAuthenticated else { return false }
        
        guard let lastSync = lastSyncDate else { return true }
        
        // Sync if last sync was more than 1 hour ago
        return Date().timeIntervalSince(lastSync) > 3600
    }
    
    /// Get time since last sync
    var timeSinceLastSync: String? {
        guard let lastSync = lastSyncDate else { return nil }
        
        let interval = Date().timeIntervalSince(lastSync)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
    }
}
