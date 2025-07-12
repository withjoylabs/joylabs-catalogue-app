import Foundation
import Combine

/// MockSearchManager - Simplified search manager for Phase 7
/// Uses MockDatabaseManager for in-memory search functionality
@MainActor
class MockSearchManager: ObservableObject {
    // MARK: - Published Properties
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    @Published var lastSearchTerm: String = ""
    
    // MARK: - Private Properties
    private let databaseManager: MockDatabaseManager
    private var searchTask: Task<Void, Never>?
    
    // Debouncing
    private var searchSubject = PassthroughSubject<(String, SearchFilters), Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(databaseManager: MockDatabaseManager? = nil) {
        if let databaseManager = databaseManager {
            self.databaseManager = databaseManager
        } else {
            self.databaseManager = MockDatabaseManager()
        }
        setupSearchDebouncing()
    }
    
    // MARK: - Public Methods
    func performSearch(searchTerm: String, filters: SearchFilters) async -> [SearchResultItem] {
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
        
        Logger.info("MockSearch", "Performing search for: '\(trimmedTerm)' with filters: \(filters)")
        
        do {
            // Search using mock database
            let results = try await databaseManager.searchCatalogItems(searchTerm: trimmedTerm, filters: filters)
            Logger.debug("MockSearch", "Search returned \(results.count) results")
            
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
            
            Logger.info("MockSearch", "Search completed: \(results.count) total results")
            return results
            
        } catch {
            Logger.error("MockSearch", "Search failed: \(error)")
            
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
    
    func clearResults() {
        searchResults = []
        lastSearchTerm = ""
        searchError = nil
    }
    
    // MARK: - Private Methods
    private func setupSearchDebouncing() {
        // Debounce search requests by 300ms
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] (searchTerm: String, filters: SearchFilters) in
                self?.searchTask = Task {
                    let _ = await self?.performSearch(searchTerm: searchTerm, filters: filters)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Logger Extension
extension MockSearchManager {
    private struct Logger {
        static func info(_ category: String, _ message: String) {
            print("[\(category)] INFO: \(message)")
        }
        
        static func debug(_ category: String, _ message: String) {
            print("[\(category)] DEBUG: \(message)")
        }
        
        static func error(_ category: String, _ message: String) {
            print("[\(category)] ERROR: \(message)")
        }
    }
}
