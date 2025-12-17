import Foundation
import OSLog

/// Service for managing Square account capabilities and feature availability
/// Checks capabilities at app startup and updates based on runtime API responses
@MainActor
class SquareCapabilitiesService: ObservableObject {

    // MARK: - Singleton
    static let shared = SquareCapabilitiesService()

    // MARK: - Published Properties
    @Published var inventoryTrackingEnabled: Bool = false
    @Published var isCheckingCapabilities: Bool = false

    // MARK: - Dependencies
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareCapabilitiesService")

    // MARK: - Initialization
    private init() {
        logger.info("[CapabilitiesService] SquareCapabilitiesService initialized")
    }

    // MARK: - Capability Checking

    /// Check inventory tracking capability at app startup
    /// Makes a lightweight API call to detect if merchant has inventory feature enabled
    func checkInventoryCapability() async {
        logger.info("[CapabilitiesService] Checking inventory tracking capability...")
        isCheckingCapabilities = true
        defer { isCheckingCapabilities = false }

        do {
            // Use factory pattern to get inventory service
            let inventoryService = SquareAPIServiceFactory.createInventoryService()

            // Try to fetch inventory counts for a minimal request
            // If this succeeds, inventory tracking is enabled
            // We'll use an empty array which should return quickly without data
            _ = try await inventoryService.fetchInventoryCounts(
                catalogObjectIds: [],
                locationIds: nil
            )

            // Success - inventory tracking is enabled
            inventoryTrackingEnabled = true
            logger.info("[CapabilitiesService] ✅ Inventory tracking is ENABLED")

        } catch let error as SquareAPIError {
            // Check if error indicates inventory not enabled
            let errorMessage = error.localizedDescription.lowercased()

            if errorMessage.contains("inventory") ||
               errorMessage.contains("not enabled") ||
               errorMessage.contains("premium") ||
               errorMessage.contains("subscription") {
                inventoryTrackingEnabled = false
                logger.info("[CapabilitiesService] ❌ Inventory tracking is NOT ENABLED (premium feature)")
            } else {
                // Other error - assume enabled but network/auth issue
                // Default to enabled to avoid blocking functionality
                inventoryTrackingEnabled = true
                logger.warning("[CapabilitiesService] ⚠️ Inventory check failed with non-premium error, assuming enabled: \(error)")
            }

        } catch {
            // Unknown error - assume enabled to avoid blocking functionality
            inventoryTrackingEnabled = true
            logger.warning("[CapabilitiesService] ⚠️ Inventory check failed with unknown error, assuming enabled: \(error)")
        }
    }

    // MARK: - Runtime Flag Updates

    /// Update inventory capability based on successful API operation
    /// Call this when inventory API succeeds to auto-detect premium upgrade
    func markInventoryAsEnabled() {
        guard !inventoryTrackingEnabled else { return }

        logger.info("[CapabilitiesService] ✅ Inventory API succeeded - updating capability flag to ENABLED")
        inventoryTrackingEnabled = true
    }

    /// Update inventory capability based on failed API operation
    /// Call this when inventory API fails with premium-related error
    func markInventoryAsDisabled(error: Error) {
        guard inventoryTrackingEnabled else { return }

        let errorMessage = error.localizedDescription.lowercased()

        if errorMessage.contains("inventory") ||
           errorMessage.contains("not enabled") ||
           errorMessage.contains("premium") ||
           errorMessage.contains("subscription") {
            logger.info("[CapabilitiesService] ❌ Inventory API failed - updating capability flag to DISABLED")
            inventoryTrackingEnabled = false
        }
    }

    // MARK: - Manual Refresh

    /// Manually refresh capabilities (e.g., from settings screen)
    func refreshCapabilities() async {
        logger.info("[CapabilitiesService] Manual capability refresh requested")
        await checkInventoryCapability()
    }
}
