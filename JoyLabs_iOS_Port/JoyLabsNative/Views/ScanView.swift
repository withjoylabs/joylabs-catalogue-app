import SwiftUI
import OSLog

struct ScanView: View {
    @State private var searchText = ""
    @State private var scanHistoryCount = 0
    @State private var isConnected = true
    @StateObject private var searchManager = SearchManager()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with JOYLABS logo and status
            HeaderView(isConnected: isConnected)

            // Scan History Button
            ScanHistoryButton(count: scanHistoryCount)

            // Main content area
            if !searchManager.isDatabaseReady {
                DatabaseInitializingView()
            } else if searchText.isEmpty {
                EmptySearchState()
            } else {
                SearchResultsView(searchManager: searchManager)
            }

            Spacer()

            // Bottom search bar (matching React Native layout)
            BottomSearchBar(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused)
        }
        .background(Color(.systemBackground))
        .onChange(of: searchText) {
            // Only trigger search if field is focused and has content
            // This prevents onChange from firing during focus changes
            if isSearchFieldFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: searchText, filters: filters)
            }
        }
    }
}

// MARK: - Search Results View
struct SearchResultsView: View {
    @ObservedObject var searchManager: SearchManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack {
                Text("Search Results")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if searchManager.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !searchManager.searchResults.isEmpty {
                    Text("\(searchManager.searchResults.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if searchManager.isSearching {
                SearchingView()
            } else if let error = searchManager.searchError {
                SearchErrorView(error: error)
            } else if searchManager.searchResults.isEmpty {
                NoResultsView()
            } else {
                SearchResultsList(results: searchManager.searchResults)
            }
        }
    }
}

// MARK: - Search State Views
struct SearchingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchErrorView: View {
    let error: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Search Error")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoResultsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchResultsList: View {
    let results: [SearchResultItem]

    var body: some View {
        List(results) { result in
            ScanResultCard(result: result)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ScanView()
}
