import Foundation
import Network

// MARK: - Printer Information
struct PrinterInfo: Identifiable, Codable {
    let id: String
    var name: String
    let type: PrinterType
    var connectionInfo: PrinterConnectionInfo?
    var capabilities: PrinterCapabilities?
    var isOnline: Bool
    var lastSeen: Date?
    
    init(id: String, name: String, type: PrinterType, connectionInfo: PrinterConnectionInfo? = nil, capabilities: PrinterCapabilities? = nil, isOnline: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.connectionInfo = connectionInfo
        self.capabilities = capabilities
        self.isOnline = isOnline
        self.lastSeen = isOnline ? Date() : nil
    }
}

// MARK: - Printer Types
enum PrinterType: String, CaseIterable, Codable {
    case airPrint = "airprint"
    case network = "network"
    case bluetooth = "bluetooth"
    case usb = "usb"
    
    var displayName: String {
        switch self {
        case .airPrint: return "AirPrint"
        case .network: return "Network Printer"
        case .bluetooth: return "Bluetooth Printer"
        case .usb: return "USB Printer"
        }
    }
    
    var systemImage: String {
        switch self {
        case .airPrint: return "printer"
        case .network: return "network"
        case .bluetooth: return "bluetooth"
        case .usb: return "cable.connector"
        }
    }
    
    var requiresDiscovery: Bool {
        switch self {
        case .airPrint, .network, .bluetooth: return true
        case .usb: return false
        }
    }
    
    var supportedFormats: [LabelFormat] {
        switch self {
        case .airPrint: return [.png, .pdf]
        case .network: return [.png, .pdf, .eps]
        case .bluetooth: return [.png]
        case .usb: return [.png, .pdf]
        }
    }
}

// MARK: - Connection Information
protocol PrinterConnectionInfo: Codable {}

struct NetworkConnectionInfo: PrinterConnectionInfo {
    let endpoint: String // Serialized NWEndpoint
    let interface: String? // Serialized NWInterface
    let ipAddress: String?
    let port: Int?
    
    init(endpoint: NWEndpoint, interface: NWInterface?) {
        self.endpoint = endpoint.debugDescription
        self.interface = interface?.debugDescription
        
        // Extract IP and port if available
        if case .hostPort(let host, let port) = endpoint {
            self.ipAddress = "\(host)"
            self.port = Int(port.rawValue)
        } else {
            self.ipAddress = nil
            self.port = nil
        }
    }
}

struct BluetoothConnectionInfo: PrinterConnectionInfo {
    let deviceId: String
    let deviceName: String
    let rssi: Int?
    let serviceUUIDs: [String]
}

struct USBConnectionInfo: PrinterConnectionInfo {
    let vendorId: String
    let productId: String
    let serialNumber: String?
}

// MARK: - Printer Capabilities
struct PrinterCapabilities: Codable {
    let supportedSizes: [LabelSize]
    let supportedFormats: [LabelFormat]
    let maxResolution: PrintResolution
    let colorSupport: ColorSupport
    let features: PrinterFeatures
    
    static let defaultAirPrint = PrinterCapabilities(
        supportedSizes: [.standard_2x1, .large_4x2],
        supportedFormats: [.png, .pdf],
        maxResolution: .dpi300,
        colorSupport: .color,
        features: PrinterFeatures(
            duplex: true,
            borderless: false,
            customSizes: true,
            qualitySettings: [.draft, .normal, .high]
        )
    )
    
    static let defaultNetwork = PrinterCapabilities(
        supportedSizes: LabelSize.allSizes,
        supportedFormats: [.png, .pdf, .eps],
        maxResolution: .dpi600,
        colorSupport: .color,
        features: PrinterFeatures(
            duplex: true,
            borderless: true,
            customSizes: true,
            qualitySettings: [.draft, .normal, .high, .photo]
        )
    )
    
    static let defaultBluetooth = PrinterCapabilities(
        supportedSizes: [.standard_2x1, .small_1x1],
        supportedFormats: [.png],
        maxResolution: .dpi203,
        colorSupport: .monochrome,
        features: PrinterFeatures(
            duplex: false,
            borderless: false,
            customSizes: false,
            qualitySettings: [.normal]
        )
    )
    
    static let defaultUSB = PrinterCapabilities(
        supportedSizes: LabelSize.allSizes,
        supportedFormats: [.png, .pdf],
        maxResolution: .dpi600,
        colorSupport: .color,
        features: PrinterFeatures(
            duplex: true,
            borderless: true,
            customSizes: true,
            qualitySettings: [.draft, .normal, .high, .photo]
        )
    )
}

enum PrintResolution: String, CaseIterable, Codable {
    case dpi150 = "150"
    case dpi203 = "203"
    case dpi300 = "300"
    case dpi600 = "600"
    case dpi1200 = "1200"
    
    var dpi: CGFloat {
        return CGFloat(Int(rawValue) ?? 300)
    }
    
    var displayName: String {
        return "\(rawValue) DPI"
    }
}

