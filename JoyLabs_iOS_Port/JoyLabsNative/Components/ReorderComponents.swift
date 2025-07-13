import SwiftUI

// MARK: - Reorders Header
struct ReordersHeader: View {
    let itemCount: Int
    let totalQuantity: Int
    let onExport: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Reorders")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Menu {
                    Button("Export", action: onExport)
                    Button("Clear All", role: .destructive, action: onClear)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            
            ReorderStatsView(itemCount: itemCount, totalQuantity: totalQuantity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

// MARK: - Reorder Stats View
struct ReorderStatsView: View {
    let itemCount: Int
    let totalQuantity: Int
    
    var body: some View {
        HStack(spacing: 20) {
            ReorderStatCard(title: "Items", value: "\(itemCount)", icon: "list.bullet")
            ReorderStatCard(title: "Total Qty", value: "\(totalQuantity)", icon: "number")
            ReorderStatCard(title: "Estimated Cost", value: "$--", icon: "dollarsign.circle")
        }
    }
}

// MARK: - Reorder Stat Card
struct ReorderStatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Reorders Empty State
struct ReordersEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cart")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Reorder Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Add items to your reorder list by scanning products or searching the catalog")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Browse Catalog") {
                // Navigate to catalog
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reorders List View
struct ReordersListView: View {
    @Binding var items: [ReorderItem]
    let onRemoveItem: (Int) -> Void
    let onUpdateQuantity: (String, Int) -> Void
    
    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ReorderItemCard(
                    item: item,
                    onRemove: { onRemoveItem(index) },
                    onUpdateQuantity: { newQuantity in
                        onUpdateQuantity(item.id, newQuantity)
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Reorder Item Card
struct ReorderItemCard: View {
    let item: ReorderItem
    let onRemove: () -> Void
    let onUpdateQuantity: (Int) -> Void
    
    @State private var quantity: Int
    
    init(item: ReorderItem, onRemove: @escaping () -> Void, onUpdateQuantity: @escaping (Int) -> Void) {
        self.item = item
        self.onRemove = onRemove
        self.onUpdateQuantity = onUpdateQuantity
        self._quantity = State(initialValue: item.quantity)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("SKU: \(item.sku)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Last ordered: \(formatDate(item.lastOrderDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Text("Quantity:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                QuantitySelector(
                    quantity: $quantity,
                    onQuantityChanged: { newQuantity in
                        onUpdateQuantity(newQuantity)
                    }
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Quantity Selector
struct QuantitySelector: View {
    @Binding var quantity: Int
    let onQuantityChanged: (Int) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if quantity > 1 {
                    quantity -= 1
                    onQuantityChanged(quantity)
                }
            }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(quantity > 1 ? .blue : .gray)
            }
            .disabled(quantity <= 1)
            
            Text("\(quantity)")
                .font(.headline)
                .frame(minWidth: 30)
            
            Button(action: {
                quantity += 1
                onQuantityChanged(quantity)
            }) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.blue)
            }
        }
    }
}

#Preview("Reorders Header") {
    ReordersHeader(
        itemCount: 5,
        totalQuantity: 15,
        onExport: {},
        onClear: {}
    )
}

#Preview("Reorders Empty State") {
    ReordersEmptyState()
}

#Preview("Reorder Item Card") {
    let sampleItem = ReorderItem(
        id: "1",
        name: "Premium Coffee Beans",
        sku: "COF001",
        quantity: 3,
        lastOrderDate: Date().addingTimeInterval(-86400 * 7)
    )
    
    ReorderItemCard(
        item: sampleItem,
        onRemove: {},
        onUpdateQuantity: { _ in }
    )
    .padding()
}
