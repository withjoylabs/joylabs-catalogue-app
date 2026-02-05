import SwiftUI
import SwiftData

// MARK: - Item Details Pricing Section
/// Handles pricing, variations, SKU, and UPC information
struct ItemDetailsPricingSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    @StateObject private var configManager = FieldConfigurationManager.shared
    let onVariationPrint: (ItemDetailsVariationData, @escaping (Bool) -> Void) -> Void
    @State private var printingVariationIndices = Set<Int>()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ItemDetailsSection(title: "Pricing & Variations", icon: "dollarsign.circle") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.variations.enumerated()), id: \.offset) { index, variation in
                        ItemDetailsVariationCard(
                            variation: Binding(
                                get: {
                                    // Safe bounds checking
                                    guard index < viewModel.variations.count else {
                                        return ItemDetailsVariationData()
                                    }
                                    return viewModel.variations[index]
                                },
                                set: { newValue in
                                    // Safe bounds checking
                                    guard index < viewModel.variations.count else { return }
                                    viewModel.variations[index] = newValue
                                }
                            ),
                            index: index,
                            focusedField: $focusedField,
                            moveToNextField: moveToNextField,
                            onDelete: {
                                // Safe removal with bounds checking
                                guard index < viewModel.variations.count && viewModel.variations.count > 1 else { return }
                                viewModel.variations.remove(at: index)
                            },
                            onPrint: { variation in
                                printingVariationIndices.insert(index)
                                onVariationPrint(variation) { _ in
                                    printingVariationIndices.remove(index)
                                }
                            },
                            isPrinting: printingVariationIndices.contains(index),
                            viewModel: viewModel,
                            modelContext: modelContext
                        )
                        
                        // Add black spacing between variations
                        if index < viewModel.variations.count - 1 {
                            Rectangle()
                                .fill(Color.itemDetailsModalBackground)
                                .frame(height: ItemDetailsSpacing.sectionSpacing)
                        }
                    }
                    
                    // Spacing before Add Variation Button
                    Rectangle()
                        .fill(Color.itemDetailsModalBackground)
                        .frame(height: ItemDetailsSpacing.compactSpacing)
                    
                    // Add Variation Button
                    ItemDetailsFieldRow {
                        ItemDetailsButton(
                            title: "Add Variation",
                            icon: "plus.circle",
                            style: .secondary
                        ) {
                            addNewVariation()
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: ItemDetailsSpacing.sectionCornerRadius,
                        topTrailingRadius: ItemDetailsSpacing.sectionCornerRadius
                    ))
                }
            }
        }
    }

    private func addNewVariation() {
        let newVariation = ItemDetailsVariationData()
        viewModel.variations.append(newVariation)

        // Focus on the new variation's name field
        let newIndex = viewModel.variations.count - 1
        focusedField = .variationName(newIndex)
    }
}