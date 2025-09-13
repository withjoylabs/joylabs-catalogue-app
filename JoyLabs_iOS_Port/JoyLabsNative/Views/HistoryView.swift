import SwiftUI
import OSLog

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanHistoryService = ScanHistoryService.shared
    @State private var isLoading = false
    @State private var selectedItem: ScanHistoryItem?
    @State private var showingItemDetails = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    LoadingHistoryView()
                } else if scanHistoryService.historyItems.isEmpty {
                    EmptyHistoryView()
                } else {
                    HistoryListView(
                        items: scanHistoryService.historyItems,
                        onItemTap: { item in
                            selectedItem = item
                            showingItemDetails = true
                        }
                    )
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                // Clear history button if there are items
                if !scanHistoryService.historyItems.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear All") {
                            scanHistoryService.clearHistory()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showingItemDetails) {
            if let selectedItem = selectedItem {
                ItemDetailsModal(
                    context: .editExisting(itemId: selectedItem.itemId),
                    onDismiss: {
                        showingItemDetails = false
                        self.selectedItem = nil
                    },
                    onSave: { _ in
                        showingItemDetails = false
                        self.selectedItem = nil
                    }
                )
                .fullScreenModal()
            }
        }
        .onAppear {
            // No need to load - ScanHistoryService already loads on init
        }
    }
    
}

// MARK: - History List View
struct HistoryListView: View {
    let items: [ScanHistoryItem]
    let onItemTap: (ScanHistoryItem) -> Void
    
    var body: some View {
        List(Array(items.enumerated()), id: \.element.id) { index, item in
            HistoryItemCard(item: item, index: index + 1)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .contentShape(Rectangle())
                .onTapGesture {
                    onItemTap(item)
                }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }
}

// MARK: - History Item Card
struct HistoryItemCard: View {
    let item: ScanHistoryItem
    let index: Int
    @State private var itemImageUrl: String?
    @State private var variationName: String?
    
    var body: some View {
        HStack(spacing: 12) {
            // Index number
            Text("\(index)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(width: 20, alignment: .center)
            
            // Item thumbnail using SimpleImageView
            SimpleImageView.thumbnail(
                imageURL: itemImageUrl,
                size: 50
            )
            
            // Item details - two row layout
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Name + variation (left) | Badge + Time (right)
                HStack {
                    // Left side: Name with variation
                    HStack(spacing: 4) {
                        Text(item.name ?? "Unknown Item")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // Variation name with bullet separator
                        if let variation = variationName, !variation.isEmpty {
                            Text("•")
                                .font(.system(size: 14))
                                .foregroundColor(Color.secondary)
                            
                            Text(variation)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Right side: Timestamp + operation badge
                    HStack(spacing: 6) {
                        if let scanTime = ISO8601DateFormatter().date(from: item.scanTime) {
                            Text(formatScanTime(scanTime))
                                .font(.system(size: 10))
                                .foregroundColor(Color.secondary)
                        }
                        
                        Text(item.operation.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(operationColor)
                            .cornerRadius(8)
                    }
                }
                
                // Row 2: Category + UPC + SKU (left) | Price (right)
                HStack {
                    // Left side: Category badge and identifiers
                    HStack(spacing: 8) {
                        if let categoryName = item.categoryName, !categoryName.isEmpty {
                            Text(categoryName)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                        
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                            
                            Text(barcode)
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                        }

                        if let sku = item.sku, !sku.isEmpty {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                            
                            Text(sku)
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    
                    Spacer()
                    
                    // Right side: Price
                    if let price = item.price, price.isFinite && !price.isNaN {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            // Bottom separator line
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .padding(.leading, 98) // Indent to align with content
            }
        )
        .onAppear {
            loadItemData()
        }
    }
    
    private var operationColor: Color {
        switch item.operation {
        case .created:
            return .green
        case .updated:
            return .blue
        }
    }
    
    private func loadItemData() {
        Task {
            let catalogLookupService = CatalogLookupService.shared
            if let catalogItem = catalogLookupService.getItem(id: item.itemId) {
                let variation = catalogLookupService.getVariationName(for: item.itemId)
                
                await MainActor.run {
                    itemImageUrl = catalogItem.primaryImageUrl
                    variationName = variation
                }
            }
        }
    }
    
    private func formatScanTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Loading View
struct LoadingHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView("Loading history...")
                .font(.subheadline)
                .foregroundColor(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty History View
struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(Color.secondary)
            
            VStack(spacing: 8) {
                Text("No Scan History")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Items you create or edit will appear here for easy access")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HistoryView()
}
