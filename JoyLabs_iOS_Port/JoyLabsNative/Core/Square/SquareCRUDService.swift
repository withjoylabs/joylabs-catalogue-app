import Foundation
import SwiftData
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
            
            // 6. UI REFRESH: Notify UI components to refresh with new data
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": createdObject.id, "operation": "create"]
                )
                logger.info("📡 Posted catalog sync notification for created item: \(createdObject.id)")
            }
            
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

            // 2. FETCH CURRENT VERSION: Get latest version from Square API (required by Square)
            logger.debug("Fetching current item version from Square API for update: \(itemId)")
            let currentObject = try await squareAPIService.fetchCatalogObjectById(itemId)
            let currentVersion = currentObject.safeVersion
            logger.debug("Current version from Square API: \(currentVersion)")

            // 3. TRANSFORM: Convert to CatalogObject with current version from Square
            var catalogObject = ItemDataTransformers.transformItemDetailsToCatalogObject(
                itemDetails,
                databaseManager: databaseManager
            )

            // 4. APPLY CURRENT VERSIONS: Set the current version from Square API for main object
            catalogObject = CatalogObject(
                id: catalogObject.id,
                type: catalogObject.type,
                updatedAt: catalogObject.updatedAt,
                version: currentVersion, // Use current version from Square API
                isDeleted: catalogObject.isDeleted,
                presentAtAllLocations: catalogObject.presentAtAllLocations,
                presentAtLocationIds: catalogObject.presentAtLocationIds,
                absentAtLocationIds: catalogObject.absentAtLocationIds,
                itemData: try updateItemDataWithCurrentVersions(catalogObject.itemData, currentItem: currentObject),
                categoryData: catalogObject.categoryData,
                itemVariationData: catalogObject.itemVariationData,
                modifierData: catalogObject.modifierData,
                modifierListData: catalogObject.modifierListData,
                taxData: catalogObject.taxData,
                discountData: catalogObject.discountData,
                imageData: catalogObject.imageData
            )
            
            // 5. SQUARE API: Update with idempotency key (get full response with ID mappings)
            let idempotencyKey = "update_item_\(itemId)_\(Date().timeIntervalSince1970)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let updatedObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from update operation")
            }

            // 6. DATABASE SYNC: Update local database with exact API response and ID mappings
            try await updateLocalDatabaseAfterUpdate(updatedObject, idMappings: response.idMappings)
            
            // 7. SUCCESS: Record operation result
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
            
            // 8. UI REFRESH: Notify UI components to refresh with updated data
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": updatedObject.id, "operation": "update"]
                )
                logger.info("📡 Posted catalog sync notification for updated item: \(updatedObject.id)")
            }
            
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
            
            // 4. UI REFRESH: Notify UI components to refresh with deleted item
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": itemId, "operation": "delete"]
                )
                logger.info("📡 Posted catalog sync notification for deleted item: \(itemId)")
            }
            
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
        
        // Validate location logic consistency
        validateLocationFields(itemDetails)
        
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
    
    // MARK: - Location Field Validation
    
    /// Validate Square location fields for consistency and log location data being sent
    private func validateLocationFields(_ itemDetails: ItemDetailsData) {
        // Log location data being sent to Square API
        logger.info("📍 CRUD Location Data - presentAtAllLocations: \(itemDetails.presentAtAllLocations)")
        logger.info("📍 CRUD Location Data - presentAtLocationIds: \(itemDetails.presentAtLocationIds.count) locations: \(itemDetails.presentAtLocationIds)")
        logger.info("📍 CRUD Location Data - absentAtLocationIds: \(itemDetails.absentAtLocationIds.count) locations: \(itemDetails.absentAtLocationIds)")
        
        // Validate Square location logic consistency
        if itemDetails.presentAtAllLocations {
            // When present at all locations, we should use absent list for exceptions
            if !itemDetails.presentAtLocationIds.isEmpty {
                logger.warning("⚠️ Potential location logic issue: presentAtAllLocations=true but presentAtLocationIds is not empty. Square uses absentAtLocationIds for exceptions when presentAtAllLocations=true")
            }
        } else {
            // When not present at all locations, we should use present list for specific locations
            if !itemDetails.absentAtLocationIds.isEmpty {
                logger.warning("⚠️ Potential location logic issue: presentAtAllLocations=false but absentAtLocationIds is not empty. Square uses presentAtLocationIds for specific locations when presentAtAllLocations=false")
            }
            
            // Validate we have at least one location specified
            if itemDetails.presentAtLocationIds.isEmpty {
                logger.warning("⚠️ Location logic warning: presentAtAllLocations=false but no presentAtLocationIds specified. Item may not be available anywhere")
            }
        }
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
        // CRITICAL: Database operations must complete BEFORE function returns to ensure data consistency
        do {
            // Insert the main item object
            try await databaseManager.insertCatalogObject(createdObject)
            logger.debug("✅ Main item object created in database: \(createdObject.id)")

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
                        presentAtAllLocations: createdObject.presentAtAllLocations, // Inherit from parent item
                        presentAtLocationIds: createdObject.presentAtLocationIds, // Inherit from parent item
                        absentAtLocationIds: createdObject.absentAtLocationIds, // Inherit from parent item
                        itemData: nil,
                        categoryData: nil,
                        itemVariationData: variation.itemVariationData,
                        modifierData: nil,
                        modifierListData: nil,
                        taxData: nil,
                        discountData: nil,
                        imageData: nil
                    )

                    try await databaseManager.insertCatalogObject(variationObject)
                    logger.debug("✅ Inserted variation: \(variation.id ?? "nil") for item \(createdObject.id)")
                }
            }
            logger.debug("✅ All database inserts completed for item: \(createdObject.id)")
        } catch {
            logger.error("❌ Database insert failed for item \(createdObject.id): \(error)")
            // Re-throw the error since this is a critical failure that should be handled by the caller
            throw error
        }

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

        // CRITICAL: Preserve existing image data before database update
        // When we omit image_ids from Square request, the response also omits images
        // We need to restore existing image data to prevent losing images during item updates
        var objectToStore = updatedObject
        if updatedObject.type == "ITEM" {
            do {
                // Get current image data from database
                let existingImageIds = try await getCurrentImageIds(for: updatedObject.id)
                if !existingImageIds.isEmpty {
                    logger.debug("🔄 Preserving \(existingImageIds.count) existing images for item: \(updatedObject.id)")
                    
                    // Create updated ItemData with preserved image IDs
                    if let itemData = updatedObject.itemData {
                        let preservedItemData = ItemData(
                            name: itemData.name,
                            description: itemData.description,
                            categoryId: itemData.categoryId,
                            taxIds: itemData.taxIds,
                            variations: itemData.variations,
                            productType: itemData.productType,
                            skipModifierScreen: itemData.skipModifierScreen,
                            itemOptions: itemData.itemOptions,
                            modifierListInfo: itemData.modifierListInfo,
                            images: itemData.images,
                            labelColor: itemData.labelColor,
                            availableOnline: itemData.availableOnline,
                            availableForPickup: itemData.availableForPickup,
                            availableElectronically: itemData.availableElectronically,
                            abbreviation: itemData.abbreviation,
                            categories: itemData.categories,
                            reportingCategory: itemData.reportingCategory,
                            imageIds: existingImageIds, // PRESERVE existing images
                            isTaxable: itemData.isTaxable,
                            isAlcoholic: itemData.isAlcoholic,
                            sortName: itemData.sortName,
                            taxNames: itemData.taxNames,
                            modifierNames: itemData.modifierNames
                        )
                        
                        // Create updated CatalogObject with preserved images
                        objectToStore = CatalogObject(
                            id: updatedObject.id,
                            type: updatedObject.type,
                            updatedAt: updatedObject.updatedAt,
                            version: updatedObject.version,
                            isDeleted: updatedObject.isDeleted,
                            presentAtAllLocations: updatedObject.presentAtAllLocations,
                            presentAtLocationIds: updatedObject.presentAtLocationIds,
                            absentAtLocationIds: updatedObject.absentAtLocationIds,
                            itemData: preservedItemData,
                            categoryData: updatedObject.categoryData,
                            itemVariationData: updatedObject.itemVariationData,
                            modifierData: updatedObject.modifierData,
                            modifierListData: updatedObject.modifierListData,
                            taxData: updatedObject.taxData,
                            discountData: updatedObject.discountData,
                            imageData: updatedObject.imageData
                        )
                        
                        logger.debug("✅ Enhanced item with preserved image IDs: \(existingImageIds)")
                    }
                }
            } catch {
                logger.warning("⚠️ Could not retrieve existing images for item \(updatedObject.id): \(error)")
                // Continue with original object if image preservation fails
            }
        }

        // WEBHOOK COMPATIBILITY: These exact timestamps will match webhook notifications
        // This ensures no conflicts when catalog.version.updated webhooks arrive
        // CRITICAL: Database operations must complete BEFORE function returns to ensure data consistency
        do {
            // Use upsert to handle both insert and update cases
            try await databaseManager.insertCatalogObject(objectToStore)
            logger.debug("✅ Main item object updated in database: \(updatedObject.id)")

            // CRITICAL: Process variations separately for scalability (same as create)
            if let itemData = objectToStore.itemData, let variations = itemData.variations {
                logger.debug("Processing \(variations.count) variations for updated item \(updatedObject.id)")
                
                // Get current variation IDs that exist in Square's response
                let currentVariationIds = Set(variations.compactMap { $0.id })
                
                // Mark removed variations as deleted in database
                do {
                    try await markRemovedVariationsAsDeleted(
                        itemId: updatedObject.id, 
                        currentVariationIds: currentVariationIds,
                        timestamp: updatedObject.safeUpdatedAt
                    )
                } catch {
                    logger.warning("⚠️ Failed to mark removed variations as deleted: \(error)")
                }

                for variation in variations {
                    // Create a separate CatalogObject for each variation
                    let variationObject = CatalogObject(
                        id: variation.id ?? "UNKNOWN_VARIATION_ID",
                        type: "ITEM_VARIATION",
                        updatedAt: updatedObject.updatedAt,
                        version: updatedObject.version,
                        isDeleted: variation.isDeleted,
                        presentAtAllLocations: updatedObject.presentAtAllLocations, // Inherit from parent item
                        presentAtLocationIds: updatedObject.presentAtLocationIds, // Inherit from parent item
                        absentAtLocationIds: updatedObject.absentAtLocationIds, // Inherit from parent item
                        itemData: nil,
                        categoryData: nil,
                        itemVariationData: variation.itemVariationData,
                        modifierData: nil,
                        modifierListData: nil,
                        taxData: nil,
                        discountData: nil,
                        imageData: nil
                    )

                    try await databaseManager.insertCatalogObject(variationObject)
                    logger.debug("✅ Updated variation: \(variation.id ?? "nil") for item \(updatedObject.id)")
                }
            }
            logger.debug("✅ All database updates completed for item: \(updatedObject.id)")
        } catch {
            logger.error("❌ Database update failed for item \(updatedObject.id): \(error)")
            // Re-throw the error since this is a critical failure that should be handled by the caller
            throw error
        }

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
                presentAtLocationIds: nil,
                absentAtLocationIds: nil,
                itemData: nil,
                categoryData: nil,
                itemVariationData: nil,
                modifierData: nil,
                modifierListData: nil,
                taxData: nil,
                discountData: nil,
                imageData: nil
            )

            // CRITICAL: Database operations must complete BEFORE function returns to ensure data consistency
            do {
                try await databaseManager.insertCatalogObject(deletedCatalogObject)
                logger.debug("✅ Deleted object marked in database: \(objectId)")
            } catch {
                logger.error("❌ Database delete failed for object \(objectId): \(error)")
                // Re-throw the error since this is a critical failure that should be handled by the caller
                throw error
            }
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

