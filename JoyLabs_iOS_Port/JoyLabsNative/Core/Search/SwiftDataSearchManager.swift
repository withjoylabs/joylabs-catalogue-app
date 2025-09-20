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
    
    // Scoring constants (from original fuzzy search)
    private struct Scores {
        static let exactWordMatch: Double = 100.0
        static let prefixMatch: Double = 80.0
        static let exactSkuMatch: Double = 60.0
        static let upcMatch: Double = 60.0
        static let multiTokenBonus: Double = 2.0
        static let allTokensMatchBonus: Double = 50.0
        static let minScoreThreshold: Double = 20.0
    }
    
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

        let searchTokens = tokenizeSearchTerm(searchTerm)
        logger.debug("[Search] Tokenized '\(searchTerm)' into: \(searchTokens)")

        var allResults: [SearchResultItem] = []
        var seenIds = Set<String>()

        // 1. Search item names with database filtering (word-start matching)
        if filters.name {
            let nameResults = try searchItemNamesByTokens(tokens: searchTokens)
            for result in nameResults {
                if seenIds.insert(result.id).inserted {
                    allResults.append(result)
                }
            }
        }

        // 2. Search exact SKU/UPC for single-word queries only
        if filters.barcode && !searchTerm.contains(" ") {
            let barcodeResults = try searchExactBarcodes(term: searchTerm)
            for result in barcodeResults {
                if seenIds.insert(result.id).inserted {
                    allResults.append(result)
                }
            }
        }

        // 3. Apply relevance scoring and sort
        let scoredResults = scoreSearchResults(allResults, searchTokens: searchTokens, originalTerm: searchTerm)
        let sortedResults = scoredResults.sorted { $0.score > $1.score }

        logger.debug("[Search] Scored and sorted \(sortedResults.count) results")
        return sortedResults.map { $0.item }
    }

    private func tokenizeSearchTerm(_ term: String) -> [String] {
        let lowercased = term.lowercased()
        let tokens = lowercased.components(separatedBy: .whitespacesAndNewlines)

        return tokens.compactMap { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            // Keep tokens >= 2 chars or single numbers
            if trimmed.count >= 2 || (trimmed.count == 1 && trimmed.first?.isNumber == true) {
                return trimmed
            }
            return nil
        }.filter { !$0.isEmpty }
    }

    private func searchItemNamesByTokens(tokens: [String]) throws -> [SearchResultItem] {
        // Build SwiftData predicate that checks if ALL tokens match word starts
        // This runs in the database, not memory!

        var results: [SearchResultItem] = []

        // For each token, find items where that token appears as word start
        for token in tokens {
            let descriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    !item.isDeleted &&
                    item.name != nil &&
                    (item.name?.localizedStandardContains(token) ?? false)
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            let items = try modelContext.fetch(descriptor)

            // Filter to items where token appears as word start (post-filter for precision)
            let filteredItems = items.filter { item in
                guard let name = item.name?.lowercased() else { return false }
                let words = name.components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
                return words.contains { word in
                    word.hasPrefix(token.lowercased())
                }
            }

            logger.debug("[Search] Token '\(token)' matched \(filteredItems.count) items")

            // Convert to SearchResultItems
            for item in filteredItems {
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
                    matchType: "name",
                    matchContext: item.name,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )

                results.append(searchResult)
            }
        }

        // Now filter to items that match ALL tokens (intersection)
        let itemCounts = Dictionary(grouping: results, by: { $0.id })
            .mapValues { $0.count }

        // Only keep items that appeared for ALL search tokens
        let finalResults = results.filter { result in
            itemCounts[result.id] == tokens.count
        }

        // Remove duplicates
        var seenIds = Set<String>()
        return finalResults.filter { result in
            seenIds.insert(result.id).inserted
        }
    }

    private func searchExactBarcodes(term: String) throws -> [SearchResultItem] {
        var results: [SearchResultItem] = []

        // Exact UPC match
        let upcDescriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.upc == term
            }
        )

        let upcVariations = try modelContext.fetch(upcDescriptor)
        for variation in upcVariations {
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
                    matchContext: term,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )
                results.append(searchResult)
            }
        }

        // Exact SKU match
        let skuDescriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.sku == term
            }
        )

        let skuVariations = try modelContext.fetch(skuDescriptor)
        for variation in skuVariations {
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
                    matchContext: term,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: (item.taxes?.count ?? 0) > 0
                )
                results.append(searchResult)
            }
        }

        return results
    }

    private func scoreSearchResults(
        _ results: [SearchResultItem],
        searchTokens: [String],
        originalTerm: String
    ) -> [(item: SearchResultItem, score: Double)] {

        return results.compactMap { result in
            let score = calculateResultScore(result, searchTokens: searchTokens, originalTerm: originalTerm)
            if score >= Scores.minScoreThreshold {
                return (item: result, score: score)
            }
            return nil
        }
    }

    private func calculateResultScore(
        _ result: SearchResultItem,
        searchTokens: [String],
        originalTerm: String
    ) -> Double {
        var totalScore: Double = 0.0

        // Exact UPC/SKU matches get highest scores
        if result.matchType == "upc" && result.barcode == originalTerm {
            totalScore += Scores.upcMatch
        }
        if result.matchType == "sku" && result.sku == originalTerm {
            totalScore += Scores.exactSkuMatch
        }

        // Fuzzy text scoring for name matches
        if result.matchType == "name" {
            let nameScore = calculateNameMatchScore(result, searchTokens: searchTokens)
            totalScore += nameScore
        }

        return totalScore
    }

    private func calculateNameMatchScore(
        _ result: SearchResultItem,
        searchTokens: [String]
    ) -> Double {
        guard let name = result.name else { return 0.0 }

        let nameWords = name.lowercased()
            .components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }

        var totalScore: Double = 0.0
        var matchedTokens = 0
        var matchPositions: [Int] = []

        for searchToken in searchTokens {
            var bestScore: Double = 0.0
            var bestPosition: Int = -1

            for (index, nameWord) in nameWords.enumerated() {
                var score: Double = 0.0

                if nameWord == searchToken {
                    score = Scores.exactWordMatch
                } else if nameWord.hasPrefix(searchToken) {
                    score = Scores.prefixMatch
                }

                if score > 0 {
                    // Position bonus - earlier matches score higher
                    let positionBonus = 1.0 - (Double(index) * 0.1)
                    score *= max(positionBonus, 0.5)

                    if score > bestScore {
                        bestScore = score
                        bestPosition = index
                    }
                }
            }

            if bestScore > 0 {
                totalScore += bestScore
                matchedTokens += 1
                matchPositions.append(bestPosition)
            }
        }

        // Sequential order bonus
        if matchPositions.count > 1 {
            let isSequential = zip(matchPositions.dropLast(), matchPositions.dropFirst())
                .allSatisfy { $0 < $1 }
            if isSequential {
                totalScore *= 3.0 // Big bonus for order matching
            }
        }

        // Multi-token bonuses
        if matchedTokens > 1 {
            totalScore *= Scores.multiTokenBonus
        }
        if matchedTokens == searchTokens.count && searchTokens.count > 1 {
            totalScore += Scores.allTokensMatchBonus
        }

        return totalScore
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