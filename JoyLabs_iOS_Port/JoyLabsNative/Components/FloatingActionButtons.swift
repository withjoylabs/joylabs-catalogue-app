import SwiftUI

// MARK: - Floating Action Buttons
struct FloatingActionButtons: View {
    let onCancel: () -> Void
    let onPrint: () -> Void
    let onSave: () -> Void
    let onSaveAndPrint: () -> Void
    let canSave: Bool
    
    var body: some View {
        HStack(spacing: 20) {
            // Cancel Button
            FloatingButton(
                icon: "xmark",
                color: .gray,
                action: onCancel
            )
            
            // Print Button
            FloatingButton(
                icon: "printer",
                color: .blue,
                action: onPrint
            )
            
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
                action: onSaveAndPrint,
                isDisabled: !canSave
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 34) // Account for safe area
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
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(isDisabled ? Color.gray.opacity(0.5) : color)
                        .shadow(
                            color: isDisabled ? .clear : color.opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .scaleEffect(isDisabled ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
    }
}

#Preview {
    VStack {
        Spacer()
        
        FloatingActionButtons(
            onCancel: { print("Cancel") },
            onPrint: { print("Print") },
            onSave: { print("Save") },
            onSaveAndPrint: { print("Save & Print") },
            canSave: true
        )
    }
    .background(Color(.systemGray6))
}
