import Foundation
import SwiftData
import os.log

/// SwiftData-based catalog database manager
/// Replaces SQLiteSwiftCatalogManager with native iOS 17+ persistence
@MainActor
class SwiftDataCatalogManager {
    
    // MARK: - Properties
    
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataCatalog")
    
    // MARK: - Initialization
    
    init() throws {
        logger.info("[Database] Initializing SwiftDataCatalogManager")
        
        // Define the schema with all catalog models
        let schema = Schema([
            CatalogItemModel.self,
            ItemVariationModel.self,
            CategoryModel.self,
            TaxModel.self,
            ModifierListModel.self,
            ModifierModel.self,
            ImageModel.self,
            TeamDataModel.self,
            // ImageURLMappingModel.self, // Removed - using pure SwiftData for images
            DiscountModel.self,
            SyncStatusModel.self
        ])
        
        // Configure the model container
        let configuration = ModelConfiguration(
            "catalog-v2.store",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        // Create the container
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        
        // Get the main context
        self.modelContext = modelContainer.mainContext
        
        // Configure context for better performance
        self.modelContext.autosaveEnabled = false  // Manual saves for batch operations
        
        logger.info("[Database] SwiftDataCatalogManager initialized with NEW container")
    }
    
    /// Initialize with existing container (for shared container architecture)
    init(existingContainer: ModelContainer) throws {
        logger.info("[Database] Initializing SwiftDataCatalogManager with existing container")
        
        // Use the provided container
        self.modelContainer = existingContainer
        
        // Get the main context
        self.modelContext = existingContainer.mainContext
        
        // Configure context for better performance
        self.modelContext.autosaveEnabled = false  // Manual saves for batch operations
        
        logger.info("[Database] SwiftDataCatalogManager initialized successfully")
    }
    
    // MARK: - Connection Management (Compatibility Layer)
    
    /// Connect to database (no-op for SwiftData, kept for compatibility)
    func connect() throws {
        // SwiftData handles connection automatically
        logger.debug("[Database] SwiftData connection verified")
    }
    
    /// Disconnect from database (no-op for SwiftData)
    func disconnect() {
        // SwiftData handles connection lifecycle automatically
        logger.debug("[Database] SwiftData disconnect called (no-op)")
    }
    
    /// Get the model context for direct operations
    func getContext() -> ModelContext {
        return modelContext
    }
    
    /// Get connection (compatibility method - returns context for SwiftData)
    func getConnection() -> ModelContext {
        return modelContext
    }
    
    /// Get database path (compatibility method)
    func getDatabasePath() -> String {
        // SwiftData manages path internally, return a placeholder
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("catalog-v2.store.store").path
    }
    
    /// Create tables (no-op for SwiftData, kept for compatibility)
    func createTables() throws {
        // SwiftData creates tables automatically based on @Model classes
        logger.debug("[Database] SwiftData tables are auto-managed (no-op)")
    }
    
    /// Create tables async (no-op for SwiftData, kept for compatibility)
    func createTablesAsync() async throws {
        // SwiftData creates tables automatically based on @Model classes
        logger.debug("[Database] SwiftData tables are auto-managed (no-op)")
    }
    
    // MARK: - Data Operations
    
    /// Clear all catalog data
    func clearAllData() throws {
        logger.info("[Database] Clearing all catalog data")
        
        do {
            // Delete all entities
            try modelContext.delete(model: CatalogItemModel.self)
            try modelContext.delete(model: ItemVariationModel.self)
            try modelContext.delete(model: CategoryModel.self)
            try modelContext.delete(model: TaxModel.self)
            try modelContext.delete(model: ModifierListModel.self)
            try modelContext.delete(model: ModifierModel.self)
            try modelContext.delete(model: ImageModel.self)
            try modelContext.delete(model: TeamDataModel.self)
            // try modelContext.delete(model: ImageURLMappingModel.self) // Removed
            try modelContext.delete(model: DiscountModel.self)
            try modelContext.delete(model: SyncStatusModel.self)
            
            // Save the deletions
            try modelContext.save()
            
            logger.info("[Database] All catalog data cleared successfully")
        } catch {
            logger.error("[Database] Failed to clear data: \(error)")
            throw error
        }
    }
    
    // MARK: - Insert Operations
    
    // TODO: TeamData Operations - Future Implementation
    // TeamData model exists but CRUD operations are deferred for future implementation.
    // When implementing, add:
    // - insertTeamData(itemId: String, teamData: TeamDataModel)
    // - fetchTeamData(for itemId: String) -> TeamDataModel?
    // - updateTeamData(itemId: String, teamData: TeamDataModel)
    // - deleteTeamData(for itemId: String)
    
    /// Insert or update a catalog object from Square API
    func insertCatalogObject(_ object: CatalogObject) async throws {
        logger.trace("[Database] Processing \(object.type) object: \(object.id)")
        
        switch object.type {
        case "CATEGORY":
            try await insertCategory(object)
            
        case "ITEM":
            try await insertItem(object)
            
        case "ITEM_VARIATION":
            try await insertItemVariation(object)
            
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
            logger.debug("[Database] Skipping unsupported type: \(object.type)")
        }
    }
    
    private func insertCategory(_ object: CatalogObject) async throws {
        let descriptor = FetchDescriptor<CategoryModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let category: CategoryModel
        if let existing = try modelContext.fetch(descriptor).first {
            category = existing
        } else {
            category = CategoryModel(id: object.id)
            modelContext.insert(category)
        }
        
        category.updateFromCatalogObject(object)
        try modelContext.save()
        logger.trace("[Database] Inserted/updated category: \(object.id)")
    }
    
    private func insertItem(_ object: CatalogObject) async throws {
        // Handle deleted items
        if object.isDeleted == true {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { $0.id == object.id }
            )
            
            if let existing = try modelContext.fetch(descriptor).first {
                existing.isDeleted = true
                existing.updatedAt = Date()
                existing.version = String(object.version ?? 0)
                try modelContext.save()
                logger.info("[Database] Marked item as deleted: \(object.id)")
            }
            return
        }
        
        // Insert or update item
        guard let itemData = object.itemData else {
            logger.warning("[Database] Item \(object.id) missing itemData")
            return
        }
        
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let item: CatalogItemModel
        if let existing = try modelContext.fetch(descriptor).first {
            item = existing
        } else {
            item = CatalogItemModel(id: object.id)
            modelContext.insert(item)
        }
        
        // Update basic fields
        item.updateFromCatalogObject(object)
        
        // Extract and store pre-computed category names for search performance
        if let categoryId = itemData.categoryId {
            item.categoryName = try await getCategoryName(categoryId)
        }
        
        if let reportingCategoryId = itemData.reportingCategory?.id {
            item.reportingCategoryId = reportingCategoryId
            item.reportingCategoryName = try await getCategoryName(reportingCategoryId)
        }
        
        // Extract tax names for display
        if let taxIds = itemData.taxIds, !taxIds.isEmpty {
            let taxNames = try await getTaxNames(taxIds)
            item.taxNames = taxNames.joined(separator: ", ")
        }
        
        // Extract modifier list names for display
        if let modifierListInfo = itemData.modifierListInfo, !modifierListInfo.isEmpty {
            let modifierListIds = modifierListInfo.compactMap { $0.modifierListId }
            let modifierNames = try await getModifierListNames(modifierListIds)
            item.modifierNames = modifierNames.joined(separator: ", ")
        }
        
        // NOTE: Image linking is deferred to post-sync batch processing 
        // because IMAGE objects are processed after ITEM objects (priority 7 vs 5)
        logger.debug("[Database] Item \(object.id) processed - image relationships will be created post-sync")
        
        try modelContext.save()
        logger.trace("[Database] Inserted/updated item: \(object.id)")
    }
    
