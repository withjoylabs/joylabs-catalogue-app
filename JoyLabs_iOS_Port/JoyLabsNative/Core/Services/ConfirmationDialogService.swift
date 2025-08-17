import SwiftUI
import Combine

// MARK: - Confirmation Dialog Configuration
struct ConfirmationDialogConfig {
    let title: String
    let message: String
    let confirmButtonText: String
    let cancelButtonText: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    let onCancel: (() -> Void)?
    
    init(
        title: String,
        message: String,
        confirmButtonText: String = "Confirm",
        cancelButtonText: String = "Cancel",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmButtonText = confirmButtonText
        self.cancelButtonText = cancelButtonText
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

// MARK: - Confirmation Dialog Service
@MainActor
class ConfirmationDialogService: ObservableObject {
    static let shared = ConfirmationDialogService()
    
    @Published var isShowing = false
    @Published var currentConfig: ConfirmationDialogConfig?
    
    private init() {}
    
    func show(_ config: ConfirmationDialogConfig) {
        // Dismiss keyboard first to prevent layout conflicts
        dismissKeyboard()
        
        // Small delay to ensure keyboard dismissal completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.currentConfig = config
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.isShowing = true
            }
        }
    }
    
    func confirm() {
        if let config = currentConfig {
            config.onConfirm()
        }
        dismiss()
    }
    
    func cancel() {
        if let config = currentConfig {
            config.onCancel?()
        }
        dismiss()
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isShowing = false
        }
        
        // Clear config after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentConfig = nil
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - View Modifier for Dialog Presentation
struct WithConfirmationDialog: ViewModifier {
    @StateObject private var dialogService = ConfirmationDialogService.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if dialogService.isShowing, let config = dialogService.currentConfig {
                CustomConfirmationDialog(config: config)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(999)
            }
        }
    }
}

extension View {
    func withConfirmationDialog() -> some View {
        modifier(WithConfirmationDialog())
    }
}