import Foundation
import SQLite
import Combine

/// SearchManager - Handles sophisticated search combining local SQLite with GraphQL
/// Ports the exact search logic from React Native performSearch function
@MainActor
class SearchManager: ObservableObject {
    // MARK: - Published Properties
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var lastSearchTerm: String = ""
    
    // MARK: - Private Properties
    private let databaseManager: DatabaseManager
    private let graphQLClient: GraphQLClient
    private var searchTask: Task<Void, Never>?
    
    // Debouncing
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager = DatabaseManager(),
        graphQLClient: GraphQLClient = GraphQLClient()
    ) {
        self.databaseManager = databaseManager
        self.graphQLClient = graphQLClient
        
        setupSearchDebouncing()
    }
    
    // MARK: - Public Methods
    func performSearch(searchTerm: String, filters: SearchFilters) async -> [SearchResultItem] {
        // Port the exact logic from React Native performSearch
        let trimmedTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTerm.isEmpty else {
            await MainActor.run {
                searchResults = []
                lastSearchTerm = ""
            }
            return []
        }
        
        await MainActor.run {
            isSearching = true
            searchError = nil
            lastSearchTerm = trimmedTerm
        }
        
        Logger.info("Search", "Performing search for: '\(trimmedTerm)' with filters: \(filters)")
        
        do {
            // 1. Local SQLite search (exact port of React Native logic)
            let localResults = try await searchLocalItems(searchTerm: trimmedTerm, filters: filters)
            Logger.debug("Search", "Local search returned \(localResults.count) results")
            
            // 2. Case UPC search via GraphQL (if numeric and barcode filter enabled)
            var caseUpcResults: [SearchResultItem] = []
            if trimmedTerm.allSatisfy(\.isNumber) && filters.barcode {
                caseUpcResults = try await searchCaseUpcItems(searchTerm: trimmedTerm)
                Logger.debug("Search", "Case UPC search returned \(caseUpcResults.count) results")
            }
            
            // 3. Combine and deduplicate results (exact port of React Native logic)
            let combinedResults = combineAndDeduplicateResults(
                localResults: localResults,
                caseUpcResults: caseUpcResults
            )
            
            await MainActor.run {
                searchResults = combinedResults
                isSearching = false
            }
            
            Logger.info("Search", "Search completed: \(combinedResults.count) total results")
            return combinedResults
            
        } catch {
            Logger.error("Search", "Search failed: \(error)")
            
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
                searchResults = []
            }
            
            return []
        }
    }
    
    func performSearchWithDebounce(searchTerm: String, filters: SearchFilters) {
        // Cancel any existing search
        searchTask?.cancel()
        
        // Send to debounced subject
        searchSubject.send((searchTerm, filters))
    }
    
    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        lastSearchTerm = ""
        isSearching = false
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncing() {
        // Debounce search requests (300ms delay like React Native)
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] (searchTerm, filters) in
                self?.searchTask = Task {
                    await self?.performSearch(searchTerm: searchTerm, filters: filters)
                }
            }
            .store(in: &cancellables)
    }
    
    private func searchLocalItems(searchTerm: String, filters: SearchFilters) async throws -> [SearchResultItem] {
        // Port the exact SQLite search logic from React Native
        let db = try await databaseManager.getDatabase()
        
        var queryParts: [String] = []
        var params: [String] = []
        let searchTermLike = "%\(searchTerm)%"
        
        // Name search (exact port)
        if filters.name {
            queryParts.append("""
                SELECT id, data_json, 'name' as match_type, name as match_context
                FROM catalog_items 
                WHERE name LIKE ? AND is_deleted = 0
            """)
            params.append(searchTermLike)
        }
        
        // SKU search (exact port)
        if filters.sku {
            queryParts.append("""
                SELECT iv.item_id as id, ci.data_json, 'sku' as match_type,
                       json_extract(iv.data_json, '$.item_variation_data.sku') as match_context
                FROM item_variations iv
                JOIN catalog_items ci ON iv.item_id = ci.id
                WHERE json_extract(iv.data_json, '$.item_variation_data.sku') LIKE ?
                  AND iv.is_deleted = 0 AND ci.is_deleted = 0
            """)
            params.append(searchTermLike)
        }
        
        // Barcode/UPC search (exact port)
        if filters.barcode {
            queryParts.append("""
                SELECT iv.item_id as id, ci.data_json, 'barcode' as match_type,
                       json_extract(iv.data_json, '$.item_variation_data.upc') as match_context
                FROM item_variations iv
                JOIN catalog_items ci ON iv.item_id = ci.id
                WHERE json_extract(iv.data_json, '$.item_variation_data.upc') LIKE ?
                  AND iv.is_deleted = 0 AND ci.is_deleted = 0
            """)
            params.append(searchTermLike)
        }
        
        // Category search (exact port)
        if filters.category {
            queryParts.append("""
                SELECT ci.id, ci.data_json, 'category' as match_type, c.name as match_context
                FROM catalog_items ci
                JOIN categories c ON ci.category_id = c.id
                WHERE c.name LIKE ? AND ci.is_deleted = 0 AND c.is_deleted = 0
            """)
            params.append(searchTermLike)
        }
        
        guard !queryParts.isEmpty else {
            return []
        }
        
        // Combine queries with UNION (exact port)
        let finalQuery = queryParts.joined(separator: " UNION ")
        
        Logger.debug("Search", "Executing local search query with \(params.count) parameters")
        
        // Execute query
        let rawResults = try db.prepare(finalQuery).map { row in
            RawSearchResult(
                id: row[0] as! String,
                dataJson: row[1] as! String,
                matchType: row[2] as! String,
                matchContext: row[3] as? String
            )
        }
        
        // Convert raw results to SearchResultItem
        return try rawResults.compactMap { rawResult in
            try convertRawResultToSearchItem(rawResult, isFromCaseUpc: false)
        }
    }
    
    private func searchCaseUpcItems(searchTerm: String) async throws -> [SearchResultItem] {
        // Port the GraphQL Case UPC search logic
        Logger.debug("Search", "Searching Case UPC for numeric term: \(searchTerm)")
        
        do {
            let caseUpcItems = try await graphQLClient.searchItemsByCaseUpc(searchTerm)
            
            return caseUpcItems.compactMap { item in
                // Convert GraphQL result to SearchResultItem
                SearchResultItem(
                    id: item.id,
                    name: "Case UPC Item", // Will be enhanced with actual data
                    sku: nil,
                    price: item.caseCost,
                    barcode: item.caseUpc,
                    categoryId: nil,
                    categoryName: nil,
                    images: nil,
                    matchType: "case_upc",
                    matchContext: item.caseUpc,
                    isFromCaseUpc: true,
                    caseUpcData: CaseUpcData(
                        caseUpc: item.caseUpc,
                        caseCost: item.caseCost,
                        caseQuantity: item.caseQuantity,
                        vendor: item.vendor,
                        discontinued: item.discontinued,
                        notes: item.notes?.map { note in
                            TeamNote(
                                id: note.id,
                                content: note.content,
                                isComplete: note.isComplete,
                                authorId: note.authorId,
                                authorName: note.authorName,
                                createdAt: note.createdAt,
                                updatedAt: note.updatedAt
                            )
                        }
                    )
                )
            }
        } catch {
            Logger.warn("Search", "Case UPC search failed: \(error)")
            return []
        }
    }
    
    private func combineAndDeduplicateResults(
        localResults: [SearchResultItem],
        caseUpcResults: [SearchResultItem]
    ) -> [SearchResultItem] {
        // Port the exact deduplication logic from React Native
        var combinedResults = localResults
        
        // Add case UPC results that don't duplicate local results
        for caseUpcResult in caseUpcResults {
            let isDuplicate = localResults.contains { localResult in
                // Check for duplicates based on barcode/UPC matching
                if let localBarcode = localResult.barcode,
                   let caseUpc = caseUpcResult.barcode {
                    return localBarcode == caseUpc
                }
                return false
            }
            
            if !isDuplicate {
                combinedResults.append(caseUpcResult)
            }
        }
        
        // Sort results (prioritize exact matches, then by name)
        return combinedResults.sorted { lhs, rhs in
            // Exact matches first
            if lhs.matchType == "barcode" && rhs.matchType != "barcode" {
                return true
            }
            if rhs.matchType == "barcode" && lhs.matchType != "barcode" {
                return false
            }
            
            // Then by name
            let lhsName = lhs.name ?? ""
            let rhsName = rhs.name ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }
    
    private func convertRawResultToSearchItem(_ rawResult: RawSearchResult, isFromCaseUpc: Bool) throws -> SearchResultItem? {
        // Parse the JSON data to extract item information
        guard let jsonData = rawResult.dataJson.data(using: .utf8),
              let catalogObject = try? JSONDecoder().decode(CatalogObject.self, from: jsonData) else {
            Logger.warn("Search", "Failed to parse catalog object JSON for ID: \(rawResult.id)")
            return nil
        }
        
        let itemData = catalogObject.itemData
        
        // Extract price from variations
        let price = itemData?.variations?.first?.itemVariationData?.priceMoney?.amount.map { Double($0) / 100.0 }
        
        // Extract barcode from variations
        let barcode = itemData?.variations?.first?.itemVariationData?.upc
        
        // Extract SKU from variations
        let sku = itemData?.variations?.first?.itemVariationData?.sku
        
        // Extract images
        let images = itemData?.images
        
        return SearchResultItem(
            id: rawResult.id,
            name: itemData?.name,
            sku: sku,
            price: price,
            barcode: barcode,
            categoryId: itemData?.categoryId,
            categoryName: nil, // Will be populated by category lookup if needed
            images: images,
            matchType: rawResult.matchType,
            matchContext: rawResult.matchContext,
            isFromCaseUpc: isFromCaseUpc,
            caseUpcData: nil
        )
    }
}

// MARK: - Supporting Types
enum SearchError: LocalizedError {
    case databaseError(Error)
    case graphQLError(Error)
    case invalidSearchTerm
    
    var errorDescription: String? {
        switch self {
        case .databaseError(let error):
            return "Database search error: \(error.localizedDescription)"
        case .graphQLError(let error):
            return "GraphQL search error: \(error.localizedDescription)"
        case .invalidSearchTerm:
            return "Invalid search term"
        }
    }
}
