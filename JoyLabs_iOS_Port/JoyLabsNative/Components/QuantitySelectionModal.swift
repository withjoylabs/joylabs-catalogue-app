import SwiftUI

struct EmbeddedQuantitySelectionModal: View {
    let item: SearchResultItem
    let initialQuantity: Int
    let isExistingItem: Bool
    
    @Binding var isPresented: Bool
    @State private var currentQuantity: Int
    
    let onSubmit: (Int) -> Void
    let onCancel: () -> Void
    
    init(
        item: SearchResultItem,
        currentQuantity: Int = 1,
        isExistingItem: Bool = false,
        isPresented: Binding<Bool>,
        onSubmit: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.initialQuantity = currentQuantity
        self.isExistingItem = isExistingItem
        self._isPresented = isPresented
        self._currentQuantity = State(initialValue: currentQuantity)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ScrollView {
                    VStack(spacing: 12) {
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

                        // ULTRA COMPACT Quantity Section - ONE LINE
                        VStack(spacing: 8) {
                            // SINGLE LINE: "Select Quantity" + Number + Warning
                            HStack(spacing: 12) {
                                Text("Qty:")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)

                                // Quantity display
                                Text("\(currentQuantity)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: 50)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemBackground))
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )

                                // INLINE warning if existing item
                                if isExistingItem {
                                    HStack(spacing: 4) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Text("In list: \(initialQuantity)")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            // COMPACT NUMPAD
                            QuantityNumpad(currentQuantity: $currentQuantity)
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
                        Button("Add") {
                            onSubmit(currentQuantity)
                        }
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}
