import SwiftUI
import AVFoundation
import Vision

/// CameraScannerView - Camera-based barcode scanner using AVFoundation
/// Provides real-time barcode detection with Vision framework
struct CameraScannerView: UIViewRepresentable {
    let isScanning: Bool
    let onCodeScanned: (String) -> Void
    let onError: (Error) -> Void
    
    func makeUIView(context: Context) -> CameraScannerUIView {
        let view = CameraScannerUIView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: CameraScannerUIView, context: Context) {
        if isScanning {
            uiView.startScanning()
        } else {
            uiView.stopScanning()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onError: onError)
    }
    
    class Coordinator: NSObject, CameraScannerDelegate {
        let onCodeScanned: (String) -> Void
        let onError: (Error) -> Void
        
        init(onCodeScanned: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
        }
        
        func cameraScannerDidScanCode(_ code: String) {
            onCodeScanned(code)
        }
        
        func cameraScannerDidEncounterError(_ error: Error) {
            onError(error)
        }
    }
}

// MARK: - Camera Scanner Delegate
protocol CameraScannerDelegate: AnyObject {
    func cameraScannerDidScanCode(_ code: String)
    func cameraScannerDidEncounterError(_ error: Error)
}

// MARK: - Camera Scanner UI View
class CameraScannerUIView: UIView {
    weak var delegate: CameraScannerDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    // Barcode detection
    private var lastScannedCode: String?
    private var lastScanTime: Date = Date()
    private let scanCooldown: TimeInterval = 1.0 // Prevent duplicate scans
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    private func configureSession() {
        guard captureSession == nil else { return }
        
        let session = AVCaptureSession()
        
        // Configure session
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async {
                self.delegate?.cameraScannerDidEncounterError(CameraScannerError.cameraUnavailable)
            }
            return
        }
        
        session.addInput(input)
        
        // Add video output
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        guard session.canAddOutput(output) else {
            DispatchQueue.main.async {
                self.delegate?.cameraScannerDidEncounterError(CameraScannerError.configurationFailed)
            }
            return
        }
        
        session.addOutput(output)
        session.commitConfiguration()
        
        // Setup preview layer
        DispatchQueue.main.async {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = self.bounds
            self.layer.addSublayer(previewLayer)
            
            self.captureSession = session
            self.previewLayer = previewLayer
            self.videoOutput = output
        }
        
        Logger.info("CameraScanner", "Camera session configured successfully")
    }
    
    // MARK: - Scanning Control
    func startScanning() {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, !session.isRunning else { return }
            session.startRunning()
            
            DispatchQueue.main.async {
                Logger.info("CameraScanner", "Camera scanning started")
            }
        }
    }
    
    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, session.isRunning else { return }
            session.stopRunning()
            
            DispatchQueue.main.async {
                Logger.info("CameraScanner", "Camera scanning stopped")
            }
        }
    }
    
    // MARK: - Barcode Detection
    private func detectBarcodes(in sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.delegate?.cameraScannerDidEncounterError(error)
                }
                return
            }
            
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            for result in results {
                if let payload = result.payloadStringValue,
                   !payload.isEmpty,
                   self?.shouldProcessScan(payload) == true {
                    
                    DispatchQueue.main.async {
                        self?.delegate?.cameraScannerDidScanCode(payload)
                    }
                    
                    self?.lastScannedCode = payload
                    self?.lastScanTime = Date()
                    break // Process only the first valid barcode
                }
            }
        }
        
        // Configure barcode types to detect
        request.symbologies = [
            .ean8,
            .ean13,
            .upce,
            .code128,
            .code39,
            .code93,
            .codabar,
            .itf14,
            .dataMatrix,
            .qr,
            .pdf417
        ]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.delegate?.cameraScannerDidEncounterError(error)
            }
        }
    }
    
    private func shouldProcessScan(_ code: String) -> Bool {
        // Prevent duplicate scans
        if code == lastScannedCode && Date().timeIntervalSince(lastScanTime) < scanCooldown {
            return false
        }
        
        // Basic validation
        return code.count >= 8 && code.count <= 50
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraScannerUIView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        detectBarcodes(in: sampleBuffer)
    }
}

