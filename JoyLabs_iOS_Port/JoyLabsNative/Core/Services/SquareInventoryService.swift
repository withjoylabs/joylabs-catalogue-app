import Foundation
import OSLog

/// Service for managing Square inventory via Inventory API
/// Handles fetching inventory counts and submitting inventory changes (adjustments and physical counts)
@MainActor
class SquareInventoryService {

    // MARK: - Dependencies

    private let httpClient: SquareHTTPClient
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareInventoryService")

    // MARK: - Initialization

    init(httpClient: SquareHTTPClient) {
        self.httpClient = httpClient
        logger.info("[InventoryService] SquareInventoryService initialized")
    }

    // MARK: - Fetch Inventory Counts

    /// Fetch current inventory counts for specific variation(s) and location(s)
    /// - Parameters:
    ///   - catalogObjectIds: Array of variation IDs to fetch counts for
    ///   - locationIds: Optional array of location IDs (if nil, fetches all locations)
    /// - Returns: Array of inventory counts
    func fetchInventoryCounts(
        catalogObjectIds: [String],
        locationIds: [String]? = nil
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Fetching inventory counts for \(catalogObjectIds.count) variations")

        // Build request body
        var requestBody: [String: Any] = [
            "catalog_object_ids": catalogObjectIds
        ]

        if let locationIds = locationIds {
            requestBody["location_ids"] = locationIds
        }

        let requestData = try JSONSerialization.data(withJSONObject: requestBody)

        // Make API request
        let response: BatchRetrieveInventoryCountsResponse = try await httpClient.makeSquareAPIRequest(
            endpoint: "/v2/inventory/counts/batch-retrieve",
            method: .POST,
            body: requestData,
            responseType: BatchRetrieveInventoryCountsResponse.self
        )

        // Check for errors
        if let errors = response.errors, !errors.isEmpty {
            let errorMessage = errors.map { $0.detail ?? $0.code }.joined(separator: ", ")
            logger.error("[InventoryService] Failed to fetch inventory counts: \(errorMessage)")
            throw SquareAPIError.inventoryError(errorMessage)
        }

        let counts = response.counts ?? []
        logger.info("[InventoryService] ✅ Fetched \(counts.count) inventory counts")

        return counts
    }

    // MARK: - Batch Change Inventory

    /// Submit inventory changes (adjustments or physical counts) to Square
    /// - Parameters:
    ///   - changes: Array of inventory changes to apply
    ///   - ignoreUnchangedCounts: Whether to skip unchanged physical counts (default: true)
    /// - Returns: Updated inventory counts after changes applied
    func batchChangeInventory(
        changes: [InventoryChange],
        ignoreUnchangedCounts: Bool = true
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Submitting \(changes.count) inventory changes")

        // Generate idempotency key
        let idempotencyKey = "inventory_change_\(UUID().uuidString)"

        // Build request
        let request = BatchChangeInventoryRequest(
            idempotencyKey: idempotencyKey,
            changes: changes,
            ignoreUnchangedCounts: ignoreUnchangedCounts
        )

        let requestData = try JSONEncoder().encode(request)

        // Make API request
        let response: BatchChangeInventoryResponse = try await httpClient.makeSquareAPIRequest(
            endpoint: "/v2/inventory/changes/batch-create",
            method: .POST,
            body: requestData,
            responseType: BatchChangeInventoryResponse.self
        )

        // Check for errors
        if let errors = response.errors, !errors.isEmpty {
            let errorMessage = errors.map { $0.detail ?? $0.code }.joined(separator: ", ")
            logger.error("[InventoryService] Failed to change inventory: \(errorMessage)")

            // Check if error indicates inventory not enabled (premium feature)
            if errorMessage.contains("INVENTORY") || errorMessage.contains("not enabled") {
                throw SquareAPIError.featureNotEnabled("Inventory tracking requires Square Premium subscription")
            }

            throw SquareAPIError.inventoryError(errorMessage)
        }

        let counts = response.counts ?? []
        logger.info("[InventoryService] ✅ Successfully applied inventory changes, received \(counts.count) updated counts")

        return counts
    }