// MARK: - SquareCRUDService Helper Methods Extension
extension SquareCRUDService {
    /// Update ItemData variations with current versions from Square API
    private func updateItemDataWithCurrentVersions(_ itemData: ItemData?, currentItem: CatalogObject) throws -> ItemData? {
        guard let itemData = itemData else { return nil }
        
        // Get current variations from Square's response to extract their versions
        let currentVariations = currentItem.itemData?.variations ?? []
        
        // Log variations being removed (present in Square but not in update)
        let updateVariationIds = Set(itemData.variations?.compactMap { $0.id } ?? [])
        for currentVar in currentVariations {
            if let varId = currentVar.id, !updateVariationIds.contains(varId) && !varId.hasPrefix("#") {
                logger.info("📝 Variation \(varId) will be removed (not included in update)")
            }
        }
        
        // Update variations with current versions
        let updatedVariations = try itemData.variations?.map { variation in
            // Find matching current variation by ID
            let currentVariation = currentVariations.first { $0.id == variation.id }
            
            var effectiveId = variation.id
            var currentVersion: Int64? = nil
            
            if let varId = variation.id, !varId.hasPrefix("#") {
                // This variation claims to have a Square ID - it MUST exist in Square
                guard let found = currentVariation else {
                    // This is a critical sync error - variation has ID but doesn't exist in Square
                    logger.error("❌ Critical sync error: Variation \(varId) not found in Square")
                    throw SquareCRUDError.invalidData("Variation \(varId) is out of sync with Square. Please perform a full sync and try again.")
                }
                
                // Variation exists in Square - use its current version
                currentVersion = found.safeVersion
                logger.debug("Variation \(varId) found in Square with version \(currentVersion ?? 0)")
                
            } else {
                // New variation with temporary ID or nil ID (intentionally created)
                if effectiveId == nil {
                    effectiveId = "#\(UUID().uuidString)"
                }
                currentVersion = nil
                logger.debug("New variation will be created with temp ID: \(effectiveId ?? "nil")")
            }
            
            return ItemVariation(
                id: effectiveId,
                type: variation.type,
                updatedAt: variation.updatedAt,
                version: currentVersion, // Use current version from Square, or nil for new variations
                isDeleted: variation.isDeleted,
                presentAtAllLocations: variation.presentAtAllLocations,
                presentAtLocationIds: variation.presentAtLocationIds,
                absentAtLocationIds: variation.absentAtLocationIds,
                itemVariationData: variation.itemVariationData
            )
        }
        
        return ItemData(
            name: itemData.name,
            description: itemData.description,
            categoryId: itemData.categoryId,
            taxIds: itemData.taxIds,
            variations: updatedVariations,
            productType: itemData.productType,
            skipModifierScreen: itemData.skipModifierScreen,
            itemOptions: itemData.itemOptions,
            modifierListInfo: itemData.modifierListInfo,
            images: itemData.images,
            labelColor: itemData.labelColor,
            availableOnline: itemData.availableOnline,
            availableForPickup: itemData.availableForPickup,
            availableElectronically: itemData.availableElectronically,
            abbreviation: itemData.abbreviation,
            categories: itemData.categories,
            reportingCategory: itemData.reportingCategory,
            imageIds: itemData.imageIds,
            isTaxable: itemData.isTaxable,
            isAlcoholic: itemData.isAlcoholic,
            sortName: itemData.sortName,
            taxNames: itemData.taxNames,
            modifierNames: itemData.modifierNames
        )
    }
    
