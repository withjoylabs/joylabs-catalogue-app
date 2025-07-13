import SwiftUI

struct ReordersView: View {
    @State private var reorderItems: [ReorderItem] = []
    @State private var showingExportOptions = false
    @State private var showingClearAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                ReordersHeader(
                    itemCount: reorderItems.count,
                    totalQuantity: reorderItems.reduce(0) { $0 + $1.quantity },
                    onExport: { showingExportOptions = true },
                    onClear: { showingClearAlert = true }
                )

                if reorderItems.isEmpty {
                    ReordersEmptyState()
                } else {
                    ReordersListView(
                        items: $reorderItems,
                        onRemoveItem: removeItem,
                        onUpdateQuantity: updateQuantity
                    )
                }

                Spacer()
            }
            .navigationBarHidden(true)
            .onAppear {
                loadMockData()
            }
            .actionSheet(isPresented: $showingExportOptions) {
                ActionSheet(
                    title: Text("Export Reorders"),
                    buttons: [
                        .default(Text("Export as CSV")) { exportAsCSV() },
                        .default(Text("Export as PDF")) { exportAsPDF() },
                        .default(Text("Share List")) { shareList() },
                        .cancel()
                    ]
                )
            }
            .alert("Clear All Reorders", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    reorderItems.removeAll()
                }
            } message: {
                Text("Are you sure you want to clear all reorder items? This action cannot be undone.")
            }
        }
    }

    private func loadMockData() {
        // Load some mock reorder items for demonstration
        reorderItems = [
            ReorderItem(id: "1", name: "Premium Coffee Beans", sku: "COF001", quantity: 5, lastOrderDate: Date().addingTimeInterval(-86400 * 7)),
            ReorderItem(id: "2", name: "Organic Tea Bags", sku: "TEA002", quantity: 3, lastOrderDate: Date().addingTimeInterval(-86400 * 14)),
            ReorderItem(id: "3", name: "Ceramic Mugs Set", sku: "MUG003", quantity: 2, lastOrderDate: Date().addingTimeInterval(-86400 * 21))
        ]
    }

    private func removeItem(at index: Int) {
        reorderItems.remove(at: index)
    }

    private func updateQuantity(for itemId: String, newQuantity: Int) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            reorderItems[index].quantity = max(1, newQuantity)
        }
    }

    private func exportAsCSV() {
        // CSV export functionality
        print("Exporting as CSV...")
    }

    private func exportAsPDF() {
        // PDF export functionality
        print("Exporting as PDF...")
    }

    private func shareList() {
        // Share functionality
        print("Sharing list...")
    }
}

#Preview {
    ReordersView()
}
