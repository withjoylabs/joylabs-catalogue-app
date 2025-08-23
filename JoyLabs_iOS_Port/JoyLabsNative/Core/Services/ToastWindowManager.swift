import UIKit
import SwiftUI
import Combine

/// Enhanced toast notification data model for stacking
struct ActiveToast: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let notification: ToastNotification
    let createdAt = Date()
    var dismissTimer: Timer?
    
    static func == (lhs: ActiveToast, rhs: ActiveToast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Industry-standard UIWindow-based toast manager with enhanced stacking UX
/// Features: bottom-up stacking, snappy animations, 2-second auto-dismiss
@MainActor
final class ToastWindowManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ToastWindowManager()
    
    // MARK: - Properties
    private var toastWindow: UIWindow?
    private var hostingController: UIHostingController<EnhancedToastContainerView>?
    private var activeToasts: [ActiveToast] = []
    private let maxVisibleToasts = 4
    
    // Observable state for SwiftUI binding
    @Published private(set) var isShowing: Bool = false
    
    // MARK: - Initialization
    private init() {
        setupWindow()
    }
    
    // MARK: - Window Setup
    private func setupWindow() {
        // Create window only when needed for efficiency
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
        
        // Create enhanced container view for stacked toasts
        let containerView = EnhancedToastContainerView(
            activeToasts: [],
            onDismiss: { [weak self] toastId in
                Task { @MainActor in
                    self?.dismissToast(withId: toastId)
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
        guard activeToasts.isEmpty else { return }
        
        // Delay destruction slightly to allow animations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.activeToasts.isEmpty else { return }
            
            self.toastWindow?.isHidden = true
            self.toastWindow = nil
            self.hostingController = nil
        }
    }
    
    // MARK: - Public Interface
    
    /// Show a toast notification with enhanced stacking
    func show(_ toast: ToastNotification) {
        // Create active toast with 2-second auto-dismiss
        var activeToast = ActiveToast(notification: toast)
        
        // Remove oldest if at max capacity
        if activeToasts.count >= maxVisibleToasts {
            if let oldestToast = activeToasts.first {
                dismissToast(withId: oldestToast.id)
            }
        }
        
        // Add to active toasts (new toasts go to end - bottom position)
        activeToasts.append(activeToast)
        
        // Update window state
        isShowing = !activeToasts.isEmpty
        
        // Create window if needed
        createWindowIfNeeded()
        
        // Make window interactive
        toastWindow?.isUserInteractionEnabled = true
        
        // Update the view with snappy animation
        updateToastDisplay()
        
        // Set up auto-dismiss timer (2 seconds for snappy UX)
        let toastId = activeToast.id
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissToast(withId: toastId)
            }
        }
        
        // Store timer reference
        if let index = activeToasts.firstIndex(where: { $0.id == activeToast.id }) {
            activeToasts[index].dismissTimer = timer
        }
    }
    
    /// Dismiss specific toast by ID
    func dismissToast(withId id: UUID) {
        guard let index = activeToasts.firstIndex(where: { $0.id == id }) else { return }
        
        // Invalidate timer
        activeToasts[index].dismissTimer?.invalidate()
        
        // Remove from active toasts
        activeToasts.remove(at: index)
        
        // Update state
        isShowing = !activeToasts.isEmpty
        
        // Update display with cascade animation
        updateToastDisplay()
        
        // Make window non-interactive if no toasts
        if activeToasts.isEmpty {
            toastWindow?.isUserInteractionEnabled = false
            destroyWindowIfNotNeeded()
        }
    }
    
    /// Clear all active toasts
    func clearAll() {
        // Invalidate all timers
        activeToasts.forEach { $0.dismissTimer?.invalidate() }
        
        // Clear all toasts
        activeToasts.removeAll()
        isShowing = false
        
        // Update display
        updateToastDisplay()
        
        // Clean up window
        toastWindow?.isUserInteractionEnabled = false
        destroyWindowIfNotNeeded()
    }
    
    // MARK: - Private Implementation
    
    private func updateToastDisplay() {
        guard let hostingController = hostingController else { return }
        
        // Update with snappy spring animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)) {
            hostingController.rootView = EnhancedToastContainerView(
                activeToasts: activeToasts,
                onDismiss: { [weak self] toastId in
                    Task { @MainActor in
                        self?.dismissToast(withId: toastId)
                    }
                }
            )
        }
    }
}

