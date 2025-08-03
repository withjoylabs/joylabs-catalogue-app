import SwiftUI

struct ReorderHeaderSection: View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int

    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption
    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode

    let onManagementAction: (ManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats (will collapse on scroll)
            ReordersScrollableHeader(
                totalItems: totalItems,
                unpurchasedItems: unpurchasedItems,
                purchasedItems: purchasedItems,
                totalQuantity: totalQuantity,
                onManagementAction: onManagementAction
            )

            // Filter Row (stays pinned)
            ReorderFilterRow(
                sortOption: $sortOption,
                filterOption: $filterOption,
                organizationOption: $organizationOption,
                displayMode: $displayMode
            )
        }
        .background(Color(.systemBackground))
    }
}