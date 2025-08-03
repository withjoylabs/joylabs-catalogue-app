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
    let onStatusChange: (String, ReorderStatus) -> Void
    let onQuantityChange: (String, Int) -> Void
    let onRemoveItem: (String) -> Void
    let onBarcodeScanned: (String) -> Void
    let onImageTap: (ReorderItem) -> Void
    let onImageLongPress: (ReorderItem) -> Void
    let onQuantityTap: (SearchResultItem) -> Void
    let onItemDetailsLongPress: (ReorderItem) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            // Content area
                            if reorderItems.isEmpty {
                                ReordersEmptyState()
                                    .frame(maxHeight: .infinity)
                            } else {
                                ReorderItemsContent(
                                    organizedItems: organizedItems,
                                    displayMode: displayMode,
                                    onStatusChange: onStatusChange,
                                    onQuantityChange: onQuantityChange,
                                    onRemoveItem: onRemoveItem,
                                    onImageTap: onImageTap,
                                    onImageLongPress: onImageLongPress,
                                    onQuantityTap: onQuantityTap,
                                    onItemDetailsLongPress: onItemDetailsLongPress
                                )
                            }
                        } header: {
                            ReorderHeaderSection(
                                totalItems: totalItems,
                                unpurchasedItems: unpurchasedItems,
                                purchasedItems: purchasedItems,
                                totalQuantity: totalQuantity,
                                sortOption: $sortOption,
                                filterOption: $filterOption,
                                organizationOption: $organizationOption,
                                displayMode: $displayMode,
                                onManagementAction: onManagementAction
                            )
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .clipped() // Prevent content from bleeding through status bar
            }
        }
        .ignoresSafeArea(.all, edges: []) // Respect safe area boundaries
        // TEXT FIELD REMOVED: Global HID scanner handles all barcode input without focus requirement
    }
}