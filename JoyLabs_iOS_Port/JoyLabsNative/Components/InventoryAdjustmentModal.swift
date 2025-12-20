import SwiftUI

// MARK: - Inventory Adjustment Modal
/// Modal for adjusting inventory counts with numpad input and image display
/// Matches reorder quantity modal UX pattern
struct InventoryAdjustmentModal: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    let variationId: String
    let locationId: String
    let onDismiss: () -> Void

    @State private var selectedReason: InventoryAdjustmentReason = .stockReceived
    @State private var quantityInput: Int = 0
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    // Get current inventory data
    private var inventoryData: VariationInventoryData? {
        viewModel.getInventoryData(variationId: variationId, locationId: locationId)
    }

    private var currentStock: Int? {
        inventoryData?.stockOnHand
    }

    private var hasInventory: Bool {
        currentStock != nil
    }

    // Get variation and location info for display
    private var variation: ItemDetailsVariationData? {
        viewModel.variations.first(where: { $0.id == variationId })
    }

    private var location: LocationData? {
        viewModel.availableLocations.first(where: { $0.id == locationId })
    }

    // Get image URL from viewModel
    private var imageURL: String? {
        return viewModel.itemData.imageURL
    }

    // Calculate new total based on reason and input
    private var calculatedNewTotal: Int? {
        guard quantityInput > 0 else { return nil }
        guard let current = currentStock else {
            return quantityInput
        }

        switch selectedReason {
        case .stockReceived, .restockReturn:
            return current + quantityInput
        case .damage, .theft, .loss:
            return max(0, current - quantityInput)
        case .inventoryRecount:
            return quantityInput
        }
    }

    private var variance: Int? {
        guard selectedReason == .inventoryRecount,
              quantityInput > 0,
              let current = currentStock else { return nil }
        return quantityInput - current
    }

    private var canSave: Bool {
        return quantityInput > 0 && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .font(.headline)
                .foregroundColor(.red)

                Spacer()

                if let variation = variation, let location = location {
                    Text("\(variation.name ?? "Unnamed") • \(location.name)")
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button(isSaving ? "Saving..." : "Save") {
                    saveAdjustment()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(canSave ? .blue : .gray)
                .disabled(!canSave)
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
                    // Image section
                    imageSection

                    // Details and input section
                    detailsSection

                    // Numpad section
                    numpadSection

                    Spacer(minLength: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Image Section
    private var imageSection: some View {
        VStack(spacing: 12) {
            // Use screen-based sizing instead of GeometryReader for proper intrinsic size
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            let padding: CGFloat = 32
            let screenWidth = UIScreen.main.bounds.width
            let imageSize = isIPad ? min(280, screenWidth * 0.7) : screenWidth - padding

            ZoomableImageView(
                imageURL: imageURL,
                size: imageSize
            )
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Details Section
    private var detailsSection: some View {
        VStack(spacing: 16) {
            // Item name with variation
            let itemName = viewModel.itemData.name
            if !itemName.isEmpty {
                Text(formatDisplayName(itemName: itemName, variationName: variation?.name))
                    .font(.headline)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .foregroundColor(.primary)
            }

            // Reason picker (only for existing inventory)
            if hasInventory {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reason")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Picker("Reason", selection: $selectedReason) {
                        ForEach(InventoryAdjustmentReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedReason) { _, _ in
                        quantityInput = 0
                    }
                }
                .padding(.horizontal, 16)
            }

            // Current stock and quantity input
            HStack(spacing: 16) {
                if let current = currentStock {
                    VStack(spacing: 4) {
                        Text("Current")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(current)")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 4) {
                    Text(hasInventory ? selectedReason.fieldLabel : "Received")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(quantityInput)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)

                if let newTotal = calculatedNewTotal, hasInventory {
                    VStack(spacing: 4) {
                        Text(selectedReason.isAbsolute ? "Variance" : "New Total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if selectedReason.isAbsolute, let varianceValue = variance {
                            Text("\(varianceValue >= 0 ? "+" : "")\(varianceValue)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(varianceValue >= 0 ? .green : .red)
                        } else {
                            Text("\(newTotal)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    // MARK: - Numpad Section
    private var numpadSection: some View {
        VStack(spacing: 16) {
            QuantityNumpad(currentQuantity: $quantityInput, itemId: variationId)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // Helper function for display name formatting
    private func formatDisplayName(itemName: String, variationName: String?) -> String {
        if let variation = variationName, !variation.isEmpty {
            return "\(itemName) • \(variation)"
        }
        return itemName
    }

    // MARK: - Save Action
    private func saveAdjustment() {
        guard quantityInput > 0 else {
            return
        }

        isSaving = true

        Task {
            do {
                // For N/A (no inventory), use initial stock setup
                if !hasInventory {
                    let inventoryService = SquareAPIServiceFactory.createInventoryService()
                    _ = try await inventoryService.setInitialStock(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: quantityInput
                    )
                    // Reload inventory data in viewModel
                    await viewModel.loadInventoryData()
                } else {
                    // For existing inventory, use adjustment
                    try await viewModel.submitInventoryAdjustment(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: quantityInput,
                        reason: selectedReason
                    )
                }

                await MainActor.run {
                    isSaving = false
                    onDismiss()
                    ToastNotificationService.shared.showSuccess("Inventory updated successfully")
                }

            } catch {
                await MainActor.run {
                    isSaving = false
                    ToastNotificationService.shared.showError("Failed to update inventory: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject private var viewModel: ItemDetailsViewModel
        @State private var showModal = true

        init() {
            let vm = ItemDetailsViewModel()
            _viewModel = StateObject(wrappedValue: vm)

            // Setup mock data
            var variation = ItemDetailsVariationData()
            variation.id = "var1"
            variation.name = "Regular"

            vm.variations = [variation]

            vm.availableLocations = [
                LocationData(
                    id: "loc1",
                    name: "Main Store",
                    address: "123 Main St",
                    isActive: true
                )
            ]

            // With inventory
            vm.inventoryData = [
                "var1_loc1": VariationInventoryData(
                    variationId: "var1",
                    locationId: "loc1",
                    stockOnHand: 50,
                    committed: 5,
                    availableToSell: 45
                )
            ]
        }

        var body: some View {
            Button("Show Modal") {
                showModal = true
            }
            .sheet(isPresented: $showModal) {
                InventoryAdjustmentModal(
                    viewModel: viewModel,
                    variationId: "var1",
                    locationId: "loc1",
                    onDismiss: {
                        showModal = false
                    }
                )
            }
        }
    }

    return PreviewWrapper()
}
