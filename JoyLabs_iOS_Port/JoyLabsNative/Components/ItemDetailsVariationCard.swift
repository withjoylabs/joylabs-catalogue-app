import SwiftUI
import SwiftData

// MARK: - Item Details Variation Card
struct ItemDetailsVariationCard: View {
    @Binding var variation: ItemDetailsVariationData
    let index: Int
    let onDelete: () -> Void
    let onPrint: (ItemDetailsVariationData) -> Void
    let isPrinting: Bool
    let viewModel: ItemDetailsViewModel
    let modelContext: ModelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with proper theming and functionality
            VariationCardHeader(
                index: index,
                variation: variation,
                onDelete: onDelete,
                onPrint: onPrint,
                isPrinting: isPrinting
            )
            
            // Fields with full duplicate detection
            VariationCardFields(
                variation: $variation,
                viewModel: viewModel,
                modelContext: modelContext
            )
            
            // Price section with location overrides
            VariationCardPriceSection(
                variation: $variation,
                viewModel: viewModel
            )
        }
        .background(Color.itemDetailsSectionBackground)
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
    }
}