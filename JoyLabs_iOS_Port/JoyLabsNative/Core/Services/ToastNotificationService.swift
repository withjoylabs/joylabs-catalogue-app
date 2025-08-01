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
    func showSuccess(_ message: String, duration: TimeInterval = 4.0) {
        showToast(ToastNotification(
            message: message,
            type: .success,
            duration: duration
        ))
    }
    
    /// Show an error toast
    func showError(_ message: String, duration: TimeInterval = 5.0) {
        showToast(ToastNotification(
            message: message,
            type: .error,
            duration: duration
        ))
    }
    
    /// Show an info toast
    func showInfo(_ message: String, duration: TimeInterval = 4.0) {
        showToast(ToastNotification(
            message: message,
            type: .info,
            duration: duration
        ))
    }
    
    /// Show a warning toast
    func showWarning(_ message: String, duration: TimeInterval = 4.5) {
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
    
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toast.color)
            
            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
            
            Spacer(minLength: 0)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toast.color.opacity(0.2), lineWidth: 1)
        )
        .offset(dragOffset)
        .scaleEffect(dragOffset == .zero ? 1.0 : 0.95)
        .onTapGesture {
            onDismiss()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow right swipes for dismissal
                    if value.translation.width > 0 {
                        dragOffset = CGSize(width: min(value.translation.width, 100), height: 0)
                    }
                }
                .onEnded { value in
                    if value.translation.width > 50 || value.velocity.width > 300 {
                        // Dismiss if swiped far enough or fast enough
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = CGSize(width: 200, height: 0)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
    }
}

// MARK: - Toast Container Modifier

struct ToastContainerModifier: ViewModifier {
    @ObservedObject private var toastService = ToastNotificationService.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(
                VStack {
                    Spacer()
                    
                    if toastService.isShowing, let toast = toastService.currentToast {
                        HStack {
                            Spacer()
                            ToastView(toast: toast) {
                                toastService.dismiss()
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1000)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 120) // Position above bottom search bar (estimated height + padding)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toastService.isShowing)
            )
    }
}

// MARK: - View Extension

extension View {
    func withToastNotifications() -> some View {
        self.modifier(ToastContainerModifier())
    }
}