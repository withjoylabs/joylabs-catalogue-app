import Foundation
import OSLog

// MARK: - ResilienceService Protocol

protocol ResilienceService {
    func executeResilient<T>(
        operationId: String,
        operation: @escaping () async throws -> T,
        fallback: T?,
        degradationStrategy: DegradationStrategy
    ) async throws -> T
}

// DegradationStrategy is already defined in CircuitBreaker.swift

// MARK: - Basic ResilienceService Implementation

actor BasicResilienceService: ResilienceService {
    func executeResilient<T>(
        operationId: String,
        operation: @escaping () async throws -> T,
        fallback: T?,
        degradationStrategy: DegradationStrategy
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            switch degradationStrategy {
            case .returnCached, .returnDefault:
                if let fallback = fallback {
                    return fallback
                }
                throw error
            case .skipOperation, .useAlternativeService:
                throw error
            }
        }
    }
}

/// Comprehensive HTTP client for Square API and backend integration
/// Ports the sophisticated API client from React Native with modern iOS patterns
actor SquareHTTPClient {
    
    // MARK: - Dependencies
    
    private let session: URLSession
    private let tokenService: TokenService
    private let resilienceService: ResilienceService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareHTTPClient")
    
    // MARK: - Configuration
    
    private let configuration: SquareConfiguration.Type
    
    // MARK: - Initialization
    
    init(
        tokenService: TokenService,
        resilienceService: ResilienceService? = nil,
        configuration: SquareConfiguration.Type = SquareConfiguration.self
    ) {
        self.tokenService = tokenService
        self.resilienceService = resilienceService ?? BasicResilienceService()
        self.configuration = configuration
        
        // Configure URLSession with timeouts and caching
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.requestTimeout
        config.timeoutIntervalForResource = configuration.requestTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024, // 10MB memory cache
            diskCapacity: 50 * 1024 * 1024,   // 50MB disk cache
            diskPath: "square_api_cache"
        )
        
        self.session = URLSession(configuration: config)
        
        logger.info("SquareHTTPClient initialized with configuration")
    }
    
    // MARK: - Public API Methods
    
    /// Make authenticated request to Square API directly
    func makeSquareAPIRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        return try await resilienceService.executeResilient(
            operationId: "square_api_\(endpoint)",
            operation: {
                try await self.performSquareAPIRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    responseType: responseType
                )
            },
            fallback: nil as T?,
            degradationStrategy: .returnCached
        )
    }
    
    /// Make request to backend Lambda proxy
    func makeBackendRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type,
        requiresAuth: Bool = true
    ) async throws -> T {
        return try await resilienceService.executeResilient(
            operationId: "backend_\(endpoint)",
            operation: {
                try await self.performBackendRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    responseType: responseType,
                    requiresAuth: requiresAuth
                )
            },
            fallback: nil as T?,
            degradationStrategy: .returnDefault
        )
    }
    
    /// Exchange authorization code for tokens
    func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenResponse {
        logger.info("Exchanging authorization code for tokens")
        
        let request = TokenExchangeRequest(code: code, codeVerifier: codeVerifier)
        let requestData = try JSONEncoder().encode(request)
        
        return try await makeBackendRequest(
            endpoint: configuration.Endpoints.tokenExchange,
            method: .POST,
            body: requestData,
            responseType: TokenResponse.self,
            requiresAuth: false
        )
    }
    
    /// Register OAuth state with backend
    func registerState(state: String, codeVerifier: String, appCallback: String) async throws {
        logger.info("Registering OAuth state with backend")
        
        let request = StateRegistrationRequest(
            state: state,
            codeVerifier: codeVerifier,
            appCallback: appCallback
        )
        let requestData = try JSONEncoder().encode(request)
        
        let _: EmptyResponse = try await makeBackendRequest(
            endpoint: configuration.Endpoints.registerState,
            method: .POST,
            body: requestData,
            responseType: EmptyResponse.self,
            requiresAuth: false
        )
    }
    
    /// Fetch catalog page from Square API
    func fetchCatalogPage(cursor: String? = nil, types: String? = nil) async throws -> CatalogResponse {
        logger.debug("Fetching catalog page with cursor: \(cursor ?? "none")")
        
        var queryItems = [URLQueryItem]()
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        let objectTypes = types ?? configuration.catalogObjectTypes
        queryItems.append(URLQueryItem(name: "types", value: objectTypes))
        
        let endpoint = buildEndpointWithQuery(
            base: configuration.Endpoints.catalogList,
            queryItems: queryItems
        )
        
        return try await makeBackendRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: CatalogResponse.self
        )
    }
    
    /// Search catalog objects with timestamp filter
    func searchCatalogObjects(beginTime: String? = nil) async throws -> CatalogSearchResponse {
        logger.debug("Searching catalog objects with beginTime: \(beginTime ?? "none")")
        
        var queryItems = [URLQueryItem]()
        
        if let beginTime = beginTime {
            queryItems.append(URLQueryItem(name: "begin_time", value: beginTime))
        }
        
        let endpoint = buildEndpointWithQuery(
            base: configuration.Endpoints.catalogSearch,
            queryItems: queryItems
        )
        
        return try await makeBackendRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: CatalogSearchResponse.self
        )
    }
    
    /// Refresh access token
    func refreshToken(refreshToken: String) async throws -> TokenResponse {
        logger.info("Refreshing access token")
        
        let url = URL(string: "\(configuration.apiBaseURL)/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.tokenExchangeTimeout
        
        // Set headers
        for (key, value) in configuration.getStandardHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Build request body
        let body = [
            "client_id": configuration.appId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SquareAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            logger.error("Token refresh failed with status: \(httpResponse.statusCode)")
            throw SquareAPIError.authenticationFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        logger.info("Token refresh successful")
        
        return tokenResponse
    }
    
    // MARK: - Private Implementation
    
    private func performSquareAPIRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T {
        // Get valid access token
        guard let accessToken = await tokenService.ensureValidToken() else {
            throw SquareAPIError.noAccessToken
        }
        
        // Build URL
        guard let url = URL(string: "\(configuration.apiBaseURL)\(endpoint)") else {
            throw SquareAPIError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.requestTimeout
        
        // Set headers
        for (key, value) in configuration.getStandardHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Set body if provided
        if let body = body {
            request.httpBody = body
        }
        
        logger.debug("Making Square API request: \(method.rawValue) \(endpoint)")
        
        // Perform request
        let (data, response) = try await session.data(for: request)
        
        return try handleResponse(data: data, response: response, responseType: responseType)
    }
    
    private func performBackendRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type,
        requiresAuth: Bool
    ) async throws -> T {
        // Build URL
        guard let url = URL(string: "\(configuration.backendBaseURL)\(endpoint)") else {
            throw SquareAPIError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.requestTimeout
        
        // Set headers
        var headers = configuration.getBackendHeaders()
        
        // Add authentication if required
        if requiresAuth {
            guard let accessToken = await tokenService.ensureValidToken() else {
                throw SquareAPIError.noAccessToken
            }
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Set body if provided
        if let body = body {
            request.httpBody = body
        }
        
        logger.debug("Making backend request: \(method.rawValue) \(endpoint)")
        
        // Perform request
        let (data, response) = try await session.data(for: request)
        
        return try handleResponse(data: data, response: response, responseType: responseType)
    }
    
    private func handleResponse<T: Codable>(
        data: Data,
        response: URLResponse,
        responseType: T.Type
    ) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SquareAPIError.invalidResponse
        }
        
        logger.debug("Received response with status: \(httpResponse.statusCode)")
        
        // Handle different status codes
        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode response
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(responseType, from: data)
            } catch {
                logger.error("Failed to decode response: \(error)")
                throw SquareAPIError.decodingError(error)
            }
            
        case 401:
            throw SquareAPIError.authenticationFailed
            
        case 429:
            throw SquareAPIError.rateLimitExceeded
            
        case 500...599:
            throw SquareAPIError.serverError(httpResponse.statusCode)
            
        default:
            logger.error("Unexpected status code: \(httpResponse.statusCode)")
            throw SquareAPIError.unknownError
        }
    }
    
    private func buildEndpointWithQuery(base: String, queryItems: [URLQueryItem]) -> String {
        guard !queryItems.isEmpty else { return base }
        
        var components = URLComponents()
        components.path = base
        components.queryItems = queryItems
        
        return components.url?.absoluteString ?? base
    }
}

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

