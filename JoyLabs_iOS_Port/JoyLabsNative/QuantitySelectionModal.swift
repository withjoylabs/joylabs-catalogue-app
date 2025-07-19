import SwiftUI

// MARK: - Quantity Selection Modal
struct EmbeddedQuantitySelectionModal: View {
    let item: SearchResultItem
    let currentQuantity: Int
    let isExistingItem: Bool
    
    @Binding var isPresented: Bool
    @State private var quantity: String
    @State private var hasUserInput: Bool = false
    
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
        self.currentQuantity = currentQuantity
        self.isExistingItem = isExistingItem
        self._isPresented = isPresented
        self._quantity = State(initialValue: String(currentQuantity))
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissModal()
                }
            
            // Modal content
            VStack(spacing: 0) {
                Spacer()
                
                // Main modal container
                VStack(spacing: 20) {
                    // Drag indicator
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(.systemGray3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                    
                    // Item image and details
                    itemDetailsSection
                    
                    // Existing item notification
                    if isExistingItem {
                        existingItemNotification
                    }
                    
                    // Quantity input section
                    quantityInputSection
                    
                    // Action buttons
                    actionButtonsSection
                    
                    // Bottom safe area padding
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 20)
                }
                .background(Color(.systemBackground))
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismissModal()
                    }
                }
        )
    }
    
    // MARK: - Item Details Section
    private var itemDetailsSection: some View {
        VStack(spacing: 12) {
            // Item image
            itemImageView
                .frame(width: 120, height: 120)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // Item name
            Text(item.name ?? "Unknown Item")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 20)
            
            // Item details
            VStack(spacing: 4) {
                if let category = item.categoryName, !category.isEmpty {
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
        .padding(.horizontal, 20)
    }
    
    // MARK: - Item Image View
    private var itemImageView: some View {
        Group {
            if let images = item.images,
               let firstImage = images.first,
               let imageData = firstImage.imageData,
               let imageUrl = imageData.url,
               !imageUrl.isEmpty {
                CachedImageView(imageURL: imageUrl)
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // Placeholder with first two letters
                PlaceholderImageView(itemName: item.name ?? "Unknown")
            }
        }
    }
    
    // MARK: - Existing Item Notification
    private var existingItemNotification: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 16))
            
            Text("Item already in list")
                .font(.subheadline)
                .foregroundColor(.blue)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Quantity Input Section
    private var quantityInputSection: some View {
        VStack(spacing: 16) {
            // Quantity label and display
            VStack(spacing: 8) {
                Text("Quantity")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Quantity display
                Text(quantity.isEmpty ? "0" : quantity)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            
            // Quantity numpad
            QuantityNumpad(
                quantity: $quantity,
                hasUserInput: $hasUserInput,
                onQuantityChange: { newQuantity in
                    quantity = newQuantity
                }
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Action Buttons
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: dismissModal) {
                Text("Cancel")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
            
            // Submit button
            Button(action: submitQuantity) {
                Text("Add to List")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Methods
    private func dismissModal() {
        isPresented = false
        onCancel()
    }
    
    private func submitQuantity() {
        let qty = Int(quantity) ?? 0
        onSubmit(qty)
        isPresented = false
    }
    
    private func formatPrice(_ price: Int) -> String {
        let dollars = Double(price) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - Placeholder Image View
struct PlaceholderImageView: View {
    let itemName: String

    private var initials: String {
        let cleanName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle empty or invalid names
        guard !cleanName.isEmpty else {
            return "??"
        }

        // Split by spaces and filter out empty strings
        let words = cleanName.split(separator: " ").filter { !$0.isEmpty }

        if words.count >= 2 {
            // Two or more words: take first letter of first two words
            let first = String(words[0].prefix(1)).uppercased()
            let second = String(words[1].prefix(1)).uppercased()
            return first + second
        } else if let firstWord = words.first {
            // Single word: take first two characters
            if firstWord.count >= 2 {
                return String(firstWord.prefix(2)).uppercased()
            } else {
                // Single character: duplicate it
                return String(firstWord.prefix(1)).uppercased() + String(firstWord.prefix(1)).uppercased()
            }
        } else {
            return "??"
        }
    }

    // Color based on first character for consistency
    private var backgroundColor: Color {
        let firstChar = itemName.first?.lowercased() ?? "a"
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .red, .pink,
            .indigo, .teal, .mint, .cyan, .brown, .gray
        ]

        let index = firstChar.unicodeScalars.first?.value ?? 97
        return colors[Int(index) % colors.count]
    }

    var body: some View {
        ZStack {
            backgroundColor
                .opacity(0.8)

            Text(initials)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview
#Preview("Quantity Selection Modal") {
    EmbeddedQuantitySelectionModal(
        item: SearchResultItem(
            id: "preview",
            name: "Sample Product Name",
            sku: "SKU123",
            price: 12.99,
            barcode: nil,
            categoryId: "cat1",
            categoryName: "Sample Category",
            images: nil,
            matchType: "name",
            matchContext: nil,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: false
        ),
        currentQuantity: 1,
        isExistingItem: false,
        isPresented: .constant(true),
        onSubmit: { qty in
            print("Submitted quantity: \(qty)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
