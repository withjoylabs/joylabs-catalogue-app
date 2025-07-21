import Foundation
import os.log

/// Service responsible for loading items from database and transforming them for UI
@MainActor
class ItemLoadingService: ObservableObject {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemLoadingService")
    private let databaseManager: SQLiteSwiftCatalogManager
    
    init(databaseManager: SQLiteSwiftCatalogManager = SQLiteSwiftCatalogManager.shared) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - Item Loading Methods
    
    /// Load an item by ID and transform it to ItemDetailsData for UI
    func loadItemById(_ itemId: String) async throws -> ItemDetailsData? {
        logger.info("Loading item by ID: \(itemId)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    // Fetch the catalog object from database
                    guard let catalogObject = try self.databaseManager.fetchItemById(itemId) else {
                        self.logger.warning("Item not found in database: \(itemId)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Fetch team data if available
                    let teamData = try self.databaseManager.fetchTeamDataForItem(itemId)
                    
                    // Transform to UI model
                    let itemDetails = ItemDataTransformers.transformCatalogObjectToItemDetails(
                        catalogObject,
                        teamData: teamData
                    )
                    
                    self.logger.info("Successfully loaded and transformed item: \(itemId)")
                    continuation.resume(returning: itemDetails)
                    
                } catch {
                    self.logger.error("Failed to load item \(itemId): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Load multiple items by IDs efficiently
    func loadItemsByIds(_ itemIds: [String]) async throws -> [ItemDetailsData] {
        logger.info("Loading \(itemIds.count) items by IDs")
        
        var items: [ItemDetailsData] = []
        
        for itemId in itemIds {
            if let item = try await loadItemById(itemId) {
                items.append(item)
            }
        }
        
        logger.info("Successfully loaded \(items.count) out of \(itemIds.count) items")
        return items
    }
    
    /// Check if an item exists in the database
    func itemExists(_ itemId: String) async throws -> Bool {
        logger.debug("Checking if item exists: \(itemId)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let catalogObject = try self.databaseManager.fetchItemById(itemId)
                    continuation.resume(returning: catalogObject != nil)
                } catch {
                    self.logger.error("Failed to check item existence \(itemId): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Load item with fallback to Square API if not found locally
    func loadItemWithFallback(_ itemId: String) async throws -> ItemDetailsData? {
        logger.info("Loading item with fallback: \(itemId)")
        
        // First try to load from local database
        if let localItem = try await loadItemById(itemId) {
            logger.info("Item found in local database: \(itemId)")
            return localItem
        }
        
        // TODO: Implement Square API fallback
        // This would fetch from Square API and store in database
        logger.warning("Item not found locally and Square API fallback not yet implemented: \(itemId)")
        return nil
    }
    
    // MARK: - Validation Methods
    
    /// Validate that an item has required data for editing
    func validateItemForEditing(_ itemDetails: ItemDetailsData) -> [String] {
        var errors: [String] = []
        
        // Check required fields
        if itemDetails.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Item name is required")
        }
        
        if itemDetails.variations.isEmpty {
            errors.append("At least one variation is required")
        } else {
            // Validate variations
            for (index, variation) in itemDetails.variations.enumerated() {
                if variation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("Variation \(index + 1) name is required")
                }
            }
        }
        
        return errors
    }
    
    /// Get item summary for display purposes
    func getItemSummary(_ itemId: String) async throws -> ItemSummary? {
        logger.debug("Getting item summary: \(itemId)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    guard let catalogObject = try self.databaseManager.fetchItemById(itemId) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let summary = ItemSummary(
                        id: catalogObject.id,
                        name: catalogObject.itemData?.name ?? "Unnamed Item",
                        description: catalogObject.itemData?.description,
                        categoryId: catalogObject.itemData?.categoryId,
                        hasVariations: !(catalogObject.itemData?.variations?.isEmpty ?? true),
                        variationCount: catalogObject.itemData?.variations?.count ?? 0,
                        isDeleted: catalogObject.isDeleted,
                        updatedAt: catalogObject.updatedAt
                    )
                    
                    continuation.resume(returning: summary)
                    
                } catch {
                    self.logger.error("Failed to get item summary \(itemId): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Lightweight item summary for display purposes
struct ItemSummary {
    let id: String
    let name: String
    let description: String?
    let categoryId: String?
    let hasVariations: Bool
    let variationCount: Int
    let isDeleted: Bool
    let updatedAt: String
}

// MARK: - Error Types

enum ItemLoadingError: LocalizedError {
    case itemNotFound(String)
    case databaseError(Error)
    case transformationError(String)
    case validationError([String])
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemId):
            return "Item not found: \(itemId)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .transformationError(let message):
            return "Data transformation error: \(message)"
        case .validationError(let errors):
            return "Validation errors: \(errors.joined(separator: ", "))"
        }
    }
}