// MARK: - Response Models

struct EmptyResponse: Codable {
    // Empty response for endpoints that don't return data
}

struct CatalogResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let relatedObjects: [CatalogObject]?
    
    enum CodingKeys: String, CodingKey {
        case objects
        case cursor
        case relatedObjects = "related_objects"
    }
}

struct CatalogSearchResponse: Codable {
    let objects: [CatalogObject]?
    let cursor: String?
    let relatedObjects: [CatalogObject]?
    
    enum CodingKeys: String, CodingKey {
        case objects
        case cursor
        case relatedObjects = "related_objects"
    }
}

// CatalogObject is defined in SearchModels.swift - using that definition

// MARK: - Catalog Data Models (Basic structure for now)

struct CatalogItemData: Codable {
    let name: String?
    let description: String?
    let categoryId: String?
    let variations: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, description
        case categoryId = "category_id"
        case variations
    }
}

struct CatalogCategoryData: Codable {
    let name: String?
    let parentCategoryId: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case parentCategoryId = "parent_category_id"
    }
}

struct CatalogItemVariationData: Codable {
    let itemId: String?
    let name: String?
    let sku: String?
    let upc: String?
    let priceMoney: Money?
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case name, sku, upc
        case priceMoney = "price_money"
    }
}

struct CatalogModifierData: Codable {
    let name: String?
    let priceMoney: Money?
    
    enum CodingKeys: String, CodingKey {
        case name
        case priceMoney = "price_money"
    }
}

struct CatalogModifierListData: Codable {
    let name: String?
    let modifiers: [String]?
}

struct CatalogTaxData: Codable {
    let name: String?
    let percentage: String?
}

struct CatalogDiscountData: Codable {
    let name: String?
    let percentage: String?
    let amountMoney: Money?
    
    enum CodingKeys: String, CodingKey {
        case name, percentage
        case amountMoney = "amount_money"
    }
}

struct CatalogImageData: Codable {
    let name: String?
    let url: String?
}

// Money is defined in SearchModels.swift - using that definition
