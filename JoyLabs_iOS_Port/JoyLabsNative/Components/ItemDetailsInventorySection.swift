import SwiftUI

// MARK: - Item Details Inventory Section
/// Displays inventory information for each variation (stock on hand, committed, available to sell)
/// Positioned between pricing section and next section as per requirements
struct ItemDetailsInventorySection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared

    // State for showing adjustment modal
    @State private var showingAdjustmentModal = false
    @State private var selectedVariationId: String?
    @State private var selectedLocationId: String?

    var body: some View {
        // Only show if field visibility is enabled
        if configManager.currentConfiguration.inventoryFields.showInventorySection {
            ItemDetailsSection(title: "Inventory", icon: "shippingbox") {
                ItemDetailsCard {
                    VStack(spacing: 0) {
                        // Show inventory for each variation
                        ForEach(Array(viewModel.variations.enumerated()), id: \.offset) { index, variation in
                            if let variationId = variation.id {
                                VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                                    // Variation name header (if multiple variations)
                                    if viewModel.variations.count > 1 {
                                        HStack {
                                            Text(variation.name ?? "Variation \(index + 1)")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, index == 0 ? 0 : ItemDetailsSpacing.compactSpacing)
                                    }

                                    // Inventory rows for each location
                                    ForEach(viewModel.availableLocations, id: \.id) { location in
                                        if let locationId = location.id {
                                            InventoryRow(
                                                variationId: variationId,
                                                locationId: locationId,
                                                locationName: location.name ?? "Unknown Location",
                                                inventoryData: viewModel.getInventoryData(
                                                    variationId: variationId,
                                                    locationId: locationId
                                                ),
                                                onTap: {
                                                    selectedVariationId = variationId
                                                    selectedLocationId = locationId
                                                    showingAdjustmentModal = true
                                                }
                                            )
                                        }
                                    }
                                }

                                // Divider between variations (if multiple)
                                if index < viewModel.variations.count - 1 {
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(height: 0.5)
                                        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                                }
                            }
                        }

                        // Loading indicator
                        if viewModel.isLoadingInventory {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Loading inventory...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        }

                        // Premium feature message if not enabled
                        if !viewModel.inventoryEnabled && !viewModel.isLoadingInventory {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.orange)
                                Text("Inventory tracking requires Square Premium")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        }
                    }
                    .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                }
            }
            .sheet(isPresented: $showingAdjustmentModal) {
                if let variationId = selectedVariationId,
                   let locationId = selectedLocationId {
                    InventoryAdjustmentModal(
                        viewModel: viewModel,
                        variationId: variationId,
                        locationId: locationId,
                        onDismiss: {
                            showingAdjustmentModal = false
                        }
                    )
                    .nestedComponentModal()
                }
            }
        }
    }
}

// MARK: - Inventory Row
/// Single row showing stock on hand, committed, and available to sell
private struct InventoryRow: View {
    let variationId: String
    let locationId: String
    let locationName: String
    let inventoryData: VariationInventoryData?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Location name (if multiple locations)
                if locationName != "Default Location" {
                    Text(locationName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                }

                Spacer()

                // Three columns: Stock on Hand | Committed | Available to Sell
                HStack(spacing: 24) {
                    // Stock on Hand
                    InventoryColumn(
                        label: "Stock on hand",
                        value: inventoryData?.displayStockOnHand ?? "N/A",
                        isNA: inventoryData?.stockOnHand == nil
                    )

                    // Committed
                    InventoryColumn(
                        label: "Committed",
                        value: inventoryData?.displayCommitted ?? "0",
                        isNA: false
                    )

                    // Available to Sell
                    InventoryColumn(
                        label: "Available to sell",
                        value: inventoryData?.displayAvailableToSell ?? "N/A",
                        isNA: inventoryData?.availableToSell == nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, ItemDetailsSpacing.minimalSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Inventory Column
/// Single column in the inventory row (label above value)
private struct InventoryColumn: View {
    let label: String
    let value: String
    let isNA: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 14, weight: isNA ? .regular : .semibold))
                .foregroundColor(isNA ? .secondary : .primary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject private var viewModel: ItemDetailsViewModel

        init() {
            let vm = ItemDetailsViewModel()
            _viewModel = StateObject(wrappedValue: vm)

            // Setup mock data
            var variation1 = ItemDetailsVariationData()
            variation1.id = "var1"
            variation1.name = "Small"

            var variation2 = ItemDetailsVariationData()
            variation2.id = "var2"
            variation2.name = "Large"

            vm.variations = [variation1, variation2]

            vm.availableLocations = [
                LocationData(
                    id: "loc1",
                    name: "Main Store",
                    address: nil,
                    timezone: nil,
                    capabilities: nil,
                    status: nil,
                    createdAt: nil,
                    merchantId: nil,
                    country: nil,
                    languageCode: nil,
                    currency: nil,
                    phoneNumber: nil,
                    businessName: nil,
                    type: nil,
                    businessHours: nil,
                    businessEmail: nil,
                    description: nil,
                    twitterUsername: nil,
                    instagramUsername: nil,
                    facebookUrl: nil,
                    coordinates: nil,
                    logoUrl: nil,
                    posBackgroundUrl: nil,
                    mcc: nil,
                    fullFormatLogoUrl: nil,
                    taxIds: nil
                )
            ]

            vm.inventoryData = [
                "var1_loc1": VariationInventoryData(
                    variationId: "var1",
                    locationId: "loc1",
                    stockOnHand: 50,
                    committed: 5,
                    availableToSell: 45
                ),
                "var2_loc1": VariationInventoryData(
                    variationId: "var2",
                    locationId: "loc1",
                    stockOnHand: nil,
                    committed: nil,
                    availableToSell: nil
                )
            ]

            vm.inventoryEnabled = true
        }

        var body: some View {
            ScrollView {
                ItemDetailsInventorySection(viewModel: viewModel)
                    .padding()
            }
            .background(Color(.systemBackground))
        }
    }

    return PreviewWrapper()
}
