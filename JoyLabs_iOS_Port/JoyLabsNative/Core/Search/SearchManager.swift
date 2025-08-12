import Foundation
import SwiftUI
import SQLite
import Combine
import os.log

/// SearchManager - Handles sophisticated search with optimized SQLite queries
/// Built specifically for iOS with industry-standard fuzzy search and tokenized ranking
class SearchManager: ObservableObject {
    // MARK: - Published Properties
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var lastSearchTerm: String = ""
    @Published var currentSearchTerm: String? = nil
    @Published var hasMoreResults = false
    @Published var totalResultsCount: Int?
    @Published var isLoadingMore = false
    @Published var isDatabaseReady = false

    private var currentOffset = 0
    private let pageSize = 50

    // MARK: - Private Properties
    private let databaseManager: SQLiteSwiftCatalogManager
    private let imageURLManager: ImageURLManager
    private var searchTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SearchManager")
    
    // Fuzzy search engine for improved relevance scoring
    private let fuzzySearch = FuzzySearch()

    // Debouncing with intelligent delay
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        // Initialize database manager on main actor if needed
        if let manager = databaseManager {
            self.databaseManager = manager
            // Check if database is already connected
            if manager.getConnection() != nil {
                // Database already connected, mark as ready
                self.isDatabaseReady = true
                logger.debug("[Search] SearchManager using pre-connected shared database")
            }
        } else {
            // Create database manager asynchronously to avoid main actor issues
            self.databaseManager = SQLiteSwiftCatalogManager()
        }

        // Initialize image URL manager (can't use factory here due to MainActor isolation)
        self.imageURLManager = ImageURLManager(databaseManager: self.databaseManager)

        setupSearchDebouncing()

