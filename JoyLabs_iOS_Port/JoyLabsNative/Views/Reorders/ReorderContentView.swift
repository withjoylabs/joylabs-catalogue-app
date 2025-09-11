import SwiftUI

struct ReorderContentView: View {
    let reorderItems: [ReorderItem]
    let filteredItems: [ReorderItem]
    let organizedItems: [(String, [ReorderItem])]
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption
    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode
    @Binding var scannerSearchText: String
    @FocusState.Binding var isScannerFieldFocused: Bool

    let onManagementAction: (ManagementAction) -> Void
    let onExportTap: () -> Void
    let onStatusChange: (String, ReorderItemStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onBarcodeScanned: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onImageLongPress: (ReorderItem) -> Void
    let onQuantityTap: (SearchResultItem) -> Void
    let onItemDetailsLongPress: (ReorderItem) -> Void

    var body: some View {
        List {
            // Restore the essential scrollable header that I incorrectly removed
            ReordersScrollableHeader(
                totalItems: totalItems,
                unpurchasedItems: unpurchasedItems,
                purchasedItems: purchasedItems,
                totalQuantity: totalQuantity,
                onManagementAction: onManagementAction,
                onExportTap: onExportTap
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            // Filter row as second item
            ReorderFilterRow(
                sortOption: $sortOption,
                filterOption: $filterOption,
                organizationOption: $organizationOption,
                displayMode: $displayMode
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemBackground))
            .listRowSeparator(.hidden)
            
            // Empty state
            if reorderItems.isEmpty {
                ReordersEmptyState()
                    .frame(maxHeight: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                // Group sections with sticky headers
                ForEach(organizedItems, id: \.0) { groupData in
                    let (sectionTitle, items) = groupData
                    
                    Section {
                        // Render items based on display mode
                        if displayMode == .list {
                            // List view - one item per row
                            ForEach(items, id: \.id) { item in
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
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } else {
                            // Photo grid view - needs special handling
                            renderPhotoGrid(items: items, displayMode: displayMode)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        // Sticky group header (only if grouping is enabled)
                        if !sectionTitle.isEmpty {
                            stickyGroupHeader(title: sectionTitle, itemCount: items.count)
                                .listRowInsets(EdgeInsets()) // Make header extend edge-to-edge
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0) // Remove gaps between sections
        .scrollContentBackground(.hidden) // Hide default List background
        .background(Color(.systemBackground)) // Solid background
        .background(Color(.systemBackground), ignoresSafeAreaEdges: .top) // Extend into status bar
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private func stickyGroupHeader(title: String, itemCount: Int) -> some View {
        // Background first, then content with padding
        Color(.systemGray6)
            .overlay(
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
            )
            .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func renderPhotoGrid(items: [ReorderItem], displayMode: ReorderDisplayMode) -> some View {
        let columnCount = displayMode.columnsPerRow
        let spacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
        
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items, id: \.id) { item in
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
        .padding(.horizontal, 16)
        .padding(.vertical, spacing)
    }
    // MARK: - Helper Function
    private func createSearchResultItem(from item: ReorderItem) -> SearchResultItem {
        var images: [CatalogImage] = []
        if let imageUrl = item.imageUrl {
            // Create a simple image structure for display
            // ID can be generated since it's not used for lookups
            let catalogImage = CatalogImage(
                id: item.imageId ?? "img_\(item.itemId)",
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
            reportingCategoryId: nil,
            categoryName: item.categoryName,
            variationName: item.variationName,
            images: images,
            matchType: "reorder",
            matchContext: item.name,
            isFromCaseUpc: false,
            caseUpcData: nil,
            hasTax: item.hasTax
        )
    }
}