// MARK: - Enhanced Toast Container View

private struct EnhancedToastContainerView: View {
    let activeToasts: [ActiveToast]
    let onDismiss: (UUID) -> Void
    
    var body: some View {
        ZStack {
            // Invisible background to pass touches through
            Color.clear
                .allowsHitTesting(false)
            
            // Stacked toasts positioned at bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    VStack(spacing: 8) { // 8px spacing between stacked toasts
                        ForEach(Array(activeToasts.enumerated()), id: \.element.id) { index, activeToast in
                            EnhancedToastView(
                                activeToast: activeToast,
                                stackIndex: index,
                                totalCount: activeToasts.count,
                                onDismiss: { onDismiss(activeToast.id) }
                            )
                            .transition(.asymmetric(
                                insertion: .slide.combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                removal: .slide.combined(with: .opacity).combined(with: .scale(scale: 0.8))
                            ))
                            .zIndex(Double(activeToasts.count - index)) // Newest on top
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 140) // Position above bottom UI elements
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!activeToasts.isEmpty) // Only intercept touches when showing toasts
    }
}

// MARK: - Enhanced Toast View

private struct EnhancedToastView: View {
    let activeToast: ActiveToast
    let stackIndex: Int
    let totalCount: Int
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    private var toast: ToastNotification {
        activeToast.notification
    }
    
    // Visual hierarchy for stacked toasts
    private var stackOpacity: Double {
        let baseOpacity = 1.0
        let fadePerLevel: Double = 0.15
        return max(0.3, baseOpacity - (Double(stackIndex) * fadePerLevel))
    }
    
    private var stackScale: CGFloat {
        let baseScale: CGFloat = 1.0
        let scalePerLevel: CGFloat = 0.05
        return max(0.8, baseScale - (CGFloat(stackIndex) * scalePerLevel))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with enhanced styling
            Image(systemName: toast.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(toast.color)
                .frame(width: 24, height: 24)
            
            // Message with better typography
            Text(toast.message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 8)
            
            // Enhanced dismiss button
            Button(action: {
                // Quick scale animation on tap
                withAnimation(.easeOut(duration: 0.15)) {
                    scale = 0.9
                    opacity = 0.7
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .opacity(0.8)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 260, maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(
                    color: .black.opacity(stackIndex == totalCount - 1 ? 0.25 : 0.15),
                    radius: stackIndex == totalCount - 1 ? 16 : 8,
                    x: 0,
                    y: stackIndex == totalCount - 1 ? 8 : 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(toast.color.opacity(0.4), lineWidth: 1.5)
        )
        // Apply stacking visual effects
        .opacity(opacity * stackOpacity)
        .scaleEffect(scale * stackScale)
        .offset(dragOffset)
        // Enhanced swipe-to-dismiss gesture
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow rightward swipes
                    if value.translation.width > 0 {
                        let progress = min(value.translation.width / 120, 1.0)
                        dragOffset = CGSize(width: value.translation.width * 0.7, height: 0)
                        opacity = Double(1.0 - (progress * 0.6))
                        scale = 1.0 - (progress * 0.1)
                    }
                }
                .onEnded { value in
                    if value.translation.width > 80 || value.velocity.width > 400 {
                        // Dismiss with slide-out animation
                        withAnimation(.easeOut(duration: 0.25)) {
                            dragOffset = CGSize(width: 400, height: 0)
                            opacity = 0
                            scale = 0.8
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onDismiss()
                        }
                    } else {
                        // Snap back with bouncy animation
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            dragOffset = .zero
                            opacity = 1.0
                            scale = 1.0
                        }
                    }
                }
        )
        .onTapGesture {
            // Tap to dismiss with gentle animation
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 0.3
                scale = 0.95
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onDismiss()
            }
        }
        .onAppear {
            // Slide in from right with snappy spring
            dragOffset = CGSize(width: 400, height: 0)
            opacity = 0
            scale = 0.9
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = .zero
                opacity = 1.0
                scale = 1.0
            }
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