    /// Mark variations as deleted in the database if they no longer exist in Square
    private func markRemovedVariationsAsDeleted(
        itemId: String, 
        currentVariationIds: Set<String>, 
        timestamp: String
    ) async throws {
        let db = databaseManager.getContext()
        
        do {
            // Find all variations in database for this item that are not in Square's current response
            let descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.itemId == itemId && !variation.isDeleted
                }
            )
            
            var variationsToDelete: [String] = []
            let variations = try db.fetch(descriptor)
            
            for variation in variations {
                let variationId = variation.id
                // If this variation ID is not in Square's current response, it was removed
                if !currentVariationIds.contains(variationId) {
                    variationsToDelete.append(variationId)
                }
            }
            
            // Mark removed variations as deleted
            if !variationsToDelete.isEmpty {
                for variationId in variationsToDelete {
                    // Find the variation to update using SwiftData
                    let updateDescriptor = FetchDescriptor<ItemVariationModel>(
                        predicate: #Predicate { variation in
                            variation.id == variationId
                        }
                    )
                    
                    if let variationToUpdate = try db.fetch(updateDescriptor).first {
                        variationToUpdate.isDeleted = true
                        variationToUpdate.updatedAt = ISO8601DateFormatter().date(from: timestamp) ?? Date()
                        try db.save()
                        logger.info("🗑️ Marked variation \(variationId) as deleted in database")
                    }
                }
                logger.info("🗑️ Marked \(variationsToDelete.count) removed variations as deleted")
            }
            
        } catch {
            logger.error("❌ Failed to mark removed variations as deleted for item \(itemId): \(error)")
            throw error
        }
    }
    
    /// Get current image IDs for an item from the database
    /// Used to preserve existing images during item updates
    private func getCurrentImageIds(for itemId: String) async throws -> [String] {
        let db = databaseManager.getContext()
        
        do {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == itemId && !item.isDeleted
                }
            )
            
            guard let catalogItem = try db.fetch(descriptor).first,
                  let dataJson = catalogItem.dataJson,
                  let data = dataJson.data(using: String.Encoding.utf8) else {
                return []
            }
            
            // Parse JSON to extract image_ids
            if let catalogData = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try nested under item_data first (current format)
                if let itemData = catalogData["item_data"] as? [String: Any],
                   let imageIds = itemData["image_ids"] as? [String] {
                    logger.debug("📷 Found \(imageIds.count) existing images in item_data for: \(itemId)")
                    return imageIds
                }
                
                // Fallback to root level (legacy format)
                if let imageIds = catalogData["image_ids"] as? [String] {
                    logger.debug("📷 Found \(imageIds.count) existing images at root level for: \(itemId)")
                    return imageIds
                }
            }
        } catch {
            logger.error("❌ Failed to get existing image IDs for item \(itemId): \(error)")
            throw error
        }
        
        // No images found
        logger.debug("📷 No existing images found for item: \(itemId)")
        return []
    }
}
