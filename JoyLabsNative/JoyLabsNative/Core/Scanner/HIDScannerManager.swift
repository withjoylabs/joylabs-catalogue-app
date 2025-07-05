import UIKit
import SwiftUI
import Combine

/// HIDScannerManager - Port of the sophisticated dual-TextInput HID scanner system
/// This replicates the exact behavior from the React Native BarcodeScanner component
class HIDScannerManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isEnabled: Bool = true
    @Published var isListening: Bool = false
    @Published var lastScannedCode: String = ""
    
    // MARK: - Private Properties
    private var primaryTextField: UITextField
    private var secondaryTextField: UITextField
    private var focusTimer: Timer?
    private var scanTimeout: Timer?
    
    // Configuration
    private let minLength: Int
    private let maxLength: Int
    private let timeout: TimeInterval
    
    // Callbacks
    var onScan: ((String) -> Void)?
    var onError: ((String) -> Void)?
    
    // MARK: - Initialization
    init(minLength: Int = 8, maxLength: Int = 50, timeout: TimeInterval = 0.15) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.timeout = timeout
        
        // Initialize text fields
        self.primaryTextField = UITextField()
        self.secondaryTextField = UITextField()
        
        setupTextFields()
        startFocusMaintenance()
    }
    
    deinit {
        stopFocusMaintenance()
        cleanup()
    }
    
    // MARK: - Setup Methods
    private func setupTextFields() {
        // Configure primary text field (main HID input receiver)
        primaryTextField.inputView = UIView() // Suppress keyboard
        primaryTextField.inputAccessoryView = UIView(frame: .zero)
        primaryTextField.autocorrectionType = .no
        primaryTextField.autocapitalizationType = .none
        primaryTextField.spellCheckingType = .no
        primaryTextField.smartDashesType = .no
        primaryTextField.smartQuotesType = .no
        primaryTextField.smartInsertDeleteType = .no
        primaryTextField.keyboardType = .numbersAndPunctuation
        primaryTextField.returnKeyType = .done
        primaryTextField.isSecureTextEntry = false
        primaryTextField.clearsOnBeginEditing = false
        primaryTextField.delegate = self
        
        // Configure secondary text field (processing buffer)
        secondaryTextField.inputView = UIView() // Suppress keyboard
        secondaryTextField.inputAccessoryView = UIView(frame: .zero)
        secondaryTextField.autocorrectionType = .no
        secondaryTextField.autocapitalizationType = .none
        secondaryTextField.spellCheckingType = .no
        secondaryTextField.delegate = self
        
        // Add target actions for text changes
        primaryTextField.addTarget(self, action: #selector(primaryTextChanged), for: .editingChanged)
        secondaryTextField.addTarget(self, action: #selector(secondaryTextChanged), for: .editingChanged)
        
        Logger.debug("HIDScanner", "Text fields configured for HID scanner input")
    }
    
    private func startFocusMaintenance() {
        // Replicate the React Native setInterval(2000) focus maintenance
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.maintainFocus()
        }
        
        Logger.debug("HIDScanner", "Focus maintenance timer started")
    }
    
    private func stopFocusMaintenance() {
        focusTimer?.invalidate()
        focusTimer = nil
        Logger.debug("HIDScanner", "Focus maintenance timer stopped")
    }
    
    private func maintainFocus() {
        guard isEnabled else { return }
        
        // Only focus if not already focused and enabled
        if !primaryTextField.isFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.primaryTextField.becomeFirstResponder()
            }
        }
    }
    
    // MARK: - Public Methods
    func enable() {
        isEnabled = true
        isListening = true
        
        DispatchQueue.main.async { [weak self] in
            self?.primaryTextField.becomeFirstResponder()
        }
        
        Logger.info("HIDScanner", "HID scanner enabled and listening")
    }
    
    func disable() {
        isEnabled = false
        isListening = false
        
        DispatchQueue.main.async { [weak self] in
            self?.primaryTextField.resignFirstResponder()
            self?.secondaryTextField.resignFirstResponder()
        }
        
        Logger.info("HIDScanner", "HID scanner disabled")
    }
    
    func cleanup() {
        stopFocusMaintenance()
        scanTimeout?.invalidate()
        
        DispatchQueue.main.async { [weak self] in
            self?.primaryTextField.resignFirstResponder()
            self?.secondaryTextField.resignFirstResponder()
        }
    }
    
    // MARK: - Text Field Actions
    @objc private func primaryTextChanged() {
        // Handle real-time text input from HID scanner
        guard let text = primaryTextField.text, !text.isEmpty else { return }
        
        Logger.debug("HIDScanner", "Primary text changed: '\(text)' (\(text.count) chars)")
        
        // Cancel any existing timeout
        scanTimeout?.invalidate()
        
        // Set timeout for processing (replicate React Native timeout behavior)
        scanTimeout = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.processPrimaryInput(text)
        }
    }
    
    @objc private func secondaryTextChanged() {
        // Handle secondary text field changes (if needed)
        guard let text = secondaryTextField.text, !text.isEmpty else { return }
        Logger.debug("HIDScanner", "Secondary text changed: '\(text)'")
    }
    
    private func processPrimaryInput(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Logger.info("HIDScanner", "Processing barcode input: '\(trimmedInput)' (\(trimmedInput.count) chars)")
        
        // Validate GTIN format (exact port from React Native)
        if isValidGTIN(trimmedInput) {
            Logger.info("HIDScanner", "Valid GTIN-\(trimmedInput.count) detected: \(trimmedInput)")
            
            // Clear inputs immediately
            clearInputs()
            
            // Store last scanned code
            lastScannedCode = trimmedInput
            
            // Trigger callback
            onScan?(trimmedInput)
            
            // Refocus primary input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.primaryTextField.becomeFirstResponder()
            }
        } else {
            let errorMsg = "Invalid GTIN format: \(trimmedInput) (\(trimmedInput.count) chars, must be 8/12/13/14 digits)"
            Logger.warn("HIDScanner", errorMsg)
            
            // Clear inputs
            clearInputs()
            
            // Trigger error callback
            onError?(errorMsg)
            
            // Refocus primary input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.primaryTextField.becomeFirstResponder()
            }
        }
    }
    
    private func clearInputs() {
        DispatchQueue.main.async { [weak self] in
            self?.primaryTextField.text = ""
            self?.secondaryTextField.text = ""
        }
    }
    
    // MARK: - GTIN Validation
    private func isValidGTIN(_ code: String) -> Bool {
        // Exact port from React Native validation logic
        let validLengths = [8, 12, 13, 14]
        
        // Check if all characters are digits
        let isAllDigits = code.allSatisfy { $0.isNumber }
        
        // Check if length is valid
        let isValidLength = validLengths.contains(code.count)
        
        return isAllDigits && isValidLength
    }
    
    // MARK: - UIView Integration
    func getHiddenTextFieldView() -> UIView {
        let containerView = UIView()
        containerView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        containerView.isHidden = true
        containerView.alpha = 0
        
        primaryTextField.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        secondaryTextField.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        containerView.addSubview(primaryTextField)
        containerView.addSubview(secondaryTextField)
        
        return containerView
    }
}

// MARK: - UITextFieldDelegate
extension HIDScannerManager: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Handle Enter key from HID scanner (replicates onSubmitEditing)
        if textField == primaryTextField {
            let completeBarcode = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if !completeBarcode.isEmpty {
                Logger.debug("HIDScanner", "Enter key pressed with barcode: '\(completeBarcode)'")
                
                // Transfer to secondary input and process
                secondaryTextField.text = completeBarcode
                processPrimaryInput(completeBarcode)
                
                // Clear primary input
                textField.text = ""
            }
        }
        
        return false // Don't dismiss keyboard (we suppress it anyway)
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Allow all character input for HID scanners
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == primaryTextField {
            isListening = true
            Logger.debug("HIDScanner", "Primary text field gained focus - listening for HID input")
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == primaryTextField {
            isListening = false
            Logger.debug("HIDScanner", "Primary text field lost focus - stopped listening")
        }
    }
}
