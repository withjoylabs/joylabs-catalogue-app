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

        return GeometryReader { geometry in
            NavigationView {
                ScrollView {
                    VStack(spacing: 6) { // REDUCED from 12 to 6 - half the margin
                        // COMPACT Item Information Section
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

                            // COMPACT Item details - SINGLE LINE EACH
                            VStack(spacing: 4) {
                                Text(item.name ?? "Unknown Item")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)

                                // SINGLE LINE: Category | SKU | Price
                                HStack(spacing: 8) {
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

                                    if let sku = item.sku, !sku.isEmpty {
                                        Text("SKU: \(sku)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    if let price = item.price {
                                        Text("$\(price, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 16)

                        // QUANTITY SECTION - QTY AND NUMBER ON SAME LINE
                        VStack(spacing: 16) {
                            // QTY LABEL + NUMBER ON SAME LINE
                            HStack(spacing: 8) {
                                Text("QTY")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)

                                Text("\(currentQuantity)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                // EXISTING ITEM WARNING
                                if isExistingItem {
                                    Text("(Already in list)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .fontWeight(.medium)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            // COMPACT NUMPAD
                            QuantityNumpad(currentQuantity: $currentQuantity, itemId: item.id)
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 8)

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
}
