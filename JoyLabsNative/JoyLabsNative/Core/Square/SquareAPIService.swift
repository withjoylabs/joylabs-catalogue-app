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

// MARK: - Temporary Model Definitions (until proper models are added)

struct SquareCatalogResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let relatedObjects: [CatalogObject]?
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
        self.tokenService = TokenService()
        self.httpClient = SquareHTTPClient(tokenService: self.tokenService, resilienceService: BasicResilienceService())
        self.oauthService = SquareOAuthService(httpClient: self.httpClient)

        logger.info("SquareAPIService initialized with resilience integration")

        // Check initial authentication state
        Task {
            await checkAuthenticationState()
        }

        // Set up authentication state monitoring
        setupAuthenticationMonitoring()
    }

    private func setupAuthenticationMonitoring() {
        // Set up a simple callback-based approach instead of polling
        // This will be triggered when OAuth completes
    }

    // MARK: - Authentication Methods

    private func fetchMerchantInfo() async {
        do {
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
        } catch {
            logger.error("Failed to fetch merchant info: \(error.localizedDescription)")
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
            let response = try await httpClient.makeSquareAPIRequest(
                endpoint: "catalog/list",
                method: .GET,
                body: nil,
                responseType: SquareCatalogResponse.self
            )

            if let objects = response.objects {
                allObjects.append(contentsOf: objects)
            }

            cursor = response.cursor

        } while cursor != nil

        logger.info("Fetched \(allObjects.count) catalog objects")
        lastSyncDate = Date()

        return allObjects
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

// MARK: - Square API Service Factory

/// Factory for creating configured SquareAPIService instances
struct SquareAPIServiceFactory {
    
    @MainActor
    static func createService() -> SquareAPIService {
        return SquareAPIService()
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
