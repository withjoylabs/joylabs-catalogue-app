import SwiftUI
import UIKit

/// SwiftUI wrapper for HIDScannerManager
/// Provides invisible overlay for HID scanner input in SwiftUI views
struct HIDScannerView: UIViewRepresentable {
    @ObservedObject var scanner: HIDScannerManager
    let enabled: Bool
    let onScan: (String) -> Void
    let onError: ((String) -> Void)?
    
    init(
        scanner: HIDScannerManager,
        enabled: Bool = true,
        onScan: @escaping (String) -> Void,
        onError: ((String) -> Void)? = nil
    ) {
        self.scanner = scanner
        self.enabled = enabled
        self.onScan = onScan
        self.onError = onError
    }
    
    func makeUIView(context: Context) -> HIDScannerUIView {
        let view = HIDScannerUIView()
        view.configure(with: scanner)
        
        // Set up callbacks
        scanner.onScan = onScan
        scanner.onError = onError
        
        return view
    }
    
    func updateUIView(_ uiView: HIDScannerUIView, context: Context) {
        // Update scanner state
        if enabled && !scanner.isEnabled {
            scanner.enable()
        } else if !enabled && scanner.isEnabled {
            scanner.disable()
        }
        
        // Update callbacks
        scanner.onScan = onScan
        scanner.onError = onError
    }
}

/// UIKit view that hosts the hidden text fields for HID scanner input
class HIDScannerUIView: UIView {
    private var scanner: HIDScannerManager?
    private var hiddenContainer: UIView?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Make this view completely invisible and non-interactive
        backgroundColor = .clear
        isUserInteractionEnabled = true
        alpha = 0.0
        
        // Ensure this view doesn't interfere with touch events
        isHidden = false // Keep visible for text field focus
    }
    
    func configure(with scanner: HIDScannerManager) {
        self.scanner = scanner
        
        // Remove any existing hidden container
        hiddenContainer?.removeFromSuperview()
        
        // Add the hidden text field container
        hiddenContainer = scanner.getHiddenTextFieldView()
        if let container = hiddenContainer {
            addSubview(container)
            
            // Position off-screen but still focusable
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1000),
                container.topAnchor.constraint(equalTo: topAnchor, constant: -1000),
                container.widthAnchor.constraint(equalToConstant: 1),
                container.heightAnchor.constraint(equalToConstant: 1)
            ])
        }
        
        Logger.debug("HIDScannerView", "Configured HID scanner UI view")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Ensure the hidden container stays positioned correctly
        if let container = hiddenContainer {
            container.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        }
    }
    
    deinit {
        scanner?.cleanup()
        Logger.debug("HIDScannerView", "HID scanner UI view deallocated")
    }
}

// MARK: - SwiftUI View Modifier
extension View {
    /// Adds invisible HID scanner overlay to any SwiftUI view
    /// Replicates the React Native BarcodeScanner component behavior
    func hidScanner(
        enabled: Bool = true,
        minLength: Int = 8,
        maxLength: Int = 50,
        timeout: TimeInterval = 0.15,
        onScan: @escaping (String) -> Void,
        onError: ((String) -> Void)? = nil
    ) -> some View {
        self.overlay(
            HIDScannerOverlay(
                enabled: enabled,
                minLength: minLength,
                maxLength: maxLength,
                timeout: timeout,
                onScan: onScan,
                onError: onError
            )
        )
    }
}

/// Internal overlay view for the HID scanner
private struct HIDScannerOverlay: View {
    @StateObject private var scanner: HIDScannerManager
    
    let enabled: Bool
    let onScan: (String) -> Void
    let onError: ((String) -> Void)?
    
    init(
        enabled: Bool,
        minLength: Int,
        maxLength: Int,
        timeout: TimeInterval,
        onScan: @escaping (String) -> Void,
        onError: ((String) -> Void)?
    ) {
        self.enabled = enabled
        self.onScan = onScan
        self.onError = onError
        
        // Initialize scanner with configuration
        self._scanner = StateObject(wrappedValue: HIDScannerManager(
            minLength: minLength,
            maxLength: maxLength,
            timeout: timeout
        ))
    }
    
    var body: some View {
        HIDScannerView(
            scanner: scanner,
            enabled: enabled,
            onScan: onScan,
            onError: onError
        )
        .allowsHitTesting(false) // Don't interfere with touch events
        .opacity(0) // Completely invisible
        .onAppear {
            if enabled {
                scanner.enable()
            }
        }
        .onDisappear {
            scanner.disable()
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        Text("HID Scanner Test View")
            .font(.title)
            .padding()
        
        Text("Scan a barcode with your HID scanner")
            .foregroundColor(.secondary)
            .padding()
        
        Spacer()
    }
    .hidScanner(
        enabled: true,
        onScan: { barcode in
            print("Scanned: \(barcode)")
        },
        onError: { error in
            print("Error: \(error)")
        }
    )
}