    // MARK: - Convenience Methods for Specific Adjustments

    /// Record stock received (NONE → IN_STOCK)
    func recordStockReceived(
        variationId: String,
        locationId: String,
        quantity: Int
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Recording stock received: variation=\(variationId), qty=\(quantity)")

        let change = InventoryChange.adjustment(
            catalogObjectId: variationId,
            locationId: locationId,
            fromState: "NONE",
            toState: "IN_STOCK",
            quantity: "\(quantity)"
        )

        return try await batchChangeInventory(changes: [change])
    }

    /// Record inventory recount (PHYSICAL_COUNT - absolute)
    func recordInventoryRecount(
        variationId: String,
        locationId: String,
        newQuantity: Int
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Recording inventory recount: variation=\(variationId), new_qty=\(newQuantity)")

        let change = InventoryChange.physicalCount(
            catalogObjectId: variationId,
            locationId: locationId,
            quantity: "\(newQuantity)"
        )

        return try await batchChangeInventory(changes: [change])
    }

    /// Record damage/theft/loss (IN_STOCK → WASTE)
    func recordInventoryLoss(
        variationId: String,
        locationId: String,
        quantity: Int,
        reason: InventoryAdjustmentReason
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Recording inventory loss: variation=\(variationId), qty=\(quantity), reason=\(reason.displayName)")

        let change = InventoryChange.adjustment(
            catalogObjectId: variationId,
            locationId: locationId,
            fromState: "IN_STOCK",
            toState: "WASTE",
            quantity: "\(quantity)"
        )

        return try await batchChangeInventory(changes: [change])
    }

    /// Submit a custom inventory adjustment based on reason
    func submitInventoryAdjustment(
        variationId: String,
        locationId: String,
        quantity: Int,
        reason: InventoryAdjustmentReason
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Submitting inventory adjustment: variation=\(variationId), qty=\(quantity), reason=\(reason.displayName)")

        let change: InventoryChange

        if reason.isAbsolute {
            // Physical count (recount)
            change = InventoryChange.physicalCount(
                catalogObjectId: variationId,
                locationId: locationId,
                quantity: "\(quantity)"
            )
        } else {
            // Adjustment (state transition)
            let (fromState, toState) = reason.getSquareStates()
            change = InventoryChange.adjustment(
                catalogObjectId: variationId,
                locationId: locationId,
                fromState: fromState,
                toState: toState,
                quantity: "\(quantity)"
            )
        }

        return try await batchChangeInventory(changes: [change])
    }

    // MARK: - Initial Stock Setup (for new items)

    /// Set initial stock for a newly created variation
    /// Uses physical count to establish baseline inventory
    func setInitialStock(
        variationId: String,
        locationId: String,
        quantity: Int
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Setting initial stock: variation=\(variationId), qty=\(quantity)")

        let change = InventoryChange.physicalCount(
            catalogObjectId: variationId,
            locationId: locationId,
            quantity: "\(quantity)"
        )

        return try await batchChangeInventory(changes: [change])
    }

    /// Set initial stock for multiple variations at once (batch operation for new items)
    func setInitialStockBatch(
        variationStocks: [(variationId: String, locationId: String, quantity: Int)]
    ) async throws -> [InventoryCountData] {
        logger.info("[InventoryService] Setting initial stock for \(variationStocks.count) variations")

        let changes = variationStocks.map { stock in
            InventoryChange.physicalCount(
                catalogObjectId: stock.variationId,
                locationId: stock.locationId,
                quantity: "\(stock.quantity)"
            )
        }

        return try await batchChangeInventory(changes: changes)
    }
}

// MARK: - Supporting Types

/// Response from batch retrieve inventory counts
struct BatchRetrieveInventoryCountsResponse: Codable {
    let errors: [SquareError]?
    let counts: [InventoryCountData]?
    let cursor: String? // For pagination (if needed in future)
}

/// Extended SquareAPIError for inventory-specific errors
extension SquareAPIError {
    static func inventoryError(_ message: String) -> SquareAPIError {
        return .generalError(message)
    }

    static func featureNotEnabled(_ message: String) -> SquareAPIError {
        return .generalError(message)
    }
}
