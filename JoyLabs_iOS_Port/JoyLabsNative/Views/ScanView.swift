import SwiftUI
import OSLog

struct ScanView: View {
    @State private var searchText = ""
    @State private var scanHistoryCount = 0
    @State private var isConnected = true
    @State private var showingHistory = false
    @StateObject private var searchManager: SearchManager = {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return SearchManager(databaseManager: databaseManager)
    }()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with JOYLABS logo and status
            HeaderView(
                isConnected: isConnected,
                scanHistoryCount: scanHistoryCount,
                onHistoryTap: handleHistoryTap
            )

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
        .sheet(isPresented: $showingHistory) {
            // TODO: Add HistoryView when it's properly added to Xcode project
            Text("History View Coming Soon")
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingHistory = false
                        }
                    }
                }
        }
        .onAppear {
            // Auto-focus the search field with a small delay to prevent constraint conflicts
            // Only focus if not already focused to prevent dictation conflicts
            if !isSearchFieldFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isSearchFieldFocused = true
                }
            }
        }
        .onChange(of: searchText) {
            // Only trigger search if field is focused and has content
            // This prevents onChange from firing during focus changes
            if isSearchFieldFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
                searchManager.performSearchWithDebounce(searchTerm: searchText, filters: filters)
            }
        }
    }

    // MARK: - Actions
    private func handleHistoryTap() {
        showingHistory = true
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
                    if let totalCount = searchManager.totalResultsCount {
                        Text("\(totalCount) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(searchManager.searchResults.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                SearchResultsList(results: searchManager.searchResults, searchManager: searchManager)
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
    @ObservedObject var searchManager: SearchManager

    var body: some View {
        List {
            ForEach(results) { result in
                ScanResultCard(result: result)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        // Load more when approaching the end
                        if result.id == results.last?.id && searchManager.hasMoreResults && !searchManager.isLoadingMore {
                            searchManager.loadMoreResults()
                        }
                    }
            }

            // Loading indicator at the bottom
            if searchManager.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView("Loading more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ScanView()
}
