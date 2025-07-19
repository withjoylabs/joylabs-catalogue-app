import SwiftUI

// MARK: - Quantity Numpad Component
struct QuantityNumpad: View {
    @Binding var quantity: String
    @Binding var hasUserInput: Bool
    
    let onQuantityChange: (String) -> Void
    
    // Grid layout for numpad
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    var body: some View {
        VStack(spacing: 16) {
            // Number grid (1-9)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...9, id: \.self) { number in
                    NumpadButton(
                        text: "\(number)",
                        action: {
                            handleNumberInput("\(number)")
                        }
                    )
                }
            }
            
            // Bottom row (Clear, 0, Delete)
            HStack(spacing: 12) {
                // Clear button
                NumpadButton(
                    text: "Clear",
                    backgroundColor: Color(.systemGray4),
                    textColor: .primary,
                    action: {
                        clearQuantity()
                    }
                )
                
                // Zero button
                NumpadButton(
                    text: "0",
                    action: {
                        handleNumberInput("0")
                    }
                )
                
                // Delete button
                NumpadButton(
                    text: "⌫",
                    backgroundColor: Color(.systemGray4),
                    textColor: .primary,
                    action: {
                        deleteLastDigit()
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Input Handling Methods
    
    private func handleNumberInput(_ digit: String) {
        if !hasUserInput {
            // CRITICAL: First input replaces default quantity (not appends)
            quantity = digit
            hasUserInput = true
            print("🔢 First digit input: '\(digit)' - replaced default quantity")
        } else {
            // Subsequent inputs build the number
            // Prevent leading zeros (except for single zero)
            if quantity == "0" && digit != "0" {
                quantity = digit
            } else if quantity != "0" {
                quantity += digit
            }
            print("🔢 Building number: '\(quantity)'")
        }
        
        // Limit to reasonable quantity (max 999)
        if let numValue = Int(quantity), numValue > 999 {
            quantity = "999"
        }
        
        onQuantityChange(quantity)
    }
    
    private func clearQuantity() {
        quantity = "1"
        hasUserInput = false
        onQuantityChange(quantity)
        print("🔢 Quantity cleared - reset to default: 1")
    }
    
    private func deleteLastDigit() {
        if hasUserInput && quantity.count > 1 {
            quantity.removeLast()
            onQuantityChange(quantity)
            print("🔢 Deleted last digit: '\(quantity)'")
        } else if hasUserInput && quantity.count == 1 {
            // If only one digit left, reset to default
            quantity = "1"
            hasUserInput = false
            onQuantityChange(quantity)
            print("🔢 Last digit deleted - reset to default: 1")
        }
    }
}

// MARK: - Numpad Button Component
struct NumpadButton: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let action: () -> Void
    
    init(
        text: String,
        backgroundColor: Color = .blue,
        textColor: Color = .white,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(backgroundColor)
                .cornerRadius(12)
        }
        .buttonStyle(NumpadButtonStyle())
    }
}

// MARK: - Custom Button Style for Haptic Feedback
struct NumpadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onTapGesture {
                // Haptic feedback for button press
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
    }
}

// MARK: - Preview
#Preview("Quantity Numpad") {
    VStack {
        Text("Quantity: 5")
            .font(.largeTitle)
            .padding()
        
        QuantityNumpad(
            quantity: .constant("5"),
            hasUserInput: .constant(true),
            onQuantityChange: { newQuantity in
                print("Quantity changed to: \(newQuantity)")
            }
        )
        
        Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Numpad Button") {
    HStack(spacing: 12) {
        NumpadButton(text: "1") {
            print("Button 1 pressed")
        }
        
        NumpadButton(
            text: "Clear",
            backgroundColor: Color(.systemGray4),
            textColor: .primary
        ) {
            print("Clear pressed")
        }
        
        NumpadButton(
            text: "⌫",
            backgroundColor: Color(.systemGray4),
            textColor: .primary
        ) {
            print("Delete pressed")
        }
    }
    .padding()
}