// MARK: - Scanner Settings View
struct ScannerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scannerHapticFeedback") private var hapticFeedback = true
    @AppStorage("scannerSoundFeedback") private var soundFeedback = false
    @AppStorage("scannerAutoSelect") private var autoSelect = true
    @AppStorage("scannerScanCooldown") private var scanCooldown = 1.0
    @AppStorage("scannerPreferredMode") private var preferredMode = "hybrid"
    
    var body: some View {
        NavigationView {
            Form {
                Section("Feedback") {
                    Toggle("Haptic Feedback", isOn: $hapticFeedback)
                    Toggle("Sound Feedback", isOn: $soundFeedback)
                }
                
                Section("Behavior") {
                    Toggle("Auto-select Single Results", isOn: $autoSelect)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scan Cooldown")
                            Spacer()
                            Text("\(scanCooldown, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $scanCooldown, in: 0.5...3.0, step: 0.1)
                    }
                }
                
                Section("Default Mode") {
                    Picker("Preferred Scan Mode", selection: $preferredMode) {
                        Text("HID Only").tag("hid")
                        Text("Camera Only").tag("camera")
                        Text("HID + Camera").tag("hybrid")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Camera") {
                    NavigationLink("Camera Permissions") {
                        CameraPermissionsView()
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Scanner Engine")
                        Spacer()
                        Text("Vision + HID")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Scanner Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Camera Permissions View
struct CameraPermissionsView: View {
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: cameraStatusIcon)
                .font(.system(size: 60))
                .foregroundColor(cameraStatusColor)
            
            Text(cameraStatusTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(cameraStatusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if cameraStatus == .denied {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if cameraStatus == .notDetermined {
                Button("Request Permission") {
                    requestCameraPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            checkCameraPermission()
        }
        .navigationTitle("Camera Access")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var cameraStatusIcon: String {
        switch cameraStatus {
        case .authorized:
            return "checkmark.circle"
        case .denied, .restricted:
            return "xmark.circle"
        case .notDetermined:
            return "questionmark.circle"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    private var cameraStatusColor: Color {
        switch cameraStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private var cameraStatusTitle: String {
        switch cameraStatus {
        case .authorized:
            return "Camera Access Granted"
        case .denied:
            return "Camera Access Denied"
        case .restricted:
            return "Camera Access Restricted"
        case .notDetermined:
            return "Camera Permission Required"
        @unknown default:
            return "Unknown Status"
        }
    }
    
    private var cameraStatusDescription: String {
        switch cameraStatus {
        case .authorized:
            return "The app has permission to use the camera for barcode scanning."
        case .denied:
            return "Camera access is required for camera-based barcode scanning. You can enable it in Settings."
        case .restricted:
            return "Camera access is restricted by device policies."
        case .notDetermined:
            return "The app needs camera permission to scan barcodes using the device camera."
        @unknown default:
            return "Camera permission status is unknown."
        }
    }
    
    private func checkCameraPermission() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraStatus = granted ? .authorized : .denied
            }
        }
    }
}

// MARK: - Scan History View
struct ScanHistoryView: View {
    let history: [ScanHistoryItem]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Scan History")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Your recent scans will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(history) { item in
                        ScanHistoryRow(item: item)
                    }
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Scan History Row
struct ScanHistoryRow: View {
    let item: ScanHistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.barcode)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(item.source.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor.opacity(0.2))
                    .foregroundColor(sourceColor)
                    .cornerRadius(4)
            }
            
            Text(RelativeDateTimeFormatter().localizedString(for: item.timestamp, relativeTo: Date()))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private var sourceColor: Color {
        switch item.source {
        case .hid:
            return .blue
        case .camera:
            return .green
        case .manual:
            return .orange
        }
    }
}

// MARK: - Camera Scanner Error
enum CameraScannerError: LocalizedError {
    case cameraUnavailable
    case configurationFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device"
        case .configurationFailed:
            return "Failed to configure camera session"
        case .permissionDenied:
            return "Camera permission is required for scanning"
        }
    }
}
