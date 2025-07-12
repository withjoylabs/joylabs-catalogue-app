import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Label Template
struct LabelTemplate: Identifiable, Codable {
    let id: String
    var name: String
    var category: LabelCategory
    var size: LabelSize
    var elements: [LabelElement]
    let isBuiltIn: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Computed properties
    var aspectRatio: CGFloat {
        return size.width / size.height
    }
    
    var displaySize: CGSize {
        return CGSize(width: size.width, height: size.height)
    }
}

// MARK: - Label Categories
enum LabelCategory: String, CaseIterable, Codable {
    case price = "price"
    case barcode = "barcode"
    case detailed = "detailed"
    case minimal = "minimal"
    case vendor = "vendor"
    case promotional = "promotional"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .price: return "Price Labels"
        case .barcode: return "Barcode Labels"
        case .detailed: return "Detailed Info"
        case .minimal: return "Minimal"
        case .vendor: return "Vendor Info"
        case .promotional: return "Promotional"
        case .custom: return "Custom"
        }
    }
    
    var systemImage: String {
        switch self {
        case .price: return "dollarsign.circle"
        case .barcode: return "barcode"
        case .detailed: return "list.bullet.rectangle"
        case .minimal: return "minus.circle"
        case .vendor: return "building.2"
        case .promotional: return "megaphone"
        case .custom: return "paintbrush"
        }
    }
    
    var color: Color {
        switch self {
        case .price: return .green
        case .barcode: return .blue
        case .detailed: return .purple
        case .minimal: return .gray
        case .vendor: return .orange
        case .promotional: return .red
        case .custom: return .pink
        }
    }
}

// MARK: - Label Sizes
struct LabelSize: Codable, Equatable {
    let width: CGFloat
    let height: CGFloat
    let name: String
    let description: String
    
    // Standard label sizes (in points, 72 DPI)
    static let small_1x1 = LabelSize(width: 100, height: 100, name: "1\" × 1\"", description: "Small square label")
    static let standard_2x1 = LabelSize(width: 200, height: 100, name: "2\" × 1\"", description: "Standard price label")
    static let large_4x2 = LabelSize(width: 400, height: 200, name: "4\" × 2\"", description: "Large detailed label")
    static let wide_4x1 = LabelSize(width: 400, height: 100, name: "4\" × 1\"", description: "Wide banner label")
    static let tall_2x4 = LabelSize(width: 200, height: 400, name: "2\" × 4\"", description: "Tall vertical label")
    static let custom = LabelSize(width: 0, height: 0, name: "Custom", description: "Custom size")
    
    static let allSizes: [LabelSize] = [
        .small_1x1,
        .standard_2x1,
        .large_4x2,
        .wide_4x1,
        .tall_2x4
    ]
    
    var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return width / height
    }
    
    var isPortrait: Bool {
        return height > width
    }
    
    var isLandscape: Bool {
        return width > height
    }
    
    var isSquare: Bool {
        return abs(width - height) < 1.0
    }
}

// MARK: - Label Element
struct LabelElement: Identifiable, Codable {
    let id: String
    var type: LabelElementType
    var content: Any?
    var frame: CGRect
    var style: LabelElementStyle
    var isLocked: Bool
    var isVisible: Bool
    var zIndex: Int
    
    init(
        id: String,
        type: LabelElementType,
        content: Any? = nil,
        frame: CGRect,
        style: LabelElementStyle = LabelElementStyle(),
        isLocked: Bool = false,
        isVisible: Bool = true,
        zIndex: Int = 0
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.frame = frame
        self.style = style
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.zIndex = zIndex
    }
    
