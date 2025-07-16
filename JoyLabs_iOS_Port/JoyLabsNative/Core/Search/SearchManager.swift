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

    // Debouncing
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        // Initialize database manager on main actor if needed
        if let manager = databaseManager {
            self.databaseManager = manager
        } else {
            // Create database manager asynchronously to avoid main actor issues
            self.databaseManager = SQLiteSwiftCatalogManager()
        }

        // Initialize image URL manager
        self.imageURLManager = ImageURLManager(databaseManager: self.databaseManager)

        setupSearchDebouncing()

        // Initialize database connection asynchronously
        Task.detached(priority: .background) {
            await self.initializeDatabaseConnection()
        }
    }

    // MARK: - Database Initialization
    private func initializeDatabaseConnection() async {
        do {
            // Connect to database
            try databaseManager.connect()
            logger.info("✅ Search manager connected to database")

            // Create tables asynchronously
            try await databaseManager.createTablesAsync()
            logger.info("✅ Database tables initialized")

            // Update on main thread without blocking
            Task { @MainActor in
                isDatabaseReady = true
            }
        } catch {
            logger.error("❌ Search manager database connection failed: \(error)")
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
            logger.debug("🔍 Skipping search for single character: '\(trimmedTerm)'")
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
            logger.debug("🔍 Search delayed - database not ready yet")
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
        }

        logger.info("🔍 Performing search for: '\(trimmedTerm)' (offset: \(self.currentOffset), loadMore: \(loadMore))")

        do {
            // 1. Get total count first (only for initial search)
            if currentOffset == 0 {
                let totalCount = try await getTotalSearchResultsCount(searchTerm: trimmedTerm, filters: filters)
                Task { @MainActor in
                    totalResultsCount = totalCount
                }
                logger.debug("📊 Total available results: \(totalCount)")

                // Debug: If total count > 0 but we're about to get 0 results, investigate
                if totalCount > 0 {
                    logger.debug("🔍 TOTAL COUNT DEBUG: Found \(totalCount) total results for '\(trimmedTerm)'")
                }
            }

            // 2. Local SQLite search with pagination
            let localResults = try await searchLocalItems(
                searchTerm: trimmedTerm,
                filters: filters,
                offset: currentOffset,
                limit: pageSize
            )
            logger.debug("📊 Local search returned \(localResults.count) results (offset: \(self.currentOffset))")

            // 3. Case UPC search (only for first page and if numeric)
            var caseUpcResults: [SearchResultItem] = []
            if currentOffset == 0 && trimmedTerm.allSatisfy(\.isNumber) && filters.barcode {
                caseUpcResults = try await searchCaseUpcItems(searchTerm: trimmedTerm)
                logger.debug("📦 Case UPC search returned \(caseUpcResults.count) results")
            }

            // 4. Combine and deduplicate results
            let newResults = combineAndDeduplicateResults(
                localResults: localResults,
                caseUpcResults: caseUpcResults
            )

            // Debug: Check for mismatch between total count and actual results
            if currentOffset == 0 && self.totalResultsCount != nil && self.totalResultsCount! > 0 && newResults.isEmpty {
                logger.error("🚨 SEARCH MISMATCH: Total count shows \(self.totalResultsCount!) but combined results are empty for '\(trimmedTerm)'")
                logger.debug("🔍 MISMATCH DEBUG: localResults=\(localResults.count), caseUpcResults=\(caseUpcResults.count)")
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

                // Debug: Log final UI state
                logger.debug("🔍 UI STATE: searchResults.count=\(self.searchResults.count), hasMoreResults=\(self.hasMoreResults), totalResultsCount=\(self.totalResultsCount ?? -1)")

                // Images will be loaded on-demand when displayed in UI
            }

            let totalCount = newResults.count
            logger.info("✅ Search completed: \(newResults.count) new results, \(totalCount) total")
            return newResults

        } catch {
            logger.error("❌ Search failed: \(error)")

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
        isSearching = false
        isLoadingMore = false
        hasMoreResults = false
        totalResultsCount = nil
        currentOffset = 0
        // Note: Don't reset isDatabaseReady as it's a persistent state
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncing() {
        // Debounce search requests (800ms delay to prevent rapid searches)
        // Use background queue to avoid blocking main thread
        searchSubject
            .debounce(for: .milliseconds(800), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] (searchTerm, filters) in
                guard let self = self else { return }
                self.searchTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    _ = await self.performSearch(searchTerm: searchTerm, filters: filters)
                }
            }
            .store(in: &cancellables)
    }
    
    private func searchLocalItems(searchTerm: String, filters: SearchFilters, offset: Int = 0, limit: Int = 50) async throws -> [SearchResultItem] {
        // Native SQLite.swift search implementation optimized for iOS
        guard let db = databaseManager.getConnection() else {
            throw SearchError.databaseError(SQLiteSwiftError.noConnection)
        }

        logger.debug("🔍 Starting local search for: '\(searchTerm)'")
        logger.debug("🔍 SEARCH TERM DEBUG: Original='\(searchTerm)', Like pattern='\(searchTerm)'")

        var results: [SearchResultItem] = []
        let searchTermLike = "%\(searchTerm)%"
        logger.debug("🔍 LIKE PATTERN: '\(searchTermLike)'")

        // Name search - optimized with direct column access
        if filters.name {
            let nameResults = try searchByName(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: nameResults)
            logger.debug("📝 Name search found \(nameResults.count) results")
        }

        // SKU search - optimized with dedicated SKU column
        if filters.sku {
            let skuResults = try searchBySKU(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: skuResults)
            logger.debug("🏷️ SKU search found \(skuResults.count) results")
        }

        // UPC/Barcode search - optimized with dedicated UPC column
        if filters.barcode {
            let upcResults = try searchByUPC(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: upcResults)
            logger.debug("📊 UPC search found \(upcResults.count) results")
        }

        // Category search
        if filters.category {
            let categoryResults = try searchByCategory(db: db, searchTerm: searchTermLike, offset: offset, limit: limit)
            results.append(contentsOf: categoryResults)
            logger.debug("📂 Category search found \(categoryResults.count) results")
        }

        // Remove duplicates and apply fuzzy ranking
        let uniqueResults = removeDuplicatesAndRank(results: results, searchTerm: searchTerm)
        logger.info("✅ Total unique results: \(uniqueResults.count)")

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
            let caseUpcCount = try db.scalar(
                CatalogTableDefinitions.catalogItems
                    .join(CatalogTableDefinitions.teamData, on: CatalogTableDefinitions.itemId == CatalogTableDefinitions.teamDataItemId)
                    .filter(CatalogTableDefinitions.teamCaseUpc == searchTerm &&
                           CatalogTableDefinitions.itemIsDeleted == false)
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

            // Populate image data
            let images = populateImageData(for: itemId)

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

    // MARK: - Image Data Population

    /// Populate image data for a search result item
    private func populateImageData(for itemId: String) -> [CatalogImage]? {
        do {
            // Get image mappings for this item
            logger.debug("🔍 Looking for image mappings for item: \(itemId) with objectType: 'ITEM'")
            let imageMappings = try imageURLManager.getImageMappings(for: itemId, objectType: "ITEM")
            logger.debug("📊 Found \(imageMappings.count) image mappings for item: \(itemId)")

            guard !imageMappings.isEmpty else {
                logger.debug("📷 No images found for item: \(itemId)")
                return nil
            }

            // Log the found mappings
            for (index, mapping) in imageMappings.enumerated() {
                logger.debug("📷 Image mapping \(index + 1): squareImageId=\(mapping.squareImageId), localCacheKey=\(mapping.localCacheKey), imageType=\(mapping.imageType)")
            }

            // Convert image mappings to CatalogImage objects
            let catalogImages = imageMappings.map { mapping in
                logger.debug("📷 Creating CatalogImage with AWS URL: \(mapping.originalAwsUrl)")
                return CatalogImage(
                    id: mapping.squareImageId,
                    type: "IMAGE",
                    updatedAt: ISO8601DateFormatter().string(from: mapping.lastAccessedAt),
                    version: nil,
                    isDeleted: false,
                    presentAtAllLocations: true,
                    imageData: ImageData(
                        name: nil,
                        url: mapping.originalAwsUrl, // Use original AWS URL for Swift to download
                        caption: nil,
                        photoStudioOrderId: nil
                    )
                )
            }

            logger.debug("📷 Found \(catalogImages.count) images for item: \(itemId)")
            return catalogImages

        } catch {
            logger.error("📷 Failed to get images for item \(itemId): \(error)")
            return nil
        }
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

            // Populate image data
            let images = populateImageData(for: itemId)

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

            // Populate image data
            let images = populateImageData(for: itemId)

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
        // Industry-standard fuzzy matching algorithm
        let searchLower = searchTerm.lowercased()

        // Check exact matches first
        if let name = result.name?.lowercased(), name.contains(searchLower) {
            if name == searchLower { return 1.0 } // Exact match
            if name.hasPrefix(searchLower) { return 0.9 } // Prefix match
            return 0.7 // Contains match
        }

        if let sku = result.sku?.lowercased(), sku.contains(searchLower) {
            if sku == searchLower { return 1.0 }
            if sku.hasPrefix(searchLower) { return 0.9 }
            return 0.8
        }

        if let barcode = result.barcode?.lowercased(), barcode.contains(searchLower) {
            if barcode == searchLower { return 1.0 }
            if barcode.hasPrefix(searchLower) { return 0.9 }
            return 0.8
        }

        return 0.5 // Default score for other matches
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
