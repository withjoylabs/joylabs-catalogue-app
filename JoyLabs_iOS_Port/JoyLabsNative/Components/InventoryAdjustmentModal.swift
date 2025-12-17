import SwiftUI

// MARK: - Inventory Adjustment Modal
/// Modal for adjusting inventory counts - matches Square Register behavior
/// Shows different UI based on whether inventory exists (N/A vs existing count)
struct InventoryAdjustmentModal: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    let variationId: String
    let locationId: String
    let onDismiss: () -> Void

    @State private var selectedReason: InventoryAdjustmentReason = .stockReceived
    @State private var quantityInput: String = ""
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

    // Calculate new total based on reason and input
    private var calculatedNewTotal: Int? {
        guard let qty = Int(quantityInput), qty > 0 else { return nil }
        guard let current = currentStock else {
            // No inventory yet - only allow initial stock received
            return qty
        }

        switch selectedReason {
        case .stockReceived, .restockReturn:
            return current + qty
        case .damage, .theft, .loss:
            return max(0, current - qty)
        case .inventoryRecount:
            return qty
        }
    }

    private var variance: Int? {
        guard selectedReason == .inventoryRecount,
              let qty = Int(quantityInput),
              let current = currentStock else { return nil }
        return qty - current
    }

    private var canSave: Bool {
        guard let qty = Int(quantityInput), qty > 0 else { return false }
        return !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header - variation and location in one line
            HStack {
                if let variation = viewModel.variations.first(where: { $0.id == variationId }),
                   let location = viewModel.availableLocations.first(where: { $0.id == locationId }) {
                    Text("\(variation.name ?? "Unnamed") • \(location.name)")
                        .font(.itemDetailsBody)
                        .foregroundColor(.itemDetailsPrimaryText)
                }
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .font(.itemDetailsBody)
            }
            .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
            .padding(.vertical, ItemDetailsSpacing.compactSpacing)

            Divider()

            // Content (no ScrollView - fits without scrolling)
            VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                if hasInventory {
                    // EXISTING INVENTORY - Show reason picker
                    inventoryExistsContent
                } else {
                    // NO INVENTORY (N/A) - Simple received input
                    inventoryNAContent
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.itemDetailsFootnote)
                        .foregroundColor(.itemDetailsDestructive)
                        .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                }
            }
            .padding(.vertical, ItemDetailsSpacing.compactSpacing)

            Spacer()

            // Bottom action button
            VStack(spacing: 0) {
                Divider()

                Button(action: saveAdjustment) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Saving...")
                        } else {
                            Text("Save")
                        }
                    }
                    .font(.itemDetailsBody.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(canSave ? Color.itemDetailsAccent : Color.secondary)
                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                    .padding(ItemDetailsSpacing.compactSpacing)
                }
                .disabled(!canSave)
            }
        }
        .presentationDetents([.height(hasInventory ? 420 : 220)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - NO INVENTORY (N/A) Content
    private var inventoryNAContent: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            ItemDetailsFieldLabel(title: "Received")
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)

            TextField("0", text: $quantityInput)
                .keyboardType(.numberPad)
                .font(.itemDetailsBody)
                .multilineTextAlignment(.center)
                .padding(ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsFieldBackground)
                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
        }
    }

    // MARK: - EXISTING INVENTORY Content
    private var inventoryExistsContent: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            // Reason picker - inline style
            ItemDetailsFieldLabel(title: "Reason")
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)

            Picker("Reason", selection: $selectedReason) {
                ForEach(InventoryAdjustmentReason.allCases, id: \.self) { reason in
                    Text(reason.displayName).tag(reason)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
            .onChange(of: selectedReason) { _, _ in
                quantityInput = "" // Reset input on reason change
            }

            // Current stock + Quantity input (side by side)
            HStack(spacing: ItemDetailsSpacing.compactSpacing) {
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    ItemDetailsFieldLabel(title: "Current")
                    Text("\(currentStock ?? 0)")
                        .font(.itemDetailsBody)
                        .foregroundColor(.itemDetailsSecondaryText)
                        .padding(ItemDetailsSpacing.compactSpacing)
                        .frame(maxWidth: .infinity)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                }

                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    ItemDetailsFieldLabel(title: selectedReason.fieldLabel)
                    TextField("0", text: $quantityInput)
                        .keyboardType(.numberPad)
                        .font(.itemDetailsBody)
                        .multilineTextAlignment(.center)
                        .padding(ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                }

                // New total / Variance
                if let newTotal = calculatedNewTotal {
                    VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                        ItemDetailsFieldLabel(title: selectedReason.isAbsolute ? "Variance" : "New Total")
                        if selectedReason.isAbsolute, let varianceValue = variance {
                            Text("\(varianceValue >= 0 ? "+" : "")\(varianceValue)")
                                .font(.itemDetailsBody)
                                .foregroundColor(varianceValue >= 0 ? .itemDetailsSuccess : .itemDetailsDestructive)
                                .padding(ItemDetailsSpacing.compactSpacing)
                                .frame(maxWidth: .infinity)
                                .background(Color.itemDetailsFieldBackground)
                                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        } else {
                            Text("\(newTotal)")
                                .font(.itemDetailsBody)
                                .foregroundColor(.itemDetailsPrimaryText)
                                .padding(ItemDetailsSpacing.compactSpacing)
                                .frame(maxWidth: .infinity)
                                .background(Color.itemDetailsFieldBackground)
                                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        }
                    }
                }
            }
            .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
        }
    }

    // MARK: - Save Action
    private func saveAdjustment() {
        guard let qty = Int(quantityInput), qty > 0 else {
            errorMessage = "Please enter a valid quantity"
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                // For N/A (no inventory), use initial stock setup
                if !hasInventory {
                    let inventoryService = SquareAPIServiceFactory.createInventoryService()
                    _ = try await inventoryService.setInitialStock(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: qty
                    )
                    // Reload inventory data in viewModel
                    await viewModel.loadInventoryData()
                } else {
                    // For existing inventory, use adjustment
                    try await viewModel.submitInventoryAdjustment(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: qty,
                        reason: selectedReason
                    )
                }

                await MainActor.run {
                    isSaving = false
                    onDismiss()

                    // Show success toast
                    ToastNotificationService.shared.showSuccess("Inventory updated successfully")
                }

            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to update inventory: \(error.localizedDescription)"
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
