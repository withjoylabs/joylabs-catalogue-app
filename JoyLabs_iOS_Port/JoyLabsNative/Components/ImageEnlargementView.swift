import SwiftUI

// MARK: - Image Enlargement View
struct ImageEnlargementView: View {
    let item: ReorderItem
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        // Enlarged image - takes up shortest dimension for iPad compatibility
                        let imageSize = min(geometry.size.width, geometry.size.height) * 0.8
                        
                        UnifiedImageView.large(
                            imageURL: item.imageUrl,
                            imageId: item.imageId,
                            itemId: item.itemId,
                            size: imageSize
                        )
                        .frame(width: imageSize, height: imageSize)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        // Item details
                        VStack(alignment: .leading, spacing: 16) {
                            // Item name
                            Text(item.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                            
                            // Details grid
                            LazyVGrid(columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)
                            ], spacing: 12) {
                                
                                // SKU
                                if let sku = item.sku, !sku.isEmpty {
                                    DetailItem(title: "SKU", value: sku)
                                }
                                
                                // Barcode
                                if let barcode = item.barcode, !barcode.isEmpty {
                                    DetailItem(title: "Barcode", value: barcode)
                                }
                                
                                // Category
                                if let category = item.categoryName, !category.isEmpty {
                                    DetailItem(title: "Category", value: category)
                                }
                                
                                // Vendor
                                if let vendor = item.vendor, !vendor.isEmpty {
                                    DetailItem(title: "Vendor", value: vendor)
                                }
                                
                                // Price
                                if let price = item.price {
                                    let priceText = String(format: "$%.2f", price) + (item.hasTax ? " +tax" : "")
                                    DetailItem(title: "Price", value: priceText)
                                }
                                
                                // Unit Cost
                                if let unitCost = item.unitCost {
                                    DetailItem(title: "Unit Cost", value: String(format: "$%.2f", unitCost))
                                }
                                
                                // Case UPC
                                if let caseUpc = item.caseUpc, !caseUpc.isEmpty {
                                    DetailItem(title: "Case UPC", value: caseUpc)
                                }
                                
                                // Case Cost
                                if let caseCost = item.caseCost {
                                    DetailItem(title: "Case Cost", value: String(format: "$%.2f", caseCost))
                                }
                                
                                // Case Quantity
                                if let caseQuantity = item.caseQuantity {
                                    DetailItem(title: "Case Qty", value: "\(caseQuantity)")
                                }
                                
                                // Status
                                DetailItem(title: "Status", value: item.status.displayName)
                                
                                // Quantity
                                DetailItem(title: "Quantity", value: "\(item.quantity)")
                            }
                            
                            // Notes
                            if let notes = item.notes, !notes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(notes)
                                        .font(.body)
                                        .foregroundColor(Color.secondary)
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Detail Item Component
struct DetailItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
                .fontWeight(.medium)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview("Image Enlargement") {
    let sampleItem = ReorderItem(
        id: "1",
        itemId: "square-item-1",
        name: "Premium Coffee Beans - Dark Roast Blend",
        sku: "COF001",
        barcode: "1234567890123",
        quantity: 3,
        status: .added
    )
    
    ImageEnlargementView(
        item: sampleItem,
        isPresented: .constant(true)
    )
}
