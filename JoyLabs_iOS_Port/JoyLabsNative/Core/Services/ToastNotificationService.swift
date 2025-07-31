import Foundation
import SwiftUI
import Combine

/// Toast Notification Service - System-wide toast notifications
@MainActor
class ToastNotificationService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ToastNotificationService()
    
    // MARK: - Published Properties
    @Published var currentToast: ToastNotification?
    @Published var isShowing: Bool = false
    
    // MARK: - Private Properties
    private var dismissTimer: Timer?
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Interface
    
    /// Show a success toast
    func showSuccess(_ message: String, duration: TimeInterval = 3.0) {
        showToast(ToastNotification(
            message: message,
            type: .success,
            duration: duration
        ))
    }
    
    /// Show an error toast
    func showError(_ message: String, duration: TimeInterval = 4.0) {
        showToast(ToastNotification(
            message: message,
            type: .error,
            duration: duration
        ))
    }
    
    /// Show an info toast
    func showInfo(_ message: String, duration: TimeInterval = 3.0) {
        showToast(ToastNotification(
            message: message,
            type: .info,
            duration: duration
        ))
    }
    
    /// Show a warning toast
    func showWarning(_ message: String, duration: TimeInterval = 3.5) {
        showToast(ToastNotification(
            message: message,
            type: .warning,
            duration: duration
        ))
    }
    
    /// Dismiss current toast
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        }
        
        // Clear toast after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentToast = nil
        }
    }
    
    // MARK: - Private Implementation
    
    private func showToast(_ toast: ToastNotification) {
        // Dismiss any existing toast
        dismissTimer?.invalidate()
        
        // Set new toast
        currentToast = toast
        
        // Show with animation
        withAnimation(.easeIn(duration: 0.3)) {
            isShowing = true
        }
        
        // Auto-dismiss after duration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: toast.duration, repeats: false) { _ in
            Task { @MainActor in
                self.dismiss()
            }
        }
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

// MARK: - Toast View Component

struct ToastView: View {
    let toast: ToastNotification
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toast.color)
            
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toast.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Toast Container Modifier

struct ToastContainerModifier: ViewModifier {
    @ObservedObject private var toastService = ToastNotificationService.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(
                VStack {
                    if toastService.isShowing, let toast = toastService.currentToast {
                        HStack {
                            Spacer()
                            ToastView(toast: toast) {
                                toastService.dismiss()
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1000)
                        }
                        .padding(.top, 60) // Below status bar
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: toastService.isShowing)
            )
    }
}

// MARK: - View Extension

extension View {
    func withToastNotifications() -> some View {
        self.modifier(ToastContainerModifier())
    }
}