import SwiftUI
import SQLite
import os.log

struct CategoriesListView: View {
    @StateObject private var viewModel = CategoriesViewModel()
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText, placeholder: "Search categories...")
                .padding(.horizontal)
                .padding(.top, 8)
            
            if viewModel.isLoading {
                ProgressView("Loading categories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.categories.isEmpty {
                EmptyStateView(
                    icon: "folder.fill",
                    title: "No Categories",
                    message: "No categories found in the catalog."
                )
            } else {
                List(filteredCategories, id: \.id) { category in
                    CategoryRowView(category: category)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.loadCategories()
            }
        }
    }
    
    private var filteredCategories: [CategoryData] {
        if searchText.isEmpty {
            return viewModel.categories
        } else {
            return viewModel.categories.filter { category in
                category.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct CategoryRowView: View {
    let category: CategoryData
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: "folder.fill")
                .foregroundColor(.orange)
                .font(.title2)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let description = category.categoryData?.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text("Updated: \(formatDate(category.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(category.version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                if category.isDeleted {
                    Text("DELETED")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct CategoryData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
    let categoryData: CategoryDataDetails?
}

struct CategoryDataDetails: Codable {
    let description: String?
    let imageIds: [String]?
}

@MainActor
class CategoriesViewModel: ObservableObject {
    @Published var categories: [CategoryData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CategoriesViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
    
    func loadCategories() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try databaseManager.connect()
            guard let db = databaseManager.getConnection() else {
                throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database connection"])
            }
            
            let categoriesTable = Table("categories")
            let id = Expression<String>("id")
            let name = Expression<String>("name")
            let isDeleted = Expression<Bool>("is_deleted")
            let updatedAt = Expression<String>("updated_at")
            let version = Expression<String>("version")
            let categoryDataJson = Expression<String?>("category_data_json")
            
            let rows = try db.prepare(categoriesTable.order(name.asc))
            
            var loadedCategories: [CategoryData] = []
            
            for row in rows {
                var categoryDataDetails: CategoryDataDetails?
                
                if let jsonString = row[categoryDataJson],
                   let jsonData = jsonString.data(using: .utf8) {
                    categoryDataDetails = try? JSONDecoder().decode(CategoryDataDetails.self, from: jsonData)
                }
                
                let category = CategoryData(
                    id: row[id],
                    name: row[name],
                    isDeleted: row[isDeleted],
                    updatedAt: row[updatedAt],
                    version: row[version],
                    categoryData: categoryDataDetails
                )
                
                loadedCategories.append(category)
            }
            
            self.categories = loadedCategories
            logger.info("Loaded \(loadedCategories.count) categories")
            
        } catch {
            logger.error("Failed to load categories: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationView {
        CategoriesListView()
    }
}
