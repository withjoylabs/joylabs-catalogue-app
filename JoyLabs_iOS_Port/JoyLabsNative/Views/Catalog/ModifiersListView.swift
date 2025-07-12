import SwiftUI
import SQLite
import os.log

struct ModifiersListView: View {
    @StateObject private var viewModel = ModifiersViewModel()
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText, placeholder: "Search modifiers...")
                .padding(.horizontal)
                .padding(.top, 8)
            
            if viewModel.isLoading {
                ProgressView("Loading modifiers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.modifiers.isEmpty {
                EmptyStateView(
                    icon: "slider.horizontal.3",
                    title: "No Modifiers",
                    message: "No modifiers found in the catalog."
                )
            } else {
                List(filteredModifiers, id: \.id) { modifier in
                    ModifierRowView(modifier: modifier)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Modifiers")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.loadModifiers()
            }
        }
    }
    
    private var filteredModifiers: [ModifierData] {
        if searchText.isEmpty {
            return viewModel.modifiers
        } else {
            return viewModel.modifiers.filter { modifier in
                modifier.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct ModifierRowView: View {
    let modifier: ModifierData
    
    var body: some View {
        HStack(spacing: 12) {
            // Modifier icon
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.purple)
                .font(.title2)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(modifier.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let modifierData = modifier.modifierData {
                    if let price = modifierData.priceMoney?.amount {
                        let priceValue = Double(price) / 100.0 // Convert cents to dollars
                        Text("$\(priceValue, specifier: "%.2f")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let onByDefault = modifierData.onByDefault, onByDefault {
                        Text("Default selection")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text("Updated: \(formatDate(modifier.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(modifier.version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                if modifier.isDeleted {
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

struct ModifierData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
    let modifierData: ModifierDataDetails?
}

struct ModifierDataDetails: Codable {
    let priceMoney: PriceMoney?
    let onByDefault: Bool?
    let ordinal: Int?
    let modifierListId: String?
}

struct PriceMoney: Codable {
    let amount: Int?
    let currency: String?
}

@MainActor
class ModifiersViewModel: ObservableObject {
    @Published var modifiers: [ModifierData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ModifiersViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
    
    func loadModifiers() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try databaseManager.connect()
            guard let db = databaseManager.getConnection() else {
                throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database connection"])
            }
            
            // Check if modifiers table exists
            let tableExists = try db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='modifiers'") as! Int64
            
            if tableExists == 0 {
                logger.info("Modifiers table does not exist yet")
                self.modifiers = []
                isLoading = false
                return
            }
            
            let modifiersTable = Table("modifiers")
            let id = Expression<String>("id")
            let name = Expression<String>("name")
            let isDeleted = Expression<Bool>("is_deleted")
            let updatedAt = Expression<String>("updated_at")
            let version = Expression<String>("version")
            let modifierDataJson = Expression<String?>("modifier_data_json")
            
            let rows = try db.prepare(modifiersTable.order(name.asc))
            
            var loadedModifiers: [ModifierData] = []
            
            for row in rows {
                var modifierDataDetails: ModifierDataDetails?
                
                if let jsonString = row[modifierDataJson],
                   let jsonData = jsonString.data(using: .utf8) {
                    modifierDataDetails = try? JSONDecoder().decode(ModifierDataDetails.self, from: jsonData)
                }
                
                let modifier = ModifierData(
                    id: row[id],
                    name: row[name],
                    isDeleted: row[isDeleted],
                    updatedAt: row[updatedAt],
                    version: row[version],
                    modifierData: modifierDataDetails
                )
                
                loadedModifiers.append(modifier)
            }
            
            self.modifiers = loadedModifiers
            logger.info("Loaded \(loadedModifiers.count) modifiers")
            
        } catch {
            logger.error("Failed to load modifiers: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationView {
        ModifiersListView()
    }
}
