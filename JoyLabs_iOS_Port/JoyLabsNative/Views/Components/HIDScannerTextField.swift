import SwiftUI
import UIKit

// MARK: - HID Scanner Compatible Text Field
struct HIDScannerTextField: UIViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: (String) -> Void
    
    func makeUIView(context: Context) -> HIDTextField {
        let textField = HIDTextField()
        
        // Basic configuration
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.backgroundColor = UIColor.clear
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.textColor = UIColor.label
        
        // Keyboard configuration optimized for HID scanners
        textField.keyboardType = .numbersAndPunctuation
        textField.returnKeyType = .done
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = .none
        
        // CRITICAL: Disable all input accessories to prevent constraint issues
        textField.inputAccessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.inputAssistantItem.allowsHidingShortcuts = true
        
        // Disable predictive text completely
        if #available(iOS 17.0, *) {
            textField.inlinePredictionType = .no
        }
        
        // Set delegate and callbacks
        textField.delegate = context.coordinator
        textField.onSubmit = onSubmit
        
        return textField
    }
    
    func updateUIView(_ uiView: HIDTextField, context: Context) {
        // Update text if different (prevents loops)
        if uiView.text != text {
            uiView.text = text
        }
        
        // Handle focus state
        DispatchQueue.main.async {
            if isFocused && !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isFocused && uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: HIDScannerTextField
        private var lastUpdateTime: TimeInterval = 0
        private let minUpdateInterval: TimeInterval = 0.016 // ~60fps
        
        init(_ parent: HIDScannerTextField) {
            self.parent = parent
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // CRITICAL: Throttle updates to prevent "multiple updates per frame" error
            let currentTime = CACurrentMediaTime()
            
            // Calculate new text
            let newText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
            
            // Only update if enough time has passed since last update
            if currentTime - lastUpdateTime >= minUpdateInterval {
                lastUpdateTime = currentTime
                
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
            } else {
                // Queue the update for the next frame
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
            }
            
            return true
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let text = textField.text ?? ""
            if !text.isEmpty {
                parent.onSubmit(text)
            }
            return true
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }
    }
}

// MARK: - Custom UITextField for HID Scanner Support
class HIDTextField: UITextField {
    var onSubmit: ((String) -> Void)?
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    // CRITICAL: Override to handle external keyboard input without requiring focus
    override var keyCommands: [UIKeyCommand]? {
        // This allows the text field to receive keyboard input even when not focused
        // Useful for HID scanners that act as external keyboards
        return [
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleReturn)),
            UIKeyCommand(input: "\n", modifierFlags: [], action: #selector(handleReturn))
        ]
    }
    
    @objc private func handleReturn() {
        if let text = self.text, !text.isEmpty {
            onSubmit?(text)
        }
    }
    
    // Override to prevent system sounds on rapid input
    override func insertText(_ text: String) {
        // Disable system keyboard sounds for rapid HID input
        UIDevice.current.playInputClick = false
        super.insertText(text)
        UIDevice.current.playInputClick = true
    }
}

// MARK: - SwiftUI Wrapper for Reorder Scanner with HID Support
struct ReorderHIDScannerField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Barcode icon
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                // HID-compatible scanner field
                HIDScannerTextField(
                    text: $text,
                    isFocused: $isFocused,
                    placeholder: "Scan to add items...",
                    onSubmit: onSubmit
                )
                
                // Clear button
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        isFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Thin bottom border
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview
#Preview("HID Scanner Field") {
    VStack {
        ReorderHIDScannerField(
            text: .constant(""),
            isFocused: FocusState<Bool>().projectedValue,
            onSubmit: { text in
                print("HID Scanned: \(text)")
            }
        )
        .padding()
        
        Spacer()
    }
}
