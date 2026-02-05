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
    @Binding var selectedCategories: Set<String>
    let availableCategories: [String]
    @Binding var scannerSearchText: String
    @FocusState.Binding var isScannerFieldFocused: Bool

    // Two-phase display mode: pill uses displayMode (immediate), content uses contentDisplayMode (deferred)
    @State private var contentDisplayMode: ReorderDisplayMode = .list

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
            // Stats header - scrolls away (regular row)
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

            // Main content section — filter row is the sticky header
            Section {
                if reorderItems.isEmpty {
                    ReordersEmptyState()
                        .frame(maxHeight: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(organizedItems, id: \.0) { groupData in
                        let (sectionTitle, items) = groupData

                        // Group header as a styled row
                        if !sectionTitle.isEmpty {
                            stickyGroupHeader(title: sectionTitle, itemCount: items.count)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        // Render items based on display mode (uses contentDisplayMode for deferred swap)
                        if contentDisplayMode == .list {
                            ForEach(items, id: \.id) { item in
                                SwipeableReorderCard(
                                    item: item,
                                    displayMode: contentDisplayMode,
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
                            // Chunked grid rows — each row is its own List row for lazy loading
                            let columnCount = contentDisplayMode.columnsPerRow
                            let gridSpacing: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8

                            ForEach(chunkedItems(items, columns: columnCount), id: \.first!.id) { rowItems in
                                HStack(spacing: gridSpacing) {
                                    ForEach(rowItems, id: \.id) { item in
                                        ReorderPhotoCard(
                                            item: item,
                                            displayMode: contentDisplayMode,
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
                                        .frame(maxWidth: .infinity)
                                    }
                                    // Fill incomplete rows
                                    if rowItems.count < columnCount {
                                        ForEach(0..<(columnCount - rowItems.count), id: \.self) { _ in
                                            Color.clear
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            } header: {
                VStack(spacing: 0) {
                    ReorderFilterRow(
                        sortOption: $sortOption,
                        filterOption: $filterOption,
                        organizationOption: $organizationOption,
                        displayMode: $displayMode,
                        selectedCategories: $selectedCategories,
                        availableCategories: availableCategories
                    )

                    if !selectedCategories.isEmpty {
                        CategoryChipsRow(selectedCategories: $selectedCategories)
                    }
                }
                .textCase(nil)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.hard, for: .all) // Disable iOS 26 soft edge effect that prevents scrolling
        .listSectionSpacing(0) // Remove gaps between sections
        .scrollContentBackground(.hidden) // Hide default List background
        .background(Color(.systemBackground)) // Solid background
        .background(Color(.systemBackground), ignoresSafeAreaEdges: .top) // Extend into status bar
        .onAppear { contentDisplayMode = displayMode }
        .onChange(of: displayMode) { _, newMode in
            // Defer content swap to next frame so pill updates instantly first
            DispatchQueue.main.async {
                contentDisplayMode = newMode
            }
        }
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
    
    private func chunkedItems(_ items: [ReorderItem], columns: Int) -> [[ReorderItem]] {
        guard columns > 0, !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
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