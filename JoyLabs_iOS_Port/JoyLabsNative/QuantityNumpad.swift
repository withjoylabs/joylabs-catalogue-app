import SwiftUI

struct QuantityNumpad: View {
    @Binding var currentQuantity: Int
    @State private var isFirstInput = true // Track if this is the first input after opening modal

    // Grid layout for numpad
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    var body: some View {
        VStack(spacing: 8) {
            // Number grid (1-9) - COMPACT
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...9, id: \.self) { number in
                    NumpadButton(
                        text: "\(number)",
                        action: {
                            handleNumberInput(number)
                        }
                    )
                }
            }

            // Bottom row: Clear, 0, Backspace - COMPACT
            HStack(spacing: 8) {
                NumpadButton(
                    text: "Clear",
                    action: {
                        currentQuantity = 0 // Clear sets to 0 (which will delete item)
                        isFirstInput = true
                    },
                    isSpecial: true
                )

                NumpadButton(
                    text: "0",
                    action: {
                        handleNumberInput(0)
                    }
                )

                NumpadButton(
                    text: "⌫",
                    action: {
                        handleBackspace()
                    },
                    isSpecial: true
                )
            }
        }
        .onAppear {
            isFirstInput = true // Reset first input flag when numpad appears
        }
    }
    
    private func handleNumberInput(_ number: Int) {
        if isFirstInput {
            // First input after opening modal - replace current quantity
            currentQuantity = number
            isFirstInput = false
        } else if currentQuantity == 0 {
            // If quantity is 0 (cleared), set to the number
            currentQuantity = number
        } else {
            // Append digit (up to 9999 limit)
            let newQuantity = currentQuantity * 10 + number
            if newQuantity <= 9999 { // Max 4 digits
                currentQuantity = newQuantity
            }
        }
    }
    
    private func handleBackspace() {
        isFirstInput = false // No longer first input after backspace

        if currentQuantity > 9 {
            currentQuantity = currentQuantity / 10
        } else if currentQuantity > 0 {
            currentQuantity = 0 // Allow clearing to 0 (which will delete item)
        }
        // If already 0, stay at 0
    }
}

struct NumpadButton: View {
    let text: String
    let action: () -> Void
    let isSpecial: Bool

    init(text: String, action: @escaping () -> Void, isSpecial: Bool = false) {
        self.text = text
        self.action = action
        self.isSpecial = isSpecial
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isSpecial ? .blue : .primary)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview("Quantity Numpad") {
    QuantityNumpad(currentQuantity: .constant(1))
        .padding()
}
