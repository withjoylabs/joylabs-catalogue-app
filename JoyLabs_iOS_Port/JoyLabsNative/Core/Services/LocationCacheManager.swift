import Foundation
import SwiftUI
import OSLog

/// Global location cache manager for app-wide location data
/// Eliminates wasteful HTTP calls by caching locations from Square API
@MainActor
class LocationCacheManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LocationCacheManager()
    
    // MARK: - Published Properties
    
    @Published var locations: [LocationData] = []
    @Published var isLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date?
    @Published var error: Error?
    
    // MARK: - Dependencies
    
    private let squareAPIService: SquareAPIService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "LocationCacheManager")
    
    // MARK: - Cache Configuration
    
    /// How long to cache locations before refreshing (24 hours)
    private let cacheValidityDuration: TimeInterval = 24 * 60 * 60
    
    // MARK: - Initialization
    
    private init() {
        self.squareAPIService = SquareAPIServiceFactory.createService()
        logger.info("LocationCacheManager initialized")
    }
    
    // MARK: - Public Methods
    
    /// Load locations from cache or fetch from API if needed
    /// This is the primary method used throughout the app
    func loadLocations() async {
        logger.info("Loading locations...")
        
        // If already loaded and cache is fresh, return immediately
        if isLoaded && isCacheFresh {
            logger.info("Using fresh cached locations (\(self.locations.count) locations)")
            return
        }
        
        // If already loading, return to prevent duplicate requests
        guard !isLoading else {
            logger.info("Location loading already in progress")
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            logger.info("Fetching locations from Square API...")
            let squareLocations = try await squareAPIService.fetchLocations()
            
            // Transform Square locations to LocationData
            let locationData = squareLocations.map { squareLocation in
                LocationData(
                    id: squareLocation.id,
                    name: squareLocation.displayName,
                    address: squareLocation.formattedAddress,
                    isActive: squareLocation.isActive
                )
            }.filter { $0.isActive } // Only include active locations
            
            // Update cache
            self.locations = locationData
            self.lastUpdated = Date()
            self.isLoaded = true
            self.error = nil
            
            logger.info("✅ Successfully cached \(locationData.count) active locations")
            
        } catch {
            logger.error("❌ Failed to load locations: \(error.localizedDescription)")
            self.error = error

            // Check for authentication failure specifically
            if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
                logger.error("[LocationCache] Authentication failed - clearing tokens and notifying user")

                // Clear invalid tokens
                let tokenService = SquareAPIServiceFactory.createTokenService()
                try? await tokenService.clearAuthData()

                // Update auth state
                squareAPIService.setAuthenticated(false)

                // Clear stale location cache
                self.locations = []
                self.isLoaded = false
                self.lastUpdated = nil

                // Notify user
                ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")

            } else {
                // For non-auth errors, keep using cached data if available
                if !self.locations.isEmpty {
                    logger.info("Using stale cached locations (\(self.locations.count) locations)")
                }
            }
        }
        
        isLoading = false
    }
    
    /// Force refresh locations from API (used during catalog sync)
    func refreshLocations() async {
        logger.info("Force refreshing locations from API...")
        
        // Reset cache state to force refresh
        lastUpdated = nil
        isLoaded = false
        
        await loadLocations()
    }
    
    /// Get all location IDs immediately (no async needed)
    var allLocationIds: [String] {
        return locations.map { $0.id }
    }
    
    /// Get location by ID
    func getLocation(by id: String) -> LocationData? {
        return locations.first { $0.id == id }
    }
    
    /// Check if locations are available (for UI display)
    var hasLocations: Bool {
        return !locations.isEmpty
    }
    
    // MARK: - Private Methods
    
    /// Check if cached data is still fresh
    private var isCacheFresh: Bool {
        guard let lastUpdated = lastUpdated else { return false }
        let timeSinceUpdate = Date().timeIntervalSince(lastUpdated)
        return timeSinceUpdate < cacheValidityDuration
    }
}

// MARK: - LocationData Model

/// Simplified location data model for app use
struct LocationData: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let isActive: Bool
    
    // Computed properties for display
    var displayName: String {
        return name.isEmpty ? "Location \(id)" : name
    }
    
    // Initializer for backward compatibility
    init(id: String, name: String, address: String = "", isActive: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.isActive = isActive
    }
}

// MARK: - Factory Integration

extension SquareAPIServiceFactory {
    
    /// Get the global location cache manager
    static func createLocationManager() -> LocationCacheManager {
        return LocationCacheManager.shared
    }
}