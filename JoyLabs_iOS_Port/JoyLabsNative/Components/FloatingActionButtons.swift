import SwiftUI

// MARK: - Floating Action Buttons
struct FloatingActionButtons: View {
    let onCancel: () -> Void
    let onPrint: () -> Bool // Now returns Bool indicating if ActionSheet needed
    let onSave: () -> Void
    let onSaveAndPrint: () -> Void
    let canSave: Bool
    let availablePrices: [(variationIndex: Int, variationName: String, price: String)]
    let onPriceSelected: (String) -> Void
    let hasChanges: Bool // NEW: Track if user has unsaved changes
    let onForceClose: () -> Void // NEW: Force close without confirmation
    
    @State private var showPriceActionSheet = false
    @State private var showCloseConfirmation = false
    @State private var showSaveAndPrintPriceSheet = false
    @State private var isSaveAndPrintAction = false
    
    var body: some View {
        HStack(spacing: 15) {
            // Cancel Button with confirmation logic
            FloatingButton(
                icon: "xmark",
                color: .gray,
                action: {
                    if hasChanges {
                        showCloseConfirmation = true
                    } else {
                        onCancel()
                    }
                }
            )
            .actionSheet(isPresented: $showCloseConfirmation) {
                ActionSheet(
                    title: Text("Discard Changes?"),
                    message: Text("You have unsaved changes. Are you sure you want to discard them?"),
                    buttons: [
                        .destructive(Text("Discard Changes")) {
                            onForceClose()
                        },
                        .cancel(Text("Keep Editing"))
                    ]
                )
            }
            
            // Print Button with ActionSheet
            FloatingButton(
                icon: "printer",
                color: .blue,
                action: {
                    print("[FAB] Print button tapped")
                    // Call onPrint() which returns Bool indicating if ActionSheet needed
                    let needsActionSheet = onPrint()
                    
                    if needsActionSheet {
                        print("[FAB] ActionSheet needed - showing now")
                        showPriceActionSheet = true
                    } else {
                        print("[FAB] Direct print - no ActionSheet needed")
                    }
                }
            )
            .actionSheet(isPresented: $showPriceActionSheet) {
                ActionSheet(
                    title: Text("Select Price"),
                    message: Text("Choose which price to use for the label"),
                    buttons: availablePrices.map { priceInfo in
                        .default(Text("$\(priceInfo.price) - \(priceInfo.variationName)")) {
                            onPriceSelected(priceInfo.price)
                        }
                    } + [.cancel()]
                )
            }
            
            // Save Button
            FloatingButton(
                icon: "checkmark",
                color: canSave ? .green : .gray,
                action: onSave,
                isDisabled: !canSave
            )
            
            // Save & Print Button
            FloatingButton(
                icon: "printer.filled.and.paper",
                color: canSave ? .purple : .gray,
                action: {
                    // Set flag and call the handler
                    isSaveAndPrintAction = true
                    onSaveAndPrint()
                    // Check if price selection is needed
                    if !availablePrices.isEmpty {
                        showSaveAndPrintPriceSheet = true  // Use separate state
                    }
                },
                isDisabled: !canSave
            )
            .actionSheet(isPresented: $showSaveAndPrintPriceSheet) {
                ActionSheet(
                    title: Text("Select Price"),
                    message: Text("Choose which price to use for the label"),
                    buttons: availablePrices.map { priceInfo in
                        .default(Text("$\(priceInfo.price) - \(priceInfo.variationName)")) {
                            onPriceSelected(priceInfo.price)
                        }
                    } + [.cancel {
                        isSaveAndPrintAction = false
                    }]
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20) // Closer to keyboard
    }
}

// MARK: - Individual Floating Button
struct FloatingButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    let isDisabled: Bool

    init(icon: String, color: Color, action: @escaping () -> Void, isDisabled: Bool = false) {
        self.icon = icon
        self.color = color
        self.action = action
        self.isDisabled = isDisabled
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .fontWeight(.medium)
        }
        .buttonStyle(.glassProminent)  // iOS 26 native Liquid Glass style
        .tint(isDisabled ? Color.gray.opacity(0.5) : color)
        .buttonBorderShape(.circle)
        .controlSize(.large)  // Larger native size
        .disabled(isDisabled)
        .scaleEffect(isDisabled ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDisabled)
    }
}

#Preview {
    VStack {
        Spacer()
        
        FloatingActionButtons(
            onCancel: { print("Cancel") },
            onPrint: { print("Print"); return false },
            onSave: { print("Save") },
            onSaveAndPrint: { print("Save & Print") },
            canSave: true,
            availablePrices: [],
            onPriceSelected: { _ in },
            hasChanges: false,
            onForceClose: { print("Force Close") }
        )
    }
    .background(Color(.systemGray6))
}
