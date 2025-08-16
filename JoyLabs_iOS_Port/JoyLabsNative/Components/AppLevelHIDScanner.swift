import SwiftUI
import UIKit

// MARK: - App-Level HID Scanner (No TextField - Pure UIKeyCommand)
class AppLevelHIDScannerViewController: UIViewController {
    // Context-aware callbacks
    var onBarcodeScanned: ((String, HIDScannerContext) -> Void)?
    private var currentContext: HIDScannerContext = .none
    
    // Input processing state  
    private var inputBuffer = ""
    private var firstCharTime: Date?
    private var inputTimer: Timer?
    
    // Timing constants for intelligent detection
    private let barcodeTimeout: TimeInterval = 0.15  // 150ms timeout
    private let maxHumanTypingSpeed: TimeInterval = 0.08  // 80ms between chars (fast human)
    
    // Focus and modal monitoring
    private var isAnyTextFieldFocused = false
    private var isModalPresented = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true  // Invisible - purely for key capture
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Always become first responder for global key capture
        if !isFirstResponder {
            becomeFirstResponder()
            print("[AppLevelHIDScanner] Became first responder for global key capture")
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    // MARK: - UIKeyCommand Implementation (No TextField Needed)
    override var keyCommands: [UIKeyCommand]? {
        // Don't process keys if a text field is focused OR a modal is presented
        guard !isAnyTextFieldFocused && !isModalPresented else { return [] }
        
        var commands: [UIKeyCommand] = []
        
        // Numbers 0-9 (most common in barcodes)
        for i in 0...9 {
            commands.append(UIKeyCommand(
                input: "\(i)",
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }
        
        // Letters A-Z (some barcodes include letters)
        for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }
        
        // Lowercase letters a-z
        for char in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(UIKeyCommand(
                input: String(char),
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }
        
        // Special characters common in barcodes
        let specialChars = ["-", "_", ".", " ", "/", "\\\\", "+", "=", "*", "%", "$", "#", "@", "!", "?"]
        for char in specialChars {
            commands.append(UIKeyCommand(
                input: char,
                modifierFlags: [],
                action: #selector(handleCharacterInput(_:))
            ))
        }
        
        // Return key (end of barcode scan)
        commands.append(UIKeyCommand(
            input: "\\r",
            modifierFlags: [],
            action: #selector(handleReturnKey)
        ))
        
        // Enter key (alternative end of barcode)
        commands.append(UIKeyCommand(
            input: "\\n", 
            modifierFlags: [],
            action: #selector(handleReturnKey)
        ))
        
        return commands
    }
    
    // MARK: - Key Input Handling
    
    @objc private func handleCharacterInput(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        
        let currentTime = Date()
        
        // Start timing on first character
        if inputBuffer.isEmpty {
            firstCharTime = currentTime
            print("[AppLevelHIDScanner] Input sequence started...")
        }
        
        // Add character to buffer
        inputBuffer += input
        
        // Reset completion timer
        inputTimer?.invalidate()
        inputTimer = Timer.scheduledTimer(withTimeInterval: barcodeTimeout, repeats: false) { [weak self] _ in
            self?.analyzeAndProcessInput()
        }
    }
    
    @objc private func handleReturnKey() {
        print("[AppLevelHIDScanner] Return key detected - processing input immediately")
        analyzeAndProcessInput()
    }
    
    private func analyzeAndProcessInput() {
        guard !inputBuffer.isEmpty else { return }
        
        let finalInput = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputLength = finalInput.count
        
        // Calculate input speed if we have timing data
        var inputSpeed: Double = 0
        if let startTime = firstCharTime {
            let totalTime = Date().timeIntervalSince(startTime)
            inputSpeed = totalTime / Double(inputLength) // seconds per character
        }
        
        // INTELLIGENT DETECTION LOGIC (from original implementation)
        let isBarcodePattern = detectBarcodePattern(input: finalInput, speed: inputSpeed, length: inputLength)
        
        if isBarcodePattern {
            print("[AppLevelHIDScanner] BARCODE DETECTED: '\(finalInput)' (speed: \(String(format: "%.3f", inputSpeed))s/char)")
            
            // Send to context-aware callback
            DispatchQueue.main.async { [weak self] in
                if let self = self {
                    self.onBarcodeScanned?(finalInput, self.currentContext)
                }
            }
        } else {
            print("[AppLevelHIDScanner] KEYBOARD INPUT IGNORED: '\(finalInput)' (speed: \(String(format: "%.3f", inputSpeed))s/char)")
        }
        
        // Clear state
        clearBuffer()
    }
    
    private func detectBarcodePattern(input: String, speed: Double, length: Int) -> Bool {
        // 1. Speed Detection: Barcode scanners are MUCH faster than human typing
        let isVeryFastInput = speed < maxHumanTypingSpeed && speed > 0
        
        // 2. Length Detection: Barcodes are typically 8-20 characters  
        let isBarcodeLength = length >= 8 && length <= 20
        
        // 3. Pattern Detection: Barcodes are usually all numbers or alphanumeric without spaces
        let isNumericOnly = input.allSatisfy { $0.isNumber }
        let isAlphanumericNoSpaces = input.allSatisfy { $0.isLetter || $0.isNumber } && !input.contains(" ")
        let isBarcodePattern = isNumericOnly || isAlphanumericNoSpaces
        
        // DECISION LOGIC: Must meet multiple criteria
        let speedAndLengthMatch = isVeryFastInput && isBarcodeLength
        let patternMatches = isBarcodePattern
        
        // High confidence: Fast input + right length + barcode pattern
        if speedAndLengthMatch && patternMatches {
            return true
        }
        
        // Medium confidence: Very fast input with reasonable length (even if pattern is unclear)
        if isVeryFastInput && length >= 6 {
            return true
        }
        
        // Low confidence: Assume it's keyboard input
        return false
    }
    
    private func clearBuffer() {
        inputBuffer = ""
        firstCharTime = nil
        inputTimer?.invalidate()
    }
    
    // MARK: - Context Management
    
    func updateContext(_ context: HIDScannerContext) {
        currentContext = context
        print("[AppLevelHIDScanner] Context updated to: \(context)")
    }
    
    func updateTextFieldFocus(_ isFocused: Bool) {
        isAnyTextFieldFocused = isFocused
        print("[AppLevelHIDScanner] Text field focus: \(isFocused)")
        
        if isFocused {
            // Clear any accumulated input when user focuses a text field
            clearBuffer()
        }
    }
    
    func updateModalPresentation(_ isPresented: Bool) {
        isModalPresented = isPresented
        print("[AppLevelHIDScanner] Modal presentation: \(isPresented)")
        
        if isPresented {
            // Clear any accumulated input when a modal is presented
            clearBuffer()
        }
    }
}

// MARK: - SwiftUI Wrapper for App-Level Scanner
struct AppLevelHIDScanner: UIViewControllerRepresentable {
    let onBarcodeScanned: (String, HIDScannerContext) -> Void
    let context: HIDScannerContext
    let isTextFieldFocused: Bool
    let isModalPresented: Bool
    
    func makeUIViewController(context: Context) -> AppLevelHIDScannerViewController {
        let controller = AppLevelHIDScannerViewController()
        controller.onBarcodeScanned = onBarcodeScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AppLevelHIDScannerViewController, context: Context) {
        uiViewController.updateContext(self.context)
        uiViewController.updateTextFieldFocus(isTextFieldFocused)
        uiViewController.updateModalPresentation(isModalPresented)
    }
}

// MARK: - HID Scanner Context
enum HIDScannerContext {
    case none
    case scanView
    case reordersView
    
    var description: String {
        switch self {
        case .none: return "none"
        case .scanView: return "scanView" 
        case .reordersView: return "reordersView"
        }
    }
}

// MARK: - Global HID Scanner Manager removed - using direct callbacks instead