import SwiftUI
import SQLite
import os.log

struct TaxesListView: View {
    @StateObject private var viewModel = TaxesViewModel()
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText, placeholder: "Search taxes...")
                .padding(.horizontal)
                .padding(.top, 8)
            
            if viewModel.isLoading {
                ProgressView("Loading taxes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.taxes.isEmpty {
                EmptyStateView(
                    icon: "percent",
                    title: "No Taxes",
                    message: "No tax configurations found in the catalog."
                )
            } else {
                List(filteredTaxes, id: \.id) { tax in
                    TaxRowView(tax: tax)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Taxes")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.loadTaxes()
            }
        }
    }
    
    private var filteredTaxes: [TaxData] {
        if searchText.isEmpty {
            return viewModel.taxes
        } else {
            return viewModel.taxes.filter { tax in
                tax.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct TaxRowView: View {
    let tax: TaxData
    
    var body: some View {
        HStack(spacing: 12) {
            // Tax icon
            Image(systemName: "percent")
                .foregroundColor(.green)
                .font(.title2)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tax.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let taxData = tax.taxData {
                    if let percentage = taxData.percentage {
                        Text("\(percentage, specifier: "%.2f")% tax rate")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let calculationPhase = taxData.calculationPhase {
                        Text("Phase: \(calculationPhase)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Updated: \(formatDate(tax.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(tax.version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                if tax.isDeleted {
                    Text("DELETED")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                
                if let taxData = tax.taxData, taxData.enabled == true {
                    Text("ACTIVE")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
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

struct TaxData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
    let taxData: TaxDataDetails?
}

struct TaxDataDetails: Codable {
    let calculationPhase: String?
    let inclusionType: String?
    let percentage: Double?
    let enabled: Bool?
    let appliesToCustomAmounts: Bool?
}

@MainActor
class TaxesViewModel: ObservableObject {
    @Published var taxes: [TaxData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "TaxesViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
    
    func loadTaxes() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try databaseManager.connect()
            guard let db = databaseManager.getConnection() else {
                throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database connection"])
            }
            
            let taxesTable = Table("taxes")
            let id = Expression<String>("id")
            let name = Expression<String>("name")
            let isDeleted = Expression<Bool>("is_deleted")
            let updatedAt = Expression<String>("updated_at")
            let version = Expression<String>("version")
            let taxDataJson = Expression<String?>("tax_data_json")
            
            let rows = try db.prepare(taxesTable.order(name.asc))
            
            var loadedTaxes: [TaxData] = []
            
            for row in rows {
                var taxDataDetails: TaxDataDetails?
                
                if let jsonString = row[taxDataJson],
                   let jsonData = jsonString.data(using: .utf8) {
                    taxDataDetails = try? JSONDecoder().decode(TaxDataDetails.self, from: jsonData)
                }
                
                let tax = TaxData(
                    id: row[id],
                    name: row[name],
                    isDeleted: row[isDeleted],
                    updatedAt: row[updatedAt],
                    version: row[version],
                    taxData: taxDataDetails
                )
                
                loadedTaxes.append(tax)
            }
            
            self.taxes = loadedTaxes
            logger.info("Loaded \(loadedTaxes.count) taxes")
            
        } catch {
            logger.error("Failed to load taxes: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationView {
        TaxesListView()
    }
}
