import Foundation
import SwiftData
import os.log

/// SwiftData-based fuzzy search maintaining IDENTICAL functionality to SQLite version
/// Uses tokenized prefix matching with sophisticated scoring - EXACT port, no simplifications
class SwiftDataFuzzySearch {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SwiftDataFuzzySearch")
    private let modelContext: ModelContext
    
    // MARK: - Scoring Constants (IDENTICAL to original)
    private struct Scores {
        static let exactWordMatch: Double = 100.0
        static let prefixMatch: Double = 80.0
        static let exactSkuMatch: Double = 60.0
        static let prefixSkuMatch: Double = 40.0
        static let upcMatch: Double = 60.0
        static let multiTokenBonus: Double = 2.0
        static let allTokensMatchBonus: Double = 50.0
    }
    
    private struct Config {
        static let maxResults: Int = 200
        static let minTokenLength: Int = 2
        static let minScoreThreshold: Double = 20.0
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Main Search Function (EXACT port from original)
    
    func performFuzzySearch(
        searchTerm: String,
        filters: SearchFilters,
        limit: Int = 50
    ) throws -> [SearchResultWithScore] {
        
        let cleanTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTerm.isEmpty else { return [] }
        
        logger.debug("[SwiftDataFuzzySearch] Starting fuzzy search for: '\(cleanTerm)'")
        
        // Determine search type based on content (IDENTICAL logic)
        let isNumericQuery = cleanTerm.allSatisfy { $0.isNumber }
        
        let candidates: [CandidateItem]
        
        if isNumericQuery {
            // Numeric query: search UPC/barcode fields only
            candidates = try searchNumericFields(term: cleanTerm, filters: filters)
        } else {
            // Text query: search name, category, and SKU fields
            candidates = try searchTextFields(term: cleanTerm, filters: filters)
        }
        
        logger.debug("[SwiftDataFuzzySearch] Found \(candidates.count) candidates")
        
        // Score and rank all candidates (IDENTICAL algorithm)
        let scoredResults = scoreAndRankCandidates(
            candidates: candidates,
            searchTerm: cleanTerm,
            isNumericQuery: isNumericQuery
        )
        
        // Apply score threshold and limit (IDENTICAL logic)
        let filteredResults = scoredResults
            .filter { $0.score >= Config.minScoreThreshold }
            .prefix(min(limit, Config.maxResults))
        
        logger.info("[SwiftDataFuzzySearch] Returning \(filteredResults.count) scored results")
        return Array(filteredResults)
    }
    
    // MARK: - Numeric Search (EXACT port)
    
    private func searchNumericFields(term: String, filters: SearchFilters) throws -> [CandidateItem] {
        logger.debug("[SwiftDataFuzzySearch] Performing numeric search for: '\(term)'")
        
        var candidates: [CandidateItem] = []
        
        if filters.barcode {
            // Search UPC exact match
            let upcDescriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    !variation.isDeleted && variation.upc == term
                }
            )
            
            let upcVariations = try modelContext.fetch(upcDescriptor)
            
            for variation in upcVariations {
                if let item = variation.item, !item.isDeleted {
                    let candidate = CandidateItem(
                        id: item.id,
                        name: item.name ?? "",
                        categoryName: item.categoryName ?? "",
                        sku: variation.sku ?? "",
                        upc: variation.upc ?? "",
                        matchField: "upc",
                        matchValue: term
                    )
                    candidates.append(candidate)
                }
            }
            
