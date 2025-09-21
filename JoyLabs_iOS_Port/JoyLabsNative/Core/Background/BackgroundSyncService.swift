import Foundation
import SwiftData
import OSLog

/// Background sync service for heavy database operations
/// Uses separate ModelContext to avoid blocking main thread
actor BackgroundSyncService {

    private let logger = Logger(subsystem: "com.joylabs.native", category: "BackgroundSync")
    private let squareAPIService: SquareAPIService
    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContainer: ModelContainer, squareAPIService: SquareAPIService) {
        self.squareAPIService = squareAPIService
        self.modelContext = ModelContext(modelContainer)

        logger.info("[BackgroundSync] BackgroundSyncService initialized with background context")
    }

    // MARK: - Background Sync Operations

    /// Perform incremental sync on background thread
    func performIncrementalSync() async throws -> BackgroundSyncResult {
        logger.info("[BackgroundSync] Starting background incremental sync")
        let startTime = Date()

        // Get the last sync timestamp from background context
        let lastUpdateTime = try await getLatestUpdatedAt()

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
        let (totalProcessed, itemsProcessed) = try await processCatalogObjectsBatch(sortedObjects)

        // Save changes to background context
        try modelContext.save()

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
        logger.info("[BackgroundSync] Starting background full sync")
        let startTime = Date()

        // Clear existing data in background context
        try await clearAllData()
        logger.info("[BackgroundSync] Cleared existing catalog data")

        // Fetch all catalog data from Square API
        let allObjects = try await squareAPIService.fetchCatalog()
        logger.info("[BackgroundSync] Fetched \(allObjects.count) objects from Square API")

        // Process objects in dependency order
        let sortedObjects = sortObjectsByDependency(allObjects)
        let (totalProcessed, itemsProcessed) = try await processCatalogObjectsBatch(sortedObjects)

        // Process image URL mappings
        let imageObjects = sortedObjects.filter { $0.type == "IMAGE" }
        for imageObject in imageObjects {
            await processImageURLMapping(imageObject)
        }

        // Save changes to background context
        try modelContext.save()

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

    private func getLatestUpdatedAt() async throws -> Date? {
        var descriptor = FetchDescriptor<SyncStatusModel>(
            sortBy: [SortDescriptor(\.lastSyncTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let results = try modelContext.fetch(descriptor)
        return results.first?.lastSyncTime
    }

    private func clearAllData() async throws {
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

    private func processCatalogObjectsBatch(_ objects: [CatalogObject]) async throws -> (totalProcessed: Int, itemsProcessed: Int) {
        var totalProcessed = 0
        var itemsProcessed = 0

        for object in objects {
            try await insertCatalogObject(object)

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

    private func insertCatalogObject(_ object: CatalogObject) async throws {
        switch object.type {
        case "ITEM":
            try await insertItem(object)
        case "ITEM_VARIATION":
            try await insertItemVariation(object)
        case "CATEGORY":
            try await insertCategory(object)
        case "TAX":
            try await insertTax(object)
        case "MODIFIER_LIST":
            try await insertModifierList(object)
        case "MODIFIER":
            try await insertModifier(object)
        case "IMAGE":
            try await insertImage(object)
        case "DISCOUNT":
            try await insertDiscount(object)
        default:
            logger.warning("[BackgroundSync] Unknown object type: \(object.type)")
        }
    }

    // MARK: - Object Insertion Methods

    private func insertItem(_ object: CatalogObject) async throws {
        guard object.itemData != nil else {
            logger.warning("[BackgroundSync] ITEM object \(object.id) missing itemData")
            return
        }

        let item = CatalogItemModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        item.updateFromCatalogObject(object)

        modelContext.insert(item)
        logger.debug("[BackgroundSync] Inserted item: \(object.id)")
    }

    private func insertItemVariation(_ object: CatalogObject) async throws {
        guard let variationData = object.itemVariationData else {
            logger.warning("[BackgroundSync] ITEM_VARIATION object \(object.id) missing itemVariationData")
            return
        }

        let variation = ItemVariationModel(
            id: object.id,
            itemId: variationData.itemId,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        variation.updateFromCatalogObject(object)

        modelContext.insert(variation)
        logger.debug("[BackgroundSync] Inserted variation: \(object.id)")
    }

    private func insertCategory(_ object: CatalogObject) async throws {
        guard object.categoryData != nil else {
            logger.warning("[BackgroundSync] CATEGORY object \(object.id) missing categoryData")
            return
        }

        let category = CategoryModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        category.updateFromCatalogObject(object)

        modelContext.insert(category)
        logger.debug("[BackgroundSync] Inserted category: \(object.id)")
    }

    private func insertTax(_ object: CatalogObject) async throws {
        guard object.taxData != nil else {
            logger.warning("[BackgroundSync] TAX object \(object.id) missing taxData")
            return
        }

        let tax = TaxModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        tax.updateFromCatalogObject(object)

        modelContext.insert(tax)
        logger.debug("[BackgroundSync] Inserted tax: \(object.id)")
    }

    private func insertModifierList(_ object: CatalogObject) async throws {
        guard object.modifierListData != nil else {
            logger.warning("[BackgroundSync] MODIFIER_LIST object \(object.id) missing modifierListData")
            return
        }

        let modifierList = ModifierListModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        modifierList.updateFromCatalogObject(object)

        modelContext.insert(modifierList)
        logger.debug("[BackgroundSync] Inserted modifier list: \(object.id)")
    }

    private func insertModifier(_ object: CatalogObject) async throws {
        guard object.modifierData != nil else {
            logger.warning("[BackgroundSync] MODIFIER object \(object.id) missing modifierData")
            return
        }

        let modifier = ModifierModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        modifier.updateFromCatalogObject(object)

        modelContext.insert(modifier)
        logger.debug("[BackgroundSync] Inserted modifier: \(object.id)")
    }

    private func insertImage(_ object: CatalogObject) async throws {
        guard object.imageData != nil else {
            logger.warning("[BackgroundSync] IMAGE object \(object.id) missing imageData")
            return
        }

        let image = ImageModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        image.updateFromCatalogObject(object)

        modelContext.insert(image)
        logger.debug("[BackgroundSync] Inserted image: \(object.id)")
    }

    private func insertDiscount(_ object: CatalogObject) async throws {
        guard object.discountData != nil else {
            logger.warning("[BackgroundSync] DISCOUNT object \(object.id) missing discountData")
            return
        }

        let discount = DiscountModel(
            id: object.id,
            updatedAt: parseDate(object.updatedAt) ?? Date(),
            version: String(object.safeVersion),
            isDeleted: object.safeIsDeleted
        )

        // Use the existing update method to populate all fields
        discount.updateFromCatalogObject(object)

        modelContext.insert(discount)
        logger.debug("[BackgroundSync] Inserted discount: \(object.id)")
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
    case objectProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPreviousSync:
            return "No previous sync found, full sync required"
        case .objectProcessingFailed(let objectId):
            return "Failed to process object: \(objectId)"
        }
    }
}