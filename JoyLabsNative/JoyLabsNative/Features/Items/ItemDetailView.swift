import SwiftUI

/// ItemDetailView - Displays detailed information about a catalog item
/// Ports the item detail functionality from React Native
struct ItemDetailView: View {
    let item: SearchResultItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ItemDetailController()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Item Header
                    ItemHeaderView(item: item)
                    
                    // Basic Information
                    ItemBasicInfoView(item: item)
                    
                    // Team Data (Case UPC info)
                    if item.isFromCaseUpc || controller.teamData != nil {
                        TeamDataView(
                            item: item,
                            teamData: controller.teamData,
                            isEditing: controller.isEditingTeamData,
                            onEdit: {
                                controller.startEditingTeamData()
                            },
                            onSave: { data in
                                Task {
                                    await controller.saveTeamData(data)
                                }
                            },
                            onCancel: {
                                controller.cancelEditingTeamData()
                            }
                        )
                    }
                    
                    // Variations
                    if !controller.variations.isEmpty {
                        ItemVariationsView(variations: controller.variations)
                    }
                    
                    // Actions
                    ItemActionsView(
                        item: item,
                        onEdit: {
                            // TODO: Implement item editing
                        },
                        onPrintLabel: {
                            // TODO: Implement label printing
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await controller.loadItemDetails(item.id)
        }
    }
}

// MARK: - Item Detail Controller
@MainActor
class ItemDetailController: ObservableObject {
    @Published var teamData: CaseUpcData?
    @Published var variations: [ItemVariationRow] = []
    @Published var isEditingTeamData: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let databaseManager = DatabaseManager()
    private let graphQLClient = GraphQLClient()
    
    func loadItemDetails(_ itemId: String) async {
        isLoading = true
        error = nil
        
        do {
            // Load variations from local database
            variations = try await databaseManager.getItemVariations(itemId: itemId)
            
            // Load team data from local database first
            teamData = try await databaseManager.getTeamData(itemId: itemId)
            
            // If no local team data, try GraphQL
            if teamData == nil {
                if let graphQLData = try await graphQLClient.getItemData(itemId) {
                    teamData = CaseUpcData(
                        caseUpc: graphQLData.caseUpc,
                        caseCost: graphQLData.caseCost,
                        caseQuantity: graphQLData.caseQuantity,
                        vendor: graphQLData.vendor,
                        discontinued: graphQLData.discontinued,
                        notes: graphQLData.notes?.map { note in
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
                }
            }
            
            isLoading = false
            
        } catch {
            Logger.error("ItemDetail", "Failed to load item details: \(error)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func startEditingTeamData() {
        isEditingTeamData = true
    }
    
    func cancelEditingTeamData() {
        isEditingTeamData = false
    }
    
    func saveTeamData(_ data: CaseUpcData) async {
        do {
            // Save to GraphQL first
            let input = ItemDataInput(
                id: "", // Will be set by the calling context
                caseUpc: data.caseUpc,
                caseCost: data.caseCost,
                caseQuantity: data.caseQuantity,
                vendor: data.vendor,
                discontinued: data.discontinued,
                notes: data.notes?.map { note in
                    NoteInput(
                        id: note.id,
                        content: note.content,
                        isComplete: note.isComplete,
                        authorId: note.authorId,
                        authorName: note.authorName
                    )
                }
            )
            
            // TODO: Implement save logic with proper item ID
            
            // Update local state
            teamData = data
            isEditingTeamData = false
            
            Logger.info("ItemDetail", "Team data saved successfully")
            
        } catch {
            Logger.error("ItemDetail", "Failed to save team data: \(error)")
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Item Header View
struct ItemHeaderView: View {
    let item: SearchResultItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Item image
            AsyncImage(url: item.images?.first?.imageData?.url.flatMap(URL.init)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 100, height: 100)
            .cornerRadius(12)
            .clipped()
            
            // Item info
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name ?? "Unnamed Item")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let price = item.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                if let sku = item.sku, !sku.isEmpty {
                    Label(sku, systemImage: "number")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let barcode = item.barcode, !barcode.isEmpty {
                    Label(barcode, systemImage: "barcode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Item Basic Info View
struct ItemBasicInfoView: View {
    let item: SearchResultItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                InfoRow(label: "Item ID", value: item.id)
                
                if let categoryName = item.categoryName {
                    InfoRow(label: "Category", value: categoryName)
                }
                
                InfoRow(label: "Match Type", value: item.matchType.capitalized)
                
                if let context = item.matchContext {
                    InfoRow(label: "Match Context", value: context)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Team Data View
struct TeamDataView: View {
    let item: SearchResultItem
    let teamData: CaseUpcData?
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: (CaseUpcData) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Team Data")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !isEditing {
                    Button("Edit", action: onEdit)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            if let data = teamData {
                if isEditing {
                    TeamDataEditView(
                        data: data,
                        onSave: onSave,
                        onCancel: onCancel
                    )
                } else {
                    TeamDataDisplayView(data: data)
                }
            } else {
                Text("No team data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Team Data Display View
struct TeamDataDisplayView: View {
    let data: CaseUpcData
    
    var body: some View {
        VStack(spacing: 8) {
            if let caseUpc = data.caseUpc {
                InfoRow(label: "Case UPC", value: caseUpc)
            }
            
            if let caseCost = data.caseCost {
                InfoRow(label: "Case Cost", value: "$\(caseCost, specifier: "%.2f")")
            }
            
            if let caseQuantity = data.caseQuantity {
                InfoRow(label: "Case Quantity", value: "\(caseQuantity)")
            }
            
            if let vendor = data.vendor {
                InfoRow(label: "Vendor", value: vendor)
            }
            
            if data.discontinued == true {
                InfoRow(label: "Status", value: "Discontinued")
            }
        }
    }
}

// MARK: - Team Data Edit View (Placeholder)
struct TeamDataEditView: View {
    let data: CaseUpcData
    let onSave: (CaseUpcData) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack {
            Text("Team data editing will be implemented in Phase 3")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
            
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Save") {
                    onSave(data)
                }
                .foregroundColor(.blue)
                .fontWeight(.medium)
            }
            .padding(.top)
        }
    }
}

// MARK: - Item Variations View
struct ItemVariationsView: View {
    let variations: [ItemVariationRow]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Variations (\(variations.count))")
                .font(.headline)
                .foregroundColor(.primary)
            
            ForEach(variations, id: \.id) { variation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(variation.name ?? "Unnamed Variation")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let sku = variation.sku {
                        Text("SKU: \(sku)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let amount = variation.priceAmount {
                        Text("Price: $\(Double(amount) / 100.0, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)
                
                if variation.id != variations.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Item Actions View
struct ItemActionsView: View {
    let item: SearchResultItem
    let onEdit: () -> Void
    let onPrintLabel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onEdit) {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Item")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            Button(action: onPrintLabel) {
                HStack {
                    Image(systemName: "printer")
                    Text("Print Label")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    ItemDetailView(
        item: SearchResultItem(
            id: "test-item-1",
            name: "Sample Product",
            sku: "SKU123",
            price: 29.99,
            barcode: "123456789012",
            categoryId: "cat1",
            categoryName: "Electronics",
            images: nil,
            matchType: "name",
            matchContext: "Sample Product",
            isFromCaseUpc: false,
            caseUpcData: nil
        )
    )
}