    private func insertItemVariation(_ object: CatalogObject) async throws {
        guard let variationData = object.itemVariationData else {
            logger.warning("[Database] Variation \(object.id) missing itemVariationData")
            return
        }
        
        // Skip orphaned variations
        guard !variationData.itemId.isEmpty else {
            logger.warning("[Database] Skipping orphaned variation \(object.id)")
            return
        }
        
        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let variation: ItemVariationModel
        if let existing = try modelContext.fetch(descriptor).first {
            variation = existing
        } else {
            variation = ItemVariationModel(id: object.id, itemId: variationData.itemId)
            modelContext.insert(variation)
        }
        
        variation.updateFromCatalogObject(object)
        
        // Link to parent item if it exists
        let itemDescriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == variationData.itemId }
        )
        if let parentItem = try modelContext.fetch(itemDescriptor).first {
            variation.item = parentItem
        }
        
        try modelContext.save()
        logger.trace("[Database] Inserted/updated variation: \(object.id)")
    }
    
    private func insertTax(_ object: CatalogObject) async throws {
        let descriptor = FetchDescriptor<TaxModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let tax: TaxModel
        if let existing = try modelContext.fetch(descriptor).first {
            tax = existing
        } else {
            tax = TaxModel(id: object.id)
            modelContext.insert(tax)
        }
        
        tax.updateFromCatalogObject(object)
        try modelContext.save()
        logger.trace("[Database] Inserted/updated tax: \(object.id)")
    }
    
    private func insertModifierList(_ object: CatalogObject) async throws {
        let descriptor = FetchDescriptor<ModifierListModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let modifierList: ModifierListModel
        if let existing = try modelContext.fetch(descriptor).first {
            modifierList = existing
        } else {
            modifierList = ModifierListModel(id: object.id)
            modelContext.insert(modifierList)
        }
        
        modifierList.updateFromCatalogObject(object)
        try modelContext.save()
        logger.trace("[Database] Inserted/updated modifier list: \(object.id)")
    }
    
    private func insertModifier(_ object: CatalogObject) async throws {
        let descriptor = FetchDescriptor<ModifierModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let modifier: ModifierModel
        if let existing = try modelContext.fetch(descriptor).first {
            modifier = existing
        } else {
            modifier = ModifierModel(id: object.id)
            modelContext.insert(modifier)
        }
        
        modifier.updateFromCatalogObject(object)
        try modelContext.save()
        logger.trace("[Database] Inserted/updated modifier: \(object.id)")
    }
    
    private func insertImage(_ object: CatalogObject) async throws {
        guard let imageData = object.imageData else {
            logger.warning("[Database] ❌ Image \(object.id) missing imageData")
            return
        }

        logger.info("[Database] 📷 Processing IMAGE object: \(object.id)")
        logger.debug("[Database]   - Image URL: \(imageData.url ?? "nil")")
        logger.debug("[Database]   - Image name: \(imageData.name ?? "nil")")

        let descriptor = FetchDescriptor<ImageModel>(
            predicate: #Predicate { $0.id == object.id }
        )

        let image: ImageModel
        if let existing = try modelContext.fetch(descriptor).first {
            logger.debug("[Database] 🔄 Updating existing image: \(object.id)")
            image = existing
        } else {
            logger.debug("[Database] ✨ Creating new image: \(object.id)")
            image = ImageModel(id: object.id)
            modelContext.insert(image)
        }

        image.updateFromCatalogObject(object)
        try modelContext.save()
        logger.info("[Database] ✅ Successfully inserted/updated image: \(object.id) with URL: \(imageData.url ?? "nil")")

        // Verify image was saved
        if let savedImage = try modelContext.fetch(descriptor).first {
            logger.debug("[Database] ✓ Verified image \(object.id) exists in database after save")
        } else {
            logger.error("[Database] ❌ CRITICAL: Image \(object.id) NOT FOUND after save!")
        }
    }
    
    private func insertDiscount(_ object: CatalogObject) async throws {
        let descriptor = FetchDescriptor<DiscountModel>(
            predicate: #Predicate { $0.id == object.id }
        )
        
        let discount: DiscountModel
        if let existing = try modelContext.fetch(descriptor).first {
            discount = existing
        } else {
            discount = DiscountModel(id: object.id)
            modelContext.insert(discount)
        }
        
        discount.updateFromCatalogObject(object)
        try modelContext.save()
        logger.trace("[Database] Inserted/updated discount: \(object.id)")
    }
    
    // MARK: - Image Relationship Management

    /// Link images to a catalog item based on imageIds array
    @MainActor
    func linkImagesToItem(itemId: String, imageIds: [String], clearExisting: Bool = true) async throws {
        logger.info("[Database] Starting image linking for item: \(itemId) with imageIds: \(imageIds)")

        let itemDescriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == itemId }
        )

        guard let item = try modelContext.fetch(itemDescriptor).first else {
            logger.warning("[Database] Cannot link images - item not found: \(itemId)")
            return
        }
        
        logger.debug("[Database] Found item: \(item.name ?? "unnamed") (\(itemId))")
        
        // Initialize images array if needed
        if item.images == nil {
            logger.debug("[Database] Initializing new images array for item")
            item.images = []
        } else if clearExisting {
            logger.debug("[Database] Clearing existing \(item.images?.count ?? 0) images for clean rebuild")
            item.images?.removeAll()
        } else {
            logger.debug("[Database] Item already has \(item.images?.count ?? 0) images - adding to existing")
        }
        
        // Add each image to the relationship
        var linkedCount = 0
        for imageId in imageIds {
            let imageDescriptor = FetchDescriptor<ImageModel>(
                predicate: #Predicate { $0.id == imageId }
            )
            
            if let image = try modelContext.fetch(imageDescriptor).first {
                // Check for duplicates only when not clearing existing
                let alreadyLinked = !clearExisting && (item.images?.contains { $0.id == imageId } == true)

                if !alreadyLinked {
                    item.images?.append(image)
                    linkedCount += 1
                    logger.debug("[Database] ✅ Linked image \(imageId) (URL: \(image.url ?? "nil")) to item \(itemId)")
                } else {
                    logger.debug("[Database] ⚠️ Image \(imageId) already linked to item \(itemId)")
                }
            } else {
                // CRITICAL: Image object not found in database - this is the problem!
                logger.error("[Database] ❌ CRITICAL: Image not found in database for linking: \(imageId) to item: \(itemId)")
                logger.error("[Database] This means either:")
                logger.error("[Database]   1. IMAGE object was not fetched during sync")
                logger.error("[Database]   2. IMAGE object failed to insert into database")
                logger.error("[Database]   3. Relationship creation ran before IMAGE object was inserted")

                // Debug: Check if ANY images exist in database
                let allImagesDescriptor = FetchDescriptor<ImageModel>()
                if let allImages = try? modelContext.fetch(allImagesDescriptor) {
                    logger.error("[Database] Total images in database: \(allImages.count)")
                    if allImages.count > 0 {
                        logger.error("[Database] Sample image IDs: \(allImages.prefix(5).map { $0.id })")
                    }
                }
            }
        }
        
        try modelContext.save()
        logger.info("[Database] Successfully linked \(linkedCount)/\(imageIds.count) images to item: \(itemId)")
    }
    
    /// Create all image relationships after bulk sync
    @MainActor
    func createAllImageRelationships() async throws {
        logger.info("[Database] 🔗 Creating image relationships for all items...")

        // First, verify how many IMAGE objects exist in database
        let allImagesDescriptor = FetchDescriptor<ImageModel>()
        let allImages = try modelContext.fetch(allImagesDescriptor)
        logger.info("[Database] 📊 Total IMAGE objects in database: \(allImages.count)")
        if allImages.count > 0 {
            logger.debug("[Database] Sample IMAGE IDs: \(allImages.prefix(10).map { $0.id }.joined(separator: ", "))")
        }

        let itemDescriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        let items = try modelContext.fetch(itemDescriptor)
        logger.info("[Database] 📦 Processing \(items.count) items for image relationships")

        var totalLinkedCount = 0
        var itemsWithImages = 0
        
        for item in items {
            // Parse imageIds from dataJson
            guard let dataJson = item.dataJson,
                  let data = dataJson.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.debug("[Database] No valid dataJson for item: \(item.id) - \(item.name ?? "unnamed")")
                continue
            }
            
            // Extract imageIds (check both nested and root locations)
            var imageIds: [String]?
            
            // Try nested under item_data first (Square API format with underscores)
            if let itemData = json["item_data"] as? [String: Any] {
                imageIds = itemData["image_ids"] as? [String]
                if imageIds != nil {
                    logger.debug("[Database] Found imageIds in item_data.image_ids for item: \(item.id)")
                }
            }
            
            // Fallback to root level (legacy format)  
            if imageIds == nil {
                imageIds = json["imageIds"] as? [String]
                if imageIds != nil {
                    logger.debug("[Database] Found imageIds in root.imageIds for item: \(item.id)")
                }
            }
            
            // Link images if found
            if let imageIds = imageIds, !imageIds.isEmpty {
                logger.info("[Database] 🔗 Found \(imageIds.count) imageIds for item: \(item.id) - \(item.name ?? "unnamed")")
                logger.debug("[Database]   ImageIds: \(imageIds.joined(separator: ", "))")
                try await linkImagesToItem(itemId: item.id, imageIds: imageIds)
                totalLinkedCount += imageIds.count
                itemsWithImages += 1
            } else {
                logger.debug("[Database] ⚠️ No imageIds found for item: \(item.id) - \(item.name ?? "unnamed")")
            }
        }

        logger.info("[Database] ✅ Image relationship creation completed: \(totalLinkedCount) total images linked to \(itemsWithImages) items")
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch a catalog item by ID
    func fetchItemById(_ itemId: String) throws -> CatalogObject? {
        logger.info("[Database] Fetching item by ID: \(itemId)")
        
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == itemId && !$0.isDeleted }
        )
        
        guard let item = try modelContext.fetch(descriptor).first else {
            logger.warning("[Database] Item not found: \(itemId)")
            return nil
        }
        
        // Convert stored JSON back to CatalogObject
        return item.toCatalogObject()
    }
    
    /// Get the current version of an item
    func getItemVersion(itemId: String) async throws -> Int64 {
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == itemId }
        )
        
        if let item = try modelContext.fetch(descriptor).first {
            let version = Int64(item.version) ?? 0
            logger.debug("[Database] Found item \(itemId) with version: \(version)")
            return version
        } else {
            logger.debug("[Database] Item \(itemId) not found, returning version 0")
            return 0
        }
    }
    
    /// Get total count of non-deleted items
    func getItemCount() async throws -> Int {
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        
        return try modelContext.fetchCount(descriptor)
    }
    
    /// Get the latest updated_at timestamp for incremental sync
    func getLatestUpdatedAt() async throws -> Date? {
        // Get the most recent update across all entities
        var latestDate: Date?
        
        // Check items
        let itemDescriptor = FetchDescriptor<CatalogItemModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let latestItem = try modelContext.fetch(itemDescriptor).first {
            latestDate = latestItem.updatedAt
        }
        
        // Check categories
        let categoryDescriptor = FetchDescriptor<CategoryModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let latestCategory = try modelContext.fetch(categoryDescriptor).first {
            if latestDate == nil || latestCategory.updatedAt > latestDate! {
                latestDate = latestCategory.updatedAt
            }
        }
        
        // Check variations
        let variationDescriptor = FetchDescriptor<ItemVariationModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let latestVariation = try modelContext.fetch(variationDescriptor).first {
            if latestDate == nil || latestVariation.updatedAt > latestDate! {
                latestDate = latestVariation.updatedAt
            }
        }
        
        logger.info("[Database] Latest updated_at timestamp: \(latestDate?.description ?? "none")")
        return latestDate
    }
    
    /// Save the catalog version timestamp from Square's webhook or API response
    func saveCatalogVersion(_ updatedAt: Date) async throws {
        // For SwiftData, use SyncStatusModel for full compatibility
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
        
        syncStatus.lastSyncTime = updatedAt
        try modelContext.save()
        logger.trace("[Database] Saved catalog version: \(updatedAt)")
        
        // Also store in UserDefaults as fallback
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAtString = formatter.string(from: updatedAt)
        UserDefaults.standard.set(updatedAtString, forKey: "swiftdata_catalog_version")
    }
    
    /// Get the stored catalog version timestamp
    func getCatalogVersion() async throws -> Date? {
        // Try SyncStatusModel first
        let descriptor = FetchDescriptor<SyncStatusModel>(
            predicate: #Predicate { $0.id == 1 }
        )
        
        if let syncStatus = try modelContext.fetch(descriptor).first,
           let lastSyncTime = syncStatus.lastSyncTime {
            logger.trace("[Database] Retrieved catalog version from SyncStatus: \(lastSyncTime)")
            return lastSyncTime
        }
        
        // Fallback to UserDefaults
        if let versionString = UserDefaults.standard.string(forKey: "swiftdata_catalog_version") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = formatter.date(from: versionString) {
                logger.trace("[Database] Retrieved catalog version from UserDefaults: \(versionString)")
                return date
            }
        }
        
        logger.info("[Database] No catalog version found")
        return nil
    }
    
    // MARK: - Sync Status Management
    
    /// Get or create the primary sync status record
    func getSyncStatus() async throws -> SyncStatusModel {
        let descriptor = FetchDescriptor<SyncStatusModel>(
            predicate: #Predicate { $0.id == 1 }
        )
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let syncStatus = SyncStatusModel(id: 1)
        modelContext.insert(syncStatus)
        try modelContext.save()
        return syncStatus
    }
    
    /// Update sync progress
    func updateSyncProgress(current: Int, total: Int) async throws {
        let syncStatus = try await getSyncStatus()
        syncStatus.updateProgress(current: current, total: total)
        try modelContext.save()
    }
    
    /// Start sync operation
    func startSync(type: String) async throws {
        let syncStatus = try await getSyncStatus()
        syncStatus.startSync(type: type)
        try modelContext.save()
    }
    
    /// Complete sync successfully
    func completeSync() async throws {
        let syncStatus = try await getSyncStatus()
        syncStatus.completeSync()
        try modelContext.save()
    }
    
    /// Complete sync with error
    func failSync(error: String) async throws {
        let syncStatus = try await getSyncStatus()
        syncStatus.failSync(error: error)
        try modelContext.save()
    }
    
    // MARK: - Helper Methods
    
    /// Encode any Codable object to JSON string
    private func encodeJSON<T: Codable>(_ object: T?) -> String? {
        guard let object = object else { return nil }
        do {
            let data = try JSONEncoder().encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            logger.error("[Database] Failed to encode JSON: \(error)")
            return nil
        }
    }
    
    /// Encode string array as JSON for database storage
    private func encodeJSONArray(_ array: [String]?) -> String? {
        guard let array = array, !array.isEmpty else { return nil }
        do {
            let data = try JSONEncoder().encode(array)
            return String(data: data, encoding: .utf8)
        } catch {
            logger.error("[Database] Failed to encode JSON array: \(error)")
            return nil
        }
    }
    
    private func getCategoryName(_ categoryId: String) async throws -> String? {
        let descriptor = FetchDescriptor<CategoryModel>(
            predicate: #Predicate { $0.id == categoryId && !$0.isDeleted }
        )

        return try modelContext.fetch(descriptor).first?.name
    }
    
    private func getTaxNames(_ taxIds: [String]) async throws -> [String] {
        var names: [String] = []
        
        for taxId in taxIds {
            let descriptor = FetchDescriptor<TaxModel>(
                predicate: #Predicate { $0.id == taxId && !$0.isDeleted }
            )
            
            if let tax = try modelContext.fetch(descriptor).first,
               let name = tax.name {
                names.append(name)
            }
        }
        
        return names
    }
    
    private func getModifierListNames(_ modifierListIds: [String]) async throws -> [String] {
        var names: [String] = []
        
        for listId in modifierListIds {
            let descriptor = FetchDescriptor<ModifierListModel>(
                predicate: #Predicate { $0.id == listId && !$0.isDeleted }
            )
            
            if let modifierList = try modelContext.fetch(descriptor).first,
               let name = modifierList.name {
                names.append(name)
            }
        }
        
        return names
    }
    
    // MARK: - Batch Operations
    
    /// Save pending changes to database
    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
            logger.debug("[Database] Changes saved to SwiftData")
        }
    }
    
    /// Process catalog objects in batch with periodic saves
    func processCatalogBatch(_ objects: [CatalogObject], saveInterval: Int = 50) async throws {
        for (index, object) in objects.enumerated() {
            try await insertCatalogObject(object)
            
            // Save periodically to avoid memory issues
            if (index + 1) % saveInterval == 0 {
                try save()
                logger.debug("[Database] Batch save at index \(index + 1)")
                
                // Allow UI updates
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }
        }
        
        // Final save for any remaining changes
        try save()
    }
}

// MARK: - Error Types

enum SwiftDataError: Error {
    case noConnection
    case insertFailed(String)
    case fetchFailed(String)
    case saveFailed(String)
}