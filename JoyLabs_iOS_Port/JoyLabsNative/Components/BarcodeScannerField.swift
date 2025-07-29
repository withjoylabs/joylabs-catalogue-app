import SwiftUI
import UIKit

// MARK: - Barcode Scanner Text Field
struct BarcodeScannerField: UIViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: (String) -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        
        // Basic configuration
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.backgroundColor = UIColor.clear
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.textColor = UIColor.label
        
        // Keyboard configuration for barcode scanning
        textField.keyboardType = .numbersAndPunctuation
        textField.returnKeyType = .done
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = .none
        
        // CRITICAL: Disable all input accessories and suggestions
        textField.inputAccessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.inputAssistantItem.allowsHidingShortcuts = true
        
        // Disable predictive text completely
        if #available(iOS 17.0, *) {
            textField.inlinePredictionType = .no
        }
        
        // Set delegate
        textField.delegate = context.coordinator
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        
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
        let parent: BarcodeScannerField
        
        init(_ parent: BarcodeScannerField) {
            self.parent = parent
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let newText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
            
            DispatchQueue.main.async {
                self.parent.text = newText
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

// MARK: - SwiftUI Wrapper for Reorder Scanner
struct ReorderScannerField: View {
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
                
                // Custom barcode scanner field
                BarcodeScannerField(
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
                            .foregroundColor(Color.secondary)
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
    }
}

// MARK: - Preview
#Preview("Barcode Scanner Field") {
    VStack {
        ReorderScannerField(
            text: .constant(""),
            isFocused: FocusState<Bool>().projectedValue,
            onSubmit: { text in
                print("Scanned: \(text)")
            }
        )
        .padding()
        
        Spacer()
    }
}