            // Search SKU containing term
            let skuDescriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    !variation.isDeleted && 
                    variation.sku != nil && 
                    variation.sku?.localizedStandardContains(term) == true
                }
            )
            
            let skuVariations = try modelContext.fetch(skuDescriptor)
            
            for variation in skuVariations {
                if let item = variation.item, !item.isDeleted {
                    let candidate = CandidateItem(
                        id: item.id,
                        name: item.name ?? "",
                        categoryName: item.categoryName ?? "",
                        sku: variation.sku ?? "",
                        upc: variation.upc ?? "",
                        matchField: "sku",
                        matchValue: variation.sku ?? ""
                    )
                    candidates.append(candidate)
                }
            }
        }
        
        logger.debug("[SwiftDataFuzzySearch] Numeric search found \(candidates.count) candidates")
        return candidates
    }
    
    // MARK: - Text Search (EXACT port)
    
    private func searchTextFields(term: String, filters: SearchFilters) throws -> [CandidateItem] {
        logger.debug("[SwiftDataFuzzySearch] Performing text search for: '\(term)'")
        
        var candidates: [CandidateItem] = []
        
        // Search item names (IDENTICAL to original logic)
        if filters.name {
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    !item.isDeleted && 
                    item.name != nil &&
                    item.name?.localizedStandardContains(term) == true
                }
            )
            
            let items = try modelContext.fetch(itemDescriptor)
            
            for item in items {
                let candidate = CandidateItem(
                    id: item.id,
                    name: item.name ?? "",
                    categoryName: item.categoryName ?? "",
                    sku: item.variations?.first?.sku ?? "",
                    upc: item.variations?.first?.upc ?? "",
                    matchField: "name",
                    matchValue: item.name ?? ""
                )
                candidates.append(candidate)
            }
        }
        
        // Search categories (IDENTICAL to original logic)
        if filters.category {
            let categoryDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    !item.isDeleted && 
                    ((item.categoryName != nil && item.categoryName?.localizedStandardContains(term) == true) ||
                     (item.reportingCategoryName != nil && item.reportingCategoryName?.localizedStandardContains(term) == true))
                }
            )
            
            let categoryItems = try modelContext.fetch(categoryDescriptor)
            
            for item in categoryItems {
                let matchedCategory = if let categoryName = item.categoryName, categoryName.localizedStandardContains(term) {
                    categoryName
                } else {
                    item.reportingCategoryName ?? ""
                }
                
                let candidate = CandidateItem(
                    id: item.id,
                    name: item.name ?? "",
                    categoryName: item.categoryName ?? "",
                    sku: item.variations?.first?.sku ?? "",
                    upc: item.variations?.first?.upc ?? "",
                    matchField: "category",
                    matchValue: matchedCategory
                )
                candidates.append(candidate)
            }
        }
        
        // Search SKUs (IDENTICAL to original logic)
        if filters.barcode {
            let skuDescriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    !variation.isDeleted && 
                    variation.sku != nil && 
                    variation.sku?.localizedStandardContains(term) == true
                }
            )
            
            let skuVariations = try modelContext.fetch(skuDescriptor)
            
            for variation in skuVariations {
                if let item = variation.item, !item.isDeleted {
                    let candidate = CandidateItem(
                        id: item.id,
                        name: item.name ?? "",
                        categoryName: item.categoryName ?? "",
                        sku: variation.sku ?? "",
                        upc: variation.upc ?? "",
                        matchField: "sku",
                        matchValue: variation.sku ?? ""
                    )
                    candidates.append(candidate)
                }
            }
        }
        
        logger.debug("[SwiftDataFuzzySearch] Text search found \(candidates.count) candidates")
        return candidates
    }
    
    // MARK: - Scoring Algorithm (IDENTICAL to original)
    
    private func scoreAndRankCandidates(
        candidates: [CandidateItem],
        searchTerm: String,
        isNumericQuery: Bool
    ) -> [SearchResultWithScore] {
        
        let searchTokens = tokenizeSearchTerm(searchTerm)
        logger.debug("[SwiftDataFuzzySearch] Search tokens: \(searchTokens)")
        
        var scoredResults: [SearchResultWithScore] = []
        
        for candidate in candidates {
            let score = calculateCandidateScore(
                candidate: candidate,
                searchTokens: searchTokens,
                originalTerm: searchTerm,
                isNumericQuery: isNumericQuery
            )
            
            if score > 0 {
                let searchResult = SearchResultItem(
                    id: candidate.id,
                    name: candidate.name,
                    sku: !candidate.sku.isEmpty ? candidate.sku : nil,
                    price: nil, // Will be enriched later
                    barcode: !candidate.upc.isEmpty ? candidate.upc : nil,
                    reportingCategoryId: nil, // Will be enriched later
                    categoryName: !candidate.categoryName.isEmpty ? candidate.categoryName : nil,
                    variationName: nil, // Will be enriched later
                    images: nil, // Will be enriched later
                    matchType: candidate.matchField,
                    matchContext: candidate.matchValue,
                    isFromCaseUpc: false,
                    caseUpcData: nil,
                    hasTax: false // Will be enriched later
                )
                
                scoredResults.append(SearchResultWithScore(item: searchResult, score: score))
            }
        }
        
        // Sort by score descending (IDENTICAL to original)
        let sortedResults = scoredResults.sorted { $0.score > $1.score }
        
        logger.debug("[SwiftDataFuzzySearch] Scored and ranked \(sortedResults.count) results")
        return sortedResults
    }
    
    // MARK: - Scoring Helpers (IDENTICAL to original)
    
    private func tokenizeSearchTerm(_ term: String) -> [String] {
        return term
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { $0.count >= Config.minTokenLength }
    }
    
    private func calculateCandidateScore(
        candidate: CandidateItem,
        searchTokens: [String],
        originalTerm: String,
        isNumericQuery: Bool
    ) -> Double {
        
        if isNumericQuery {
            return calculateNumericScore(candidate: candidate, searchTerm: originalTerm)
        } else {
            return calculateTextScore(candidate: candidate, searchTokens: searchTokens, originalTerm: originalTerm)
        }
    }
    
    private func calculateNumericScore(candidate: CandidateItem, searchTerm: String) -> Double {
        let lowerTerm = searchTerm.lowercased()
        
        // UPC exact match gets highest score (IDENTICAL logic)
        if candidate.matchField == "upc" && candidate.upc.lowercased() == lowerTerm {
            return Scores.upcMatch
        }
        
        // SKU exact match
        if candidate.matchField == "sku" && candidate.sku.lowercased() == lowerTerm {
            return Scores.exactSkuMatch
        }
        
        // SKU prefix match
        if candidate.matchField == "sku" && candidate.sku.lowercased().hasPrefix(lowerTerm) {
            return Scores.prefixSkuMatch
        }
        
        // SKU contains match (lower score)
        if candidate.matchField == "sku" && candidate.sku.lowercased().contains(lowerTerm) {
            return Scores.prefixSkuMatch * 0.5
        }
        
        return 0.0
    }
    
    private func calculateTextScore(candidate: CandidateItem, searchTokens: [String], originalTerm: String) -> Double {
        var totalScore: Double = 0.0
        var matchedTokens = 0
        
        let candidateTokens = tokenizeSearchTerm(candidate.name + " " + candidate.categoryName + " " + candidate.sku)
        
        for searchToken in searchTokens {
            var tokenScore: Double = 0.0
            
            // Check for matches in candidate tokens (IDENTICAL scoring logic)
            for candidateToken in candidateTokens {
                if candidateToken == searchToken {
                    // Exact word match
                    tokenScore = max(tokenScore, Scores.exactWordMatch)
                    matchedTokens += 1
                } else if candidateToken.hasPrefix(searchToken) {
                    // Prefix match
                    tokenScore = max(tokenScore, Scores.prefixMatch)
                    matchedTokens += 1
                }
            }
            
            totalScore += tokenScore
        }
        
        // Apply bonuses for multiple token matches (IDENTICAL logic)
        if matchedTokens > 1 {
            totalScore *= Scores.multiTokenBonus
        }
        
        // Big bonus if ALL tokens match
        if matchedTokens == searchTokens.count && searchTokens.count > 1 {
            totalScore += Scores.allTokensMatchBonus
        }
        
        return totalScore
    }
}

// MARK: - Supporting Types (IDENTICAL to original)

struct CandidateItem {
    let id: String
    let name: String
    let categoryName: String
    let sku: String
    let upc: String
    let matchField: String
    let matchValue: String
}

struct SearchResultWithScore {
    let item: SearchResultItem
    let score: Double
}