enum ColorSupport: String, CaseIterable, Codable {
    case monochrome = "monochrome"
    case color = "color"
    
    var displayName: String {
        switch self {
        case .monochrome: return "Black & White"
        case .color: return "Color"
        }
    }
}

struct PrinterFeatures: Codable {
    let duplex: Bool
    let borderless: Bool
    let customSizes: Bool
    let qualitySettings: [PrintQuality]
}

enum PrintQuality: String, CaseIterable, Codable {
    case draft = "draft"
    case normal = "normal"
    case high = "high"
    case photo = "photo"
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .normal: return "Normal"
        case .high: return "High Quality"
        case .photo: return "Photo Quality"
        }
    }
}

// MARK: - Print Settings
struct PrintSettings: Codable {
    var copies: Int
    var quality: PrintQuality
    var resolution: PrintResolution
    var colorMode: ColorSupport
    var paperSize: LabelSize
    var margins: PrintMargins
    var scaling: PrintScaling
    var orientation: PrintOrientation
    var advanced: AdvancedPrintSettings
    
    init(
        copies: Int = 1,
        quality: PrintQuality = .normal,
        resolution: PrintResolution = .dpi300,
        colorMode: ColorSupport = .color,
        paperSize: LabelSize = .standard_2x1,
        margins: PrintMargins = PrintMargins(),
        scaling: PrintScaling = .fitToPage,
        orientation: PrintOrientation = .portrait,
        advanced: AdvancedPrintSettings = AdvancedPrintSettings()
    ) {
        self.copies = copies
        self.quality = quality
        self.resolution = resolution
        self.colorMode = colorMode
        self.paperSize = paperSize
        self.margins = margins
        self.scaling = scaling
        self.orientation = orientation
        self.advanced = advanced
    }
}

struct PrintMargins: Codable {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat
    
    init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
    
    static let none = PrintMargins()
    static let small = PrintMargins(top: 2, bottom: 2, left: 2, right: 2)
    static let medium = PrintMargins(top: 5, bottom: 5, left: 5, right: 5)
    static let large = PrintMargins(top: 10, bottom: 10, left: 10, right: 10)
}

enum PrintScaling: String, CaseIterable, Codable {
    case none = "none"
    case fitToPage = "fit_to_page"
    case fillPage = "fill_page"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .none: return "Actual Size"
        case .fitToPage: return "Fit to Page"
        case .fillPage: return "Fill Page"
        case .custom: return "Custom"
        }
    }
}

enum PrintOrientation: String, CaseIterable, Codable {
    case portrait = "portrait"
    case landscape = "landscape"
    
    var displayName: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }
}

struct AdvancedPrintSettings: Codable {
    var brightness: Double
    var contrast: Double
    var saturation: Double
    var sharpness: Double
    var gamma: Double
    var blackPointCompensation: Bool
    var colorProfile: String?
    
    init(
        brightness: Double = 0.0,
        contrast: Double = 0.0,
        saturation: Double = 0.0,
        sharpness: Double = 0.0,
        gamma: Double = 1.0,
        blackPointCompensation: Bool = true,
        colorProfile: String? = nil
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
        self.gamma = gamma
        self.blackPointCompensation = blackPointCompensation
        self.colorProfile = colorProfile
    }
}

// MARK: - Print Job
struct PrintJob: Identifiable, Codable {
    let id: String
    let templateId: String
    let itemId: String?
    let printerName: String
    let settings: PrintSettings
    var status: PrintJobStatus
    let createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
    
    init(id: String, templateId: String, itemId: String? = nil, printerName: String, settings: PrintSettings, status: PrintJobStatus, createdAt: Date) {
        self.id = id
        self.templateId = templateId
        self.itemId = itemId
        self.printerName = printerName
        self.settings = settings
        self.status = status
        self.createdAt = createdAt
    }
}

enum PrintJobStatus: Codable, Equatable {
    case queued
    case printing
    case completed
    case failed(String)
    case cancelled
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .printing: return "Printing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .queued, .printing: return true
        case .completed, .failed, .cancelled: return false
        }
    }
    
    var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - Printer Connection Status
enum PrinterConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Printer Errors
enum PrinterError: LocalizedError {
    case noPrinterSelected
    case printerNotFound
    case connectionFailed
    case printingFailed
    case unsupportedFormat
    case unsupportedPrinterType
    case invalidConnectionInfo
    case printerOffline
    case insufficientPermissions
    
    var errorDescription: String? {
        switch self {
        case .noPrinterSelected:
            return "No printer selected"
        case .printerNotFound:
            return "Printer not found"
        case .connectionFailed:
            return "Failed to connect to printer"
        case .printingFailed:
            return "Printing failed"
        case .unsupportedFormat:
            return "Unsupported print format"
        case .unsupportedPrinterType:
            return "Unsupported printer type"
        case .invalidConnectionInfo:
            return "Invalid printer connection information"
        case .printerOffline:
            return "Printer is offline"
        case .insufficientPermissions:
            return "Insufficient permissions to access printer"
        }
    }
}
