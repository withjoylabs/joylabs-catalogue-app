import SwiftUI

struct EmbeddedQuantitySelectionModal: View {
    let item: SearchResultItem
    let initialQuantity: Int
    let isExistingItem: Bool
    
    @Binding var isPresented: Bool
    @State private var currentQuantity: Int
    
    let onSubmit: (Int) -> Void
    let onCancel: () -> Void
    let onQuantityChange: ((Int) -> Void)?

    init(
        item: SearchResultItem,
        currentQuantity: Int = 1,
        isExistingItem: Bool = false,
        isPresented: Binding<Bool>,
        onSubmit: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void,
        onQuantityChange: ((Int) -> Void)? = nil
    ) {
        self.item = item
        self.initialQuantity = currentQuantity
        self.isExistingItem = isExistingItem
        self._isPresented = isPresented
        self._currentQuantity = State(initialValue: currentQuantity)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onQuantityChange = onQuantityChange
    }
    
    var body: some View {
        print("🚨 DEBUG: EmbeddedQuantitySelectionModal body rendering for: \(item.name ?? "Unknown")")
        print("🚨 DEBUG: Modal isPresented: \(isPresented)")
        print("🚨 DEBUG: Modal currentQuantity: \(currentQuantity)")
        print("🚨 DEBUG: Modal isExistingItem: \(isExistingItem)")

        return modalContent
        .onChange(of: currentQuantity) { _, newQuantity in
            onQuantityChange?(newQuantity)
        }
        .onChange(of: item.id) { _, newItemId in
            // RESET MODAL STATE WHEN ITEM CHANGES (CHAIN SCANNING)
            print("🔄 MODAL RESET: Item changed to \(item.name ?? "Unknown"), resetting quantity to \(initialQuantity)")
            currentQuantity = initialQuantity
            onQuantityChange?(initialQuantity)
        }
    }

    // MARK: - Computed Properties for Clean Architecture
    private var modalContent: some View {
        GeometryReader { geometry in
            NavigationView {
                ScrollView {
                    VStack(spacing: 6) {
                        itemThumbnailSection(geometry: geometry)
                        itemDetailsSection
                        quantitySection
                        Spacer(minLength: 20)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Add to Reorder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .font(.headline)
                        .foregroundColor(.red)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(currentQuantity == 0 ? "Delete" : "Add") {
                            onSubmit(currentQuantity)
                        }
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(currentQuantity == 0 ? .red : .blue)
                    }
                }
            }
        }
    }

    private func itemThumbnailSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // RESPONSIVE THUMBNAIL - 70% SCREEN WIDTH
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray6), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: geometry.size.width * 0.7,
                    height: geometry.size.width * 0.5
                )
                .overlay(
                    Text(String(item.name?.prefix(2) ?? "??").uppercased())
                        .font(.system(size: geometry.size.width * 0.08, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }

    private var itemDetailsSection: some View {
        VStack(spacing: 6) {
            // ITEM NAME WITH WORD WRAPPING
            Text(item.name ?? "Unknown Item")
                .font(.headline)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.primary)

            // SINGLE LINE: Category | UPC | SKU | Price
            HStack(spacing: 8) {
                // CATEGORY BADGE
                if let category = item.categoryName {
                    Text(category)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }

                // UPC (NO LABEL - EASILY INFERRED)
                if let barcode = item.barcode, !barcode.isEmpty {
                    Text(barcode)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // SKU
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU: \(sku)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // PRICE
                if let price = item.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    private var quantitySection: some View {
        VStack(spacing: 16) {
            // 3-COLUMN QTY LAYOUT ALIGNED WITH NUMPAD
            HStack(spacing: 0) {
                // COLUMN 1: "QTY" RIGHT JUSTIFIED
                HStack {
                    Spacer()
                    Text("QTY")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)

                // COLUMN 2: QUANTITY NUMBER CENTERED
                HStack {
                    Spacer()
                    Text("\(currentQuantity)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                // COLUMN 3: "ALREADY IN LIST" LEFT JUSTIFIED
                HStack {
                    if isExistingItem {
                        Text("(Already in list)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            // COMPACT NUMPAD
            QuantityNumpad(currentQuantity: $currentQuantity, itemId: item.id)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}
