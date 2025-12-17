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

    // MARK: - Scoring Infrastructure

    /// Scored search result with relevance ranking
    private struct ScoredSearchResult {
        let item: SearchResultItem
        let score: Int
        let matchDetails: String
    }
    
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
        let tokens = filterTokens(cleanTerm)

        logger.info("[Search] 🔍 Search term: '\(cleanTerm)' | Tokens: \(tokens)")

        var scoredResults: [ScoredSearchResult] = []

        // Search names
        if filters.name {
            let nameResults = try searchNames(searchTerm: cleanTerm, tokens: tokens)
            scoredResults.append(contentsOf: nameResults)
        }

        // Search barcodes
        if filters.barcode {
            let barcodeResults = try searchBarcodes(searchTerm: cleanTerm, tokens: tokens)
            scoredResults.append(contentsOf: barcodeResults)
        }

        // Remove duplicates (keep highest scoring version)
        var seenIds = [String: ScoredSearchResult]()
        for result in scoredResults {
            if let existing = seenIds[result.item.id] {
                if result.score > existing.score {
                    seenIds[result.item.id] = result
                }
            } else {
                seenIds[result.item.id] = result
            }
        }

        // Sort by score (highest first)
        let rankedResults = seenIds.values.sorted { $0.score > $1.score }

        // Log final ranking
        logger.info("[Search] 📊 Final ranking (\(rankedResults.count) results):")
        for (index, result) in rankedResults.prefix(10).enumerated() {
            logger.info("[Search]   \(index+1). '\(result.item.name ?? "nil")' - Score: \(result.score) - \(result.matchDetails)")
        }
        if rankedResults.count > 10 {
            logger.info("[Search]   ... and \(rankedResults.count - 10) more")
        }

        // Extract items for pagination
        let allResults = rankedResults.map { $0.item }

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

    private func searchNames(searchTerm: String, tokens: [String]) throws -> [ScoredSearchResult] {
        let descriptor = FetchDescriptor<CatalogItemModel>(
            predicate: buildSimplePredicate(tokens: tokens)
            // NO SORT - we'll sort by relevance score instead
        )

        let items = try modelContext.fetch(descriptor)
        logger.debug("[Search] DB returned \(items.count) items for name search")

        // Post-filter results to ensure word order and prefix matching
        let filteredItems = items.filter { item in
            guard let name = item.name?.lowercased() else { return false }
            return matchesWithWordOrder(name: name, tokens: tokens)
        }

        logger.debug("[Search] After word order filtering: \(filteredItems.count) items")

        // Convert to search results and calculate scores
        let searchResults = try createSearchResultsFromItems(filteredItems, matchType: "name")
        let scoredResults = searchResults.map { item in
            calculateMatchScore(item: item, searchTerm: searchTerm, tokens: tokens, matchType: "name")
        }

        return scoredResults
    }

    // MARK: - Token Filtering and Validation Helpers

    /// Filter tokens to ignore single letters but KEEP numbers (industry standard)
    private func filterTokens(_ searchTerm: String) -> [String] {
        return searchTerm.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { token in
                // Keep if: length > 1 OR is a number (even single digit like "8")
                token.count > 1 || token.allSatisfy { $0.isNumber }
            }
    }

    /// Check if name matches all tokens in order with prefix matching
    private func matchesWithWordOrder(name: String, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }

        var searchStartIndex = name.startIndex

        for token in tokens {
            // Find token as word prefix in remaining string
            guard let range = name[searchStartIndex...].range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: token))",
                options: [.regularExpression, .caseInsensitive]
            ) else {
                return false  // Token not found or not at word boundary
            }

            // Move search position past this match
            searchStartIndex = range.upperBound
        }

        return true  // All tokens found in order
    }

    // MARK: - Match Scoring

    /// Calculate token proximity - how close matched tokens are to each other
    private func calculateTokenProximity(name: String, tokens: [String]) -> Int {
        guard tokens.count > 1 else { return 0 }

        let words = name.lowercased().components(separatedBy: .whitespaces)
        var matchedIndices: [Int] = []

        for (index, word) in words.enumerated() {
            for token in tokens {
                if word.hasPrefix(token) || word.contains(token) {
                    matchedIndices.append(index)
                    break
                }
            }
        }

        guard matchedIndices.count > 1 else { return 0 }

        // Calculate distance between first and last matched token
        let distance = matchedIndices.last! - matchedIndices.first!

        // Bonus based on proximity
        switch distance {
        case 0: return 0  // Should not happen
        case 1: return 100 // Adjacent (best)
        case 2: return 50  // 1 word apart
        default: return 0  // 2+ words apart
        }
    }

    /// Calculate match density - percentage of words that matched
    private func calculateMatchDensity(name: String, tokens: [String]) -> Int {
        let words = name.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0 }

        var matchedCount = 0
        for word in words {
            for token in tokens {
                if word.hasPrefix(token) || word.contains(token) {
                    matchedCount += 1
                    break
                }
            }
        }

        let density = Double(matchedCount) / Double(words.count)

        // Bonus based on density
        switch density {
        case 0.8...1.0: return 50  // 80-100% match
        case 0.6..<0.8: return 40  // 60-80% match
        case 0.4..<0.6: return 30  // 40-60% match
        case 0.2..<0.4: return 20  // 20-40% match
        default: return 10         // <20% match
        }
    }

    /// Calculate relevance score for search result with detailed logging
    private func calculateMatchScore(
        item: SearchResultItem,
        searchTerm: String,
        tokens: [String],
        matchType: String
    ) -> ScoredSearchResult {
        var score = 0
        var matchDetails: [String] = []

        let itemName = (item.name ?? "").lowercased()
        let searchLower = searchTerm.lowercased()

        // Exact name match (highest priority)
        if itemName == searchLower {
            score += 1000
            matchDetails.append("exact_name")
        }
        // Name starts with search term (very high priority)
        else if itemName.hasPrefix(searchLower) {
            score += 500
            matchDetails.append("name_prefix")
        }
        // All tokens match in order at word boundaries (high priority)
        else if matchesWithWordOrder(name: itemName, tokens: tokens) {
            score += 300
            matchDetails.append("word_order_match")

            // Bonus: First word starts with first token
            if let firstToken = tokens.first, itemName.hasPrefix(firstToken) {
                score += 100
                matchDetails.append("first_word_prefix")
            }

            // NEW: Proximity bonus - how close are matched tokens?
            let proximityBonus = calculateTokenProximity(name: itemName, tokens: tokens)
            if proximityBonus > 0 {
                score += proximityBonus
                matchDetails.append("proximity(\(proximityBonus))")
            }

            // NEW: Density bonus - what % of words matched?
            let densityBonus = calculateMatchDensity(name: itemName, tokens: tokens)
            if densityBonus > 0 {
                score += densityBonus
                matchDetails.append("density(\(densityBonus))")
            }
        }

        // SKU exact match
        if let sku = item.sku?.lowercased(), sku == searchLower {
            score += 800
            matchDetails.append("exact_sku")
        }
        // SKU starts with search
        else if let sku = item.sku?.lowercased(), sku.hasPrefix(searchLower) {
            score += 400
            matchDetails.append("sku_prefix")
        }
        // SKU contains search
        else if let sku = item.sku?.lowercased(), sku.contains(searchLower) {
            score += 200
            matchDetails.append("sku_contains")
        }

        // UPC exact match (highest for barcodes)
        if let upc = item.barcode?.lowercased(), upc == searchLower {
            score += 900
            matchDetails.append("exact_upc(900)")
        }
        // UPC suffix match (last digits - important for check digits and retail references)
        else if let upc = item.barcode?.lowercased(), upc.hasSuffix(searchLower) {
            score += 400
            matchDetails.append("upc_suffix(400)")
        }
        // UPC prefix match (starts with - manufacturer codes)
        else if let upc = item.barcode?.lowercased(), upc.hasPrefix(searchLower) {
            score += 300
            matchDetails.append("upc_prefix(300)")
        }
        // UPC contains search (middle of barcode - least specific)
        else if let upc = item.barcode?.lowercased(), upc.contains(searchLower) {
            score += 200
            matchDetails.append("upc_contains(200)")
        }

        // Penalty for longer names (prefer shorter, more specific matches)
        let nameLength = itemName.count
        if nameLength > 50 {
            score -= 10
            matchDetails.append("long_penalty(-10)")
        } else if nameLength > 30 {
            score -= 5
            matchDetails.append("med_penalty(-5)")
        }

        // Ensure minimum score of 1 for valid matches
        if score == 0 && matchType == "name" {
            score = 1
            matchDetails.append("basic_match")
        }

        let details = matchDetails.joined(separator: " + ")
        logger.info("[Search] Score: \(score) | '\(item.name ?? "nil")' | \(details)")

        return ScoredSearchResult(item: item, score: score, matchDetails: details)
    }

    private func buildSimplePredicate(tokens: [String]) -> Predicate<CatalogItemModel> {
        // Handle empty tokens
        guard !tokens.isEmpty else {
            return #Predicate { item in
                !item.isDeleted && item.name != nil
            }
        }

        // SIMPLIFIED: Only use first token for database-level filtering
        // SwiftData predicates have strict complexity limits - keep it simple
        // Post-filtering in matchesWithWordOrder() handles:
        // - All tokens (not just first)
        // - Word order validation
        // - Prefix matching with word boundaries
        let token = tokens[0]
        return #Predicate { item in
            !item.isDeleted && item.name != nil &&
            (item.name?.localizedStandardContains(token) ?? false)
        }
    }

    private func searchBarcodes(searchTerm: String, tokens: [String]) throws -> [ScoredSearchResult] {
        // For numbers: match anywhere in SKU/UPC (prefix, suffix, contains)
        // For text: match anywhere in SKU
        // For multi-token searches: ensure all tokens appear (order matters for readability)

        logger.debug("[Search] Barcode search with tokens: \(tokens)")

        let descriptor = FetchDescriptor<ItemVariationModel>(
            predicate: #Predicate { variation in
                !variation.isDeleted && variation.item != nil &&
                ((variation.sku?.localizedStandardContains(searchTerm) ?? false) ||
                 (variation.upc?.localizedStandardContains(searchTerm) ?? false))
            }
        )

        let variations = try modelContext.fetch(descriptor)
        logger.debug("[Search] DB returned \(variations.count) variations for barcode search")

        // Post-filter for token matching (if multiple tokens)
        let filteredVariations: [ItemVariationModel]
        if tokens.count > 1 {
            filteredVariations = variations.filter { variation in
                let sku = variation.sku?.lowercased() ?? ""
                let upc = variation.upc?.lowercased() ?? ""

                // Check if all tokens appear in SKU or UPC
                return tokens.allSatisfy { token in
                    sku.contains(token) || upc.contains(token)
                }
            }
            logger.debug("[Search] After token filtering: \(filteredVariations.count) variations")
        } else {
            filteredVariations = variations
        }

        // Convert to search results
        let searchResults = filteredVariations.compactMap { variation -> SearchResultItem? in
            guard let item = variation.item, !item.isDeleted else { return nil }
            return try? createSearchResultFromItemAndVariation(item, variation, matchType: "barcode")
        }

        // Calculate scores
        let scoredResults = searchResults.map { item in
            calculateMatchScore(item: item, searchTerm: searchTerm, tokens: tokens, matchType: "barcode")
        }

        return scoredResults
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
                images: buildCatalogImages(from: item.imageIds),
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
            images: buildCatalogImages(from: item.imageIds),
            matchType: matchType,
            matchContext: matchType == "upc" ? variation.upc : variation.sku,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: (item.taxes?.count ?? 0) > 0
        )
    }

    // SIMPLE: Convert imageIds to CatalogImage array using ImageURLCache
    private func buildCatalogImages(from imageIds: [String]?) -> [CatalogImage]? {
        guard let imageIds = imageIds, !imageIds.isEmpty else { return nil }

        let images = imageIds.compactMap { imageId -> CatalogImage? in
            guard let url = ImageURLCache.shared.getURL(forImageId: imageId) else { return nil }

            return CatalogImage(
                id: imageId,
                type: "IMAGE",
                updatedAt: "",
                version: 0,
                isDeleted: false,
                presentAtAllLocations: true,
                imageData: ImageData(name: nil, url: url, caption: nil, photoStudioOrderId: nil)
            )
        }

        return images.isEmpty ? nil : images
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
                    images: buildCatalogImages(from: item.imageIds),
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
                    images: buildCatalogImages(from: item.imageIds),
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
                    images: buildCatalogImages(from: item.imageIds),
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
                    images: buildCatalogImages(from: item.imageIds),
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