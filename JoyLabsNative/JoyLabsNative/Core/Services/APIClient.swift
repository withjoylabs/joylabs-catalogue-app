import Foundation

/// APIClient - Handles HTTP requests to Square API and backend
/// Ports the sophisticated API client from React Native
class APIClient {
    // MARK: - Private Properties
    private let session: URLSession
    private let tokenService: TokenService
    private let baseURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production"
    
    // MARK: - Initialization
    init(tokenService: TokenService = TokenService()) {
        self.tokenService = tokenService
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    func fetchCatalogPage(cursor: String? = nil) async throws -> CatalogResponse {
        Logger.info("API", "Fetching catalog page with cursor: \(cursor ?? "none")")
        
        var components = URLComponents(string: "\(baseURL)/v2/catalog/list")!
        var queryItems: [URLQueryItem] = []
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        queryItems.append(URLQueryItem(name: "types", value: "ITEM,CATEGORY,ITEM_VARIATION,MODIFIER,MODIFIER_LIST,TAX,DISCOUNT"))
        components.queryItems = queryItems
        
        let request = try await buildAuthenticatedRequest(url: components.url!)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let catalogResponse = try JSONDecoder().decode(CatalogResponse.self, from: data)
        
        Logger.debug("API", "Fetched \(catalogResponse.objects?.count ?? 0) objects")
        
        return catalogResponse
    }
    
    func createItem(_ item: CreateItemRequest) async throws -> CatalogObject {
        Logger.info("API", "Creating new item: \(item.name ?? "unnamed")")
        
        let url = URL(string: "\(baseURL)/v2/catalog/object")!
        var request = try await buildAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = try JSONEncoder().encode(item)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let createResponse = try JSONDecoder().decode(CreateItemResponse.self, from: data)
        
        Logger.info("API", "Item created successfully: \(createResponse.catalogObject.id)")
        
        return createResponse.catalogObject
    }
    
    func updateItem(_ itemId: String, _ item: UpdateItemRequest) async throws -> CatalogObject {
        Logger.info("API", "Updating item: \(itemId)")
        
        let url = URL(string: "\(baseURL)/v2/catalog/object")!
        var request = try await buildAuthenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = try JSONEncoder().encode(item)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let updateResponse = try JSONDecoder().decode(UpdateItemResponse.self, from: data)
        
        Logger.info("API", "Item updated successfully: \(updateResponse.catalogObject.id)")
        
        return updateResponse.catalogObject
    }
    
    func getMerchantInfo() async throws -> MerchantInfo {
        Logger.info("API", "Fetching merchant info")
        
        let url = URL(string: "\(baseURL)/v2/merchants/me")!
        let request = try await buildAuthenticatedRequest(url: url)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let merchantResponse = try JSONDecoder().decode(MerchantResponse.self, from: data)
        
        Logger.debug("API", "Merchant info fetched successfully")
        
        return merchantResponse.merchant
    }
    
    // MARK: - Private Methods
    private func buildAuthenticatedRequest(url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        
        // Get valid token
        guard let token = await tokenService.ensureValidToken() else {
            throw APIError.notAuthenticated
        }
        
        // Add authentication header
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("JoyLabsApp/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-03-19", forHTTPHeaderField: "Square-Version")
        
        return request
    }
}

// MARK: - Supporting Types
enum APIError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpError(Int)
    case decodingError
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .networkError:
            return "Network error"
        }
    }
}

// Request/Response types (simplified for now)
struct CreateItemRequest: Codable {
    let name: String?
    let description: String?
    let categoryId: String?
}

struct UpdateItemRequest: Codable {
    let name: String?
    let description: String?
    let categoryId: String?
    let version: Int64
}

struct CreateItemResponse: Codable {
    let catalogObject: CatalogObject
    
    enum CodingKeys: String, CodingKey {
        case catalogObject = "catalog_object"
    }
}

struct UpdateItemResponse: Codable {
    let catalogObject: CatalogObject
    
    enum CodingKeys: String, CodingKey {
        case catalogObject = "catalog_object"
    }
}

struct MerchantResponse: Codable {
    let merchant: MerchantInfo
}

struct MerchantInfo: Codable {
    let id: String
    let businessName: String?
    let country: String?
    let languageCode: String?
    let currency: String?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case businessName = "business_name"
        case country
        case languageCode = "language_code"
        case currency
        case status
    }
}
