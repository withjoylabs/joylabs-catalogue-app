import SwiftUI
import AVFoundation

/// EnhancedScannerView - Advanced scanner interface with multiple scanning modes
/// Combines HID scanner with camera scanner and provides rich feedback
struct EnhancedScannerView: View {
    @StateObject private var controller = ScannerController()
    @State private var showingSettings = false
    @State private var showingHistory = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top toolbar
                    ScannerToolbar(
                        scanMode: controller.scanMode,
                        isHIDEnabled: controller.isHIDEnabled,
                        onToggleHID: controller.toggleHIDScanner,
                        onToggleCamera: controller.toggleCameraScanner,
                        onShowSettings: { showingSettings = true },
                        onShowHistory: { showingHistory = true }
                    )
                    
                    // Main scanning area
                    ZStack {
                        // Camera preview (when camera mode is enabled)
                        if controller.scanMode == .camera || controller.scanMode == .hybrid {
                            CameraScannerView(
                                isScanning: controller.isCameraScanning,
                                onCodeScanned: controller.handleCameraScanned,
                                onError: controller.handleCameraError
                            )
                        } else {
                            // HID-only mode background
                            Rectangle()
                                .fill(Color.black)
                                .overlay(
                                    VStack(spacing: 20) {
                                        Image(systemName: "barcode.viewfinder")
                                            .font(.system(size: 80))
                                            .foregroundColor(.white.opacity(0.3))
                                        
                                        Text("HID Scanner Mode")
                                            .font(.title2)
                                            .foregroundColor(.white.opacity(0.7))
                                        
                                        Text("Use your handheld scanner")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                )
                        }
                        
                        // Scanning overlay
                        ScanningOverlay(
                            scanMode: controller.scanMode,
                            isScanning: controller.isScanning,
                            lastScannedCode: controller.lastScannedCode,
                            scanningFeedback: controller.scanningFeedback
                        )
                        
                        // Scan results overlay
                        if !controller.searchResults.isEmpty {
                            ScanResultsOverlay(
                                results: controller.searchResults,
                                onSelectItem: controller.selectItem,
                                onDismiss: controller.clearResults
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Bottom controls
                    ScannerBottomControls(
                        scanMode: controller.scanMode,
                        isScanning: controller.isScanning,
                        onManualEntry: controller.showManualEntry,
                        onClearResults: controller.clearResults
                    )
                }
                
                // Manual entry sheet
                if controller.showingManualEntry {
                    ManualEntryOverlay(
                        onSubmit: controller.handleManualEntry,
                        onCancel: controller.hideManualEntry
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSettings) {
            ScannerSettingsView()
        }
        .sheet(isPresented: $showingHistory) {
            ScanHistoryView(history: controller.scanHistory)
        }
        .sheet(isPresented: $controller.showingItemDetail) {
            if let item = controller.selectedItem {
                ItemDetailView(item: item)
            }
        }
        // Add HID scanner overlay
        .hidScanner(
            enabled: controller.isHIDEnabled,
            onScan: controller.handleHIDScanned,
            onError: controller.handleHIDError
        )
        .onAppear {
            controller.startScanning()
        }
        .onDisappear {
            controller.stopScanning()
        }
    }
}

// MARK: - Scanner Controller
@MainActor
class ScannerController: ObservableObject {
    // MARK: - Published Properties
    @Published var scanMode: ScanMode = .hybrid
    @Published var isHIDEnabled: Bool = true
    @Published var isCameraScanning: Bool = false
    @Published var isScanning: Bool = false
    @Published var lastScannedCode: String = ""
    @Published var scanningFeedback: ScanningFeedback?
    @Published var searchResults: [SearchResultItem] = []
    @Published var selectedItem: SearchResultItem?
    @Published var showingItemDetail: Bool = false
    @Published var showingManualEntry: Bool = false
    @Published var scanHistory: [ScanHistoryItem] = []
    
    // MARK: - Private Properties
    private let searchManager = SearchManager()
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Scan Modes
    enum ScanMode: CaseIterable {
        case hid
        case camera
        case hybrid
        
        var title: String {
            switch self {
            case .hid: return "HID Only"
            case .camera: return "Camera Only"
            case .hybrid: return "HID + Camera"
            }
        }
        
        var icon: String {
            switch self {
            case .hid: return "barcode"
            case .camera: return "camera"
            case .hybrid: return "barcode.viewfinder"
            }
        }
    }
    
    // MARK: - Public Methods
    func startScanning() {
        isScanning = true
        
        if scanMode == .camera || scanMode == .hybrid {
            isCameraScanning = true
        }
        
        Logger.info("Scanner", "Started scanning in \(scanMode.title) mode")
    }
    
    func stopScanning() {
        isScanning = false
        isCameraScanning = false
        
        Logger.info("Scanner", "Stopped scanning")
    }
    
    func toggleHIDScanner() {
        isHIDEnabled.toggle()
        
        if isHIDEnabled {
            scanMode = scanMode == .camera ? .hybrid : .hid
        } else {
            scanMode = .camera
        }
        
        Logger.info("Scanner", "HID scanner \(isHIDEnabled ? "enabled" : "disabled")")
    }
    
    func toggleCameraScanner() {
        switch scanMode {
        case .hid:
            scanMode = .hybrid
            isCameraScanning = true
        case .camera:
            scanMode = .hid
            isCameraScanning = false
        case .hybrid:
            scanMode = .hid
            isCameraScanning = false
        }
        
        Logger.info("Scanner", "Switched to \(scanMode.title) mode")
    }
    
    func handleHIDScanned(_ barcode: String) {
        processScan(barcode, source: .hid)
    }
    
    func handleCameraScanned(_ barcode: String) {
        processScan(barcode, source: .camera)
    }
    
    func handleManualEntry(_ barcode: String) {
        hideManualEntry()
        processScan(barcode, source: .manual)
    }
    
    func handleHIDError(_ error: String) {
        showScanningFeedback(.error(error), duration: 3.0)
    }
    
    func handleCameraError(_ error: Error) {
        showScanningFeedback(.error(error.localizedDescription), duration: 3.0)
    }
    
    func selectItem(_ item: SearchResultItem) {
        selectedItem = item
        showingItemDetail = true
        clearResults()
    }
    
    func clearResults() {
        searchResults = []
        scanningFeedback = nil
    }
    
    func showManualEntry() {
        showingManualEntry = true
    }
    
    func hideManualEntry() {
        showingManualEntry = false
    }
    
    // MARK: - Private Methods
    private func processScan(_ barcode: String, source: ScanSource) {
        Logger.info("Scanner", "Processing scan: \(barcode) from \(source)")
        
        lastScannedCode = barcode
        
        // Add to scan history
        let historyItem = ScanHistoryItem(
            barcode: barcode,
            source: source,
            timestamp: Date()
        )
        scanHistory.insert(historyItem, at: 0)
        
        // Keep only last 50 scans
        if scanHistory.count > 50 {
            scanHistory = Array(scanHistory.prefix(50))
        }
        
        // Provide haptic feedback
        hapticFeedback.impactOccurred()
        
        // Show scanning feedback
        showScanningFeedback(.scanning(barcode), duration: 1.0)
        
        // Perform search
        Task {
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)
            
            await MainActor.run {
                self.searchResults = results
                
                if results.isEmpty {
                    self.showScanningFeedback(.noResults, duration: 2.0)
                } else if results.count == 1 {
                    // Auto-select single result after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.selectItem(results[0])
                    }
                } else {
                    self.showScanningFeedback(.multipleResults(results.count), duration: 2.0)
                }
            }
        }
    }
    
    private func showScanningFeedback(_ feedback: ScanningFeedback, duration: TimeInterval) {
        scanningFeedback = feedback
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.scanningFeedback == feedback {
                self?.scanningFeedback = nil
            }
        }
    }
}

// MARK: - Supporting Types
enum ScanSource: String, CaseIterable {
    case hid = "HID"
    case camera = "Camera"
    case manual = "Manual"
}

enum ScanningFeedback: Equatable {
    case scanning(String)
    case noResults
    case multipleResults(Int)
    case error(String)
    
    var message: String {
        switch self {
        case .scanning(let code):
            return "Scanning: \(code)"
        case .noResults:
            return "No results found"
        case .multipleResults(let count):
            return "\(count) results found"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var color: Color {
        switch self {
        case .scanning:
            return .blue
        case .noResults:
            return .orange
        case .multipleResults:
            return .green
        case .error:
            return .red
        }
    }
}

struct ScanHistoryItem: Identifiable {
    let id = UUID()
    let barcode: String
    let source: ScanSource
    let timestamp: Date
}

#Preview {
    EnhancedScannerView()
}
