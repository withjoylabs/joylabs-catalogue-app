import SwiftUI
import UIKit

// MARK: - Custom TextField to Prevent InputAccessoryGenerator Conflicts
/// Direct UITextField wrapper that prevents SwiftUI's automatic InputAccessoryGenerator creation
/// which causes constraint conflicts with external Bluetooth keyboards on iPad
struct CustomTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: UIFont = .systemFont(ofSize: 17)
    var textColor: UIColor = .label
    var keyboardType: UIKeyboardType = .default
    var isSecureTextEntry: Bool = false
    var textAlignment: NSTextAlignment = .natural
    var onEditingChanged: ((Bool) -> Void)?
    var onCommit: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.text = text
        textField.font = font
        textField.textColor = textColor
        textField.keyboardType = keyboardType
        textField.isSecureTextEntry = isSecureTextEntry
        textField.textAlignment = textAlignment
        textField.delegate = context.coordinator
        
        // CRITICAL: Prevent InputAccessoryGenerator by explicitly setting nil
        // This prevents the 69-point constraint conflict with external keyboards
        textField.inputAccessoryView = nil
        
        // Disable all autocorrection features that might trigger accessories
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        
        // Set content priority to prevent layout issues
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update if text actually changed to prevent cursor jumping
        if uiView.text != text {
            uiView.text = text
        }
        
        // Always ensure inputAccessoryView stays nil
        if uiView.inputAccessoryView != nil {
            uiView.inputAccessoryView = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: CustomTextField
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Update binding only if text actually changed
            if parent.text != textField.text ?? "" {
                parent.text = textField.text ?? ""
            }
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged?(true)
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged?(false)
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit?()
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - SwiftUI-style Modifiers
extension CustomTextField {
    func font(_ font: Font) -> CustomTextField {
        var copy = self
        // Convert SwiftUI Font to UIFont
        switch font {
        case .largeTitle:
            copy.font = .preferredFont(forTextStyle: .largeTitle)
        case .title:
            copy.font = .preferredFont(forTextStyle: .title1)
        case .headline:
            copy.font = .preferredFont(forTextStyle: .headline)
        case .subheadline:
            copy.font = .preferredFont(forTextStyle: .subheadline)
        case .body:
            copy.font = .preferredFont(forTextStyle: .body)
        case .callout:
            copy.font = .preferredFont(forTextStyle: .callout)
        case .footnote:
            copy.font = .preferredFont(forTextStyle: .footnote)
        case .caption:
            copy.font = .preferredFont(forTextStyle: .caption1)
        default:
            copy.font = .systemFont(ofSize: 17)
        }
        return copy
    }
    
    func foregroundColor(_ color: Color) -> CustomTextField {
        var copy = self
        copy.textColor = UIColor(color)
        return copy
    }
    
    func multilineTextAlignment(_ alignment: TextAlignment) -> CustomTextField {
        var copy = self
        switch alignment {
        case .leading:
            copy.textAlignment = .left
        case .center:
            copy.textAlignment = .center
        case .trailing:
            copy.textAlignment = .right
        }
        return copy
    }
}