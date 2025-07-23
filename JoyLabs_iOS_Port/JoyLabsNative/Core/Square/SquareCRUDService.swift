import Foundation
import os.log

/// Comprehensive CRUD service that ensures perfect synchronization between Square API and local database
/// CRITICAL: Every successful API operation MUST immediately update the local database with exact response data
///
/// WEBHOOK COMPATIBILITY: This service preserves exact timestamps and versions from Square API responses
/// to ensure compatibility with Square's webhook system (catalog.version.updated events).
/// When webhooks arrive, they will find matching timestamps and versions, preventing conflicts.
@MainActor
class SquareCRUDService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let squareAPIService: SquareAPIService
    private let databaseManager: SQLiteSwiftCatalogManager
    private let dataConverter: SquareDataConverter
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareCRUDService")
    
    // MARK: - Published State
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var lastOperationResult: CRUDOperationResult?
    
    // MARK: - Initialization
    
    init(
        squareAPIService: SquareAPIService,
        databaseManager: SQLiteSwiftCatalogManager,
        dataConverter: SquareDataConverter
    ) {
        self.squareAPIService = squareAPIService
        self.databaseManager = databaseManager
        self.dataConverter = dataConverter
        
        logger.info("SquareCRUDService initialized")
    }
    
    // MARK: - Create Operations
    
    /// Create a new catalog item with perfect synchronization
    /// Returns the created object with Square-generated ID and version
    func createItem(_ itemDetails: ItemDetailsData) async throws -> CatalogObject {
        logger.info("Creating new item: \(itemDetails.name)")
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // 1. VALIDATION: Pre-validate data using SquareDataConverter
            try validateItemForCreation(itemDetails)
            
            // 2. TRANSFORM: Convert ItemDetailsData to CatalogObject for API
            let catalogObject = ItemDataTransformers.transformItemDetailsToCatalogObject(
                itemDetails, 
                databaseManager: databaseManager
            )
            
            // 3. SQUARE API: Create object with idempotency key (get full response with ID mappings)
            let idempotencyKey = "create_item_\(UUID().uuidString)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let createdObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from create operation")
            }

            // 4. DATABASE SYNC: Immediately update local database with exact API response and ID mappings
            try await updateLocalDatabaseAfterCreate(createdObject, idMappings: response.idMappings)
            
            // 5. SUCCESS: Record operation result
            let result = CRUDOperationResult(
                operation: .create,
                objectId: createdObject.id,
                objectType: createdObject.type,
                success: true,
                timestamp: Date(),
                squareVersion: createdObject.safeVersion
            )
            lastOperationResult = result
            
            logger.info("✅ Successfully created item: \(createdObject.id) (version: \(createdObject.safeVersion))")
            return createdObject
            
        } catch {
            logger.error("❌ Failed to create item: \(error.localizedDescription)")
            lastError = error
            
            let result = CRUDOperationResult(
                operation: .create,
                objectId: itemDetails.id ?? "unknown",
                objectType: "ITEM",
                success: false,
                timestamp: Date(),
                error: error.localizedDescription
            )
            lastOperationResult = result
            
            throw error
        }
    }
    
    // MARK: - Update Operations
    
    /// Update an existing catalog item with perfect synchronization
    /// Returns the updated object with new version from Square
    func updateItem(_ itemDetails: ItemDetailsData) async throws -> CatalogObject {
        guard let itemId = itemDetails.id else {
            throw SquareCRUDError.missingItemId
        }
        
        logger.info("Updating item: \(itemId)")
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // 1. VALIDATION: Pre-validate data
            try validateItemForUpdate(itemDetails)

            // 2. FETCH LATEST VERSION: Get current version from database to avoid version mismatch
            let latestVersion = try await databaseManager.getItemVersion(itemId: itemId)
            logger.debug("Latest version from database: \(latestVersion)")

            // 3. TRANSFORM: Convert to CatalogObject with latest version
            var catalogObject = ItemDataTransformers.transformItemDetailsToCatalogObject(
                itemDetails,
                databaseManager: databaseManager
            )

            // Update with latest version to prevent version mismatch
            catalogObject = CatalogObject(
                id: catalogObject.id,
                type: catalogObject.type,
                updatedAt: catalogObject.updatedAt,
                version: latestVersion, // Use latest version from database
                isDeleted: catalogObject.isDeleted,
                presentAtAllLocations: catalogObject.presentAtAllLocations,
                itemData: catalogObject.itemData,
                categoryData: catalogObject.categoryData,
                itemVariationData: catalogObject.itemVariationData,
                modifierData: catalogObject.modifierData,
                modifierListData: catalogObject.modifierListData,
                taxData: catalogObject.taxData,
                discountData: catalogObject.discountData,
                imageData: catalogObject.imageData
            )
            
            // 3. SQUARE API: Update with idempotency key (get full response with ID mappings)
            let idempotencyKey = "update_item_\(itemId)_\(Date().timeIntervalSince1970)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let updatedObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from update operation")
            }

            // 4. DATABASE SYNC: Update local database with exact API response and ID mappings
            try await updateLocalDatabaseAfterUpdate(updatedObject, idMappings: response.idMappings)
            
            // 5. SUCCESS: Record operation result
            let result = CRUDOperationResult(
                operation: .update,
                objectId: updatedObject.id,
                objectType: updatedObject.type,
                success: true,
                timestamp: Date(),
                squareVersion: updatedObject.safeVersion
            )
            lastOperationResult = result
            
            logger.info("✅ Successfully updated item: \(updatedObject.id) (version: \(updatedObject.safeVersion))")
            return updatedObject
            
        } catch {
            logger.error("❌ Failed to update item: \(error.localizedDescription)")
            lastError = error
            
            let result = CRUDOperationResult(
                operation: .update,
                objectId: itemId,
                objectType: "ITEM",
                success: false,
                timestamp: Date(),
                error: error.localizedDescription
            )
            lastOperationResult = result
            
            throw error
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a catalog item with perfect synchronization
    /// Returns information about the deleted object
    func deleteItem(_ itemId: String) async throws -> DeletedCatalogObject {
        logger.info("Deleting item: \(itemId)")
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // 1. SQUARE API: Delete object
            let deletedObject = try await squareAPIService.deleteCatalogObject(itemId)
            
            // 2. DATABASE SYNC: Update local database to mark as deleted
            try await updateLocalDatabaseAfterDelete(deletedObject)
            
            // 3. SUCCESS: Record operation result
            let result = CRUDOperationResult(
                operation: .delete,
                objectId: itemId,
                objectType: deletedObject.objectType ?? "ITEM",
                success: true,
                timestamp: Date(),
                squareVersion: deletedObject.version
            )
            lastOperationResult = result
            
            logger.info("✅ Successfully deleted item: \(itemId)")
            return deletedObject
            
        } catch {
            logger.error("❌ Failed to delete item: \(error.localizedDescription)")
            lastError = error
            
            let result = CRUDOperationResult(
                operation: .delete,
                objectId: itemId,
                objectType: "ITEM",
                success: false,
                timestamp: Date(),
                error: error.localizedDescription
            )
            lastOperationResult = result
            
            throw error
        }
    }
    
    // MARK: - Validation Methods
    
    private func validateItemForCreation(_ itemDetails: ItemDetailsData) throws {
        // Validate required fields
        guard !itemDetails.name.isEmpty else {
            throw SquareCRUDError.invalidData("Item name is required")
        }
        
        // Validate at least one variation exists
        guard !itemDetails.variations.isEmpty else {
            throw SquareCRUDError.invalidData("At least one variation is required")
        }
        
        // Validate category exists if specified
        if let categoryId = itemDetails.reportingCategoryId {
            guard dataConverter.validateCategoryExists(id: categoryId) else {
                throw SquareCRUDError.invalidData("Invalid category ID: \(categoryId)")
            }
        }
        
        // Validate tax IDs
        let invalidTaxIds = itemDetails.taxIds.filter { !dataConverter.validateTaxExists(id: $0) }
        if !invalidTaxIds.isEmpty {
            throw SquareCRUDError.invalidData("Invalid tax IDs: \(invalidTaxIds.joined(separator: ", "))")
        }
        
        logger.debug("✅ Item validation passed for creation")
    }
    
    private func validateItemForUpdate(_ itemDetails: ItemDetailsData) throws {
        // All creation validations plus ID requirement
        try validateItemForCreation(itemDetails)
        
        guard itemDetails.id != nil else {
            throw SquareCRUDError.missingItemId
        }
        
        logger.debug("✅ Item validation passed for update")
    }
    
    // MARK: - Database Synchronization Methods

    private func updateLocalDatabaseAfterCreate(_ createdObject: CatalogObject, idMappings: [IdMapping]? = nil) async throws {
        logger.debug("Updating local database after create: \(createdObject.id)")

        // CRITICAL: Preserve exact timestamp from Square API response for webhook compatibility
        logger.debug("Square API returned timestamp: \(createdObject.safeUpdatedAt)")
        logger.debug("Square API returned version: \(createdObject.safeVersion)")

        // Log ID mappings for debugging
        if let mappings = idMappings, !mappings.isEmpty {
            logger.debug("Square API returned \(mappings.count) ID mappings:")
            for mapping in mappings {
                logger.debug("  \(mapping.clientObjectId ?? "nil") → \(mapping.objectId ?? "nil")")
            }
        }

        // WEBHOOK COMPATIBILITY: Ensure timestamps match Square's webhook system
        // This prevents conflicts when webhooks arrive for the same object
        try await Task.detached { [self] in
            // Insert the main item object
            try await self.databaseManager.insertCatalogObject(createdObject)

            // CRITICAL: Process variations separately for scalability
            // Square returns variations as part of the item, but we need to store them separately
            if let itemData = createdObject.itemData, let variations = itemData.variations {
                logger.debug("Processing \(variations.count) variations for item \(createdObject.id)")

                for variation in variations {
                    // Create a separate CatalogObject for each variation
                    let variationObject = CatalogObject(
                        id: variation.id ?? "UNKNOWN_VARIATION_ID",
                        type: "ITEM_VARIATION",
                        updatedAt: createdObject.updatedAt,
                        version: createdObject.version,
                        isDeleted: variation.isDeleted,
                        presentAtAllLocations: variation.presentAtAllLocations,
                        itemData: nil,
                        categoryData: nil,
                        itemVariationData: variation.itemVariationData,
                        modifierData: nil,
                        modifierListData: nil,
                        taxData: nil,
                        discountData: nil,
                        imageData: nil
                    )

                    try await self.databaseManager.insertCatalogObject(variationObject)
                    logger.debug("Inserted variation: \(variation.id ?? "nil") for item \(createdObject.id)")
                }
            }
        }.value

        logger.debug("✅ Local database updated after create with exact Square timestamps (webhook-compatible)")
    }

    private func updateLocalDatabaseAfterUpdate(_ updatedObject: CatalogObject, idMappings: [IdMapping]? = nil) async throws {
        logger.debug("Updating local database after update: \(updatedObject.id)")

        // CRITICAL: Preserve exact timestamp and version from Square API response for webhook compatibility
        logger.debug("Square API returned updated timestamp: \(updatedObject.safeUpdatedAt)")
        logger.debug("Square API returned new version: \(updatedObject.safeVersion)")

        // Log ID mappings for debugging
        if let mappings = idMappings, !mappings.isEmpty {
            logger.debug("Square API returned \(mappings.count) ID mappings for update:")
            for mapping in mappings {
                logger.debug("  \(mapping.clientObjectId ?? "nil") → \(mapping.objectId ?? "nil")")
            }
        }

        // WEBHOOK COMPATIBILITY: These exact timestamps will match webhook notifications
        // This ensures no conflicts when catalog.version.updated webhooks arrive
        try await Task.detached { [self] in
            // Use upsert to handle both insert and update cases
            try await self.databaseManager.insertCatalogObject(updatedObject)

            // CRITICAL: Process variations separately for scalability (same as create)
            if let itemData = updatedObject.itemData, let variations = itemData.variations {
                logger.debug("Processing \(variations.count) variations for updated item \(updatedObject.id)")

                for variation in variations {
                    // Create a separate CatalogObject for each variation
                    let variationObject = CatalogObject(
                        id: variation.id ?? "UNKNOWN_VARIATION_ID",
                        type: "ITEM_VARIATION",
                        updatedAt: updatedObject.updatedAt,
                        version: updatedObject.version,
                        isDeleted: variation.isDeleted,
                        presentAtAllLocations: variation.presentAtAllLocations,
                        itemData: nil,
                        categoryData: nil,
                        itemVariationData: variation.itemVariationData,
                        modifierData: nil,
                        modifierListData: nil,
                        taxData: nil,
                        discountData: nil,
                        imageData: nil
                    )

                    try await self.databaseManager.insertCatalogObject(variationObject)
                    logger.debug("Updated variation: \(variation.id ?? "nil") for item \(updatedObject.id)")
                }
            }
        }.value

        logger.debug("✅ Local database updated after update with exact Square timestamps (webhook-compatible)")
    }

    private func updateLocalDatabaseAfterDelete(_ deletedObject: DeletedCatalogObject) async throws {
        logger.debug("Updating local database after delete: \(deletedObject.id ?? "unknown")")

        // Create a CatalogObject marked as deleted for database update
        if let objectId = deletedObject.id, let objectType = deletedObject.objectType {
            let deletedCatalogObject = CatalogObject(
                id: objectId,
                type: objectType,
                updatedAt: deletedObject.deletedAt ?? ISO8601DateFormatter().string(from: Date()),
                version: deletedObject.version,
                isDeleted: true, // Mark as deleted
                presentAtAllLocations: nil,
                itemData: nil,
                categoryData: nil,
                itemVariationData: nil,
                modifierData: nil,
                modifierListData: nil,
                taxData: nil,
                discountData: nil,
                imageData: nil
            )

            try await Task.detached {
                try await self.databaseManager.insertCatalogObject(deletedCatalogObject)
            }.value
        }

        logger.debug("✅ Local database updated after delete")
    }
}

// MARK: - Supporting Types

enum SquareCRUDError: LocalizedError {
    case missingItemId
    case invalidData(String)
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingItemId:
            return "Item ID is required for update operations"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .syncFailed(let message):
            return "Database synchronization failed: \(message)"
        }
    }
}

struct CRUDOperationResult {
    let operation: CRUDOperation
    let objectId: String
    let objectType: String
    let success: Bool
    let timestamp: Date
    let squareVersion: Int64?
    let error: String?
    
    init(operation: CRUDOperation, objectId: String, objectType: String, success: Bool, timestamp: Date, squareVersion: Int64? = nil, error: String? = nil) {
        self.operation = operation
        self.objectId = objectId
        self.objectType = objectType
        self.success = success
        self.timestamp = timestamp
        self.squareVersion = squareVersion
        self.error = error
    }
}

enum CRUDOperation: String, CaseIterable {
    case create = "CREATE"
    case update = "UPDATE"
    case delete = "DELETE"
}
