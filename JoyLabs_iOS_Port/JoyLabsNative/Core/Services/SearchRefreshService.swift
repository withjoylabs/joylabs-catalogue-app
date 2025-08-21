import Foundation

// MARK: - Search Refresh Service
/// Centralized service to handle search refresh logic after item saves
/// Ensures consistent behavior across all views that use ItemDetailsModal
class SearchRefreshService {
    static let shared = SearchRefreshService()
    
    private init() {}
    
    /// Refreshes search results after an item is saved
    /// - Parameters:
    ///   - query: The search query to refresh with
    ///   - searchManager: The SearchManager instance to refresh
    func refreshSearchAfterSave(
        with query: String,
        searchManager: SearchManager
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedQuery.isEmpty else { 
            print("🔄 [SearchRefresh] No query to refresh with")
            return 
        }
        
        let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
        searchManager.performSearchWithDebounce(searchTerm: trimmedQuery, filters: filters)
        print("🔄 [SearchRefresh] Refreshed search for query: '\(trimmedQuery)'")
    }
}