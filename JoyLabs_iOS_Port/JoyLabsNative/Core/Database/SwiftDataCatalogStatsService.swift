import Foundation
import SwiftData
import os.log

/// SwiftData-based catalog statistics service
/// EXACT functionality replacement for SQLiteSwiftCatalogManager-based version
@MainActor
class SwiftDataCatalogStatsService: ObservableObject {
    
    // MARK: - Published Properties (IDENTICAL)
    
    @Published var itemsCount: Int = 0
    @Published var categoriesCount: Int = 0
    @Published var variationsCount: Int = 0
    @Published var totalObjectsCount: Int = 0
    @Published var imagesCount: Int = 0
    @Published var taxesCount: Int = 0
    @Published var discountsCount: Int = 0  // Keep for compatibility even though discounts are minimal
    @Published var modifiersCount: Int = 0
    @Published var modifierListsCount: Int = 0
    
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    // MARK: - Dependencies
    
    private let modelContext: ModelContext
    private var hasLoadedStats = false
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataCatalogStats")
    
    // MARK: - Computed Properties (IDENTICAL)
    
    var hasData: Bool {
        return totalObjectsCount > 0
    }
    
    var formattedLastUpdated: String {
        guard let lastUpdated = lastUpdated else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("[CatalogStats] SwiftDataCatalogStatsService initialized")
    }
    
    // MARK: - Public Methods (IDENTICAL interface)
    
    func refreshStats(force: Bool = false) async {
        // Only refresh if we haven't loaded stats yet, or if forced
        guard !hasLoadedStats || force else {
            logger.debug("[CatalogStats] Stats already loaded, skipping refresh")
            return
        }
        
        logger.info("[CatalogStats] Refreshing catalog statistics...")
        
        isLoading = true
        
        do {
            // Count all object types using SwiftData (IDENTICAL logic to original)
            let items = try await countItems()
            let categories = try await countCategories()
            let variations = try await countVariations()
            let images = try await countImages()
            let taxes = try await countTaxes()
            let modifiers = try await countModifiers()
            let modifierLists = try await countModifierLists()
            let discounts = 0  // Minimal discount support like original
            
            // Update published properties on main actor
            itemsCount = items
            categoriesCount = categories
            variationsCount = variations
            imagesCount = images
            taxesCount = taxes
            modifiersCount = modifiers
            modifierListsCount = modifierLists
            discountsCount = discounts
            
            // Calculate total (IDENTICAL calculation)
            totalObjectsCount = items + categories + variations + images + taxes + modifiers + modifierLists + discounts
            
            lastUpdated = Date()
            hasLoadedStats = true
            
            logger.info("[CatalogStats] Stats refreshed: \(self.totalObjectsCount) total objects")
            logger.debug("[CatalogStats] Items: \(items), Categories: \(categories), Variations: \(variations), Images: \(images)")
            
        } catch {
            logger.error("[CatalogStats] Failed to refresh stats: \(error)")
        }
        
        isLoading = false
    }
    
    /// Force refresh stats (called after sync completion)
    func forceRefresh() async {
        await refreshStats(force: true)
    }
    
    /// Reset stats to zero (called before sync starts)
    func resetStats() {
        logger.debug("[CatalogStats] Resetting stats to zero")
        
        itemsCount = 0
        categoriesCount = 0
        variationsCount = 0
        totalObjectsCount = 0
        imagesCount = 0
        taxesCount = 0
        discountsCount = 0
        modifiersCount = 0
        modifierListsCount = 0
        lastUpdated = nil
        hasLoadedStats = false
    }
    
    // MARK: - Private Counting Methods (EXACT SwiftData equivalents)
    
    private func countItems() async throws -> Int {
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countCategories() async throws -> Int {
        let descriptor = FetchDescriptor<CategoryModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countVariations() async throws -> Int {
        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countImages() async throws -> Int {
        let descriptor = FetchDescriptor<ImageModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countTaxes() async throws -> Int {
        let descriptor = FetchDescriptor<TaxModel>(
            predicate: #Predicate { !$0.isDeleted && ($0.enabled ?? false) }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countModifiers() async throws -> Int {
        let descriptor = FetchDescriptor<ModifierModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    private func countModifierLists() async throws -> Int {
        let descriptor = FetchDescriptor<ModifierListModel>(
            predicate: #Predicate { !$0.isDeleted }
        )
        return try modelContext.fetchCount(descriptor)
    }
    
    // MARK: - Compatibility Interface
    
    /// Legacy method name for compatibility with existing code
    func loadInitialStats() async {
        await refreshStats(force: false)
    }
}