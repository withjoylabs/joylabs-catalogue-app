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
    private let databaseManager: SwiftDataCatalogManager
    private let dataConverter: SquareDataConverter
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareCRUDService")
    
    // MARK: - Published State
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var lastOperationResult: CRUDOperationResult?
    
    // MARK: - Initialization
    
    init(
        squareAPIService: SquareAPIService,
        databaseManager: SwiftDataCatalogManager,
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
    
    // MARK: - Image CRUD Operations

    /// Attach an image to an item (independent of item details modal)
    /// Preserves existing images and adds the new one at the specified position
    func attachImageToItem(imageId: String, itemId: String, isPrimary: Bool = false, ordinal: Int? = nil) async throws -> CatalogObject {
        logger.info("Attaching image \(imageId) to item \(itemId) (primary: \(isPrimary))")

        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1. FETCH CURRENT ITEM: Get latest data from Square
            logger.debug("Fetching current item from Square API: \(itemId)")
            let currentObject = try await squareAPIService.fetchCatalogObjectById(itemId)
            let currentVersion = currentObject.safeVersion

            // 2. GET CURRENT IMAGES: Extract existing imageIds
            var imageIds = currentObject.itemData?.imageIds ?? []
            logger.debug("Current imageIds: \(imageIds)")

            // 3. ADD NEW IMAGE: Insert at specified position or make primary
            if isPrimary {
                // Remove imageId if it already exists (to avoid duplicates)
                imageIds.removeAll { $0 == imageId }
                // Insert at beginning as primary
                imageIds.insert(imageId, at: 0)
                logger.info("Added image \(imageId) as primary (position 0)")
            } else if let ordinal = ordinal, ordinal < imageIds.count {
                // Remove imageId if it already exists
                imageIds.removeAll { $0 == imageId }
                // Insert at specified position
                imageIds.insert(imageId, at: ordinal)
                logger.info("Added image \(imageId) at position \(ordinal)")
            } else {
                // Append to end if not already present
                if !imageIds.contains(imageId) {
                    imageIds.append(imageId)
                    logger.info("Added image \(imageId) at end (position \(imageIds.count - 1))")
                } else {
                    logger.info("Image \(imageId) already exists in item \(itemId), no changes needed")
                }
            }

            // 4. CREATE UPDATE PAYLOAD: Preserve all item data, only update imageIds
            guard let itemData = currentObject.itemData else {
                throw SquareCRUDError.invalidData("Item data not found for item \(itemId)")
            }

            let updatedItemData = ItemData(
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
                imageIds: imageIds.isEmpty ? nil : imageIds, // Updated imageIds
                isTaxable: itemData.isTaxable,
                isAlcoholic: itemData.isAlcoholic,
                sortName: itemData.sortName,
                taxNames: itemData.taxNames,
                modifierNames: itemData.modifierNames
            )

            let catalogObject = CatalogObject(
                id: itemId,
                type: "ITEM",
                updatedAt: currentObject.updatedAt,
                version: currentVersion,
                isDeleted: currentObject.isDeleted,
                presentAtAllLocations: currentObject.presentAtAllLocations,
                presentAtLocationIds: currentObject.presentAtLocationIds,
                absentAtLocationIds: currentObject.absentAtLocationIds,
                itemData: updatedItemData,
                categoryData: nil,
                itemVariationData: nil,
                modifierData: nil,
                modifierListData: nil,
                taxData: nil,
                discountData: nil,
                imageData: nil
            )

            // 5. SQUARE API: Update item with new imageIds
            let idempotencyKey = "attach_image_\(itemId)_\(imageId)_\(Date().timeIntervalSince1970)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let updatedObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from image attach operation")
            }

            // 6. DATABASE SYNC: Update local database
            try await updateLocalDatabaseAfterUpdate(updatedObject, idMappings: response.idMappings)

            logger.info("✅ Successfully attached image \(imageId) to item \(itemId)")

            // 7. UI REFRESH
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": itemId, "operation": "attachImage"]
                )
            }

            return updatedObject

        } catch {
            logger.error("❌ Failed to attach image: \(error.localizedDescription)")
            lastError = error
            throw error
        }
    }

    /// Remove an image from an item (independent of item details modal)
    /// Preserves all other images
    func removeImageFromItem(imageId: String, itemId: String) async throws -> CatalogObject {
        logger.info("Removing image \(imageId) from item \(itemId)")

        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1. FETCH CURRENT ITEM
            let currentObject = try await squareAPIService.fetchCatalogObjectById(itemId)
            let currentVersion = currentObject.safeVersion

            // 2. REMOVE IMAGE: Filter out the specified imageId
            var imageIds = currentObject.itemData?.imageIds ?? []
            let originalCount = imageIds.count
            imageIds.removeAll { $0 == imageId }

            guard imageIds.count < originalCount else {
                logger.warning("Image \(imageId) not found in item \(itemId), no changes needed")
                return currentObject
            }

            logger.info("Removed image \(imageId), \(originalCount) -> \(imageIds.count) images remaining")

            // 3. CREATE UPDATE PAYLOAD
            guard let itemData = currentObject.itemData else {
                throw SquareCRUDError.invalidData("Item data not found for item \(itemId)")
            }

            let updatedItemData = ItemData(
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
                imageIds: imageIds.isEmpty ? nil : imageIds,
                isTaxable: itemData.isTaxable,
                isAlcoholic: itemData.isAlcoholic,
                sortName: itemData.sortName,
                taxNames: itemData.taxNames,
                modifierNames: itemData.modifierNames
            )

            let catalogObject = CatalogObject(
                id: itemId,
                type: "ITEM",
                updatedAt: currentObject.updatedAt,
                version: currentVersion,
                isDeleted: currentObject.isDeleted,
                presentAtAllLocations: currentObject.presentAtAllLocations,
                presentAtLocationIds: currentObject.presentAtLocationIds,
                absentAtLocationIds: currentObject.absentAtLocationIds,
                itemData: updatedItemData,
                categoryData: nil,
                itemVariationData: nil,
                modifierData: nil,
                modifierListData: nil,
                taxData: nil,
                discountData: nil,
                imageData: nil
            )

            // 4. SQUARE API UPDATE
            let idempotencyKey = "remove_image_\(itemId)_\(imageId)_\(Date().timeIntervalSince1970)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let updatedObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from image remove operation")
            }

            // 5. DATABASE SYNC
            try await updateLocalDatabaseAfterUpdate(updatedObject, idMappings: response.idMappings)

            logger.info("✅ Successfully removed image \(imageId) from item \(itemId)")

            // 6. UI REFRESH
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": itemId, "operation": "removeImage"]
                )
            }

            return updatedObject

        } catch {
            logger.error("❌ Failed to remove image: \(error.localizedDescription)")
            lastError = error
            throw error
        }
    }

    /// Reorder images for an item (preserves image order)
    /// Pass the complete list of imageIds in the desired order
    func reorderImages(itemId: String, imageIds: [String]) async throws -> CatalogObject {
        logger.info("Reordering images for item \(itemId): \(imageIds)")

        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1. FETCH CURRENT ITEM
            let currentObject = try await squareAPIService.fetchCatalogObjectById(itemId)
            let currentVersion = currentObject.safeVersion

            // 2. CREATE UPDATE PAYLOAD with new image order
            guard let itemData = currentObject.itemData else {
                throw SquareCRUDError.invalidData("Item data not found for item \(itemId)")
            }

            let updatedItemData = ItemData(
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
                imageIds: imageIds.isEmpty ? nil : imageIds, // New order
                isTaxable: itemData.isTaxable,
                isAlcoholic: itemData.isAlcoholic,
                sortName: itemData.sortName,
                taxNames: itemData.taxNames,
                modifierNames: itemData.modifierNames
            )

            let catalogObject = CatalogObject(
                id: itemId,
                type: "ITEM",
                updatedAt: currentObject.updatedAt,
                version: currentVersion,
                isDeleted: currentObject.isDeleted,
                presentAtAllLocations: currentObject.presentAtAllLocations,
                presentAtLocationIds: currentObject.presentAtLocationIds,
                absentAtLocationIds: currentObject.absentAtLocationIds,
                itemData: updatedItemData,
                categoryData: nil,
                itemVariationData: nil,
                modifierData: nil,
                modifierListData: nil,
                taxData: nil,
                discountData: nil,
                imageData: nil
            )

            // 3. SQUARE API UPDATE
            let idempotencyKey = "reorder_images_\(itemId)_\(Date().timeIntervalSince1970)"
            let response = try await squareAPIService.upsertCatalogObjectWithMappings(
                catalogObject,
                idempotencyKey: idempotencyKey
            )

            guard let updatedObject = response.catalogObject else {
                throw SquareAPIError.upsertFailed("No object returned from image reorder operation")
            }

            // 4. DATABASE SYNC
            try await updateLocalDatabaseAfterUpdate(updatedObject, idMappings: response.idMappings)

            logger.info("✅ Successfully reordered images for item \(itemId)")

            // 5. UI REFRESH
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .catalogSyncCompleted,
                    object: nil,
                    userInfo: ["itemId": itemId, "operation": "reorderImages"]
                )
            }

            return updatedObject

        } catch {
            logger.error("❌ Failed to reorder images: \(error.localizedDescription)")
            lastError = error
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

        // WEBHOOK COMPATIBILITY: These exact timestamps will match webhook notifications
        // This ensures no conflicts when catalog.version.updated webhooks arrive
        // CRITICAL: Database operations must complete BEFORE function returns to ensure data consistency
        //
        // NOTE: Image preservation now happens at API request level (in updateItemDataWithCurrentVersions)
        // We send the correct imageIds to Square, so the response will include them
        do {
            // Use upsert to handle both insert and update cases
            try await databaseManager.insertCatalogObject(updatedObject)
            logger.debug("✅ Main item object updated in database: \(updatedObject.id)")

            // CRITICAL: Process variations separately for scalability (same as create)
            if let itemData = updatedObject.itemData, let variations = itemData.variations {
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
    /// CRITICAL: Also preserves existing imageIds to prevent image deletion during updates
    private func updateItemDataWithCurrentVersions(_ itemData: ItemData?, currentItem: CatalogObject) throws -> ItemData? {
        guard let itemData = itemData else { return nil }

        // CRITICAL: Extract current imageIds from Square to preserve them during update
        // If we don't do this, sending imageIds: nil will delete all images
        let currentImageIds = currentItem.itemData?.imageIds ?? []
        logger.debug("[SquareCRUDService] Preserving \(currentImageIds.count) existing imageIds from Square: \(currentImageIds)")

        // Get current variations from Square's response to extract their versions
        let currentVariations = currentItem.itemData?.variations ?? []

        // Build set of variation IDs that user wants to keep/update
        let updateVariationIds: Set<String> = Set(itemData.variations?.compactMap { variation in
            // Only count variations that have Square IDs (not temp IDs)
            if let id = variation.id, !id.hasPrefix("#") {
                return id
            }
            return nil
        } ?? [])

        // CRITICAL: Build list of variations to send
        // Square API: Omit deleted variations entirely (don't send with isDeleted: true)
        var allVariationsToSend: [ItemVariation] = []

        // Log which variations will be deleted (omitted from request)
        for currentVar in currentVariations {
            if let varId = currentVar.id, !updateVariationIds.contains(varId) && !varId.hasPrefix("#") {
                logger.info("[SquareCRUDService] Variation \(varId) will be deleted (omitted from update request)")
            }
        }

        // Then, add user's variations (updated and new)
        if let userVariations = itemData.variations {
            for variation in userVariations {
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

                allVariationsToSend.append(ItemVariation(
                    id: effectiveId,
                    type: variation.type,
                    updatedAt: variation.updatedAt,
                    version: currentVersion, // Use current version from Square, or nil for new variations
                    isDeleted: false, // User's variations are not deleted
                    presentAtAllLocations: variation.presentAtAllLocations,
                    presentAtLocationIds: variation.presentAtLocationIds,
                    absentAtLocationIds: variation.absentAtLocationIds,
                    itemVariationData: variation.itemVariationData
                ))
            }
        }

        logger.info("[SquareCRUDService] Total variations in update request: \(allVariationsToSend.count)")

        // Update variations to include both deleted and active variations
        let updatedVariations = allVariationsToSend.isEmpty ? nil : allVariationsToSend

        // CRITICAL: Use currentImageIds from Square to preserve existing images
        // This prevents image deletion when updating item properties
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
            imageIds: currentImageIds.isEmpty ? nil : currentImageIds, // PRESERVE existing images from Square
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
}
