import SwiftUI

struct ReorderItemsContent: View {
    let organizedItems: [(String, [ReorderItem])]
    let displayMode: ReorderDisplayMode
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onImageLongPress: (ReorderItem) -> Void
    let onQuantityTap: (SearchResultItem) -> Void
    let onItemDetailsLongPress: (ReorderItem) -> Void

    var body: some View {
        // Capture the callback to avoid scope issues
        let itemDetailsCallback = onItemDetailsLongPress
        
        LazyVStack(spacing: 0) {
            // ELEGANT SOLUTION: Manual rendering to avoid SwiftUI ForEach compiler bug
            if organizedItems.count == 1 {
                // Single section - render directly
                let (_, items) = organizedItems[0]
                renderItemsSection(
                    items: items, 
                    displayMode: displayMode,
                    onStatusChange: onStatusChange,
                    onQuantityChange: onQuantityChange,
                    onRemoveItem: onRemoveItem,
                    onImageTap: onImageTap,
                    onImageLongPress: onImageLongPress,
                    onQuantityTap: onQuantityTap,
                    onItemDetailsLongPress: itemDetailsCallback
                )
            } else if organizedItems.count > 1 {
                // Multiple sections - render each manually
                renderMultipleSections(itemDetailsCallback: itemDetailsCallback)
            }
        }
    }

    // MARK: - Multiple Sections Rendering
    @ViewBuilder
    private func renderMultipleSections(itemDetailsCallback: @escaping (ReorderItem) -> Void) -> some View {
        // Section 1
        if organizedItems.count > 0 {
            let (sectionTitle1, items1) = organizedItems[0]
            if !sectionTitle1.isEmpty {
                sectionHeader(title: sectionTitle1, itemCount: items1.count)
            }
            renderItemsSection(
                items: items1, 
                displayMode: displayMode,
                onStatusChange: onStatusChange,
                onQuantityChange: onQuantityChange,
                onRemoveItem: onRemoveItem,
                onImageTap: onImageTap,
                onImageLongPress: onImageLongPress,
                onQuantityTap: onQuantityTap,
                onItemDetailsLongPress: itemDetailsCallback
            )
        }
        
        // Section 2
        if organizedItems.count > 1 {
            let (sectionTitle2, items2) = organizedItems[1]
            if !sectionTitle2.isEmpty {
                sectionHeader(title: sectionTitle2, itemCount: items2.count)
            }
            renderItemsSection(
                items: items2, 
                displayMode: displayMode,
                onStatusChange: onStatusChange,
                onQuantityChange: onQuantityChange,
                onRemoveItem: onRemoveItem,
                onImageTap: onImageTap,
                onImageLongPress: onImageLongPress,
                onQuantityTap: onQuantityTap,
                onItemDetailsLongPress: itemDetailsCallback
            )
        }
        
        // Section 3 and beyond (if needed)
        if organizedItems.count > 2 {
            let (sectionTitle3, items3) = organizedItems[2]
            if !sectionTitle3.isEmpty {
                sectionHeader(title: sectionTitle3, itemCount: items3.count)
            }
            renderItemsSection(
                items: items3, 
                displayMode: displayMode,
                onStatusChange: onStatusChange,
                onQuantityChange: onQuantityChange,
                onRemoveItem: onRemoveItem,
                onImageTap: onImageTap,
                onImageLongPress: onImageLongPress,
                onQuantityTap: onQuantityTap,
                onItemDetailsLongPress: itemDetailsCallback
            )
        }
    }

