import SwiftUI
import SwiftData
import UIKit

// MARK: - External Keyboard Handler for Modal
class InventoryKeyboardViewController: UIViewController {
    var onNumberInput: ((Int) -> Void)?
    var onEnter: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onEscape: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Numbers 0-9
        for i in 0...9 {
            commands.append(UIKeyCommand(
                input: "\(i)",
                modifierFlags: [],
                action: #selector(handleNumber(_:))
            ))
        }

        // Enter/Return
        commands.append(UIKeyCommand(
            input: "\r",
            modifierFlags: [],
            action: #selector(handleEnter)
        ))

        // Delete/Backspace
        commands.append(UIKeyCommand(
            input: "\u{8}",
            modifierFlags: [],
            action: #selector(handleBackspace)
        ))

        // Escape
        commands.append(UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(handleEscape)
        ))

        return commands
    }

    @objc private func handleNumber(_ command: UIKeyCommand) {
        if let input = command.input, let digit = Int(input) {
            onNumberInput?(digit)
        }
    }

    @objc private func handleEnter() {
        onEnter?()
    }

    @objc private func handleBackspace() {
        onBackspace?()
    }

    @objc private func handleEscape() {
        onEscape?()
    }
}

// MARK: - SwiftUI Wrapper for Keyboard Handler
struct InventoryKeyboardHandler: UIViewControllerRepresentable {
    @Binding var quantityInput: Int
    let onSave: () -> Void
    let onDismiss: () -> Void
    let maxValue: Int

    func makeUIViewController(context: Context) -> InventoryKeyboardViewController {
        let vc = InventoryKeyboardViewController()

        vc.onNumberInput = { digit in
            let newValue = (quantityInput * 10) + digit
            if newValue <= maxValue {
                quantityInput = newValue
            }
        }

        vc.onBackspace = {
            quantityInput = quantityInput / 10
        }

        vc.onEnter = onSave
        vc.onEscape = onDismiss

        return vc
    }

    func updateUIViewController(_ uiViewController: InventoryKeyboardViewController, context: Context) {
        // Update callbacks in case bindings change
        uiViewController.onNumberInput = { digit in
            let newValue = (quantityInput * 10) + digit
            if newValue <= maxValue {
                quantityInput = newValue
            }
        }

        uiViewController.onBackspace = {
            quantityInput = quantityInput / 10
        }

        uiViewController.onEnter = onSave
        uiViewController.onEscape = onDismiss
    }
}

// MARK: - Inventory Adjustment Modal
/// Modal for adjusting inventory counts with numpad input and image display
/// Matches reorder quantity modal UX pattern
/// Uses @Query for automatic SwiftData reactivity
struct InventoryAdjustmentModal: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    let variationId: String
    let locationId: String
    let onDismiss: () -> Void

    @State private var selectedReason: InventoryAdjustmentReason = .stockReceived
    @State private var quantityInput: Int = 0
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    // SwiftData query for automatic reactivity
    @Query private var inventoryCounts: [InventoryCountModel]

    init(viewModel: ItemDetailsViewModel, variationId: String, locationId: String, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.variationId = variationId
        self.locationId = locationId
        self.onDismiss = onDismiss

        // Query for IN_STOCK count for this variation + location
        let compositeId = "\(variationId)_\(locationId)_IN_STOCK"
        let predicate = #Predicate<InventoryCountModel> { model in
            model.id == compositeId
        }
        _inventoryCounts = Query(filter: predicate)
    }

    private var inventoryCount: InventoryCountModel? {
        inventoryCounts.first
    }

    private var currentStock: Int? {
        inventoryCount?.quantityInt
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

    // Get image ID from viewModel
    private var imageId: String? {
        return viewModel.itemData.imageId
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
        ZStack {
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

            // Invisible keyboard handler
            InventoryKeyboardHandler(
                quantityInput: $quantityInput,
                onSave: {
                    if canSave && !isSaving {
                        saveAdjustment()
                    }
                },
                onDismiss: onDismiss,
                maxValue: 999_999
            )
            .frame(width: 0, height: 0)
            .opacity(0)
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
                imageId: imageId,
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

            // Reason picker (only for existing inventory) - single line
            if hasInventory {
                HStack {
                    Text("Reason")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Spacer()

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

            // Current stock and quantity input - always 3 columns to prevent shifting
            HStack(spacing: 16) {
                // Column 1: Current stock
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

                // Column 2: Input quantity (always visible, center/larger)
                VStack(spacing: 4) {
                    Text(hasInventory ? selectedReason.fieldLabel : "Received")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(quantityInput)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)

                // Column 3: Result (always visible to prevent shifting)
                if hasInventory {
                    VStack(spacing: 4) {
                        Text(selectedReason.isAbsolute ? "Variance" : "New Total")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let newTotal = calculatedNewTotal {
                            if selectedReason.isAbsolute, let varianceValue = variance {
                                Text("\(varianceValue >= 0 ? "+" : "")\(varianceValue)")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(varianceValue >= 0 ? .green : .red)
                            } else {
                                Text("\(newTotal)")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        } else {
                            // Placeholder when no input yet
                            Text("--")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.secondary)
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
                    let counts = try await inventoryService.setInitialStock(
                        variationId: variationId,
                        locationId: locationId,
                        quantity: quantityInput
                    )

                    // Save to database - SwiftData @Query will auto-update UI!
                    let db = SquareAPIServiceFactory.createDatabaseManager().getContext()
                    for countData in counts {
                        _ = InventoryCountModel.createOrUpdate(from: countData, in: db)
                    }
                    try db.save()

                    // Mark inventory as enabled on successful initial stock
                    await MainActor.run {
                        SquareCapabilitiesService.shared.markInventoryAsEnabled()

                        // Auto-switch to stock count mode when initial stock is set (per-location)
                        if let variationIndex = viewModel.variations.firstIndex(where: { $0.id == variationId }) {
                            if !viewModel.variations[variationIndex].isTracking(at: locationId) {
                                viewModel.variations[variationIndex].setTracking(true, at: locationId)
                            }
                        }
                    }
                } else {
                    // For existing inventory, use adjustment
                    // SwiftData @Query automatically updates UI when database changes!
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

            // Note: Inventory data now loaded via @Query from SwiftData
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
