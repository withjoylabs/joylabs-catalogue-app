import UIKit
import SwiftUI
import Combine

/// Industry-standard UIWindow-based toast manager for universal coverage
/// This ensures toasts appear above ALL content including sheets and modals
@MainActor
final class ToastWindowManager {
    
    // MARK: - Singleton
    static let shared = ToastWindowManager()
    
    // MARK: - Properties
    private var toastWindow: UIWindow?
    private var hostingController: UIHostingController<ToastContainerView>?
    private var currentToast: ToastNotification?
    private var toastQueue: [ToastNotification] = []
    private var dismissTimer: Timer?
    
    // Observable state for SwiftUI binding
    @Published private(set) var isShowing: Bool = false
    
    // MARK: - Initialization
    private init() {
        setupWindow()
    }
    
    // MARK: - Window Setup
    private func setupWindow() {
        // Create window only when needed, destroy when not
        // This is more efficient than keeping a window around
    }
    
    private func createWindowIfNeeded() {
        guard toastWindow == nil else { return }
        
        // Get the active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else {
            print("[ToastWindow] No active window scene found")
            return
        }
        
        // Create toast window at highest level
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 100 // Above alerts and keyboards
        window.isHidden = false
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true
        
        // Create container view for toast
        let containerView = ToastContainerView(
            toast: .constant(nil),
            onDismiss: { [weak self] in
                Task { @MainActor in
                    self?.dismissCurrentToast()
                }
            }
        )
        
        // Create hosting controller
        let hosting = UIHostingController(rootView: containerView)
        hosting.view.backgroundColor = .clear
        
        // Configure window
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        
        // Store references
        self.toastWindow = window
        self.hostingController = hosting
        
        // Make window non-interactive initially
        window.isUserInteractionEnabled = false
    }
    
    private func destroyWindowIfNotNeeded() {
        guard toastQueue.isEmpty && currentToast == nil else { return }
        
        // Delay destruction slightly to allow animations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self,
                  self.toastQueue.isEmpty,
                  self.currentToast == nil else { return }
            
            self.toastWindow?.isHidden = true
            self.toastWindow = nil
            self.hostingController = nil
        }
    }
    
    // MARK: - Public Interface
    
    /// Show a toast notification
    func show(_ toast: ToastNotification) {
        // Add to queue
        toastQueue.append(toast)
        
        // Process queue if not currently showing
        if currentToast == nil {
            processNextToast()
        }
    }
    
    /// Dismiss the current toast
    func dismissCurrentToast() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        // Clear current toast
        currentToast = nil
        isShowing = false
        
        // Update the view
        if let hostingController = hostingController {
            hostingController.rootView = ToastContainerView(
                toast: .constant(nil),
                onDismiss: { [weak self] in
                    Task { @MainActor in
                        self?.dismissCurrentToast()
                    }
                }
            )
        }
        
        // Make window non-interactive when no toast
        toastWindow?.isUserInteractionEnabled = false
        
        // Process next toast after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.processNextToast()
        }
    }
    
    /// Clear all pending toasts
    func clearAll() {
        toastQueue.removeAll()
        dismissCurrentToast()
    }
    
    // MARK: - Private Implementation
    
    private func processNextToast() {
        guard !toastQueue.isEmpty else {
            destroyWindowIfNotNeeded()
            return
        }
        
        // Sort by priority if needed (error > warning > success > info)
        toastQueue.sort { $0.priority > $1.priority }
        
        // Get next toast
        let toast = toastQueue.removeFirst()
        currentToast = toast
        
        // Create window if needed
        createWindowIfNeeded()
        
        // Make window interactive for this toast
        toastWindow?.isUserInteractionEnabled = true
        
        // Update the hosting controller's view
        if let hostingController = hostingController {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                hostingController.rootView = ToastContainerView(
                    toast: .constant(toast),
                    onDismiss: { [weak self] in
                        Task { @MainActor in
                            self?.dismissCurrentToast()
                        }
                    }
                )
                isShowing = true
            }
        }
        
        // Set up auto-dismiss timer
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: toast.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissCurrentToast()
            }
        }
    }
}

// MARK: - Toast Container View

private struct ToastContainerView: View {
    @Binding var toast: ToastNotification?
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Invisible background to pass touches through
            Color.clear
                .allowsHitTesting(false)
            
            // Toast positioned at bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    if let toast = toast {
                        ToastView(
                            toast: toast,
                            onDismiss: onDismiss
                        )
                        .offset(dragOffset)
                        .opacity(opacity)
                        .transition(.asymmetric(
                            insertion: .offset(x: 400, y: 0).combined(with: .opacity),
                            removal: .offset(x: 400, y: 0).combined(with: .opacity)
                        ))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.width > 0 {
                                        dragOffset = CGSize(width: value.translation.width * 0.5, height: 0)
                                        opacity = Double(1.0 - (value.translation.width / 300))
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.width > 100 || value.velocity.width > 500 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            dragOffset = CGSize(width: 400, height: 0)
                                            opacity = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            onDismiss()
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            dragOffset = .zero
                                            opacity = 1
                                        }
                                    }
                                }
                        )
                        .onAppear {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                opacity = 1
                            }
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 140) // Position above bottom UI elements
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(toast != nil) // Only intercept touches when showing toast
    }
}

// MARK: - Enhanced Toast View

private struct ToastView: View {
    let toast: ToastNotification
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: toast.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(toast.color)
                .frame(width: 24, height: 24)
            
            // Message
            Text(toast.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 8)
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 280, maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(toast.color.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            onDismiss()
        }
    }
}

// MARK: - Toast Notification Extended

extension ToastNotification {
    /// Priority for queue management
    var priority: Int {
        switch type {
        case .error: return 4
        case .warning: return 3
        case .success: return 2
        case .info: return 1
        }
    }
}