import SwiftUI

// MARK: - Display Name Formatting
private func formatDisplayName(itemName: String?, variationName: String?) -> String {
    let name = itemName ?? "Unknown Item"
    if let variation = variationName, !variation.isEmpty {
        return "\(name) • \(variation)"
    }
    return name
}

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
        modalContent
            .onChange(of: currentQuantity) { _, newQuantity in
                onQuantityChange?(newQuantity)
            }
            .onChange(of: item.id) { _, newItemId in
                // RESET MODAL STATE WHEN ITEM CHANGES (CHAIN SCANNING)
                currentQuantity = initialQuantity
                onQuantityChange?(initialQuantity)
            }
    }

    // MARK: - Computed Properties for Clean Architecture
    private var modalContent: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .font(.headline)
                .foregroundColor(.red)

                Spacer()

                Text("Add to Reorder")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(currentQuantity == 0 ? "Delete" : "Add") {
                    onSubmit(currentQuantity)
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(currentQuantity == 0 ? .red : .blue)
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                Divider()
                    .frame(maxWidth: .infinity, maxHeight: 1)
                    .background(Color(.separator)),
                alignment: .bottom
            )

            ScrollView {
                VStack(spacing: 0) {
                    itemThumbnailSection
                    itemDetailsSection
                    quantitySection
                    Spacer(minLength: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var itemThumbnailSection: some View {
        GeometryReader { geometry in
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            let padding: CGFloat = 32 // 16 on each side
            let containerWidth = geometry.size.width
            let imageSize = isIPad ? min(280, containerWidth * 0.7) : containerWidth - padding

            VStack(spacing: 12) {
                // Use zoomable image with pinch-to-zoom functionality
                ZoomableImageView(
                    imageId: imageId,
                    size: imageSize
                )
                .frame(width: imageSize, height: imageSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 312 : 360)
    }

    private var itemDetailsSection: some View {
        VStack(spacing: 6) {
            // ITEM NAME WITH VARIATION AND WORD WRAPPING
            Text(formatDisplayName(itemName: item.name, variationName: item.variationName))
                .font(.headline)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.primary)

            // SINGLE LINE: Category | UPC | SKU | Price - CENTERED
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
                        .foregroundColor(Color.secondary)
                }

                // SKU
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU: \(sku)")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }

                // PRICE
                if let price = item.price {
                    Text("$\(price, specifier: "%.2f")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    private var imageId: String? {
        return item.images?.first?.id
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
        .frame(maxHeight: .infinity)
        .padding(.top, 8)
    }
}
