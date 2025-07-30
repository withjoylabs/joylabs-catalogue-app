import Foundation
import OSLog

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

    // MARK: - State Management
    private var isCheckingAuthentication = false
    
    // MARK: - Initialization

    init() {
        self.resilienceService = BasicResilienceService()
        self.tokenService = SquareAPIServiceFactory.createTokenService()
        self.httpClient = SquareAPIServiceFactory.createHTTPClient()
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
        logger.info("Starting Square authentication")

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
        logger.debug("Checking cached authentication")

        do {
            let tokenData = try await tokenService.getCurrentTokenData()
            
            // Check if we actually have a valid access token
            if let accessToken = tokenData.accessToken, !accessToken.isEmpty {
                // Also check if token is expired
                let isExpired = await tokenService.isTokenExpired(tokenData)
                if !isExpired {
                    authenticationState = .authenticated
                    isAuthenticated = true
                    logger.debug("Found valid cached authentication")
                } else {
                    logger.debug("Cached token is expired")
                    authenticationState = .unauthenticated
                    isAuthenticated = false
                }
            } else {
                logger.debug("No access token found in cached authentication")
                authenticationState = .unauthenticated
                isAuthenticated = false
            }
        } catch {
            logger.error("Error checking cached authentication: \(error.localizedDescription)")
            authenticationState = .unauthenticated
            isAuthenticated = false
            logger.debug("No valid cached authentication found")
        }
    }

    /// Public method to check authentication state
    func checkAuthenticationState() async {
        // Prevent duplicate simultaneous authentication checks
        guard !isCheckingAuthentication else {
            logger.debug("Authentication check already in progress, skipping")
            return
        }

        isCheckingAuthentication = true
        defer { isCheckingAuthentication = false }

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



    
    // MARK: - Generic API Methods

    /// Make a generic Square API request
    func makeAPIRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await httpClient.makeSquareAPIRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            responseType: responseType
        )
    }

    // MARK: - Catalog API Methods

    /// Fetch complete catalog from Square with resilience
    func fetchCatalog() async throws -> [CatalogObject] {
        logger.info("Fetching complete catalog from Square with resilience")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        // For catalog sync, we don't want fallback behavior - we need to fail fast on errors
        // so the sync can properly handle and report the failure
        return try await performCatalogFetch()
    }

    /// Fetch a specific catalog object by ID
    func fetchCatalogObjectById(
        _ objectId: String,
        includeRelatedObjects: Bool = true,
        catalogVersion: Int64? = nil
    ) async throws -> CatalogObject {
        logger.info("Fetching catalog object by ID: \(objectId)")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        let response = try await httpClient.fetchCatalogObjectById(
            objectId,
            includeRelatedObjects: includeRelatedObjects,
            catalogVersion: catalogVersion
        )

        guard let object = response.object else {
            throw SquareAPIError.objectNotFound(objectId)
        }

        logger.info("Successfully fetched catalog object: \(objectId)")
        return object
    }

    /// Create or update a catalog object
    func upsertCatalogObject(
        _ object: CatalogObject,
        idempotencyKey: String? = nil
    ) async throws -> CatalogObject {
        logger.info("Upserting catalog object: \(object.id) (type: \(object.type))")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        let requestKey = idempotencyKey ?? UUID().uuidString

        let response = try await httpClient.upsertCatalogObject(
            object,
            idempotencyKey: requestKey
        )

        guard let upsertedObject = response.catalogObject else {
            throw SquareAPIError.upsertFailed("No object returned from upsert operation")
        }

        // CRITICAL: Update catalog version after successful local CRUD operation
        // Since Square API doesn't return catalog_version, we set it to current time
        let catalogVersion = Date()
        try await SquareAPIServiceFactory.createDatabaseManager().saveCatalogVersion(catalogVersion)
        logger.info("📅 Updated catalog version after upsert: \(catalogVersion)")

        // DEDUPLICATION: Record this local operation to prevent processing webhooks for our own changes
        PushNotificationService.shared.recordLocalOperation(itemId: upsertedObject.id)

        logger.info("Successfully upserted catalog object: \(upsertedObject.id) (version: \(upsertedObject.safeVersion))")
        return upsertedObject
    }

    /// Create or update a catalog object (returns full response with ID mappings)
    func upsertCatalogObjectWithMappings(
        _ object: CatalogObject,
        idempotencyKey: String? = nil
    ) async throws -> UpsertCatalogObjectResponse {
        logger.info("Upserting catalog object with mappings: \(object.id) (type: \(object.type))")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        let requestKey = idempotencyKey ?? UUID().uuidString

        let response = try await httpClient.upsertCatalogObject(
            object,
            idempotencyKey: requestKey
        )

        guard let upsertedObject = response.catalogObject else {
            throw SquareAPIError.upsertFailed("No object returned from upsert operation")
        }

        // CRITICAL: Update catalog version after successful local CRUD operation
        let catalogVersion = Date()
        try await SquareAPIServiceFactory.createDatabaseManager().saveCatalogVersion(catalogVersion)
        logger.info("📅 Updated catalog version after upsert with mappings: \(catalogVersion)")

        // DEDUPLICATION: Record this local operation to prevent processing webhooks for our own changes
        PushNotificationService.shared.recordLocalOperation(itemId: upsertedObject.id)

        logger.info("Successfully upserted catalog object: \(upsertedObject.id) (version: \(upsertedObject.safeVersion))")

        if let mappings = response.idMappings, !mappings.isEmpty {
            logger.info("Received \(mappings.count) ID mappings from Square API")
        }

        return response
    }

    /// Delete a catalog object
    func deleteCatalogObject(_ objectId: String) async throws -> DeletedCatalogObject {
        logger.info("Deleting catalog object: \(objectId)")

        guard isAuthenticated else {
            throw SquareAPIError.authenticationFailed
        }

        let response = try await httpClient.deleteCatalogObject(objectId)

        guard let deletedObject = response.deletedObject else {
            throw SquareAPIError.deleteFailed("No deleted object information returned")
        }

        // CRITICAL: Update catalog version after successful local CRUD operation
        let catalogVersion = Date()
        try await SquareAPIServiceFactory.createDatabaseManager().saveCatalogVersion(catalogVersion)
        logger.info("📅 Updated catalog version after delete: \(catalogVersion)")

        // DEDUPLICATION: Record this local operation to prevent processing webhooks for our own changes
        PushNotificationService.shared.recordLocalOperation(itemId: objectId)

        logger.info("Successfully deleted catalog object: \(objectId) at \(deletedObject.deletedAt ?? "unknown time")")
        return deletedObject
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

        logger.debug("Fetched \(allObjects.count) catalog objects from Square API")

        // Validate that we got a reasonable number of objects
        // If we got 0 objects, this likely indicates an error condition
        if allObjects.isEmpty {
            logger.error("❌ Received 0 objects from Square API - this likely indicates an error")
            throw SquareAPIError.invalidResponse
        }

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

        // Use the HTTP client to perform the actual search
        let response = try await httpClient.searchCatalogObjects(beginTime: beginTime)
        
        let objects = response.objects ?? []
        logger.info("Found \(objects.count) catalog objects")
        
        return objects
    }
    
    /// Sync catalog changes since last sync with cursor pagination support
    func syncCatalogChanges() async throws -> [CatalogObject] {
        logger.info("Syncing catalog changes since last sync")
        
        let beginTime = lastSyncDate?.iso8601String
        var allObjects: [CatalogObject] = []
        var cursor: String?
        var pageCount = 0
        
        // Handle cursor pagination for catalogs with >1000 changed objects
        repeat {
            logger.info("Fetching page \(pageCount + 1) of catalog changes...")
            
            let response = try await httpClient.searchCatalogObjects(beginTime: beginTime, cursor: cursor)
            
            if let objects = response.objects {
                allObjects.append(contentsOf: objects)
                logger.info("Page \(pageCount + 1): fetched \(objects.count) objects, total: \(allObjects.count)")
            }
            
            cursor = response.cursor
            pageCount += 1
            
            // Safety check to prevent infinite loops
            if pageCount > 100 {
                logger.error("Too many pages (>100) in catalog sync - possible API issue")
                break
            }
            
        } while cursor != nil
        
        logger.info("✅ Fetched \(allObjects.count) total changed objects across \(pageCount) pages")
        
        if !allObjects.isEmpty {
            lastSyncDate = Date()
        }
        
        return allObjects
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
