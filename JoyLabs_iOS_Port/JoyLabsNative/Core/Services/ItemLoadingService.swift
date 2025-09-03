import Foundation
import SwiftData
import os.log

/// Service responsible for loading items from database and transforming them for UI
@MainActor
class ItemLoadingService: ObservableObject {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ItemLoadingService")
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Item Loading Methods
    
    /// Load an item by ID and transform it to ItemDetailsData for UI
    func loadItemById(_ itemId: String) async throws -> ItemDetailsData? {
        logger.info("Loading item by ID: \(itemId)")
        
        do {
            // Fetch item from SwiftData
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            guard let catalogItem = try modelContext.fetch(descriptor).first else {
                logger.warning("Item not found in database: \(itemId)")
                return nil
            }
            
            // Fetch team data if available
            let teamData = catalogItem.teamData
            
            // Transform to ItemDetailsData
            let itemDetails = transformCatalogItemToItemDetails(catalogItem, teamData: teamData)
            
            logger.info("Successfully loaded and transformed item: \(itemId)")
            return itemDetails
            
        } catch {
            logger.error("Failed to load item \(itemId): \(error)")
            throw ItemLoadingError.databaseError(error)
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
        
        do {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            let count = try modelContext.fetchCount(descriptor)
            return count > 0
            
        } catch {
            logger.error("Failed to check item existence \(itemId): \(error)")
            throw ItemLoadingError.databaseError(error)
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
        
        do {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            guard let catalogItem = try modelContext.fetch(descriptor).first else {
                return nil
            }
            
            let summary = ItemSummary(
                id: catalogItem.id,
                name: catalogItem.name ?? "Unnamed Item",
                description: catalogItem.itemDescription,
                categoryId: catalogItem.categoryId,
                hasVariations: catalogItem.hasVariations,
                variationCount: catalogItem.variations?.count ?? 0,
                isDeleted: catalogItem.isDeleted,
                updatedAt: catalogItem.updatedAt.description
            )
            
            return summary
            
        } catch {
            logger.error("Failed to get item summary \(itemId): \(error)")
            throw ItemLoadingError.databaseError(error)
        }
    }
    
    // MARK: - Private Methods
    
    /// Transform CatalogItemModel to ItemDetailsData
    private func transformCatalogItemToItemDetails(_ item: CatalogItemModel, teamData: TeamDataModel?) -> ItemDetailsData {
        var itemDetails = ItemDetailsData()
        
        // Core identification
        itemDetails.id = item.id
        itemDetails.version = Int64(item.version) ?? 0
        
        // Basic information
        itemDetails.name = item.name ?? ""
        itemDetails.description = item.itemDescription ?? ""
        
        // Categories
        itemDetails.reportingCategoryId = item.reportingCategoryId
        itemDetails.categoryIds = [] // TODO: Implement additional categories
        
        // Transform variations
        if let variations = item.variations {
            itemDetails.variations = variations.map { variation in
                var variationData = ItemDetailsVariationData()
                variationData.id = variation.id
                variationData.version = Int64(variation.version) ?? 0
                variationData.name = variation.name
                variationData.sku = variation.sku
                variationData.upc = variation.upc
                variationData.ordinal = Int(variation.ordinal ?? 0)
                
                // Price data
                if let priceAmount = variation.priceAmount,
                   let priceCurrency = variation.priceCurrency {
                    variationData.priceMoney = MoneyData(amount: Int(priceAmount), currency: priceCurrency)
                }
                
                return variationData
            }
        } else {
            // Default variation if none exist
            itemDetails.variations = [ItemDetailsVariationData()]
        }
        
        // Location settings
        itemDetails.presentAtAllLocations = item.presentAtAllLocations ?? true
        itemDetails.presentAtLocationIds = item.presentAtLocationIds ?? []
        itemDetails.absentAtLocationIds = item.absentAtLocationIds ?? []
        
        // Images
        if let images = item.images, let primaryImage = images.first {
            itemDetails.imageURL = primaryImage.url
            itemDetails.imageId = primaryImage.id
        }
        
        // Team data
        if let teamData = teamData {
            itemDetails.teamData = TeamItemData(
                caseUpc: teamData.caseUpc,
                caseCost: teamData.caseCost,
                caseQuantity: Int(teamData.caseQuantity),
                vendor: teamData.vendor,
                discontinued: teamData.discontinued,
                notes: teamData.notes
            )
        }
        
        // Metadata
        itemDetails.isDeleted = item.isDeleted
        itemDetails.updatedAt = item.updatedAt.description
        
        return itemDetails
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
