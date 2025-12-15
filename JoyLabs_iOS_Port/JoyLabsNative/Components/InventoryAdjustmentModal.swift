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
        NavigationView {
            VStack(spacing: 0) {
                // Variation info header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let variation = viewModel.variations.first(where: { $0.id == variationId }) {
                            Text(variation.name ?? "Unnamed Variation")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }

                        if let location = viewModel.availableLocations.first(where: { $0.id == locationId }) {
                            Text(location.name)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(.systemGray6))

                ScrollView {
                    VStack(spacing: 20) {
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
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 20)
                }

                // Bottom action button
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)

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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canSave ? Color.blue : Color.gray)
                        .cornerRadius(10)
                        .padding(16)
                    }
                    .disabled(!canSave)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }

    // MARK: - NO INVENTORY (N/A) Content
    private var inventoryNAContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Initial Stock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Received")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("0", text: $quantityInput)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - EXISTING INVENTORY Content
    private var inventoryExistsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Reason picker
            VStack(alignment: .leading, spacing: 12) {
                Text("Reason")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                ForEach(InventoryAdjustmentReason.allCases, id: \.self) { reason in
                    Button(action: {
                        selectedReason = reason
                        quantityInput = "" // Reset input on reason change
                    }) {
                        HStack {
                            Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedReason == reason ? .blue : .secondary)
                            Text(reason.displayName)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(12)
                        .background(selectedReason == reason ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)

            // Current stock display
            if let current = currentStock {
                HStack {
                    Text("Current Stock")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(current)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }

            // Quantity input
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedReason.fieldLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("0", text: $quantityInput)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)

            // New total / Variance display
            if let newTotal = calculatedNewTotal {
                HStack {
                    Text(selectedReason.isAbsolute ? "Variance" : "New Total")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()

                    if selectedReason.isAbsolute, let varianceValue = variance {
                        HStack(spacing: 4) {
                            Text(varianceValue >= 0 ? "+" : "")
                            Text("\(varianceValue)")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(varianceValue >= 0 ? .green : .red)
                    } else {
                        Text("\(newTotal)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }
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
                    try await inventoryService.setInitialStock(
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
