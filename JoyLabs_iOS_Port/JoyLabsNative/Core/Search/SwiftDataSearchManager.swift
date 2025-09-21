import Foundation
import SwiftUI
import SwiftData
import Combine
import os.log

/// SwiftData-based SearchManager
/// Replaces SQLite queries with SwiftData predicates and fetch descriptors
@MainActor
class SwiftDataSearchManager: ObservableObject {
    // MARK: - Published Properties
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var lastSearchTerm: String = ""
    @Published var currentSearchTerm: String? = nil
    @Published var totalResultsCount: Int? = nil
    @Published var hasMoreResults: Bool = false
    @Published var currentPage: Int = 0

    // MARK: - Pagination Properties
    private var allSearchResults: [SearchResultItem] = []
    private let pageSize: Int = 50
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataSearch")
    
    // Simple search - no complex scoring needed
    
    // Debouncing
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(modelContext: ModelContext? = nil) {
        if let context = modelContext {
            self.modelContext = context
            logger.debug("[Search] Using provided model context")
        } else {
            // Get context from SwiftDataCatalogManager
            do {
                let manager = try SwiftDataCatalogManager()
                self.modelContext = manager.getContext()
                logger.debug("[Search] Created new model context")
            } catch {
                fatalError("Failed to initialize SwiftDataSearchManager: \(error)")
            }
        }
        
        // No need for separate fuzzy search instance - using native SwiftData
        
        setupSearchDebouncing()
    }
    
    // MARK: - Main Search Function

    func performSearch(searchTerm: String, filters: SearchFilters) async -> [SearchResultItem] {
        // Reset pagination for new search
        await MainActor.run {
            currentPage = 0
            allSearchResults = []
        }
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTerm.isEmpty else {
            clearSearch()
            return []
        }
        
        guard trimmedTerm.count >= 3 else {
            Task { @MainActor in
                searchResults = []
                totalResultsCount = nil
            }
            return []
        }
        
        Task { @MainActor in
            isSearching = true
            searchError = nil
            lastSearchTerm = trimmedTerm
            currentSearchTerm = trimmedTerm
        }
        
        logger.debug("[Search] Performing search for: '\(trimmedTerm)'")
        
        do {
            // Use native SwiftData predicates for database-level filtering (no memory processing!)
            logger.debug("[Search] Using native SwiftData predicates for term: '\(trimmedTerm)'")

            let catalogResults = try await performNativeSwiftDataSearch(
                searchTerm: trimmedTerm,
                filters: filters
            )

            logger.info("[Search] Native SwiftData search returned \(catalogResults.count) results")

            // Results are already enriched from native search - no double processing needed
            let enrichedCatalogResults = catalogResults
            
            // Check for case UPC matches if searching for numeric term (IDENTICAL logic)
            var caseUpcResults: [SearchResultItem] = []
            if trimmedTerm.allSatisfy({ $0.isNumber }) && filters.barcode {
                caseUpcResults = try await searchCaseUpc(searchTerm: trimmedTerm)
            }
            
            // Combine and deduplicate results (preserving fuzzy search ranking!)
            let allResults = combineResults(catalogResults: enrichedCatalogResults, caseUpcResults: caseUpcResults)
            
            Task { @MainActor in
                // Store all results and show first page
                allSearchResults = allResults
                totalResultsCount = allResults.count

                // Show first page (50 results)
                let firstPage = Array(allResults.prefix(pageSize))
                searchResults = firstPage
                hasMoreResults = allResults.count > pageSize
                currentPage = 1

                isSearching = false
            }
            
            logger.debug("[Search] Found \(allResults.count) results")
            return allResults
            
        } catch {
            logger.error("[Search] Search failed: \(error)")
            
            Task { @MainActor in
                searchError = error.localizedDescription
                isSearching = false
                searchResults = []
            }
            
            return []
        }
    }
    
    // MARK: - Native SwiftData Search (Database-Level Filtering)

    private func performNativeSwiftDataSearch(
        searchTerm: String,
        filters: SearchFilters
    ) async throws -> [SearchResultItem] {

        let cleanTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("[Search] Simple search for: '\(cleanTerm)'")

        var results: [SearchResultItem] = []

        // Search names
        if filters.name {
            let nameResults = try searchNames(searchTerm: cleanTerm)
            results.append(contentsOf: nameResults)
        }

        // Search barcodes
        if filters.barcode {
            let barcodeResults = try searchBarcodes(searchTerm: cleanTerm)
            results.append(contentsOf: barcodeResults)
        }

        // Remove duplicates
        var seenIds = Set<String>()
        let allResults = results.filter { seenIds.insert($0.id).inserted }

        // Set up pagination infrastructure
        await MainActor.run {
            // Store all results for pagination
            allSearchResults = allResults
            totalResultsCount = allResults.count

            // Show first page (50 results)
            let firstPage = Array(allResults.prefix(pageSize))
            searchResults = firstPage
            hasMoreResults = allResults.count > pageSize
            currentPage = 1
        }

        logger.debug("[Search] Found \(allResults.count) total results, showing first \(min(allResults.count, self.pageSize))")
        return allResults
    }

