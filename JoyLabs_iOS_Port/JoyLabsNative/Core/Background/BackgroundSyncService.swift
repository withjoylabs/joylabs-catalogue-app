import Foundation
import SwiftData
import OSLog

/// Background sync service for heavy database operations
/// Creates ModelContext within each method to ensure proper thread isolation
actor BackgroundSyncService {

    private let logger = Logger(subsystem: "com.joylabs.native", category: "BackgroundSync")
    private let squareAPIService: SquareAPIService
    private let modelContainer: ModelContainer

    // MARK: - Sync State Management

    private var isSyncInProgress: Bool = false
    private var currentSyncType: SyncType?

    // MARK: - Initialization

    init(modelContainer: ModelContainer, squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.modelContainer = modelContainer

        logger.info("[BackgroundSync] BackgroundSyncService initialized")
    }

    // MARK: - Background Sync Operations

    /// Perform incremental sync on background thread
    func performIncrementalSync() async throws -> BackgroundSyncResult {
        // Check if sync is already in progress
        if isSyncInProgress {
            logger.warning("[BackgroundSync] Sync already in progress (\(self.currentSyncType?.rawValue ?? "unknown")), skipping incremental sync request")
            throw BackgroundSyncError.syncInProgress
        }

        // Mark sync as in progress
        isSyncInProgress = true
        currentSyncType = .incremental
        defer {
            isSyncInProgress = false
            currentSyncType = nil
        }

        logger.info("[BackgroundSync] Starting background incremental sync")
        let startTime = Date()

        // Create ModelContext for this operation on background thread
        let modelContext = ModelContext(modelContainer)

        // Get the last sync timestamp from background context
        let lastUpdateTime = try await getLatestUpdatedAt(modelContext: modelContext)

        guard let lastUpdate = lastUpdateTime else {
            logger.info("[BackgroundSync] No previous sync found, suggesting full sync")
            throw BackgroundSyncError.noPreviousSync
        }

        let formatter = ISO8601DateFormatter()
        let beginTime = formatter.string(from: lastUpdate)
        logger.info("[BackgroundSync] Incremental sync from: \(beginTime)")

        // Fetch updated objects since last sync
        let updatedObjects = try await squareAPIService.searchCatalog(beginTime: beginTime)
        logger.info("[BackgroundSync] Found \(updatedObjects.count) updated objects")

        if updatedObjects.isEmpty {
            let result = BackgroundSyncResult(
                syncType: SyncType.incremental,
                duration: Date().timeIntervalSince(startTime),
                totalProcessed: 0,
                itemsProcessed: 0,
                inserted: 0,
                updated: 0,
                deleted: 0,
                errors: [],
                timestamp: Date()
            )
            logger.info("[BackgroundSync] Incremental sync completed - no changes")
            return result
        }

        // Process objects in dependency order
        let sortedObjects = sortObjectsByDependency(updatedObjects)
        let (totalProcessed, itemsProcessed) = try await processCatalogObjectsBatch(sortedObjects, modelContext: modelContext)

        // Save changes to background context
        try modelContext.save()

        // Save sync timestamp to prevent future full syncs
        try await saveSyncTimestamp(modelContext: modelContext)

        let result = BackgroundSyncResult(
            syncType: SyncType.incremental,
            duration: Date().timeIntervalSince(startTime),
            totalProcessed: totalProcessed,
            itemsProcessed: itemsProcessed,
            inserted: 0,
            updated: totalProcessed,
            deleted: 0,
            errors: [],
            timestamp: Date()
        )

        logger.info("[BackgroundSync] Incremental sync completed: \(result.summary)")
        return result
    }

    /// Perform full sync on background thread
    func performFullSync() async throws -> BackgroundSyncResult {
        // Check if sync is already in progress
        if isSyncInProgress {
            logger.warning("[BackgroundSync] Sync already in progress (\(self.currentSyncType?.rawValue ?? "unknown")), skipping full sync request")
            throw BackgroundSyncError.syncInProgress
        }

        // Mark sync as in progress
        isSyncInProgress = true
        currentSyncType = .full
        defer {
            isSyncInProgress = false
            currentSyncType = nil
        }

        logger.info("[BackgroundSync] Starting background full sync")
        let startTime = Date()

        // Create ModelContext for this operation on background thread
        let modelContext = ModelContext(modelContainer)

        // Clear existing data in background context
        try await clearAllData(modelContext: modelContext)
        logger.info("[BackgroundSync] Cleared existing catalog data")

        // Fetch all catalog data from Square API
        let allObjects = try await squareAPIService.fetchCatalog()
        logger.info("[BackgroundSync] Fetched \(allObjects.count) objects from Square API")

        // Process objects in dependency order
        let sortedObjects = sortObjectsByDependency(allObjects)
        let (totalProcessed, itemsProcessed) = try await processCatalogObjectsBatch(sortedObjects, modelContext: modelContext)

        // Process image URL mappings
        let imageObjects = sortedObjects.filter { $0.type == "IMAGE" }
        for imageObject in imageObjects {
            await processImageURLMapping(imageObject)
        }

        // CRITICAL: Save sync timestamp BEFORE final save to ensure it's in the same transaction
        try await saveSyncTimestamp(modelContext: modelContext)

        // Final save to commit everything including timestamp
        try modelContext.save()
        logger.info("[BackgroundSync] Saved full sync with timestamp - future syncs will be incremental")

        let result = BackgroundSyncResult(
            syncType: SyncType.full,
            duration: Date().timeIntervalSince(startTime),
            totalProcessed: totalProcessed,
            itemsProcessed: itemsProcessed,
            inserted: totalProcessed,
            updated: 0,
            deleted: 0,
            errors: [],
            timestamp: Date()
        )

        logger.info("[BackgroundSync] Full sync completed: \(result.summary)")
        return result
    }

    // MARK: - Private Methods

    private func getLatestUpdatedAt(modelContext: ModelContext) async throws -> Date? {
        var descriptor = FetchDescriptor<SyncStatusModel>(
            sortBy: [SortDescriptor(\.lastSyncTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let results = try modelContext.fetch(descriptor)
        return results.first?.lastSyncTime
    }

    private func clearAllData(modelContext: ModelContext) async throws {
        // Clear all catalog data types in background context
        let itemDescriptor = FetchDescriptor<CatalogItemModel>()
        let items = try modelContext.fetch(itemDescriptor)
        for item in items {
            modelContext.delete(item)
        }

        let variationDescriptor = FetchDescriptor<ItemVariationModel>()
        let variations = try modelContext.fetch(variationDescriptor)
        for variation in variations {
            modelContext.delete(variation)
        }

        let categoryDescriptor = FetchDescriptor<CategoryModel>()
        let categories = try modelContext.fetch(categoryDescriptor)
        for category in categories {
            modelContext.delete(category)
        }

        let taxDescriptor = FetchDescriptor<TaxModel>()
        let taxes = try modelContext.fetch(taxDescriptor)
        for tax in taxes {
            modelContext.delete(tax)
        }

        let modifierListDescriptor = FetchDescriptor<ModifierListModel>()
        let modifierLists = try modelContext.fetch(modifierListDescriptor)
        for modifierList in modifierLists {
            modelContext.delete(modifierList)
        }

        let modifierDescriptor = FetchDescriptor<ModifierModel>()
        let modifiers = try modelContext.fetch(modifierDescriptor)
        for modifier in modifiers {
            modelContext.delete(modifier)
        }

        let imageDescriptor = FetchDescriptor<ImageModel>()
        let images = try modelContext.fetch(imageDescriptor)
        for image in images {
            modelContext.delete(image)
        }

        let teamDataDescriptor = FetchDescriptor<TeamDataModel>()
        let teamData = try modelContext.fetch(teamDataDescriptor)
        for data in teamData {
            modelContext.delete(data)
        }

        let discountDescriptor = FetchDescriptor<DiscountModel>()
        let discounts = try modelContext.fetch(discountDescriptor)
        for discount in discounts {
            modelContext.delete(discount)
        }

        try modelContext.save()
        logger.info("[BackgroundSync] All catalog data cleared from background context")
    }

    private func processCatalogObjectsBatch(_ objects: [CatalogObject], modelContext: ModelContext) async throws -> (totalProcessed: Int, itemsProcessed: Int) {
        var totalProcessed = 0
        var itemsProcessed = 0

        for object in objects {
            try await insertCatalogObject(object, modelContext: modelContext)

            totalProcessed += 1
            if object.type == "ITEM" {
                itemsProcessed += 1
            }

            // Periodic saves for large batches
            if totalProcessed % 100 == 0 {
                try modelContext.save()
                logger.debug("[BackgroundSync] Saved batch at \(totalProcessed) objects")
            }
        }

        logger.info("[BackgroundSync] Processed \(totalProcessed) objects (\(itemsProcessed) items)")
        return (totalProcessed, itemsProcessed)
    }

    private func sortObjectsByDependency(_ objects: [CatalogObject]) -> [CatalogObject] {
        // Sort by dependency order to ensure proper relationships
        let order: [String: Int] = [
            "CATEGORY": 1,      // Categories must come first
            "TAX": 2,           // Taxes needed for items
            "MODIFIER_LIST": 3, // Modifier lists before modifiers
            "MODIFIER": 4,      // Modifiers before items use them
            "ITEM": 5,          // Items before their variations
            "ITEM_VARIATION": 6,// Variations after items
            "IMAGE": 7,         // Images after everything else
            "DISCOUNT": 8       // Discounts last
        ]

        return objects.sorted { first, second in
            let firstOrder = order[first.type] ?? 999
            let secondOrder = order[second.type] ?? 999
            return firstOrder < secondOrder
        }
    }

    private func insertCatalogObject(_ object: CatalogObject, modelContext: ModelContext) async throws {
        switch object.type {
        case "ITEM":
            try await insertItem(object, modelContext: modelContext)
        case "ITEM_VARIATION":
            try await insertItemVariation(object, modelContext: modelContext)
        case "CATEGORY":
            try await insertCategory(object, modelContext: modelContext)
        case "TAX":
            try await insertTax(object, modelContext: modelContext)
        case "MODIFIER_LIST":
            try await insertModifierList(object, modelContext: modelContext)
        case "MODIFIER":
            try await insertModifier(object, modelContext: modelContext)
        case "IMAGE":
            try await insertImage(object, modelContext: modelContext)
        case "DISCOUNT":
            try await insertDiscount(object, modelContext: modelContext)
        default:
            logger.warning("[BackgroundSync] Unknown object type: \(object.type)")
        }
    }

    // MARK: - Object Insertion Methods

    private func insertItem(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted items FIRST (before checking itemData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<CatalogItemModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked item as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted item \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.itemData != nil else {
            logger.warning("[BackgroundSync] ITEM object \(object.id) missing itemData")
            return
        }

        // Check if item already exists (UPSERT logic)
        let descriptor = FetchDescriptor<CatalogItemModel>(predicate: #Predicate { $0.id == object.id })

        if let existingItem = try modelContext.fetch(descriptor).first {
            // Update existing item
            existingItem.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing item: \(object.id)")
        } else {
            // Insert new item
            let item = CatalogItemModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            item.updateFromCatalogObject(object)
            modelContext.insert(item)
            logger.debug("[BackgroundSync] Inserted new item: \(object.id)")
        }
    }

    private func insertItemVariation(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted variations FIRST (before checking itemVariationData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<ItemVariationModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked variation as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted variation \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard let variationData = object.itemVariationData else {
            logger.warning("[BackgroundSync] ITEM_VARIATION object \(object.id) missing itemVariationData")
            return
        }

        // Check if variation already exists (UPSERT logic)
        let descriptor = FetchDescriptor<ItemVariationModel>(predicate: #Predicate { $0.id == object.id })

        if let existingVariation = try modelContext.fetch(descriptor).first {
            // Update existing variation
            existingVariation.updateFromCatalogObject(object)

            // Ensure relationship to parent item is established (may have been missing)
            if existingVariation.item == nil {
                let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                    predicate: #Predicate { $0.id == variationData.itemId }
                )
                if let parentItem = try modelContext.fetch(itemDescriptor).first {
                    existingVariation.item = parentItem
                    logger.debug("[BackgroundSync] Linked existing variation \(object.id) to parent item \(variationData.itemId)")
                }
            }

            logger.debug("[BackgroundSync] Updated existing variation: \(object.id)")
        } else {
            // Insert new variation
            let variation = ItemVariationModel(
                id: object.id,
                itemId: variationData.itemId,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            variation.updateFromCatalogObject(object)
            modelContext.insert(variation)

            // Link to parent item if it exists
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { $0.id == variationData.itemId }
            )
            if let parentItem = try modelContext.fetch(itemDescriptor).first {
                variation.item = parentItem
                logger.debug("[BackgroundSync] Linked new variation \(object.id) to parent item \(variationData.itemId)")
            }

            logger.debug("[BackgroundSync] Inserted new variation: \(object.id)")
        }
    }

    private func insertCategory(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted categories FIRST (before checking categoryData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<CategoryModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked category as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted category \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.categoryData != nil else {
            logger.warning("[BackgroundSync] CATEGORY object \(object.id) missing categoryData")
            return
        }

        // Check if category already exists (UPSERT logic)
        let descriptor = FetchDescriptor<CategoryModel>(predicate: #Predicate { $0.id == object.id })

        if let existingCategory = try modelContext.fetch(descriptor).first {
            // Update existing category
            existingCategory.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing category: \(object.id)")
        } else {
            // Insert new category
            let category = CategoryModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            category.updateFromCatalogObject(object)
            modelContext.insert(category)
            logger.debug("[BackgroundSync] Inserted new category: \(object.id)")
        }
    }

    private func insertTax(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted taxes FIRST (before checking taxData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<TaxModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked tax as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted tax \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.taxData != nil else {
            logger.warning("[BackgroundSync] TAX object \(object.id) missing taxData")
            return
        }

        // Check if tax already exists (UPSERT logic)
        let descriptor = FetchDescriptor<TaxModel>(predicate: #Predicate { $0.id == object.id })

        if let existingTax = try modelContext.fetch(descriptor).first {
            // Update existing tax
            existingTax.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing tax: \(object.id)")
        } else {
            // Insert new tax
            let tax = TaxModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            tax.updateFromCatalogObject(object)
            modelContext.insert(tax)
            logger.debug("[BackgroundSync] Inserted new tax: \(object.id)")
        }
    }

    private func insertModifierList(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted modifier lists FIRST (before checking modifierListData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<ModifierListModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked modifier list as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted modifier list \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.modifierListData != nil else {
            logger.warning("[BackgroundSync] MODIFIER_LIST object \(object.id) missing modifierListData")
            return
        }

        // Check if modifier list already exists (UPSERT logic)
        let descriptor = FetchDescriptor<ModifierListModel>(predicate: #Predicate { $0.id == object.id })

        if let existingModifierList = try modelContext.fetch(descriptor).first {
            // Update existing modifier list
            existingModifierList.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing modifier list: \(object.id)")
        } else {
            // Insert new modifier list
            let modifierList = ModifierListModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            modifierList.updateFromCatalogObject(object)
            modelContext.insert(modifierList)
            logger.debug("[BackgroundSync] Inserted new modifier list: \(object.id)")
        }
    }

    private func insertModifier(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted modifiers FIRST (before checking modifierData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<ModifierModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked modifier as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted modifier \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.modifierData != nil else {
            logger.warning("[BackgroundSync] MODIFIER object \(object.id) missing modifierData")
            return
        }

        // Check if modifier already exists (UPSERT logic)
        let descriptor = FetchDescriptor<ModifierModel>(predicate: #Predicate { $0.id == object.id })

        if let existingModifier = try modelContext.fetch(descriptor).first {
            // Update existing modifier
            existingModifier.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing modifier: \(object.id)")
        } else {
            // Insert new modifier
            let modifier = ModifierModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            modifier.updateFromCatalogObject(object)
            modelContext.insert(modifier)
            logger.debug("[BackgroundSync] Inserted new modifier: \(object.id)")
        }
    }

    private func insertImage(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted images FIRST (before checking imageData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<ImageModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked image as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted image \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.imageData != nil else {
            logger.warning("[BackgroundSync] IMAGE object \(object.id) missing imageData")
            return
        }

        // Check if image already exists (UPSERT logic)
        let descriptor = FetchDescriptor<ImageModel>(predicate: #Predicate { $0.id == object.id })

        if let existingImage = try modelContext.fetch(descriptor).first {
            // Update existing image
            existingImage.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing image: \(object.id)")
        } else {
            // Insert new image
            let image = ImageModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            image.updateFromCatalogObject(object)
            modelContext.insert(image)
            logger.debug("[BackgroundSync] Inserted new image: \(object.id)")
        }
    }

    private func insertDiscount(_ object: CatalogObject, modelContext: ModelContext) async throws {
        // Handle deleted discounts FIRST (before checking discountData)
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<DiscountModel>(predicate: #Predicate { $0.id == object.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.safeVersion)
                logger.debug("[BackgroundSync] Marked discount as deleted: \(object.id)")
            } else {
                logger.debug("[BackgroundSync] Deleted discount \(object.id) doesn't exist locally - skipping")
            }
            return
        }

        guard object.discountData != nil else {
            logger.warning("[BackgroundSync] DISCOUNT object \(object.id) missing discountData")
            return
        }

        // Check if discount already exists (UPSERT logic)
        let descriptor = FetchDescriptor<DiscountModel>(predicate: #Predicate { $0.id == object.id })

        if let existingDiscount = try modelContext.fetch(descriptor).first {
            // Update existing discount
            existingDiscount.updateFromCatalogObject(object)
            logger.debug("[BackgroundSync] Updated existing discount: \(object.id)")
        } else {
            // Insert new discount
            let discount = DiscountModel(
                id: object.id,
                updatedAt: parseDate(object.updatedAt) ?? Date(),
                version: String(object.safeVersion),
                isDeleted: object.safeIsDeleted
            )

            discount.updateFromCatalogObject(object)
            modelContext.insert(discount)
            logger.debug("[BackgroundSync] Inserted new discount: \(object.id)")
        }
    }

    private func processImageURLMapping(_ object: CatalogObject) async {
        guard let imageData = object.imageData else {
            logger.warning("[BackgroundSync] IMAGE object \(object.id) missing imageData")
            return
        }

        guard let awsUrl = imageData.url, !awsUrl.isEmpty else {
            logger.warning("[BackgroundSync] IMAGE object \(object.id) missing URL")
            return
        }

        // Skip processing deleted images
        if object.safeIsDeleted {
            return
        }

        logger.debug("[BackgroundSync] Processed image URL mapping for: \(object.id) -> \(awsUrl)")
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }

    private func saveSyncTimestamp(modelContext: ModelContext) async throws {
        let descriptor = FetchDescriptor<SyncStatusModel>(
            predicate: #Predicate { $0.id == 1 }
        )

        let syncStatus: SyncStatusModel
        if let existing = try modelContext.fetch(descriptor).first {
            syncStatus = existing
        } else {
            syncStatus = SyncStatusModel(id: 1)
            modelContext.insert(syncStatus)
        }

        syncStatus.lastSyncTime = Date()
        try modelContext.save()
        logger.info("[BackgroundSync] Saved sync timestamp: \(syncStatus.lastSyncTime!)")
    }
}

// MARK: - Supporting Types

struct BackgroundSyncResult {
    let syncType: SyncType
    let duration: TimeInterval
    let totalProcessed: Int
    let itemsProcessed: Int
    let inserted: Int
    let updated: Int
    let deleted: Int
    let errors: [SyncError]
    let timestamp: Date

    var summary: String {
        return "Processed: \(itemsProcessed) items (\(totalProcessed) total objects), Inserted: \(inserted), Updated: \(updated), Deleted: \(deleted), Errors: \(errors.count)"
    }
}

enum BackgroundSyncError: LocalizedError {
    case noPreviousSync
    case syncInProgress
    case objectProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPreviousSync:
            return "No previous sync found, full sync required"
        case .syncInProgress:
            return "Sync already in progress, please wait"
        case .objectProcessingFailed(let objectId):
            return "Failed to process object: \(objectId)"
        }
    }
}