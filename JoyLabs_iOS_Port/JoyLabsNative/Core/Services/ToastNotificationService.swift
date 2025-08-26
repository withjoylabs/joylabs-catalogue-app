import Foundation
import SwiftUI
import Combine

/// Toast Notification Service - System-wide toast notifications
/// Now uses UIWindow-based presentation for universal coverage
@MainActor
class ToastNotificationService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ToastNotificationService()
    
    // MARK: - Published Properties (Kept for backward compatibility)
    @Published var currentToast: ToastNotification?
    @Published var isShowing: Bool = false
    
    // MARK: - Private Properties
    private let windowManager = ToastWindowManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    private init() {
        // Sync state with window manager for backward compatibility
        windowManager.$isShowing
            .assign(to: &$isShowing)
    }
    
    // MARK: - Public Interface
    
    /// Show a success toast
    func showSuccess(_ message: String, duration: TimeInterval = 4.0) {
        let toast = ToastNotification(
            message: message,
            type: .success,
            duration: duration
        )
        currentToast = toast
        windowManager.show(toast)
    }
    
    /// Show an error toast
    func showError(_ message: String, duration: TimeInterval = 5.0) {
        let toast = ToastNotification(
            message: message,
            type: .error,
            duration: duration
        )
        currentToast = toast
        windowManager.show(toast)
    }
    
    /// Show an info toast
    func showInfo(_ message: String, duration: TimeInterval = 4.0) {
        let toast = ToastNotification(
            message: message,
            type: .info,
            duration: duration
        )
        currentToast = toast
        windowManager.show(toast)
    }
    
    /// Show a warning toast
    func showWarning(_ message: String, duration: TimeInterval = 4.5) {
        let toast = ToastNotification(
            message: message,
            type: .warning,
            duration: duration
        )
        currentToast = toast
        windowManager.show(toast)
    }
    
    /// Dismiss current toast
    func dismiss() {
        if let toast = currentToast {
            windowManager.dismissToast(withId: toast.id)
        }
        currentToast = nil
    }
    
    /// Clear all pending toasts
    func clearAll() {
        windowManager.clearAll()
        currentToast = nil
    }
}

// MARK: - Supporting Types

/// Toast notification model
struct ToastNotification {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    let timestamp = Date()
    
    var icon: String {
        switch type {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch type {
        case .success:
            return .green
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}

/// Toast notification types
enum ToastType {
    case success
    case error
    case warning
    case info
}

// Note: Toast presentation is now handled by ToastWindowManager
// The old ViewModifier approach has been removed in favor of UIWindow-based presentation
// This ensures toasts appear above all content including sheets and modals