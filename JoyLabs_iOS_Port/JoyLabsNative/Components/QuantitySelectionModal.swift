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
        // Calculate modal width similar to image picker
        let modalWidth = UIDevice.current.userInterfaceIdiom == .pad ? 
            min(UIScreen.main.bounds.width * 0.6, 400) : UIScreen.main.bounds.width
        
        modalContent
        .frame(width: modalWidth)
        .frame(
            minHeight: min(700, UIScreen.main.bounds.height * 0.9),
            maxHeight: UIScreen.main.bounds.height * 0.9
        ) // Responsive to orientation - shrinks in landscape and constrains width on iPad
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
        GeometryReader { outerGeometry in
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
                        itemThumbnailSection(geometry: outerGeometry)
                        itemDetailsSection
                        quantitySection
                        Spacer(minLength: 20)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func itemThumbnailSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // RESPONSIVE 1:1 SQUARE IMAGE
            // On iPhone: Full width minus standard padding (16 on each side)
            // On iPad: Keep 70% width for better proportions
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            let padding: CGFloat = 32 // 16 on each side
            let imageSize = isIPad ? geometry.size.width * 0.7 : geometry.size.width - padding

            // Use zoomable image with pinch-to-zoom functionality
            ZoomableImageView(
                imageURL: imageURL,
                size: imageSize
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 16) // Standard padding to match other elements
        .padding(.top, 16)
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

    private var imageURL: String? {
        return item.images?.first?.imageData?.url
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