        // Initialize database connection asynchronously only if not already connected
        if !isDatabaseReady {
            Task.detached(priority: .background) {
                await self.initializeDatabaseConnection()
            }
        }
    }

    // MARK: - Database Initialization
    private func initializeDatabaseConnection() async {
        do {
            // Use existing connection or connect if not already connected
            if databaseManager.getConnection() == nil {
                try databaseManager.connect()
                logger.debug("[Search] Search manager connected to database")
            } else {
                logger.debug("[Search] Search manager using existing database connection")
            }

            // Tables are already created during app startup - no need to recreate
            logger.debug("[Search] Database tables already initialized during app startup")

            // Update on main thread without blocking
            Task { @MainActor in
                isDatabaseReady = true
            }
        } catch {
            logger.error("[Search] Search manager database connection failed: \(error)")
            // Update on main thread without blocking
            Task { @MainActor in
                searchError = "Database connection failed: \(error.localizedDescription)"
                isDatabaseReady = false
            }
        }
    }
    
    // MARK: - Public Methods
    
    
    func performSearch(searchTerm: String, filters: SearchFilters, loadMore: Bool = false) async -> [SearchResultItem] {
        // Port the exact logic from React Native performSearch with pagination
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTerm.isEmpty else {
            // Clear search state efficiently without blocking UI
            Task { @MainActor in
                if !searchResults.isEmpty {
                    searchResults = []
                }
                if !lastSearchTerm.isEmpty {
                    lastSearchTerm = ""
                }
                if currentOffset != 0 {
                    currentOffset = 0
                }
                if hasMoreResults {
                    hasMoreResults = false
                }
                if totalResultsCount != nil {
                    totalResultsCount = nil
                }
            }
            return []
        }

        // Skip search for single character queries to reduce excessive results
        guard trimmedTerm.count >= 2 else {
            // Clear results for single character but don't show error
            Task { @MainActor in
                if !searchResults.isEmpty {
                    searchResults = []
                }
                if hasMoreResults {
                    hasMoreResults = false
                }
                if totalResultsCount != nil {
                    totalResultsCount = nil
                }
            }
            return []
        }

        // Wait for database to be ready before performing search
        guard isDatabaseReady else {
            return []
        }

        // Reset pagination for new searches
        if !loadMore || lastSearchTerm != trimmedTerm {
            Task { @MainActor in
                currentOffset = 0
                searchResults = []
                totalResultsCount = nil
            }
        }

        Task { @MainActor in
            if loadMore {
                isLoadingMore = true
            } else {
                isSearching = true
            }
            searchError = nil
            lastSearchTerm = trimmedTerm
            currentSearchTerm = trimmedTerm
        }

        logger.info("[Search] Performing search for: '\(trimmedTerm)' (offset: \(self.currentOffset), loadMore: \(loadMore))")

        do {
            // 1. Get total count first (only for initial search)
            if currentOffset == 0 {
                let totalCount = try await getTotalSearchResultsCount(searchTerm: trimmedTerm, filters: filters)
                Task { @MainActor in
                    totalResultsCount = totalCount
                }



            }

            // 2. Local SQLite search with pagination
            let localResults = try await searchLocalItems(
                searchTerm: trimmedTerm,
                filters: filters,
                offset: currentOffset,
                limit: pageSize
            )


            // 3. Case UPC search (only for first page and if numeric)
            var caseUpcResults: [SearchResultItem] = []
            if currentOffset == 0 && trimmedTerm.allSatisfy(\.isNumber) && filters.barcode {
                caseUpcResults = try await searchCaseUpcItems(searchTerm: trimmedTerm)
                logger.debug("[Search] Case UPC search returned \(caseUpcResults.count) results")
            }

            // 4. Combine and deduplicate results
            let newResults = combineAndDeduplicateResults(
                localResults: localResults,
                caseUpcResults: caseUpcResults
            )

            // Check for mismatch between total count and actual results
            if currentOffset == 0 && self.totalResultsCount != nil && self.totalResultsCount! > 0 && newResults.isEmpty {
                logger.error("[Search] SEARCH MISMATCH: Total count shows \(self.totalResultsCount!) but combined results are empty for '\(trimmedTerm)'")
            }

            Task { @MainActor in
                if loadMore {
                    // Append new results, avoiding duplicates
                    let existingIds = Set(searchResults.map { $0.id })
                    let uniqueNewResults = newResults.filter { !existingIds.contains($0.id) }
                    searchResults.append(contentsOf: uniqueNewResults)
                    isLoadingMore = false
                } else {
                    searchResults = newResults
                    isSearching = false
                }

                // Update pagination state
                currentOffset += pageSize
                hasMoreResults = searchResults.count < (totalResultsCount ?? 0)



                // Images will be loaded on-demand when displayed in UI
            }

            let totalCount = newResults.count
            logger.info("[Search] Search completed: \(newResults.count) new results, \(totalCount) total")
            return newResults

        } catch {
            logger.error("[Search] Search failed: \(error)")

            Task { @MainActor in
                searchError = error.localizedDescription
                if loadMore {
                    isLoadingMore = false
                } else {
                    isSearching = false
                    searchResults = []
                }
            }

            return []
        }
    }
    
    func performSearchWithDebounce(searchTerm: String, filters: SearchFilters) {
        // Cancel any existing search asynchronously to avoid blocking main thread
        let taskToCancel = searchTask
        searchTask = nil

        // Cancel on background queue to avoid blocking
        Task.detached(priority: .background) {
            taskToCancel?.cancel()
        }

        // Send to debounced subject
        searchSubject.send((searchTerm, filters))
    }
    
    func loadMoreResults() {
        guard !isLoadingMore && hasMoreResults && !lastSearchTerm.isEmpty else { return }

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            _ = await self.performSearch(
                searchTerm: self.lastSearchTerm,
                filters: SearchFilters(name: true, sku: true, barcode: true, category: false),
                loadMore: true
            )
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        lastSearchTerm = ""
        currentSearchTerm = nil
        isSearching = false
        isLoadingMore = false
        hasMoreResults = false
        totalResultsCount = nil
        currentOffset = 0
        // Note: Don't reset isDatabaseReady as it's a persistent state
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncing() {
        // Intelligent debouncing: shorter delay for longer queries
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] (searchTerm, filters) in
                guard let self = self else { return }
                
                // Skip debouncing for single character to provide immediate feedback of "no results"
                let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                let delay: Int = {
                    if trimmedTerm.count == 1 { return 0 }        // Immediate for single char
                    if trimmedTerm.count == 2 { return 200 }      // Fast for 2 chars
                    if trimmedTerm.count >= 3 { return 100 }      // Very fast for 3+ chars
                    return 300                                     // Default
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
    
    private func searchLocalItems(searchTerm: String, filters: SearchFilters, offset: Int = 0, limit: Int = 50) async throws -> [SearchResultItem] {
        // RESTORED: Use the original working search architecture with proper data enrichment
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        var results: [SearchResultItem] = []
        let searchTermLike = "%\(searchTerm)%"

        // Name search - uses proper getCompleteItemData() enrichment
        if filters.name {
            let nameResults = try searchByName(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: nameResults)
        }

        // SKU search - uses proper getCompleteItemData() enrichment  
        if filters.sku {
            let skuResults = try searchBySKU(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: skuResults)
        }

        // UPC/Barcode search - uses proper getCompleteItemData() enrichment
        if filters.barcode {
            let upcResults = try searchByUPC(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: upcResults)
        }

        // Category search - uses proper getCompleteItemData() enrichment
        if filters.category {
            let categoryResults = try searchByCategory(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: categoryResults)
            logger.debug("📂 Category search found \(categoryResults.count) results")
        }

        // PRESERVED: Your working deduplication and ranking logic
        let uniqueResults = removeDuplicatesAndRank(results: results, searchTerm: searchTerm)
        logger.info("✅ Total unique results with complete data: \(uniqueResults.count)")

        return uniqueResults
    }

    private func getTotalSearchResultsCount(searchTerm: String, filters: SearchFilters) async throws -> Int {
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        var totalCount = 0
        // Removed unused searchTermLike variable

        // Tokenize search term for consistent counting
        let tokens = searchTerm.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        // Count name search results with tokenized search
        if filters.name {
            var nameQuery = CatalogTableDefinitions.catalogItems
                .filter(CatalogTableDefinitions.itemIsDeleted == false)

            // Build AND conditions for each token (all tokens must match)
            for token in tokens {
                let tokenPattern = "%\(token)%"
                nameQuery = nameQuery.filter(CatalogTableDefinitions.itemName.like(tokenPattern))
            }

            let nameCount = try db.scalar(nameQuery.count)
            totalCount += nameCount
        }

        // Count SKU search results with tokenized search
        if filters.sku {
            let variations = CatalogTableDefinitions.itemVariations.alias("iv")
            let items = CatalogTableDefinitions.catalogItems.alias("ci")

            var skuQuery = variations
                .join(items, on: variations[CatalogTableDefinitions.variationItemId] == items[CatalogTableDefinitions.itemId])
                .filter(variations[CatalogTableDefinitions.variationIsDeleted] == false &&
                       items[CatalogTableDefinitions.itemIsDeleted] == false)

            // Build AND conditions for each token (all tokens must match)
            for token in tokens {
                let tokenPattern = "%\(token)%"
                skuQuery = skuQuery.filter(variations[CatalogTableDefinitions.variationSku].like(tokenPattern))
            }

            let skuCount = try db.scalar(skuQuery.count)
            totalCount += skuCount
        }

        // Count UPC search results with tokenized search
        if filters.barcode {
            let variations = CatalogTableDefinitions.itemVariations.alias("iv")
            let items = CatalogTableDefinitions.catalogItems.alias("ci")

            var upcQuery = variations
                .join(items, on: variations[CatalogTableDefinitions.variationItemId] == items[CatalogTableDefinitions.itemId])
                .filter(variations[CatalogTableDefinitions.variationIsDeleted] == false &&
                       items[CatalogTableDefinitions.itemIsDeleted] == false)

            // Build AND conditions for each token (all tokens must match)
            for token in tokens {
                let tokenPattern = "%\(token)%"
                upcQuery = upcQuery.filter(variations[CatalogTableDefinitions.variationUpc].like(tokenPattern))
            }

            let upcCount = try db.scalar(upcQuery.count)
            totalCount += upcCount
        }

        // Count case UPC results (if numeric)
        if searchTerm.allSatisfy(\.isNumber) && filters.barcode {
            let items = CatalogTableDefinitions.catalogItems.alias("ci")
            let teamData = CatalogTableDefinitions.teamData.alias("td")

            let caseUpcCount = try db.scalar(
                items
                    .join(teamData, on: items[CatalogTableDefinitions.itemId] == teamData[CatalogTableDefinitions.teamDataItemId])
                    .filter(teamData[CatalogTableDefinitions.teamCaseUpc] == searchTerm &&
                           items[CatalogTableDefinitions.itemIsDeleted] == false)
                    .count
            )
            totalCount += caseUpcCount
        }

        return totalCount
    }

    // MARK: - Individual Search Methods

    private func searchByName(db: Connection, searchTerm: String, offset: Int = 0, limit: Int = 50) throws -> [SearchResultItem] {
        // Extract the actual search term from the LIKE pattern (remove % characters)
        let cleanSearchTerm = searchTerm.replacingOccurrences(of: "%", with: "")

        // Tokenize search term for multi-word fuzzy search
        let tokens = cleanSearchTerm.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        var query = CatalogTableDefinitions.catalogItems
            .select(CatalogTableDefinitions.itemId, CatalogTableDefinitions.itemName)
            .filter(CatalogTableDefinitions.itemIsDeleted == false)

        // Build AND conditions for each token (all tokens must match)
        for token in tokens {
            let tokenPattern = "%\(token)%"
            query = query.filter(CatalogTableDefinitions.itemName.like(tokenPattern))
        }

        query = query.order(CatalogTableDefinitions.itemName.asc).limit(limit, offset: offset)

        var results: [SearchResultItem] = []
        for row in try db.prepare(query) {
            let itemId = try row.get(CatalogTableDefinitions.itemId)
            let itemName = try row.get(CatalogTableDefinitions.itemName)

            // Use unified retrieval for complete item data
            if let result = getCompleteItemData(itemId: itemId, db: db, matchType: "name", matchContext: itemName) {
                results.append(result)
            }
        }
        return results
    }

    private func searchBySKU(db: Connection, searchTerm: String, offset: Int = 0, limit: Int = 50) throws -> [SearchResultItem] {
        let variations = CatalogTableDefinitions.itemVariations.alias("iv")
        let items = CatalogTableDefinitions.catalogItems.alias("ci")

        // Extract the actual search term from the LIKE pattern (remove % characters)
        let cleanSearchTerm = searchTerm.replacingOccurrences(of: "%", with: "")

        // Tokenize search term for multi-word fuzzy search
        let tokens = cleanSearchTerm.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        var query = variations
            .select(
                items[CatalogTableDefinitions.itemId],
                variations[CatalogTableDefinitions.variationSku]
            )
            .join(items, on: variations[CatalogTableDefinitions.variationItemId] == items[CatalogTableDefinitions.itemId])
            .filter(variations[CatalogTableDefinitions.variationIsDeleted] == false &&
                   items[CatalogTableDefinitions.itemIsDeleted] == false)

        // Build AND conditions for each token (all tokens must match)
        for token in tokens {
            let tokenPattern = "%\(token)%"
            query = query.filter(variations[CatalogTableDefinitions.variationSku].like(tokenPattern))
        }

        query = query.order(items[CatalogTableDefinitions.itemName].asc).limit(limit, offset: offset)

        return try db.prepare(query).compactMap { row in
            let itemId = try row.get(items[CatalogTableDefinitions.itemId])
            let sku = try row.get(variations[CatalogTableDefinitions.variationSku])

            // Use unified retrieval for complete item data
            return getCompleteItemData(itemId: itemId, db: db, matchType: "sku", matchContext: sku)
        }
    }

    private func searchByUPC(db: Connection, searchTerm: String, offset: Int = 0, limit: Int = 50) throws -> [SearchResultItem] {
        let variations = CatalogTableDefinitions.itemVariations.alias("iv")
        let items = CatalogTableDefinitions.catalogItems.alias("ci")

        // Extract the actual search term from the LIKE pattern (remove % characters)
        let cleanSearchTerm = searchTerm.replacingOccurrences(of: "%", with: "")

        // For UPC, usually we want exact matches, but allow tokenized search for partial UPCs
        let tokens = cleanSearchTerm.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        var query = variations
            .select(
                items[CatalogTableDefinitions.itemId],
                variations[CatalogTableDefinitions.variationUpc]
            )
            .join(items, on: variations[CatalogTableDefinitions.variationItemId] == items[CatalogTableDefinitions.itemId])
            .filter(variations[CatalogTableDefinitions.variationIsDeleted] == false &&
                   items[CatalogTableDefinitions.itemIsDeleted] == false)

        // Build AND conditions for each token (all tokens must match)
        for token in tokens {
            let tokenPattern = "%\(token)%"
            query = query.filter(variations[CatalogTableDefinitions.variationUpc].like(tokenPattern))
        }

        query = query.order(items[CatalogTableDefinitions.itemName].asc).limit(limit, offset: offset)

        return try db.prepare(query).compactMap { row in
            let itemId = try row.get(items[CatalogTableDefinitions.itemId])
            let upc = try row.get(variations[CatalogTableDefinitions.variationUpc])

            // Use unified retrieval for complete item data
            return getCompleteItemData(itemId: itemId, db: db, matchType: "upc", matchContext: upc)
        }
    }

    private func searchByCategory(db: Connection, searchTerm: String, offset: Int = 0, limit: Int = 50) throws -> [SearchResultItem] {
        let items = CatalogTableDefinitions.catalogItems.alias("ci")
        let categories = CatalogTableDefinitions.categories.alias("cat")

        let query = items
            .select(
                items[CatalogTableDefinitions.itemId],
                categories[CatalogTableDefinitions.categoryName]
            )
            .join(categories, on: items[CatalogTableDefinitions.itemCategoryId] == categories[CatalogTableDefinitions.categoryId])
            .filter(categories[CatalogTableDefinitions.categoryName].like(searchTerm) &&
                   items[CatalogTableDefinitions.itemIsDeleted] == false &&
                   categories[CatalogTableDefinitions.categoryIsDeleted] == false)
            .order(items[CatalogTableDefinitions.itemName].asc)
            .limit(limit, offset: offset)

        return try db.prepare(query).compactMap { row in
            let itemId = try row.get(items[CatalogTableDefinitions.itemId])
            let categoryName = try row.get(categories[CatalogTableDefinitions.categoryName])

            // Use unified retrieval for complete item data
            return getCompleteItemData(itemId: itemId, db: db, matchType: "category", matchContext: categoryName)
        }
    }

    // MARK: - Unified Item Retrieval

    /// Single source of truth for retrieving complete item data by item ID
    /// This function is used by ALL search types to ensure consistency
    private func getCompleteItemData(itemId: String, db: Connection, matchType: String, matchContext: String? = nil) -> SearchResultItem? {
        do {
            // Simple query to get basic item data and first variation
            let items = CatalogTableDefinitions.catalogItems.alias("ci")
            let variations = CatalogTableDefinitions.itemVariations.alias("iv")

            let query = items
                .select(
                    // Item data
                    items[CatalogTableDefinitions.itemId],
                    items[CatalogTableDefinitions.itemName],
                    items[CatalogTableDefinitions.itemCategoryId],
                    items[CatalogTableDefinitions.itemReportingCategoryName],
                    items[CatalogTableDefinitions.itemCategoryName],
                    // First variation data (for SKU, price, UPC)
                    variations[CatalogTableDefinitions.variationSku],
                    variations[CatalogTableDefinitions.variationUpc],
                    variations[CatalogTableDefinitions.variationPriceAmount]
                )
                .join(.leftOuter, variations, on: items[CatalogTableDefinitions.itemId] == variations[CatalogTableDefinitions.variationItemId] && variations[CatalogTableDefinitions.variationIsDeleted] == false)
                .filter(items[CatalogTableDefinitions.itemId] == itemId && items[CatalogTableDefinitions.itemIsDeleted] == false)
                .limit(1) // We only need one result per item

            guard let row = try db.pluck(query) else {
                return nil
            }

            // Extract all data from the unified query
            let itemName = try row.get(items[CatalogTableDefinitions.itemName])
            let categoryId = try? row.get(items[CatalogTableDefinitions.itemCategoryId])
            let reportingCategoryName = try? row.get(items[CatalogTableDefinitions.itemReportingCategoryName])
            let regularCategoryName = try? row.get(items[CatalogTableDefinitions.itemCategoryName])
            let categoryName = reportingCategoryName ?? regularCategoryName

            let sku = try? row.get(variations[CatalogTableDefinitions.variationSku])
            let upc = try? row.get(variations[CatalogTableDefinitions.variationUpc])
            let priceAmount = try? row.get(variations[CatalogTableDefinitions.variationPriceAmount])

            // Get case UPC data separately if needed (for case UPC match type)
            var caseUpc: String? = nil
            var caseCost: Double? = nil

            if matchType == "case_upc" {
                // Only query team data when we actually need it
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

            // Determine price and barcode based on match type
            let price: Double?
            let barcode: String?
            let isFromCaseUpc: Bool

            switch matchType {
            case "case_upc":
                price = caseCost // Case cost is already in dollars
                barcode = caseUpc
                isFromCaseUpc = true
            default:
                // Convert price from cents to dollars for regular items
                if let amount = priceAmount, amount > 0 {
                    let convertedPrice = Double(amount) / 100.0
                    price = convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
                } else {
                    price = nil
                }
                barcode = upc
                isFromCaseUpc = false
            }

            // Check if item has taxes
            let hasTax = checkItemHasTaxById(itemId: itemId)

            // Get primary image URL using unified approach
            let images = getPrimaryImageForSearchResult(itemId: itemId)

            return SearchResultItem(
                id: itemId,
                name: itemName,
                sku: sku,
                price: price,
                barcode: barcode,
                categoryId: categoryId,
                categoryName: categoryName,
                images: images,
                matchType: matchType,
                matchContext: matchContext,
                isFromCaseUpc: isFromCaseUpc,
                caseUpcData: isFromCaseUpc ? CaseUpcData(
                    caseUpc: caseUpc ?? "",
                    caseCost: caseCost ?? 0.0,
                    caseQuantity: 1, // Default, could be enhanced
                    vendor: nil,
                    discontinued: false,
                    notes: nil
                ) : nil,
                hasTax: hasTax
            )

        } catch {
            logger.error("Failed to retrieve item data for \(itemId): \(error)")
            return nil
        }
    }

    // MARK: - Unified Image Integration

    /// Get primary image for search result using CORRECT database order
    private func getPrimaryImageForSearchResult(itemId: String) -> [CatalogImage]? {
        do {
            guard let db = databaseManager.getConnection() else {
                return nil
            }
            
            // Get item's image_ids array from database (CORRECT approach)
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
                    
                    // Try nested under item_data first (current format)
                    if let itemData = currentData["item_data"] as? [String: Any] {
                        imageIds = itemData["image_ids"] as? [String]
                    }
                    
                    // Fallback to root level (legacy format)
                    if imageIds == nil {
                        imageIds = currentData["image_ids"] as? [String]
                    }
                    
                    if let imageIdArray = imageIds, let primaryImageId = imageIdArray.first {
                    // Get image mapping for this specific image ID
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
            
        } catch {
            // Silent failure for image retrieval - don't spam logs
        }
        
        return nil
    }

    // MARK: - Result Creation and Ranking

    private func createSearchResultFromRow(_ row: Row, matchType: String) -> SearchResultItem? {
        do {
            let itemId = try row.get(CatalogTableDefinitions.itemId)
            let itemName = try row.get(CatalogTableDefinitions.itemName)
            let categoryId = try row.get(CatalogTableDefinitions.itemCategoryId)
            let dataJson = try row.get(CatalogTableDefinitions.itemDataJson)

            // Get pre-stored category names (fast!) - prioritize reporting category over regular category
            let reportingCategoryName = try? row.get(CatalogTableDefinitions.itemReportingCategoryName)
            let regularCategoryName = try? row.get(CatalogTableDefinitions.itemCategoryName)
            let categoryName = reportingCategoryName ?? regularCategoryName

            // Debug: Check what we're getting from database
            logger.debug("🔍 SEARCH: Item \(itemId) DB retrieval: reporting='\(reportingCategoryName ?? "nil")', regular='\(regularCategoryName ?? "nil")', final='\(categoryName ?? "nil")'")

            if categoryName == nil {
                logger.warning("🔍 SEARCH: No category found in DB for item \(itemId) that should have category")
            }

            // Get first variation data for SKU, price, and barcode
            let variationData = getFirstVariationForItem(itemId: itemId)

            // Check if item has taxes by parsing the dataJson
            let hasTax = checkItemHasTax(dataJson: dataJson)

            // Get primary image URL using unified approach
            let images = getPrimaryImageForSearchResult(itemId: itemId)
            
            // SimpleImageView with AsyncImage handles caching automatically - no pre-loading needed

            return SearchResultItem(
                id: itemId,
                name: itemName,
                sku: variationData.sku,
                price: variationData.price,
                barcode: variationData.barcode,
                categoryId: categoryId,
                categoryName: categoryName,
                images: images,
                matchType: matchType,
                matchContext: matchType == "category" ? categoryName : itemName,
                isFromCaseUpc: false,
                caseUpcData: nil,
                hasTax: hasTax
            )
        } catch {
            logger.error("Failed to create search result from row: \(error)")
            return nil
        }
    }

    private func createSearchResultFromVariationRow(_ row: Row, matchType: String) -> SearchResultItem? {
        do {
            // Access columns directly - the JOIN query will have flattened the results
            let itemId = try row.get(CatalogTableDefinitions.itemId)
            let itemName = try row.get(CatalogTableDefinitions.itemName)
            let categoryId = try row.get(CatalogTableDefinitions.itemCategoryId)
            let sku = try row.get(CatalogTableDefinitions.variationSku)
            let upc = try row.get(CatalogTableDefinitions.variationUpc)
            let priceAmount = try row.get(CatalogTableDefinitions.variationPriceAmount)

            // Get pre-stored category names (fast!) - prioritize reporting category over regular category
            let reportingCategoryName = try? row.get(CatalogTableDefinitions.itemReportingCategoryName)
            let regularCategoryName = try? row.get(CatalogTableDefinitions.itemCategoryName)
            let categoryName = reportingCategoryName ?? regularCategoryName

            // Debug: Check what we're getting from database for variation results
            logger.debug("🔍 VARIATION SEARCH: Item \(itemId) DB retrieval: reporting='\(reportingCategoryName ?? "nil")', regular='\(regularCategoryName ?? "nil")', final='\(categoryName ?? "nil")'")

            if categoryName == nil {
                logger.warning("🔍 VARIATION SEARCH: No category found in DB for item \(itemId) that should have category")
            }

            // Safely convert price, ensuring no NaN values
            let price: Double?
            if let amount = priceAmount, amount > 0 {
                let convertedPrice = Double(amount) / 100.0 // Convert from cents
                // Additional safety check for NaN/infinite values
                if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                    price = convertedPrice
                } else {
                    price = nil
                }
            } else {
                price = nil // Use nil instead of 0 to avoid NaN issues
            }

            let matchContext = matchType == "sku" ? sku : upc

            // For variation rows, we need to get the item's dataJson to check for taxes
            // This requires a separate query since the variation JOIN doesn't include dataJson
            let hasTax = checkItemHasTaxById(itemId: itemId)

            // Get primary image URL using unified approach
            let images = getPrimaryImageForSearchResult(itemId: itemId)

            return SearchResultItem(
                id: itemId,
                name: itemName,
                sku: sku,
                price: price,
                barcode: upc,
                categoryId: categoryId,
                categoryName: categoryName,
                images: images,
                matchType: matchType,
                matchContext: matchContext,
                isFromCaseUpc: false,
                caseUpcData: nil,
                hasTax: hasTax
            )
        } catch {
            logger.error("Failed to create search result from variation row: \(error)")
            return nil
        }
    }

    private func removeDuplicatesAndRank(results: [SearchResultItem], searchTerm: String) -> [SearchResultItem] {
        // Remove duplicates by ID
        var uniqueResults: [String: SearchResultItem] = [:]

        for result in results {
            // Keep the result with the best match type priority
            if let existing = uniqueResults[result.id] {
                if getMatchTypePriority(result.matchType) < getMatchTypePriority(existing.matchType) {
                    uniqueResults[result.id] = result
                }
            } else {
                uniqueResults[result.id] = result
            }
        }

        // Apply fuzzy ranking and sort
        return Array(uniqueResults.values)
            .map { result in
                let rankedResult = result
                // Calculate fuzzy score based on match quality
                _ = calculateFuzzyScore(result: result, searchTerm: searchTerm)
                // Store score in a way that can be used for sorting
                return rankedResult
            }
            .sorted { lhs, rhs in
                // Sort by match type priority first, then by name
                let lhsPriority = getMatchTypePriority(lhs.matchType)
                let rhsPriority = getMatchTypePriority(rhs.matchType)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                // Then by name alphabetically
                let lhsName = lhs.name ?? ""
                let rhsName = rhs.name ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    private func getMatchTypePriority(_ matchType: String?) -> Int {
        switch matchType {
        case "upc", "barcode": return 1 // Exact barcode matches are highest priority
        case "sku": return 2 // SKU matches are second priority
        case "name": return 3 // Name matches are third priority
        case "category": return 4 // Category matches are lowest priority
        default: return 5
        }
    }

    private func calculateFuzzyScore(result: SearchResultItem, searchTerm: String) -> Double {
        // Enhanced fuzzy matching with Levenshtein distance for typo tolerance
        let searchLower = searchTerm.lowercased()
        var bestScore: Double = 0.0

        // Score name field (weight: 1.0)
        if let name = result.name?.lowercased() {
            let nameScore = scoreField(name, against: searchLower, weight: 1.0)
            bestScore = max(bestScore, nameScore)
        }

        // Score SKU field (weight: 1.3 - higher priority)
        if let sku = result.sku?.lowercased() {
            let skuScore = scoreField(sku, against: searchLower, weight: 1.3)
            bestScore = max(bestScore, skuScore)
        }

        // Score barcode field (weight: 1.5 - highest priority)
        if let barcode = result.barcode?.lowercased() {
            let barcodeScore = scoreField(barcode, against: searchLower, weight: 1.5)
            bestScore = max(bestScore, barcodeScore)
        }

        // Score category field (weight: 0.7 - lower priority)
        if let category = result.categoryName?.lowercased() {
            let categoryScore = scoreField(category, against: searchLower, weight: 0.7)
            bestScore = max(bestScore, categoryScore)
        }

        return min(bestScore, 1.0) // Cap at 1.0
    }
    
    private func scoreField(_ field: String, against searchTerm: String, weight: Double) -> Double {
        // Exact match (highest score)
        if field == searchTerm {
            return 1.0 * weight
        }
        
        // Prefix match  
        if field.hasPrefix(searchTerm) {
            return 0.9 * weight
        }
        
        // Substring match
        if field.contains(searchTerm) {
            return 0.7 * weight  
        }
        
        // Fuzzy match using Levenshtein distance for typo tolerance
        let distance = levenshteinDistance(field, searchTerm)
        let maxLength = max(field.count, searchTerm.count)
        
        if distance <= 2 && maxLength > 2 {
            let similarity = 1.0 - (Double(distance) / Double(maxLength))
            return (0.5 * similarity) * weight
        }
        
        // Token-based matching for multi-word queries
        let searchTokens = searchTerm.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if searchTokens.count > 1 {
            var tokenMatches = 0
            for token in searchTokens {
                if field.contains(token) {
                    tokenMatches += 1
                }
            }
            if tokenMatches > 0 {
                let matchRatio = Double(tokenMatches) / Double(searchTokens.count)
                return (0.4 * matchRatio) * weight
            }
        }
        
        return 0.0
    }
    
    // Levenshtein distance for typo tolerance
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }

    private func searchCaseUpcItems(searchTerm: String) async throws -> [SearchResultItem] {
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        logger.debug("🔍 Searching Case UPC for numeric term: \(searchTerm)")

        // Check if team_data table has any case UPC data
        let teamDataCount = try db.scalar(
            CatalogTableDefinitions.teamData
                .filter(CatalogTableDefinitions.teamCaseUpc != nil)
                .count
        )

        if teamDataCount == 0 {
            logger.info("📦 No team data with case UPC found - table empty or user not signed in")
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

                // Use unified retrieval for complete item data
                return getCompleteItemData(itemId: itemId, db: db, matchType: "case_upc", matchContext: caseUpc)
            } catch {
                logger.error("Failed to create case UPC search result: \(error)")
                return nil
            }
        }
    }
    
    private func combineAndDeduplicateResults(
        localResults: [SearchResultItem],
        caseUpcResults: [SearchResultItem]
    ) -> [SearchResultItem] {
        // Combine all results and use the advanced ranking system
        let allResults = localResults + caseUpcResults

        // The removeDuplicatesAndRank method already handles deduplication and ranking
        return removeDuplicatesAndRank(results: allResults, searchTerm: lastSearchTerm)
    }

    // MARK: - Tax Helper Methods

    private func checkItemHasTax(dataJson: String?) -> Bool {
        guard let dataJson = dataJson,
              let data = dataJson.data(using: .utf8) else {
            return false
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taxIds = json["tax_ids"] as? [String] {
                return !taxIds.isEmpty
            }
        } catch {
            logger.debug("Failed to parse dataJson for tax info: \(error)")
        }

        return false
    }

    private func checkItemHasTaxById(itemId: String) -> Bool {
        guard let db = databaseManager.getConnection() else {
            return false
        }

        do {
            let query = CatalogTableDefinitions.catalogItems
                .select(CatalogTableDefinitions.itemDataJson)
                .filter(CatalogTableDefinitions.itemId == itemId)

            if let row = try db.pluck(query) {
                let dataJson = try row.get(CatalogTableDefinitions.itemDataJson)
                return checkItemHasTax(dataJson: dataJson)
            }
        } catch {
            logger.debug("Failed to check tax for item \(itemId): \(error)")
        }

        return false
    }

    // MARK: - Data Population Helper Methods



    private func getFirstVariationForItem(itemId: String) -> (sku: String?, price: Double?, barcode: String?) {
        guard let db = databaseManager.getConnection() else {
            return (nil, nil, nil)
        }

        do {
            let query = CatalogTableDefinitions.itemVariations
                .select(CatalogTableDefinitions.variationSku,
                       CatalogTableDefinitions.variationPriceAmount,
                       CatalogTableDefinitions.variationUpc)
                .filter(CatalogTableDefinitions.variationItemId == itemId &&
                       CatalogTableDefinitions.variationIsDeleted == false)
                .limit(1)

            if let row = try db.pluck(query) {
                let sku = try row.get(CatalogTableDefinitions.variationSku)
                let priceAmount = try row.get(CatalogTableDefinitions.variationPriceAmount)
                let upc = try row.get(CatalogTableDefinitions.variationUpc)

                // Convert price from cents to dollars
                let price: Double?
                if let amount = priceAmount, amount > 0 {
                    let convertedPrice = Double(amount) / 100.0
                    if convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 {
                        price = convertedPrice
                    } else {
                        price = nil
                    }
                } else {
                    price = nil
                }

                return (sku, price, upc)
            }
        } catch {
            logger.debug("Failed to get variation data for item \(itemId): \(error)")
        }

        return (nil, nil, nil)
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

// MARK: - Raw Search Result (for internal use)
struct RawSearchResult {
    let id: String
    let dataJson: String
    let matchType: String
    let matchContext: String?
}
