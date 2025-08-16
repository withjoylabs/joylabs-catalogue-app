import UIKit
import Foundation

// MARK: - UITextField InputAccessory Swizzling
/// Fixes InputAccessoryGenerator constraint conflicts with external keyboards on iPad
/// by preventing ANY TextField in the app from having an inputAccessoryView
extension UITextField {
    
    /// Call this once at app startup to fix InputAccessoryGenerator conflicts globally
    static func swizzleInputAccessoryView() {
        guard !hasSwizzledInputAccessory else { return }
        hasSwizzledInputAccessory = true
        
        let originalSelector = #selector(setter: UITextField.inputAccessoryView)
        let swizzledSelector = #selector(UITextField.swizzled_setInputAccessoryView(_:))
        
        guard let originalMethod = class_getInstanceMethod(UITextField.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UITextField.self, swizzledSelector) else {
            print("❌ [UITextField+Swizzle] Failed to get methods for swizzling")
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
        print("✅ [UITextField+Swizzle] Successfully swizzled inputAccessoryView setter")
        print("✅ [UITextField+Swizzle] All TextFields will now have nil inputAccessoryView")
        print("✅ [UITextField+Swizzle] This prevents InputAccessoryGenerator constraint conflicts")
    }
    
    /// Track if we've already swizzled to prevent double-swizzling
    private static var hasSwizzledInputAccessory = false
    
    /// Swizzled implementation that always sets nil
    @objc private func swizzled_setInputAccessoryView(_ view: UIView?) {
        // ALWAYS set nil to prevent InputAccessoryGenerator creation
        // This fixes the 69-point constraint conflict with external keyboards
        
        if view != nil {
            print("🛡️ [UITextField+Swizzle] Blocked inputAccessoryView assignment for \(self)")
            print("🛡️ [UITextField+Swizzle] Prevented InputAccessoryGenerator creation")
        }
        
        // Call original method with nil instead of the provided view
        self.swizzled_setInputAccessoryView(nil)
    }
}

// MARK: - Debug Helper
extension UITextField {
    /// Debug method to check if a TextField has an inputAccessoryView
    func debugInputAccessory() {
        if let accessoryView = self.inputAccessoryView {
            print("🔍 [Debug] TextField has inputAccessoryView: \(accessoryView)")
            print("🔍 [Debug] Type: \(type(of: accessoryView))")
            print("🔍 [Debug] Frame: \(accessoryView.frame)")
        } else {
            print("✅ [Debug] TextField has nil inputAccessoryView (no conflicts)")
        }
    }
}