    // Custom Codable implementation to handle Any? content
    enum CodingKeys: String, CodingKey {
        case id, type, frame, style, isLocked, isVisible, zIndex
        case contentString, contentDouble, contentInt, contentBool
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(LabelElementType.self, forKey: .type)
        frame = try container.decode(CGRect.self, forKey: .frame)
        style = try container.decode(LabelElementStyle.self, forKey: .style)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        
        // Decode content based on type
        if let stringContent = try? container.decode(String.self, forKey: .contentString) {
            content = stringContent
        } else if let doubleContent = try? container.decode(Double.self, forKey: .contentDouble) {
            content = doubleContent
        } else if let intContent = try? container.decode(Int.self, forKey: .contentInt) {
            content = intContent
        } else if let boolContent = try? container.decode(Bool.self, forKey: .contentBool) {
            content = boolContent
        } else {
            content = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(frame, forKey: .frame)
        try container.encode(style, forKey: .style)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(zIndex, forKey: .zIndex)
        
        // Encode content based on type
        if let stringContent = content as? String {
            try container.encode(stringContent, forKey: .contentString)
        } else if let doubleContent = content as? Double {
            try container.encode(doubleContent, forKey: .contentDouble)
        } else if let intContent = content as? Int {
            try container.encode(intContent, forKey: .contentInt)
        } else if let boolContent = content as? Bool {
            try container.encode(boolContent, forKey: .contentBool)
        }
    }
}

// MARK: - Label Element Types
enum LabelElementType: String, CaseIterable, Codable {
    case text = "text"
    case barcode = "barcode"
    case qrCode = "qr_code"
    case image = "image"
    case line = "line"
    case rectangle = "rectangle"
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .barcode: return "Barcode"
        case .qrCode: return "QR Code"
        case .image: return "Image"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        }
    }
    
    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .barcode: return "barcode"
        case .qrCode: return "qrcode"
        case .image: return "photo"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        }
    }
    
    var supportsContent: Bool {
        switch self {
        case .text, .barcode, .qrCode, .image: return true
        case .line, .rectangle: return false
        }
    }
    
    var supportsText: Bool {
        return self == .text
    }
    
    var requiresContent: Bool {
        switch self {
        case .text, .barcode, .qrCode: return true
        case .image, .line, .rectangle: return false
        }
    }
}

// MARK: - Label Element Style
struct LabelElementStyle: Codable {
    var fontSize: CGFloat
    var fontWeight: FontWeight
    var fontFamily: String
    var textAlignment: TextAlignment
    var textColor: ColorInfo
    var backgroundColor: ColorInfo
    var borderColor: ColorInfo
    var borderWidth: CGFloat
    var cornerRadius: CGFloat
    var opacity: Double
    var rotation: CGFloat
    var shadow: ShadowStyle?
    
    init(
        fontSize: CGFloat = 12,
        fontWeight: FontWeight = .regular,
        fontFamily: String = "System",
        textAlignment: TextAlignment = .left,
        textColor: ColorInfo = .black,
        backgroundColor: ColorInfo = .clear,
        borderColor: ColorInfo = .clear,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        opacity: Double = 1.0,
        rotation: CGFloat = 0,
        shadow: ShadowStyle? = nil
    ) {
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontFamily = fontFamily
        self.textAlignment = textAlignment
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.rotation = rotation
        self.shadow = shadow
    }
}

// MARK: - Supporting Style Types
enum FontWeight: String, CaseIterable, Codable {
    case ultraLight = "ultraLight"
    case thin = "thin"
    case light = "light"
    case regular = "regular"
    case medium = "medium"
    case semibold = "semibold"
    case bold = "bold"
    case heavy = "heavy"
    case black = "black"
    
    var swiftUIWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

enum TextAlignment: String, CaseIterable, Codable {
    case left = "left"
    case center = "center"
    case right = "right"
    case justified = "justified"
    
    var swiftUIAlignment: SwiftUI.TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .justified: return .leading // SwiftUI doesn't have justified
        }
    }
}

struct ColorInfo: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    var color: Color {
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    var uiColor: UIColor {
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    static let black = ColorInfo(red: 0, green: 0, blue: 0)
    static let white = ColorInfo(red: 1, green: 1, blue: 1)
    static let clear = ColorInfo(red: 0, green: 0, blue: 0, alpha: 0)
    static let red = ColorInfo(red: 1, green: 0, blue: 0)
    static let green = ColorInfo(red: 0, green: 1, blue: 0)
    static let blue = ColorInfo(red: 0, green: 0, blue: 1)
    static let gray = ColorInfo(red: 0.5, green: 0.5, blue: 0.5)
}

struct ShadowStyle: Codable {
    let color: ColorInfo
    let radius: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    
    init(color: ColorInfo = ColorInfo(red: 0, green: 0, blue: 0, alpha: 0.3), radius: CGFloat = 2, offsetX: CGFloat = 1, offsetY: CGFloat = 1) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

// MARK: - Label Output
struct LabelOutput {
    let image: UIImage
    let pdfData: Data?
    let template: LabelTemplate
    let renderingInfo: LabelRenderingInfo
}

struct LabelRenderingInfo {
    let resolution: CGSize
    let dpi: CGFloat
    let renderTime: TimeInterval
    let fileSize: Int
    let format: LabelFormat
}

enum LabelFormat: String, CaseIterable {
    case png = "png"
    case pdf = "pdf"
    case svg = "svg"
    case eps = "eps"
    
    var displayName: String {
        return rawValue.uppercased()
    }
    
    var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .pdf: return "application/pdf"
        case .svg: return "image/svg+xml"
        case .eps: return "application/postscript"
        }
    }
}

// MARK: - Extensions for CGRect Codable
extension CGRect: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
    
    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
}
