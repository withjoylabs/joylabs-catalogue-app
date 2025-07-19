import SwiftUI
import Combine
import OSLog

/// Service for handling Bluetooth HID barcode scanner input
/// This service listens for keyboard input from connected HID devices (barcode scanners)
/// and provides debounced search functionality for the reorder page
class BluetoothHIDScannerService: ObservableObject {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "BluetoothHIDScanner")
    
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var lastScannedCode: String = ""
    @Published var scanHistory: [ScanHistoryItem] = []
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: Timer?
    private var currentInput = ""
    private var inputStartTime: Date?
    
    // Configuration
    private let debounceDelay: TimeInterval = 0.5 // 500ms debounce
    private let maxInputLength = 50
    private let minInputLength = 3
    private let scanTimeout: TimeInterval = 2.0 // Reset input after 2 seconds of inactivity
    
    // Callbacks
    var onBarcodeScanned: ((String) -> Void)?
    var onScanError: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupKeyboardMonitoring()
        logger.info("🔍 BluetoothHIDScannerService initialized")
    }
    
    deinit {
        stopListening()
        logger.info("🔍 BluetoothHIDScannerService deinitialized")
    }
    
    // MARK: - Public Methods
    
    /// Start listening for HID scanner input
    func startListening() {
        guard !isListening else { return }
        
        isListening = true
        currentInput = ""
        inputStartTime = nil
        
        logger.info("🔍 Started listening for HID scanner input")
    }
    
    /// Stop listening for HID scanner input
    func stopListening() {
        isListening = false
        debounceTimer?.invalidate()
        debounceTimer = nil
        currentInput = ""
        inputStartTime = nil
        
        logger.info("🔍 Stopped listening for HID scanner input")
    }
    
    /// Clear scan history
    func clearHistory() {
        scanHistory.removeAll()
        logger.debug("🔍 Cleared scan history")
    }
    
    // MARK: - Private Methods
    
    private func setupKeyboardMonitoring() {
        // Note: iOS doesn't provide direct access to global keyboard events for security reasons
        // This is a conceptual implementation - actual implementation would need to use:
        // 1. A hidden UITextField that captures HID input
        // 2. UIApplication.shared.sendEvent override (requires app-level implementation)
        // 3. Or integrate with the existing search field to detect rapid input patterns
        
        logger.info("🔍 Setting up keyboard monitoring for HID devices")
    }
    
    /// Process character input from HID device
    func processCharacterInput(_ character: String) {
        guard isListening else { return }
        
        // Start timing if this is the first character
        if currentInput.isEmpty {
            inputStartTime = Date()
        }
        
        // Check for timeout (reset if too much time has passed)
        if let startTime = inputStartTime,
           Date().timeIntervalSince(startTime) > scanTimeout {
            currentInput = ""
            inputStartTime = Date()
        }
        
        // Add character to current input
        currentInput += character
        
        // Prevent excessively long inputs
        if currentInput.count > maxInputLength {
            resetInput()
            onScanError?("Scanned code too long")
            return
        }
        
        // Reset debounce timer
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            self?.processCompletedInput()
        }
    }
    
    /// Process return key press (indicates end of barcode scan)
    func processReturnKey() {
        guard isListening else { return }
        
        debounceTimer?.invalidate()
        processCompletedInput()
    }
    
    private func processCompletedInput() {
        let trimmedInput = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedInput.isEmpty,
              trimmedInput.count >= minInputLength else {
            resetInput()
            return
        }
        
        // Validate barcode format
        if isValidBarcode(trimmedInput) {
            handleSuccessfulScan(trimmedInput)
        } else {
            onScanError?("Invalid barcode format: \(trimmedInput)")
            logger.warning("🔍 Invalid barcode format: \(trimmedInput)")
        }
        
        resetInput()
    }
    
    private func resetInput() {
        currentInput = ""
        inputStartTime = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    private func handleSuccessfulScan(_ barcode: String) {
        lastScannedCode = barcode
        
        // Add to history
        let historyItem = ScanHistoryItem(
            id: UUID().uuidString,
            barcode: barcode,
            timestamp: Date(),
            source: .hidScanner
        )
        scanHistory.insert(historyItem, at: 0)
        
        // Keep history limited
        if scanHistory.count > 100 {
            scanHistory = Array(scanHistory.prefix(100))
        }
        
        // Notify callback
        onBarcodeScanned?(barcode)
        
        logger.info("🔍 Successfully scanned barcode: \(barcode)")
    }
    
    private func isValidBarcode(_ input: String) -> Bool {
        // Validate common barcode formats
        let patterns = [
            "^\\d{8}$",           // EAN-8 (8 digits)
            "^\\d{12}$",          // UPC-A (12 digits)
            "^\\d{13}$",          // EAN-13 (13 digits)
            "^\\d{14}$",          // ITF-14 (14 digits)
            "^[A-Za-z0-9]{1,50}$" // Alphanumeric SKUs (up to 50 chars)
        ]
        
        return patterns.contains { pattern in
            input.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

// MARK: - Supporting Models

struct ScanHistoryItem: Identifiable, Codable {
    let id: String
    let barcode: String
    let timestamp: Date
    let source: ScanSource
}

enum ScanSource: String, Codable {
    case hidScanner = "hid_scanner"
    case cameraScanner = "camera_scanner"
    case manualEntry = "manual_entry"
    
    var displayName: String {
        switch self {
        case .hidScanner: return "HID Scanner"
        case .cameraScanner: return "Camera"
        case .manualEntry: return "Manual"
        }
    }
}

// MARK: - HID Scanner Integration View

/// A view component that integrates HID scanner functionality with a search field
struct HIDScannerIntegratedSearchField: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    @StateObject private var scannerService = BluetoothHIDScannerService()
    
    let placeholder: String
    let onBarcodeScanned: (String) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.default)
                .focused($isSearchFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    // Handle manual search submission
                    if !searchText.isEmpty {
                        onBarcodeScanned(searchText)
                    }
                    isSearchFieldFocused = false
                }
                // REMOVED: .onChange detectHIDInput to prevent recursive barcode processing
                // The HID scanner service already handles barcode detection through onBarcodeScanned callback

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearchFieldFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Scanner status indicator
            if scannerService.isListening {
                Image(systemName: "barcode.viewfinder")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onAppear {
            setupScannerCallbacks()
            scannerService.startListening()
        }
        .onDisappear {
            scannerService.stopListening()
        }
    }
    
    private func setupScannerCallbacks() {
        scannerService.onBarcodeScanned = { barcode in
            DispatchQueue.main.async {
                // DO NOT set searchText = barcode to prevent duplicate .onSubmit trigger
                // Only call the callback directly for HID scanner input
                onBarcodeScanned(barcode)
            }
        }
        
        scannerService.onScanError = { error in
            print("Scanner error: \(error)")
        }
    }
    
    // REMOVED: detectHIDInput function - was causing recursive barcode processing
    // HID scanner detection is now handled entirely by the BluetoothHIDScannerService
}