    // MARK: - Helper Functions
    @ViewBuilder
    private func sectionHeader(title: String, itemCount: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
            Text("\(itemCount) items")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func renderItemsSection(
        items: [ReorderItem], 
        displayMode: ReorderDisplayMode,
        onStatusChange: @escaping (String, ReorderStatus) -> Void,
        onQuantityChange: @escaping (String, Int) -> Void,
        onRemoveItem: @escaping (String) -> Void,
        onImageTap: @escaping (ReorderItem) -> Void,
        onImageLongPress: @escaping (ReorderItem) -> Void,
        onQuantityTap: @escaping (SearchResultItem) -> Void,
        onItemDetailsLongPress: @escaping (ReorderItem) -> Void
    ) -> some View {
        switch displayMode {
        case .list:
            renderListView(
                items: items,
                onStatusChange: onStatusChange,
                onQuantityChange: onQuantityChange,
                onRemoveItem: onRemoveItem,
                onImageTap: onImageTap,
                onImageLongPress: onImageLongPress,
                onQuantityTap: onQuantityTap,
                onItemDetailsLongPress: onItemDetailsLongPress
            )

        case .photosLarge, .photosMedium, .photosSmall:
            renderPhotoGridView(
                items: items,
                displayMode: displayMode,
                onStatusChange: onStatusChange,
                onQuantityChange: onQuantityChange,
                onRemoveItem: onRemoveItem,
                onImageLongPress: onImageLongPress,
                onQuantityTap: onQuantityTap,
                onItemDetailsLongPress: onItemDetailsLongPress
            )
        }
    }
    
    // MARK: - List View Rendering
    @ViewBuilder
    private func renderListView(
        items: [ReorderItem],
        onStatusChange: @escaping (String, ReorderStatus) -> Void,
        onQuantityChange: @escaping (String, Int) -> Void,
        onRemoveItem: @escaping (String) -> Void,
        onImageTap: @escaping (ReorderItem) -> Void,
        onImageLongPress: @escaping (ReorderItem) -> Void,
        onQuantityTap: @escaping (SearchResultItem) -> Void,
        onItemDetailsLongPress: @escaping (ReorderItem) -> Void
    ) -> some View {
        ForEach(items, id: \.id) { (item: ReorderItem) in
            SwipeableReorderCard(
                item: item,
                displayMode: displayMode,
                onStatusChange: { newStatus in
                    onStatusChange(item.id, newStatus)
                },
                onQuantityChange: { newQuantity in
                    onQuantityChange(item.id, newQuantity)
                },
                onQuantityTap: {
                    let searchItem = createSearchResultItem(from: item)
                    onQuantityTap(searchItem)
                },
                onRemove: {
                    onRemoveItem(item.id)
                },
                onImageTap: {
                    onImageTap(item)
                },
                onImageLongPress: { _ in
                    onImageLongPress(item)
                },
                onItemDetailsLongPress: { _ in
                    onItemDetailsLongPress(item)
                }
            )
        }
    }
    
    // MARK: - Photo Grid View Rendering
    @ViewBuilder
    private func renderPhotoGridView(
        items: [ReorderItem],
        displayMode: ReorderDisplayMode,
        onStatusChange: @escaping (String, ReorderStatus) -> Void,
        onQuantityChange: @escaping (String, Int) -> Void,
        onRemoveItem: @escaping (String) -> Void,
        onImageLongPress: @escaping (ReorderItem) -> Void,
        onQuantityTap: @escaping (SearchResultItem) -> Void,
        onItemDetailsLongPress: @escaping (ReorderItem) -> Void
    ) -> some View {
        let columnCount = displayMode.columnsPerRow
        let spacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
        
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items, id: \.id) { (item: ReorderItem) in
                ReorderPhotoCard(
                    item: item,
                    displayMode: displayMode,
                    onStatusChange: { newStatus in
                        onStatusChange(item.id, newStatus)
                    },
                    onQuantityChange: { newQuantity in
                        onQuantityChange(item.id, newQuantity)
                    },
                    onRemove: {
                        onRemoveItem(item.id)
                    },
                    onImageTap: {
                        // Image tap toggles bought status (handled in ReorderPhotoCard)
                    },
                    onImageLongPress: { _ in
                        onImageLongPress(item)
                    },
                    onItemDetailsTap: {
                        let searchItem = createSearchResultItem(from: item)
                        onQuantityTap(searchItem)
                    },
                    onItemDetailsLongPress: { item in
                        onItemDetailsLongPress(item)
                    }
                )
            }
        }
        .id("photo-grid-\(displayMode.rawValue)")
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helper Function
    private func createSearchResultItem(from item: ReorderItem) -> SearchResultItem {
        var images: [CatalogImage] = []
        if let imageUrl = item.imageUrl, let imageId = item.imageId {
            let catalogImage = CatalogImage(
                id: imageId,
                type: "IMAGE",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: nil,
                isDeleted: false,
                presentAtAllLocations: true,
                imageData: ImageData(
                    name: nil,
                    url: imageUrl,
                    caption: nil,
                    photoStudioOrderId: nil
                )
            )
            images = [catalogImage]
        }

        return SearchResultItem(
            id: item.itemId,
            name: item.name,
            sku: item.sku,
            price: item.price,
            barcode: item.barcode,
            categoryId: nil,
            categoryName: item.categoryName,
            images: images,
            matchType: "reorder",
            matchContext: item.name,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: item.hasTax
        )
    }
}