    private func searchNames(searchTerm: String) throws -> [SearchResultItem] {
        let tokens = searchTerm.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: buildSimplePredicate(tokens: tokens),
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let items = try modelContext.fetch(descriptor)
        logger.debug("[Search] Found \(items.count) items for name search")

        return try createSearchResultsFromItems(items, matchType: "name")
    }

    private func buildSimplePredicate(tokens: [String]) -> Predicate<CatalogItemModel> {
        if tokens.count == 1 {
            let token = tokens[0]
            return #Predicate { item in
                !item.isDeleted && item.name != nil &&
                (item.name?.localizedStandardContains(token) ?? false)
            }
        } else if tokens.count == 2 {
            let token1 = tokens[0]
            let token2 = tokens[1]
            return #Predicate { item in
                !item.isDeleted && item.name != nil &&
                (item.name?.localizedStandardContains(token1) ?? false) &&
                (item.name?.localizedStandardContains(token2) ?? false)
            }
        } else {
            // For 3+ tokens, use first token in DB query
            let token = tokens[0]
            return #Predicate { item in
                !item.isDeleted && item.name != nil &&
                (item.name?.localizedStandardContains(token) ?? false)
            }
        }
    }

    private func searchBarcodes(searchTerm: String) throws -> [SearchResultItem] {
        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.item != nil &&
                ((variation.sku?.localizedStandardContains(searchTerm) ?? false) || variation.upc == searchTerm)
            }
        )

        let variations = try modelContext.fetch(descriptor)
        logger.debug("[Search] Found \(variations.count) variations for barcode search")

        return variations.compactMap { variation in
            guard let item = variation.item, !item.isDeleted else { return nil }
            return try? createSearchResultFromItemAndVariation(item, variation, matchType: "barcode")
        }
    }

    // SIMPLE: Create SearchResultItems from items
    private func createSearchResultsFromItems(_ items: [CatalogItemModel], matchType: String) throws -> [SearchResultItem] {
        var results: [SearchResultItem] = []

        for item in items {
            let variation = item.variations?.first { !$0.isDeleted }

            let searchResult = SearchResultItem(
                id: item.id,
                name: item.name,
                sku: variation?.sku,
                price: variation?.priceInDollars,
                barcode: variation?.upc,
                reportingCategoryId: item.reportingCategoryId,
                categoryName: item.categoryName ?? item.reportingCategoryName,
                variationName: variation?.name,
                images: item.images?.map { $0.toCatalogImage() },
                matchType: matchType,
                matchContext: item.name,
                isFromCaseUpc: false,
                caseUpcData: nil,
                hasTax: (item.taxes?.count ?? 0) > 0
            )

            results.append(searchResult)
        }

        return results
    }

    // SIMPLE: Create SearchResultItem from item and specific variation
    private func createSearchResultFromItemAndVariation(_ item: CatalogItemModel, _ variation: ItemVariationModel, matchType: String) throws -> SearchResultItem {
        return SearchResultItem(
            id: item.id,
            name: item.name,
            sku: variation.sku,
            price: variation.priceInDollars,
            barcode: variation.upc,
            reportingCategoryId: item.reportingCategoryId,
            categoryName: item.categoryName ?? item.reportingCategoryName,
            variationName: variation.name,
            images: item.images?.map { $0.toCatalogImage() },
            matchType: matchType,
            matchContext: matchType == "upc" ? variation.upc : variation.sku,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: (item.taxes?.count ?? 0) > 0
        )
    }

    // MARK: - Legacy Methods (kept for compatibility)
    
    private func searchCaseUpc(searchTerm: String) async throws -> [SearchResultItem] {
        logger.debug("[Search] Searching for case UPC: \(searchTerm)")
        
        // Search in team data for case UPC matches
        let descriptor = FetchDescriptor<TeamDataModel>(
            predicate: #Predicate { teamData in
                teamData.caseUpc == searchTerm && !teamData.discontinued
            }
        )
        
        let teamDataResults = try modelContext.fetch(descriptor)
        
        var results: [SearchResultItem] = []
        
        for teamData in teamDataResults {
            // Get the associated catalog item
            if let item = teamData.catalogItem, !item.isDeleted {
                let variation = item.variations?.first { !$0.isDeleted }
                
                let searchResult = SearchResultItem(
                    id: item.id,
                    name: item.name,
                    sku: variation?.sku,
                    price: teamData.caseCost,
                    barcode: teamData.caseUpc,
                    reportingCategoryId: item.reportingCategoryId,
                    categoryName: item.categoryName ?? item.reportingCategoryName,
                    variationName: variation?.name,
                    images: item.images?.map { $0.toCatalogImage() },
                    matchType: "case_upc",
                    matchContext: teamData.caseUpc,
                    isFromCaseUpc: true,
                    caseUpcData: CaseUpcData(
                        caseUpc: teamData.caseUpc ?? "",
                        caseCost: teamData.caseCost ?? 0.0,
                        caseQuantity: teamData.caseQuantity ?? 1,
                        vendor: teamData.vendor,
                        discontinued: teamData.discontinued,
                        notes: teamData.notes != nil ? [TeamNote(
                            id: UUID().uuidString,
                            content: teamData.notes!,
                            isComplete: false,
                            authorId: teamData.owner ?? "system",
                            authorName: teamData.owner ?? "System",
                            createdAt: ISO8601DateFormatter().string(from: teamData.createdAt),
                            updatedAt: ISO8601DateFormatter().string(from: teamData.updatedAt)
                        )] : nil
                    ),
                    hasTax: false
                )
                
                results.append(searchResult)
            }
        }
        
        logger.debug("[Search] Found \(results.count) case UPC matches")
        return results
    }
    
    // MARK: - Targeted Item Updates
    
    func updateItemInSearchResults(itemId: String) {
        logger.debug("[Search] Updating item in search results: \(itemId)")
        
        guard let index = searchResults.firstIndex(where: { $0.id == itemId }) else {
            logger.debug("[Search] Item not in current results, skipping update")
            return
        }
        
        // Fetch updated item from SwiftData
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == itemId && !$0.isDeleted }
        )
        
        do {
            if let item = try modelContext.fetch(descriptor).first {
                let existingResult = searchResults[index]
                let variation = item.variations?.first { !$0.isDeleted }
                
                // Create updated search result preserving match context
                let updatedResult = SearchResultItem(
                    id: item.id,
                    name: item.name,
                    sku: variation?.sku,
                    price: variation?.priceInDollars,
                    barcode: variation?.upc,
                    reportingCategoryId: item.reportingCategoryId,
                    categoryName: item.categoryName ?? item.reportingCategoryName,
                    variationName: variation?.name,
                    images: item.images?.map { $0.toCatalogImage() },
                    matchType: existingResult.matchType,
                    matchContext: existingResult.matchContext,
                    isFromCaseUpc: existingResult.isFromCaseUpc,
                    caseUpcData: existingResult.caseUpcData,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )
                
                searchResults[index] = updatedResult
                logger.debug("[Search] Successfully updated item \(itemId)")
            }
        } catch {
            logger.error("[Search] Failed to fetch updated item: \(error)")
        }
    }
    
    func removeItemFromSearchResults(itemId: String) {
        searchResults.removeAll { $0.id == itemId }
    }
    
    /// Checks if a newly created item should appear in current search results
    func itemMatchesCurrentSearch(itemId: String) -> Bool {
        guard let currentTerm = currentSearchTerm,
              !currentTerm.isEmpty else {
            return false
        }
        
        // Fetch the new item to check if it matches current search criteria
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: #Predicate { $0.id == itemId && !$0.isDeleted }
        )
        
        do {
            if let newItem = try modelContext.fetch(descriptor).first {
                let searchTerm = currentTerm.lowercased()
                
                if let name = newItem.name?.lowercased(), name.contains(searchTerm) { return true }
                if let categoryName = newItem.categoryName?.lowercased(), categoryName.contains(searchTerm) { return true }
                if let reportingCategoryName = newItem.reportingCategoryName?.lowercased(), reportingCategoryName.contains(searchTerm) { return true }
                
                // Check variations for SKU/UPC matches
                if let variations = newItem.variations {
                    for variation in variations where !variation.isDeleted {
                        if let sku = variation.sku?.lowercased(), sku.contains(searchTerm) { return true }
                        if variation.upc == currentTerm { return true }
                    }
                }
            }
        } catch {
            logger.error("[Search] Failed to check item match: \(error)")
        }
        
        return false
    }
    
    // MARK: - HID Scanner Optimized Search
    
    /// Optimized search for AppLevelHIDScanner - bypasses fuzzy search for exact barcode lookups
    /// 10x faster than fuzzy search by doing direct SwiftData queries with no tokenization/scoring
    func performAppLevelHIDScannerSearch(barcode: String) async -> [SearchResultItem] {
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedBarcode.isEmpty else {
            await MainActor.run { clearSearch() }
            return []
        }
        
        // Set search state for UI consistency
        await MainActor.run {
            isSearching = true
            searchError = nil
            lastSearchTerm = trimmedBarcode
            currentSearchTerm = trimmedBarcode
        }
        
        logger.debug("[Search] AppLevelHIDScanner direct search for barcode: '\(trimmedBarcode)'")
        
        do {
            var results: [SearchResultItem] = []
            
            // 1. Direct UPC exact match (most common case)
            let upcResults = try await searchExactUPC(barcode: trimmedBarcode)
            results.append(contentsOf: upcResults)
            
            // 2. If no UPC match, try exact SKU match  
            if results.isEmpty {
                let skuResults = try await searchExactSKU(sku: trimmedBarcode)
                results.append(contentsOf: skuResults)
            }
            
            // 3. Check case UPC (for completeness)
            if trimmedBarcode.allSatisfy({ $0.isNumber }) {
                let caseUpcResults = try await searchCaseUpc(searchTerm: trimmedBarcode)
                results.append(contentsOf: caseUpcResults)
            }
            
            // 4. Fallback to fuzzy search only if no exact matches (edge cases)
            if results.isEmpty {
                logger.debug("[Search] No exact matches found, falling back to fuzzy search")
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                results = await performSearch(searchTerm: trimmedBarcode, filters: filters)
                return results // performSearch handles UI state updates
            }
            
            // Update UI with direct search results
            await MainActor.run {
                searchResults = results
                totalResultsCount = results.count
                isSearching = false
            }
            
            logger.debug("[Search] AppLevelHIDScanner found \(results.count) direct results")
            return results
            
        } catch {
            logger.error("[Search] AppLevelHIDScanner search failed: \(error)")
            
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
                searchResults = []
            }
            
            return []
        }
    }
    
    // MARK: - Direct Search Helpers
    
    private func searchExactUPC(barcode: String) async throws -> [SearchResultItem] {
        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.upc == barcode
            }
        )
        
        let variations = try modelContext.fetch(descriptor)
        
        var results: [SearchResultItem] = []
        for variation in variations {
            if let item = variation.item, !item.isDeleted {
                let searchResult = SearchResultItem(
                    id: item.id,
                    name: item.name,
                    sku: variation.sku,
                    price: variation.priceInDollars,
                    barcode: variation.upc,
                    reportingCategoryId: item.reportingCategoryId,
                    categoryName: item.categoryName ?? item.reportingCategoryName,
                    variationName: variation.name,
                    images: item.images?.map { $0.toCatalogImage() },
                    matchType: "upc",
                    matchContext: barcode,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )
                results.append(searchResult)
            }
        }
        
        return results
    }
    
    private func searchExactSKU(sku: String) async throws -> [SearchResultItem] {
        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.sku == sku
            }
        )
        
        let variations = try modelContext.fetch(descriptor)
        
        var results: [SearchResultItem] = []
        for variation in variations {
            if let item = variation.item, !item.isDeleted {
                let searchResult = SearchResultItem(
                    id: item.id,
                    name: item.name,
                    sku: variation.sku,
                    price: variation.priceInDollars,
                    barcode: variation.upc,
                    reportingCategoryId: item.reportingCategoryId,
                    categoryName: item.categoryName ?? item.reportingCategoryName,
                    variationName: variation.name,
                    images: item.images?.map { $0.toCatalogImage() },
                    matchType: "sku",
                    matchContext: sku,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )
                results.append(searchResult)
            }
        }
        
        return results
    }
    
    // MARK: - Debouncing and Utilities
    
    func performSearchWithDebounce(searchTerm: String, filters: SearchFilters) {
        searchTask?.cancel()
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
        logger.debug("[Search] Search cleared")
    }
    
    private func setupSearchDebouncing() {
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] (searchTerm, filters) in
                guard let self = self else { return }

                // Cancel any existing search task
                self.searchTask?.cancel()

                // Start new search immediately after debounce (no extra delays)
                self.searchTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self, !Task.isCancelled else { return }
                    _ = await self.performSearch(searchTerm: searchTerm, filters: filters)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Pagination Support

    func loadMoreResults() {
        guard hasMoreResults, !isSearching else { return }

        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, allSearchResults.count)

        guard startIndex < allSearchResults.count else { return }

        let nextPage = Array(allSearchResults[startIndex..<endIndex])
        searchResults.append(contentsOf: nextPage)

        currentPage += 1
        hasMoreResults = endIndex < allSearchResults.count

        logger.debug("[Search] Loaded page \(self.currentPage), showing \(self.searchResults.count) of \(self.allSearchResults.count) results")
    }

    private func combineResults(catalogResults: [SearchResultItem], caseUpcResults: [SearchResultItem]) -> [SearchResultItem] {
        var seenIds = Set<String>()
        var combined: [SearchResultItem] = []

        // Add catalog results first (already sorted by relevance)
        for result in catalogResults {
            if seenIds.insert(result.id).inserted {
                combined.append(result)
            }
        }

        // Add case UPC results
        for result in caseUpcResults {
            if seenIds.insert(result.id).inserted {
                combined.append(result)
            }
        }

        return combined
    }
}