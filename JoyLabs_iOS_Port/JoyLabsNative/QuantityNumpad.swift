import SwiftUI

struct QuantityNumpad: View {
    @Binding var currentQuantity: Int
    
    // Grid layout for numpad
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    var body: some View {
        VStack(spacing: 12) {
            // Number grid (1-9)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...9, id: \.self) { number in
                    NumpadButton(
                        text: "\(number)",
                        action: {
                            handleNumberInput(number)
                        }
                    )
                }
            }
            
            // Bottom row: Clear, 0, Done
            HStack(spacing: 12) {
                NumpadButton(
                    text: "Clear",
                    action: {
                        currentQuantity = 1
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
        .padding(.horizontal, 20)
    }
    
    private func handleNumberInput(_ number: Int) {
        if currentQuantity == 0 {
            currentQuantity = number
        } else {
            // Append digit (up to reasonable limit)
            let newQuantity = currentQuantity * 10 + number
            if newQuantity <= 9999 { // Reasonable limit
                currentQuantity = newQuantity
            }
        }
    }
    
    private func handleBackspace() {
        if currentQuantity > 9 {
            currentQuantity = currentQuantity / 10
        } else {
            currentQuantity = 1 // Don't go below 1
        }
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
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isSpecial ? .blue : .primary)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.1), value: false)
    }
}

#Preview("Quantity Numpad") {
    QuantityNumpad(currentQuantity: .constant(1))
        .padding()
}
