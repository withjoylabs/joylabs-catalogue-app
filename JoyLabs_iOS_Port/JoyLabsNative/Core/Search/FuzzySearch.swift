import Foundation
import SQLite
import os.log

/// Fuzzy search with advanced ranking algorithms
/// Implements Levenshtein distance, TF-IDF scoring, and multi-field weighted relevance  
class FuzzySearch {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "FuzzySearch")
    
    // MARK: - Relevance Weights (tunable)
    private struct FieldWeights {
        static let exactMatch: Double = 100.0
        static let prefixMatch: Double = 85.0    // Increased for better prefix matching
        static let substringMatch: Double = 70.0 // Increased for better substring matching
        static let fuzzyMatch: Double = 50.0     // Increased for better typo tolerance
        static let tokenMatch: Double = 40.0     // Increased for better multi-word search
        
        // Field-specific multipliers - tuned for catalog search
        static let barcode: Double = 2.0    // Highest priority - exact barcode matches are critical
        static let sku: Double = 1.5        // High priority - SKUs are precise identifiers
        static let name: Double = 1.0       // Base weight - most common search
        static let category: Double = 0.8   // Slightly higher - categories are important for browsing
    }
    
    private struct SearchConfig {
        static let maxEditDistance: Int = 3        // Allow more typos for better tolerance
        static let minTokenLength: Int = 2         // Keep minimum token length reasonable
        static let maxResults: Int = 200           // Increased for better search coverage
        static let fuzzyThreshold: Double = 0.2    // Lower threshold to include more fuzzy matches
        static let multiFieldBonus: Double = 0.3  // Bonus for matches across multiple fields
        static let exactMatchBonus: Double = 0.5  // Extra bonus for exact matches
    }
    
    // MARK: - Main Search Function
    
    func performFuzzySearch(
        searchTerm: String,
        in database: Connection,
        filters: SearchFilters,
        limit: Int = 50
    ) throws -> [SearchResultWithScore] {
        
        let cleanTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTerm.isEmpty else { return [] }
        
        logger.debug("[Search] Starting fuzzy search for: '\(cleanTerm)'")
        
        // Tokenize search term
        let tokens = tokenize(cleanTerm)
        logger.debug("[Search] Search tokens: \(tokens)")
        
        // Get candidate items from database
        let candidates = try getCandidateItems(tokens: tokens, database: database, filters: filters)
        logger.debug("[Search] Found \(candidates.count) candidate items")
        
        // Score and rank all candidates
        let scoredResults = scoreAndRankCandidates(
            candidates: candidates,
            searchTerm: cleanTerm,
            tokens: tokens
        )
        
        // Filter by minimum score and limit results
        let filteredResults = scoredResults
            .filter { $0.score >= SearchConfig.fuzzyThreshold }
            .prefix(limit)
        
        logger.debug("[Search] Returning \(filteredResults.count) results after scoring")
        return Array(filteredResults)
    }
    
    // MARK: - Tokenization
    
    private func tokenize(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return text
            .lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= SearchConfig.minTokenLength }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Candidate Retrieval
    
    private func getCandidateItems(
        tokens: [String],
        database: Connection,
        filters: SearchFilters
    ) throws -> [CandidateItem] {
        
        var candidates: [String: CandidateItem] = [:]
        
        // Search by name (if enabled)
        if filters.name {
            let nameResults = try searchByNameFuzzy(tokens: tokens, database: database)
            mergeCandidates(&candidates, newCandidates: nameResults)
        }
        
        // Search by SKU (if enabled)
        if filters.sku {
            let skuResults = try searchBySkuFuzzy(tokens: tokens, database: database)
            mergeCandidates(&candidates, newCandidates: skuResults)
        }
        
        // Search by barcode/UPC (if enabled)
        if filters.barcode {
            let barcodeResults = try searchByBarcodeFuzzy(tokens: tokens, database: database)
            mergeCandidates(&candidates, newCandidates: barcodeResults)
        }
        
        // Category search removed - categories contain thousands of items and are not useful for search
        
        // TODO: Add case UPC search when implemented
        // if filters.barcode {
        //     let caseUpcResults = try searchByCaseUpcFuzzy(tokens: tokens, database: database)
        //     mergeCandidates(&candidates, newCandidates: caseUpcResults)
        // }
        
        return Array(candidates.values)
    }
    
    private func mergeCandidates(_ existing: inout [String: CandidateItem], newCandidates: [CandidateItem]) {
        for candidate in newCandidates {
            if let existingCandidate = existing[candidate.id] {
                // Merge search fields
                existing[candidate.id] = CandidateItem(
                    id: candidate.id,
                    name: candidate.name,
                    sku: candidate.sku ?? existingCandidate.sku,
                    barcode: candidate.barcode ?? existingCandidate.barcode,
                    categoryName: candidate.categoryName ?? existingCandidate.categoryName,
                    categoryId: candidate.categoryId ?? existingCandidate.categoryId,
                    price: candidate.price ?? existingCandidate.price,
                    images: candidate.images ?? existingCandidate.images,
                    hasTax: candidate.hasTax
                )
            } else {
                existing[candidate.id] = candidate
            }
        }
    }
    
    // MARK: - Field-Specific Search Methods
    
    private func searchByNameFuzzy(tokens: [String], database: Connection) throws -> [CandidateItem] {
        var results: [CandidateItem] = []
        
        // Build flexible OR query for name search
        var whereConditions: [String] = []
        var bindValues: [Binding?] = []
        
        for token in tokens {
            // Exact matches
            whereConditions.append("LOWER(name) = ?")
            bindValues.append(token.lowercased())
            
            // Prefix matches  
            whereConditions.append("LOWER(name) LIKE ?")
            bindValues.append("\(token.lowercased())%")
            
            // Substring matches
            whereConditions.append("LOWER(name) LIKE ?")
            bindValues.append("%\(token.lowercased())%")
        }
        
        let query = """
            SELECT DISTINCT ci.id, ci.name, ci.category_id, ci.category_name, ci.reporting_category_name
            FROM catalog_items ci
            WHERE ci.is_deleted = 0 
            AND (\(whereConditions.joined(separator: " OR ")))
            LIMIT \(SearchConfig.maxResults)
        """
        
        let statement = try database.prepare(query)
        for row in try statement.run(bindValues) {
            if let candidate = createCandidateFromItemRow(row) {
                results.append(candidate)
            }
        }
        
        
        return results
    }
    
    private func searchBySkuFuzzy(tokens: [String], database: Connection) throws -> [CandidateItem] {
        var results: [CandidateItem] = []
        
        var whereConditions: [String] = []
        var bindValues: [Binding?] = []
        
        for token in tokens {
            whereConditions.append("LOWER(iv.sku) = ?")
            bindValues.append(token.lowercased())
            
            whereConditions.append("LOWER(iv.sku) LIKE ?")
            bindValues.append("\(token.lowercased())%")
            
            whereConditions.append("LOWER(iv.sku) LIKE ?")
            bindValues.append("%\(token.lowercased())%")
        }
        
        let query = """
            SELECT DISTINCT ci.id, ci.name, ci.category_id, ci.category_name, ci.reporting_category_name,
                   iv.sku, iv.upc, iv.price_amount
            FROM catalog_items ci
            JOIN item_variations iv ON ci.id = iv.item_id
            WHERE ci.is_deleted = 0 AND iv.is_deleted = 0
            AND (\(whereConditions.joined(separator: " OR ")))
            LIMIT \(SearchConfig.maxResults)
        """
        
        let statement = try database.prepare(query)
        for row in try statement.run(bindValues) {
            if let candidate = createCandidateFromVariationRow(row) {
                results.append(candidate)
            }
        }
        
        return results
    }
    
    private func searchByBarcodeFuzzy(tokens: [String], database: Connection) throws -> [CandidateItem] {
        var results: [CandidateItem] = []
        
        var whereConditions: [String] = []
        var bindValues: [Binding?] = []
        
        for token in tokens {
            // For barcodes, exact and prefix matches are most important
            whereConditions.append("iv.upc = ?")
            bindValues.append(token)
            
            whereConditions.append("iv.upc LIKE ?")
            bindValues.append("\(token)%")
            
            // Only add substring match for longer tokens
            if token.count >= 4 {
                whereConditions.append("iv.upc LIKE ?")
                bindValues.append("%\(token)%")
            }
        }
        
        guard !whereConditions.isEmpty else { return [] }
        
        let query = """
            SELECT DISTINCT ci.id, ci.name, ci.category_id, ci.category_name, ci.reporting_category_name,
                   iv.sku, iv.upc, iv.price_amount
            FROM catalog_items ci
            JOIN item_variations iv ON ci.id = iv.item_id
            WHERE ci.is_deleted = 0 AND iv.is_deleted = 0
            AND (\(whereConditions.joined(separator: " OR ")))
            LIMIT \(SearchConfig.maxResults)
        """
        
        let statement = try database.prepare(query)
        for row in try statement.run(bindValues) {
            if let candidate = createCandidateFromVariationRow(row) {
                results.append(candidate)
            }
        }
        
        return results
    }
    
    private func searchByCategoryFuzzy(tokens: [String], database: Connection) throws -> [CandidateItem] {
        var results: [CandidateItem] = []
        
        var whereConditions: [String] = []
        var bindValues: [Binding?] = []
        
        for token in tokens {
            // Search both regular and reporting category names
            whereConditions.append("LOWER(ci.category_name) LIKE ?")
            bindValues.append("%\(token.lowercased())%")
            
            whereConditions.append("LOWER(ci.reporting_category_name) LIKE ?")
            bindValues.append("%\(token.lowercased())%")
        }
        
        let query = """
            SELECT DISTINCT ci.id, ci.name, ci.category_id, ci.category_name, ci.reporting_category_name
            FROM catalog_items ci
            WHERE ci.is_deleted = 0 
            AND (\(whereConditions.joined(separator: " OR ")))
            LIMIT \(SearchConfig.maxResults)
        """
        
        let statement = try database.prepare(query)
        for row in try statement.run(bindValues) {
            if let candidate = createCandidateFromItemRow(row) {
                results.append(candidate)
            }
        }
        
        return results
    }
    
    // MARK: - Candidate Creation
    
    private func createCandidateFromItemRow(_ row: Statement.Element) -> CandidateItem? {
        guard let id = row[0] as? String,
              let name = row[1] as? String else { return nil }
        
        let categoryId = row[2] as? String
        let categoryName = row[3] as? String
        let reportingCategoryName = row[4] as? String
        
        return CandidateItem(
            id: id,
            name: name,
            sku: nil,
            barcode: nil,
            categoryName: reportingCategoryName ?? categoryName,
            categoryId: categoryId,
            price: nil,
            images: nil,
            hasTax: false
        )
    }
    
    private func createCandidateFromVariationRow(_ row: Statement.Element) -> CandidateItem? {
        guard let id = row[0] as? String,
              let name = row[1] as? String else { return nil }
        
        let categoryId = row[2] as? String
        let categoryName = row[3] as? String
        let reportingCategoryName = row[4] as? String
        let sku = row[5] as? String
        let upc = row[6] as? String
        let priceAmount = row[7] as? Int64
        
        let price: Double? = {
            guard let amount = priceAmount, amount > 0 else { return nil }
            let convertedPrice = Double(amount) / 100.0
            return convertedPrice.isFinite && !convertedPrice.isNaN && convertedPrice > 0 ? convertedPrice : nil
        }()
        
        return CandidateItem(
            id: id,
            name: name,
            sku: sku,
            barcode: upc,
            categoryName: reportingCategoryName ?? categoryName,
            categoryId: categoryId,
            price: price,
            images: nil,
            hasTax: false
        )
    }
    
    // MARK: - Advanced Scoring Algorithm
    
    private func scoreAndRankCandidates(
        candidates: [CandidateItem],
        searchTerm: String,
        tokens: [String]
    ) -> [SearchResultWithScore] {
        
        logger.debug("[Search] Scoring \(candidates.count) candidates for term: '\(searchTerm)'")
        
        let scoredResults = candidates.compactMap { candidate -> SearchResultWithScore? in
            let score = calculateRelevanceScore(candidate: candidate, searchTerm: searchTerm, tokens: tokens)
            guard score > 0 else { return nil }
            
            // Debug log for each scored item
            logger.debug("[Search] Item '\(candidate.name ?? "unknown")' (ID: \(candidate.id)) scored: \(String(format: "%.1f", score))")
            
            return SearchResultWithScore(
                item: convertToSearchResult(candidate),
                score: score,
                explanation: "Score: \(String(format: "%.1f", score))"
            )
        }
        
        let sortedResults = scoredResults.sorted { $0.score > $1.score }
        
        // Log top 10 results after sorting
        logger.debug("[Search] Top 10 results after sorting:")
        for (index, result) in sortedResults.prefix(10).enumerated() {
            logger.debug("[Search]   \(index + 1). '\(result.item.name ?? "unknown")' - Score: \(String(format: "%.1f", result.score))")
        }
        
        return sortedResults
    }
    
    private func calculateRelevanceScore(
        candidate: CandidateItem,
        searchTerm: String,
        tokens: [String]
    ) -> Double {
        
        let searchLower = searchTerm.lowercased()
        
        // Score each field and find the BEST match (don't add them together)
        var bestScore: Double = 0.0
        var bestField: String = "none"
        
        // Score name field
        let nameScore = scoreField(candidate.name, against: searchLower, tokens: tokens, weight: FieldWeights.name)
        if nameScore > bestScore {
            bestScore = nameScore
            bestField = "name"
        }
        
        // Score SKU field  
        if let sku = candidate.sku {
            let skuScore = scoreField(sku, against: searchLower, tokens: tokens, weight: FieldWeights.sku)
            if skuScore > bestScore {
                bestScore = skuScore
                bestField = "sku"
            }
        }
        
        // Score barcode field
        if let barcode = candidate.barcode {
            let barcodeScore = scoreField(barcode, against: searchLower, tokens: tokens, weight: FieldWeights.barcode)
            if barcodeScore > bestScore {
                bestScore = barcodeScore
                bestField = "barcode"
            }
        }
        
        // Category field scoring removed - not useful for search
        
        // Simple bonus for exact matches (but don't override the main scoring)
        let exactMatchCount = countExactFieldMatches(candidate: candidate, searchTerm: searchLower)
        if exactMatchCount > 0 {
            bestScore += 5.0 // Small bonus, don't override field scoring
        }
        
        let finalScore = min(bestScore, 150.0)
        
        // Enhanced debug logging showing which field won
        if finalScore > 0 {
            logger.debug("[Search]   -> '\(candidate.name ?? "unknown")' best match in '\(bestField)' field: \(String(format: "%.1f", finalScore))")
        }
        
        return finalScore
    }
    
    private func scoreField(
        _ fieldValue: String?,
        against searchTerm: String,
        tokens: [String],
        weight: Double
    ) -> Double {
        
        guard let field = fieldValue?.lowercased(), !field.isEmpty else { return 0.0 }
        
        var fieldScore: Double = 0.0
        
        // 1. Exact match (highest score)
        if field == searchTerm {
            fieldScore = FieldWeights.exactMatch
        }
        // 2. Prefix match with length-based scoring  
        else if field.hasPrefix(searchTerm) {
            // Better score for shorter words (closer matches)
            let lengthRatio = Double(searchTerm.count) / Double(field.count)
            // Higher ratio = shorter word = better match
            fieldScore = FieldWeights.prefixMatch * (0.5 + 0.5 * lengthRatio)
        }
        // 3. Word-level matching - CRITICAL for good search
        else {
            // Split the field into words and check each word
            let words = field.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            
            var bestWordScore: Double = 0.0
            
            for (wordIndex, word) in words.enumerated() {
                var wordScore: Double = 0.0
                
                // Check if search term matches this word
                if word == searchTerm {
                    // Exact word match
                    wordScore = 95.0
                } else if word.hasPrefix(searchTerm) {
                    // Word starts with search term
                    let lengthRatio = Double(searchTerm.count) / Double(word.count)
                    wordScore = 85.0 * (0.5 + 0.5 * lengthRatio)
                } else if word.contains(searchTerm) {
                    // Search term is substring of word
                    let position = word.range(of: searchTerm)?.lowerBound.utf16Offset(in: word) ?? 0
                    let positionRatio = Double(position) / Double(word.count)
                    // Score decreases the further into the word the match is
                    wordScore = 30.0 * (1.0 - positionRatio * 0.5)
                }
                
                // Apply position decay - earlier words in the name are more important
                let positionMultiplier = 1.0 - (Double(wordIndex) * 0.1)
                wordScore *= max(positionMultiplier, 0.5)
                
                bestWordScore = max(bestWordScore, wordScore)
            }
            
            // Also check the entire field as a substring (but with lower score)
            if bestWordScore == 0.0 && field.contains(searchTerm) {
                // Substring match that doesn't align with word boundaries
                let position = field.range(of: searchTerm)?.lowerBound.utf16Offset(in: field) ?? 0
                let positionRatio = Double(position) / Double(field.count)
                // Much lower score for non-word-boundary matches
                fieldScore = 25.0 * (1.0 - positionRatio * 0.5)
            } else {
                fieldScore = bestWordScore
            }
        }
        
        // 4. Token-based scoring for multi-word queries
        if tokens.count > 1 {
            let tokenScore = scoreTokens(field: field, tokens: tokens)
            fieldScore = max(fieldScore, tokenScore)
        }
        
        return fieldScore * weight
    }
    
    private func scoreTokens(field: String, tokens: [String]) -> Double {
        guard tokens.count > 1 else { return 0.0 }
        
        // Split field into words for fuzzy matching
        let words = field.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        guard !words.isEmpty else { return 0.0 }
        
        var totalScore: Double = 0.0
        var tokenMatches: [Double] = []
        
        // For each token, find the best fuzzy match among all words
        for token in tokens {
            var bestTokenScore: Double = 0.0
            
            for (wordIndex, word) in words.enumerated() {
                let fuzzyScore = calculateFuzzyWordMatch(token: token, word: word, wordPosition: wordIndex)
                bestTokenScore = max(bestTokenScore, fuzzyScore)
            }
            
            tokenMatches.append(bestTokenScore)
            totalScore += bestTokenScore
        }
        
        // Calculate coverage ratio - how many tokens found good matches
        let goodMatches = tokenMatches.filter { $0 > 20.0 }.count
        let coverageRatio = Double(goodMatches) / Double(tokens.count)
        
        // Apply coverage bonus - multi-word queries should match most tokens
        let coverageBonus = coverageRatio >= 0.8 ? 1.2 : coverageRatio
        
        let finalScore = (totalScore / Double(tokens.count)) * coverageBonus
        
        return min(finalScore, 95.0) // Cap at 95 to leave room for exact matches
    }
    
    private func calculateFuzzyWordMatch(token: String, word: String, wordPosition: Int) -> Double {
        let tokenLower = token.lowercased()
        let wordLower = word.lowercased()
        
        // 1. Exact word match
        if tokenLower == wordLower {
            return applyPositionBonus(score: 90.0, position: wordPosition)
        }
        
        // 2. Word starts with token (prefix match)
        if wordLower.hasPrefix(tokenLower) {
            let lengthRatio = Double(tokenLower.count) / Double(wordLower.count)
            let prefixScore = 80.0 * (0.6 + 0.4 * lengthRatio)
            return applyPositionBonus(score: prefixScore, position: wordPosition)
        }
        
        // 3. Token starts with word (token is longer)
        if tokenLower.hasPrefix(wordLower) {
            let lengthRatio = Double(wordLower.count) / Double(tokenLower.count)
            let reverseScore = 70.0 * (0.5 + 0.5 * lengthRatio)
            return applyPositionBonus(score: reverseScore, position: wordPosition)
        }
        
        // 4. Fuzzy match using Levenshtein distance
        let distance = levenshteinDistance(tokenLower, wordLower)
        let maxLength = max(tokenLower.count, wordLower.count)
        
        // Only consider fuzzy matches if they're reasonable
        if distance <= 3 && maxLength > 0 {
            let similarity = 1.0 - (Double(distance) / Double(maxLength))
            
            // Require reasonable similarity for fuzzy matches
            if similarity >= 0.4 {
                let fuzzyScore = 60.0 * similarity
                return applyPositionBonus(score: fuzzyScore, position: wordPosition)
            }
        }
        
        // 5. Substring match (lowest priority)
        if wordLower.contains(tokenLower) && tokenLower.count >= 3 {
            let position = wordLower.range(of: tokenLower)?.lowerBound.utf16Offset(in: wordLower) ?? 0
            let positionRatio = Double(position) / Double(wordLower.count)
            let substringScore = 25.0 * (1.0 - positionRatio * 0.5)
            return applyPositionBonus(score: substringScore, position: wordPosition)
        }
        
        return 0.0
    }
    
    private func applyPositionBonus(score: Double, position: Int) -> Double {
        // Strong position preference - first words much more important
        let positionMultiplier: Double
        switch position {
        case 0: positionMultiplier = 1.0      // First word - full score
        case 1: positionMultiplier = 0.8      // Second word - 80%
        case 2: positionMultiplier = 0.6      // Third word - 60%  
        case 3: positionMultiplier = 0.4      // Fourth word - 40%
        default: positionMultiplier = 0.3     // Fifth+ word - 30%
        }
        
        return score * positionMultiplier
    }
    
    private func countFieldMatches(candidate: CandidateItem, searchTerm: String) -> Int {
        var matches = 0
        
        if candidate.name?.lowercased().contains(searchTerm) == true { matches += 1 }
        if candidate.sku?.lowercased().contains(searchTerm) == true { matches += 1 }
        if candidate.barcode?.lowercased().contains(searchTerm) == true { matches += 1 }
        if candidate.categoryName?.lowercased().contains(searchTerm) == true { matches += 1 }
        
        return matches
    }
    
    private func countExactFieldMatches(candidate: CandidateItem, searchTerm: String) -> Int {
        var exactMatches = 0
        
        if candidate.name?.lowercased() == searchTerm { exactMatches += 1 }
        if candidate.sku?.lowercased() == searchTerm { exactMatches += 1 }
        if candidate.barcode?.lowercased() == searchTerm { exactMatches += 1 }
        if candidate.categoryName?.lowercased() == searchTerm { exactMatches += 1 }
        
        return exactMatches
    }
    
    // MARK: - Levenshtein Distance Algorithm
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        // Initialize first row and column
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        // Fill matrix
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
    
    // MARK: - Helper Methods
    
    private func convertToSearchResult(_ candidate: CandidateItem) -> SearchResultItem {
        return SearchResultItem(
            id: candidate.id,
            name: candidate.name,
            sku: candidate.sku,
            price: candidate.price,
            barcode: candidate.barcode,
            categoryId: candidate.categoryId,
            categoryName: candidate.categoryName,
            variationName: nil, // FuzzySearch doesn't currently include variation names
            images: candidate.images,
            matchType: "fuzzy",
            matchContext: candidate.name,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: candidate.hasTax
        )
    }
    
    // Score explanation simplified - just show the numerical score
    // Full explanations removed as per user preference
}

// MARK: - Supporting Types

struct CandidateItem {
    let id: String
    let name: String?
    let sku: String?
    let barcode: String?
    let categoryName: String?
    let categoryId: String?
    let price: Double?
    let images: [CatalogImage]?
    let hasTax: Bool
}

struct SearchResultWithScore {
    let item: SearchResultItem
    let score: Double
    let explanation: String
}