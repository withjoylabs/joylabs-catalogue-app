import Foundation
import os.log

/// Service for fetching and managing Square locations
/// Reference: https://developer.squareup.com/reference/square/locations-api
@MainActor
class SquareLocationsService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var locations: [SquareLocation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareLocations")
    
    // MARK: - Initialization
    
    init(squareAPIService: SquareAPIService = SquareAPIServiceFactory.shared.createAPIService()) {
        self.squareAPIService = squareAPIService
    }
    
    // MARK: - Public Methods
    
    func fetchLocations() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            logger.info("🏪 Fetching Square locations...")
            
            let fetchedLocations = try await squareAPIService.fetchLocations()
            
            self.locations = fetchedLocations
            logger.info("✅ Successfully fetched \(fetchedLocations.count) locations")
            
        } catch {
            logger.error("❌ Failed to fetch locations: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func refreshLocations() async {
        await fetchLocations()
    }
}

// MARK: - Square Location Models

struct SquareLocation: Codable, Identifiable {
    let id: String
    let name: String?
    let address: SquareAddress?
    let timezone: String?
    let capabilities: [String]?
    let status: String?
    let createdAt: String?
    let merchantId: String?
    let country: String?
    let languageCode: String?
    let currency: String?
    let phoneNumber: String?
    let businessName: String?
    let type: String?
    let websiteUrl: String?
    let businessHours: SquareBusinessHours?
    let businessEmail: String?
    let description: String?
    let twitterUsername: String?
    let instagramUsername: String?
    let facebookUrl: String?
    let coordinates: SquareCoordinates?
    let logoUrl: String?
    let posBackgroundUrl: String?
    let mcc: String?
    let fullFormatLogoUrl: String?
    let taxIds: SquareTaxIds?
    
    // Computed properties for UI display
    var displayName: String {
        return name ?? businessName ?? "Unnamed Location"
    }
    
    var isActive: Bool {
        return status?.uppercased() == "ACTIVE"
    }
    
    var formattedAddress: String {
        guard let address = address else { return "No address" }
        
        var components: [String] = []
        
        if let addressLine1 = address.addressLine1, !addressLine1.isEmpty {
            components.append(addressLine1)
        }
        
        if let locality = address.locality, !locality.isEmpty {
            components.append(locality)
        }
        
        if let administrativeDistrictLevel1 = address.administrativeDistrictLevel1, !administrativeDistrictLevel1.isEmpty {
            components.append(administrativeDistrictLevel1)
        }
        
        if let postalCode = address.postalCode, !postalCode.isEmpty {
            components.append(postalCode)
        }
        
        return components.joined(separator: ", ")
    }
}

struct SquareAddress: Codable {
    let addressLine1: String?
    let addressLine2: String?
    let addressLine3: String?
    let locality: String?
    let sublocality: String?
    let sublocality2: String?
    let sublocality3: String?
    let administrativeDistrictLevel1: String?
    let administrativeDistrictLevel2: String?
    let administrativeDistrictLevel3: String?
    let postalCode: String?
    let country: String?
    let firstName: String?
    let lastName: String?
}

struct SquareBusinessHours: Codable {
    let periods: [SquareBusinessPeriod]?
}

struct SquareBusinessPeriod: Codable {
    let dayOfWeek: String?
    let startLocalTime: String?
    let endLocalTime: String?
}

struct SquareCoordinates: Codable {
    let latitude: Double?
    let longitude: Double?
}

struct SquareTaxIds: Codable {
    let euVat: String?
    let frSiret: String?
    let frNaf: String?
    let esNif: String?
}

// MARK: - SquareAPIService Extension

extension SquareAPIService {
    
    func fetchLocations() async throws -> [SquareLocation] {
        let endpoint = "/v2/locations"
        
        let response: SquareLocationsResponse = try await makeRequest(
            endpoint: endpoint,
            method: "GET"
        )
        
        return response.locations ?? []
    }
}

// MARK: - Response Models

private struct SquareLocationsResponse: Codable {
    let locations: [SquareLocation]?
    let errors: [SquareAPIError]?
}
