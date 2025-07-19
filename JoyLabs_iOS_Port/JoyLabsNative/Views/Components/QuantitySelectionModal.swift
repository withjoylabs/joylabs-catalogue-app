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
                VStack(spacing: 0) {
                    // Item Information Section
                    VStack(spacing: 20) {
                        // RESPONSIVE THUMBNAIL - 70% SCREEN WIDTH
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color(.systemGray6), Color(.systemGray5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * 0.7,
                                height: geometry.size.width * 0.7
                            )
                            .overlay(
                                Text(String(item.name?.prefix(2) ?? "??").uppercased())
                                    .font(.system(size: geometry.size.width * 0.12, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                        // Item details with better styling
                        VStack(spacing: 8) {
                            Text(item.name ?? "Unknown Item")
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundColor(.primary)

                            if let category = item.categoryName {
                                Text(category)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            HStack(spacing: 16) {
                                if let sku = item.sku, !sku.isEmpty {
                                    Text("SKU: \(sku)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }

                                if let price = item.price {
                                    Text("$\(price, specifier: "%.2f")")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                    // Existing item notification with better styling
                    if isExistingItem {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text("Item already in list. Current quantity: \(initialQuantity)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }

                    // Quantity Section with better styling
                    VStack(spacing: 20) {
                        Text("Select Quantity")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        // Quantity display with modern styling
                        Text("\(currentQuantity)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(minWidth: 100)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .stroke(Color(.systemGray4), lineWidth: 2)
                            )

                        // NUMPAD
                        QuantityNumpad(currentQuantity: $currentQuantity)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 24)

                    Spacer()
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
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }
}
