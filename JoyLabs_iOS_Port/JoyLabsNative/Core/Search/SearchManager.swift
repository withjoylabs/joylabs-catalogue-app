import Foundation
import SwiftUI
import SQLite
import Combine
import os.log

/// Simple SearchManager - Industry standard approach
/// Load ALL results once, LazyVStack handles virtualization
class SearchManager: ObservableObject {
    // MARK: - Published Properties
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var lastSearchTerm: String = ""
    @Published var currentSearchTerm: String? = nil
    @Published var totalResultsCount: Int? = nil
    @Published var isDatabaseReady = false

    // MARK: - Private Properties
    private let databaseManager: SQLiteSwiftCatalogManager
    private let imageURLManager: ImageURLManager
    private var searchTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SearchManager")
    
    // Fuzzy search engine
    private let fuzzySearch = FuzzySearch()

    // Debouncing
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        if let manager = databaseManager {
            self.databaseManager = manager
            if manager.getConnection() != nil {
                self.isDatabaseReady = true
                // Using pre-connected shared database
            }
        } else {
            self.databaseManager = SQLiteSwiftCatalogManager()
        }

        self.imageURLManager = ImageURLManager(databaseManager: self.databaseManager)

        setupSearchDebouncing()

        if !isDatabaseReady {
            Task.detached(priority: .background) {
                await self.initializeDatabaseConnection()
            }
        }
    }

    // MARK: - Database Initialization
    private func initializeDatabaseConnection() async {
        do {
            if databaseManager.getConnection() == nil {
                try databaseManager.connect()
                // Search manager connected to database
            } else {
                // Using existing database connection
            }

            Task { @MainActor in
                isDatabaseReady = true
            }
        } catch {
            // Database connection failed
            Task { @MainActor in
                searchError = "Database connection failed: \\(error.localizedDescription)"
                isDatabaseReady = false
            }
        }
    }
    
    // MARK: - Main Search Function
    
    func performSearch(searchTerm: String, filters: SearchFilters) async -> [SearchResultItem] {
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTerm.isEmpty else {
            Task { @MainActor in
                searchResults = []
                lastSearchTerm = ""
                currentSearchTerm = nil
                totalResultsCount = nil
            }
            return []
        }

        guard trimmedTerm.count >= 3 else {
            Task { @MainActor in
                searchResults = []
                totalResultsCount = nil
            }
            return []
        }

        guard isDatabaseReady else {
            return []
        }

        Task { @MainActor in
            isSearching = true
            searchError = nil
            lastSearchTerm = trimmedTerm
            currentSearchTerm = trimmedTerm
        }
        
        // Performing search

        do {
            // 1. Get ALL fuzzy search results at once
            let allFuzzyResults = try await getAllFuzzySearchResults(
                searchTerm: trimmedTerm,
                filters: filters
            )
            
            // 2. Case UPC search (if numeric)
            var caseUpcResults: [SearchResultItem] = []
            if trimmedTerm.allSatisfy({ $0.isNumber }) && filters.barcode {
                caseUpcResults = try await searchCaseUpcItems(searchTerm: trimmedTerm)
            }
            
            // 3. Combine and store ALL results in searchResults
            let allResults = combineAndDeduplicateResults(
                localResults: allFuzzyResults,
                caseUpcResults: caseUpcResults
            )

            Task { @MainActor in
                searchResults = allResults  // Store ALL results - LazyVStack handles virtualization
                totalResultsCount = allResults.count
                isSearching = false
                
                // Populating UI with results
            }
            
            // Search completed
            return allResults

        } catch {
            // Search failed

            Task { @MainActor in
                searchError = error.localizedDescription
                isSearching = false
                searchResults = []
            }

            return []
        }
    }
    
    private func getAllFuzzySearchResults(searchTerm: String, filters: SearchFilters) async throws -> [SearchResultItem] {
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        // Running fuzzy search
        
        // Get ALL results from fuzzy search - no pagination!
        let scoredResults = try fuzzySearch.performFuzzySearch(
            searchTerm: searchTerm,
            in: db,
            filters: filters,
            limit: 1000 // Get everything
        )
        
        // FuzzySearch returned results
        
        // Extract SearchResultItems maintaining the scored order
        let results = scoredResults.map { $0.item }
        
        // Enrich results while preserving order
        let enrichedResults = enrichSearchResultsPreservingOrder(results, db: db)
        
        // Enriched results, order preserved
        
        return enrichedResults
    }
    
    func performSearchWithDebounce(searchTerm: String, filters: SearchFilters) {
        let taskToCancel = searchTask
        searchTask = nil

        Task.detached(priority: .background) {
            taskToCancel?.cancel()
        }

        searchSubject.send((searchTerm, filters))
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        lastSearchTerm = ""
        currentSearchTerm = nil
        totalResultsCount = nil
        isSearching = false
        // Search cleared
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncing() {
        searchSubject
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] (searchTerm, filters) in
                guard let self = self else { return }
                
                let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let delay: Int = {
                    if trimmedTerm.count < 3 { return 0 }
                    if trimmedTerm.count == 3 { return 300 }
                    if trimmedTerm.count >= 4 && trimmedTerm.count <= 6 { return 200 }
                    if trimmedTerm.count > 6 { return 150 }
                    return 250
                }()
                
                self.searchTask = Task.detached(priority: .userInitiated) { [weak self] in
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
                    }
                    guard let self = self, !Task.isCancelled else { return }
                    _ = await self.performSearch(searchTerm: searchTerm, filters: filters)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Result Enrichment
    
    private func enrichSearchResults(_ results: [SearchResultItem], db: Connection) -> [SearchResultItem] {
        return results.compactMap { result in
            return getCompleteItemData(itemId: result.id, db: db, matchType: result.matchType, matchContext: result.matchContext)
        }
    }
    
    private func enrichSearchResultsPreservingOrder(_ results: [SearchResultItem], db: Connection) -> [SearchResultItem] {
        // Enrich each result but maintain the exact input order
        var enrichedResults: [SearchResultItem] = []
        
        for result in results {
            if let enrichedResult = getCompleteItemData(itemId: result.id, db: db, matchType: result.matchType, matchContext: result.matchContext) {
                enrichedResults.append(enrichedResult)
            }
        }
        
        return enrichedResults
    }

    private func getCompleteItemData(itemId: String, db: Connection, matchType: String, matchContext: String? = nil) -> SearchResultItem? {
        do {
            let items = CatalogTableDefinitions.catalogItems.alias("ci")
            let variations = CatalogTableDefinitions.itemVariations.alias("iv")

            var query = items
                .select(
                    items[CatalogTableDefinitions.itemId],
                    items[CatalogTableDefinitions.itemName],
                    items[CatalogTableDefinitions.itemCategoryId],
                    items[CatalogTableDefinitions.itemReportingCategoryId],
                    items[CatalogTableDefinitions.itemReportingCategoryName],
                    items[CatalogTableDefinitions.itemCategoryName],
                    variations[CatalogTableDefinitions.variationSku],
                    variations[CatalogTableDefinitions.variationUpc],
                    variations[CatalogTableDefinitions.variationPriceAmount],
                    variations[CatalogTableDefinitions.variationName]
                )
                .join(.leftOuter, variations, on: items[CatalogTableDefinitions.itemId] == variations[CatalogTableDefinitions.variationItemId] && variations[CatalogTableDefinitions.variationIsDeleted] == false)
                .filter(items[CatalogTableDefinitions.itemId] == itemId && items[CatalogTableDefinitions.itemIsDeleted] == false)
            
            // For barcode searches, find the specific variation that matches the scanned barcode
            if matchType == "barcode" || matchType == "upc", let searchedBarcode = matchContext {
                query = query.filter(variations[CatalogTableDefinitions.variationUpc] == searchedBarcode)
            }
            
            query = query.limit(1)

            guard let row = try db.pluck(query) else {
                return nil
            }

            let itemName = try row.get(items[CatalogTableDefinitions.itemName])
            let categoryId = try? row.get(items[CatalogTableDefinitions.itemReportingCategoryId])
            let reportingCategoryName = try? row.get(items[CatalogTableDefinitions.itemReportingCategoryName])
            let regularCategoryName = try? row.get(items[CatalogTableDefinitions.itemCategoryName])
            let categoryName = reportingCategoryName ?? regularCategoryName

            let sku = try? row.get(variations[CatalogTableDefinitions.variationSku])
            let upc = try? row.get(variations[CatalogTableDefinitions.variationUpc])
            let priceAmount = try? row.get(variations[CatalogTableDefinitions.variationPriceAmount])
            let variationName = try? row.get(variations[CatalogTableDefinitions.variationName])

            var caseUpc: String? = nil
            var caseCost: Double? = nil

            if matchType == "case_upc" {
                let teamData = CatalogTableDefinitions.teamData.alias("td")
                let teamQuery = teamData
                    .select(
                        teamData[CatalogTableDefinitions.teamCaseUpc],
                        teamData[CatalogTableDefinitions.teamCaseCost]
                    )
                    .filter(teamData[CatalogTableDefinitions.teamDataItemId] == itemId)
                    .limit(1)

                if let teamRow = try db.pluck(teamQuery) {
                    caseUpc = try? teamRow.get(teamData[CatalogTableDefinitions.teamCaseUpc])
                    caseCost = try? teamRow.get(teamData[CatalogTableDefinitions.teamCaseCost])
                }
            }

            let price: Double?
            let barcode: String?
            let isFromCaseUpc: Bool

            switch matchType {
            case "case_upc":
                price = caseCost
                barcode = caseUpc
                isFromCaseUpc = true
            default:
                if let amount = priceAmount, amount > 0 {
                    let convertedPrice = Double(amount) / 100.0
                    price = convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
                } else {
                    price = nil
                }
                barcode = upc
                isFromCaseUpc = false
            }

            let hasTax = false
            let images = getPrimaryImageForSearchResult(itemId: itemId)

            return SearchResultItem(
                id: itemId,
                name: itemName,
                sku: sku,
                price: price,
                barcode: barcode,
                categoryId: categoryId,
                categoryName: categoryName,
                variationName: variationName,
                images: images,
                matchType: matchType,
                matchContext: matchContext,
                isFromCaseUpc: isFromCaseUpc,
                caseUpcData: isFromCaseUpc ? CaseUpcData(
                    caseUpc: caseUpc ?? "",
                    caseCost: caseCost ?? 0.0,
                    caseQuantity: 1,
                    vendor: nil,
                    discontinued: false,
                    notes: nil
                ) : nil,
                hasTax: hasTax
            )

        } catch {
            logger.error("Failed to retrieve item data for \\(itemId): \\(error)")
            return nil
        }
    }

    private func getPrimaryImageForSearchResult(itemId: String) -> [CatalogImage]? {
        do {
            guard let db = databaseManager.getConnection() else {
                return nil
            }
            
            let selectQuery = """
                SELECT data_json FROM catalog_items
                WHERE id = ? AND is_deleted = 0
            """
            
            let statement = try db.prepare(selectQuery)
            for row in try statement.run([itemId]) {
                let dataJsonString = row[0] as? String ?? "{}"
                let dataJsonData = dataJsonString.data(using: String.Encoding.utf8) ?? Data()
                
                if let currentData = try JSONSerialization.jsonObject(with: dataJsonData) as? [String: Any] {
                    var imageIds: [String]? = nil
                    
                    if let itemData = currentData["item_data"] as? [String: Any] {
                        imageIds = itemData["image_ids"] as? [String]
                    }
                    
                    if imageIds == nil {
                        imageIds = currentData["image_ids"] as? [String]
                    }
                    
                    if let imageIdArray = imageIds, let primaryImageId = imageIdArray.first {
                    let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
                    if let mapping = imageMappings.first(where: { $0.squareImageId == primaryImageId }) {
                        let catalogImage = CatalogImage(
                            id: primaryImageId,
                            type: "IMAGE",
                            updatedAt: ISO8601DateFormatter().string(from: mapping.lastAccessedAt),
                            version: nil,
                            isDeleted: false,
                            presentAtAllLocations: true,
                            imageData: ImageData(
                                name: nil,
                                url: mapping.originalAwsUrl,
                                caption: nil,
                                photoStudioOrderId: nil
                            )
                        )

                        return [catalogImage]
                        }
                    }
                }
            }
            
        } catch _ {
            // Silent failure for image retrieval - error intentionally ignored
        }
        
        return nil
    }

    private func removeDuplicatesAndRank(results: [SearchResultItem], searchTerm: String) -> [SearchResultItem] {
        // Use a Set to track which IDs we've seen, but preserve the input order
        var seenIds = Set<String>()
        var deduplicatedResults: [SearchResultItem] = []
        
        for result in results {
            if seenIds.insert(result.id).inserted {
                // This ID is new, add the result
                deduplicatedResults.append(result)
            }
        }
        
        // Deduplicated results
        
        return deduplicatedResults
    }

    private func searchCaseUpcItems(searchTerm: String) async throws -> [SearchResultItem] {
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        // Searching Case UPC

        let teamDataCount = try db.scalar(
            CatalogTableDefinitions.teamData
                .filter(CatalogTableDefinitions.teamCaseUpc != nil)
                .count
        )

        if teamDataCount == 0 {
            // No team data with case UPC found
            return []
        }

        let items = CatalogTableDefinitions.catalogItems.alias("ci")
        let teamData = CatalogTableDefinitions.teamData.alias("td")

        let query = items
            .select(
                items[CatalogTableDefinitions.itemId],
                teamData[CatalogTableDefinitions.teamCaseUpc]
            )
            .join(teamData, on: items[CatalogTableDefinitions.itemId] == teamData[CatalogTableDefinitions.teamDataItemId])
            .filter(teamData[CatalogTableDefinitions.teamCaseUpc] == searchTerm &&
                   items[CatalogTableDefinitions.itemIsDeleted] == false &&
                   teamData[CatalogTableDefinitions.teamCaseUpc] != nil)
            .order(items[CatalogTableDefinitions.itemName].asc)
            .limit(50)

        return try db.prepare(query).compactMap { row in
            do {
                let itemId = try row.get(items[CatalogTableDefinitions.itemId])
                let caseUpc = try row.get(teamData[CatalogTableDefinitions.teamCaseUpc])

                return getCompleteItemData(itemId: itemId, db: db, matchType: "case_upc", matchContext: caseUpc)
            } catch {
                logger.error("Failed to create case UPC search result: \\(error)")
                return nil
            }
        }
    }
    
    // MARK: - Targeted Item Updates (No Full Refresh)
    
    /// Updates a specific item in search results without full refresh
    func updateItemInSearchResults(itemId: String) {
        print("🔍 [SearchManager] updateItemInSearchResults called for itemId: \(itemId)")
        
        guard let db = databaseManager.getConnection() else { 
            print("❌ [SearchManager] Database connection failed")
            return 
        }
        
        print("🔍 [SearchManager] Current search results count: \(searchResults.count)")
        
        // Find the item index in current search results
        guard let index = searchResults.firstIndex(where: { $0.id == itemId }) else {
            print("⚠️ [SearchManager] Item \(itemId) not found in current search results - no update needed")
            return
        }
        
        print("✅ [SearchManager] Found item \(itemId) at index \(index)")
        
        // Get the existing item to preserve match context
        let existingItem = searchResults[index]
        let oldPrice = existingItem.price
        
        print("🔍 [SearchManager] Existing item price: \(oldPrice ?? 0.0)")
        
        // Fetch updated item data from database
        if let updatedItem = getCompleteItemData(
            itemId: itemId, 
            db: db, 
            matchType: existingItem.matchType,
            matchContext: existingItem.matchContext
        ) {
            let newPrice = updatedItem.price
            print("🔄 [SearchManager] Updated item price: \(newPrice ?? 0.0)")
            
            // Replace only this item in the array
            searchResults[index] = updatedItem
            print("✅ [SearchManager] Successfully updated item \(itemId) in search results (price: \(oldPrice ?? 0.0) → \(newPrice ?? 0.0))")
            // SwiftUI will automatically detect the change and update the UI
        } else {
            print("❌ [SearchManager] Failed to fetch updated item data for \(itemId)")
        }
    }
    
    /// Removes a specific item from search results
    func removeItemFromSearchResults(itemId: String) {
        searchResults.removeAll { $0.id == itemId }
    }
    
    /// Checks if a newly created item should appear in current search results
    func itemMatchesCurrentSearch(itemId: String) -> Bool {
        guard let currentTerm = currentSearchTerm,
              !currentTerm.isEmpty,
              let db = databaseManager.getConnection() else {
            return false
        }
        
        // Fetch the new item to check if it matches current search criteria
        if let newItem = getCompleteItemData(itemId: itemId, db: db, matchType: "name") {
            // Check if any of the item's fields match the current search term
            let searchTerm = currentTerm.lowercased()
            
            if let name = newItem.name?.lowercased(), name.contains(searchTerm) { return true }
            if let sku = newItem.sku?.lowercased(), sku.contains(searchTerm) { return true }
            if let barcode = newItem.barcode?.lowercased(), barcode.contains(searchTerm) { return true }
            if let category = newItem.categoryName?.lowercased(), category.contains(searchTerm) { return true }
        }
        
        return false
    }
    
    private func combineAndDeduplicateResults(
        localResults: [SearchResultItem],
        caseUpcResults: [SearchResultItem]
    ) -> [SearchResultItem] {
        // Combine results - fuzzy results (already sorted by score) come first, then case UPC results
        // This preserves the score-based ordering from fuzzy search
        let allResults = localResults + caseUpcResults
        // Combining fuzzy and case UPC results
        return removeDuplicatesAndRank(results: allResults, searchTerm: lastSearchTerm)
    }
}

// MARK: - Supporting Types

enum SearchError: LocalizedError {
    case databaseError(Error)
    case invalidSearchTerm
    case noConnection

    var errorDescription: String? {
        switch self {
        case .databaseError(let error):
            return "Database search error: \(error.localizedDescription)"
        case .invalidSearchTerm:
            return "Invalid search term"
        case .noConnection:
            return "Database connection not available"
        }
    }
}