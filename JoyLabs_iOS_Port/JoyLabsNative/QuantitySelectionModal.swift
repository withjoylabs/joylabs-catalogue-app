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
        NavigationView {
            VStack(spacing: 24) {
                // Item Information
                VStack(spacing: 16) {
                    // Item image placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(String(item.name?.prefix(2) ?? "??").uppercased())
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        )
                    
                    // Item details
                    VStack(spacing: 8) {
                        Text(item.name ?? "Unknown Item")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        if let category = item.categoryName {
                            Text(category)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let sku = item.sku, !sku.isEmpty {
                            Text("SKU: \(sku)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let price = item.price {
                            Text("$\(price, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.top, 20)
                
                // Existing item notification
                if isExistingItem {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Item already in list. Current quantity: \(initialQuantity)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Quantity Section
                VStack(spacing: 16) {
                    Text("Select Quantity")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    // Quantity display
                    Text("\(currentQuantity)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(minWidth: 100)
                    
                    // Quantity controls
                    HStack(spacing: 20) {
                        Button(action: { 
                            if currentQuantity > 1 { currentQuantity -= 1 }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(currentQuantity > 1 ? .blue : .gray)
                        }
                        .disabled(currentQuantity <= 1)
                        
                        Button(action: { currentQuantity += 1 }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Add to Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onSubmit(currentQuantity)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
