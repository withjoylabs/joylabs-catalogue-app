import SwiftUI
import OSLog

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var historyItems: [ScanHistoryItem] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    LoadingHistoryView()
                } else if historyItems.isEmpty {
                    EmptyHistoryView()
                } else {
                    HistoryListView(items: historyItems)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadHistoryItems()
        }
    }
    
    // MARK: - Actions
    private func loadHistoryItems() {
        isLoading = true
        
        // TODO: Load actual history items from database
        // For now, create some mock data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            historyItems = createMockHistoryItems()
            isLoading = false
        }
    }
    
    private func createMockHistoryItems() -> [ScanHistoryItem] {
        return [
            ScanHistoryItem(
                id: "1",
                scanId: "scan_1",
                scanTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
                name: "Sample Product 1",
                sku: "SKU001",
                price: 19.99,
                barcode: "1234567890123",
                categoryId: "cat1",
                categoryName: "Electronics"
            ),
            ScanHistoryItem(
                id: "2",
                scanId: "scan_2",
                scanTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)),
                name: "Sample Product 2",
                sku: "SKU002",
                price: 29.99,
                barcode: "2345678901234",
                categoryId: "cat2",
                categoryName: "Home & Garden"
            )
        ]
    }
}

// MARK: - History List View
struct HistoryListView: View {
    let items: [ScanHistoryItem]
    
    var body: some View {
        List(items) { item in
            HistoryItemCard(item: item)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }
}

// MARK: - History Item Card
struct HistoryItemCard: View {
    let item: ScanHistoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Placeholder image
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
                .cornerRadius(6)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                )
            
            // Item details
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name ?? "Unknown Item")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let categoryName = item.categoryName, !categoryName.isEmpty {
                        Text(categoryName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray4))
                            .cornerRadius(4)
                    }
                    
                    if let barcode = item.barcode, !barcode.isEmpty {
                        Text(barcode)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Bullet point separator (only if both UPC and SKU are present)
                    if let barcode = item.barcode, !barcode.isEmpty,
                       let sku = item.sku, !sku.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if let sku = item.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Scan time
                if let scanTime = ISO8601DateFormatter().date(from: item.scanTime) {
                    Text(formatScanTime(scanTime))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Price
            if let price = item.price, price.isFinite && !price.isNaN {
                Text("$\(price, specifier: "%.2f")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            // Subtle divider line
            VStack {
                Spacer()
                HStack {
                    Spacer()
                        .frame(width: 62)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                }
            }
        )
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
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No History Yet")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Items you scan or modify will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HistoryView()
}
