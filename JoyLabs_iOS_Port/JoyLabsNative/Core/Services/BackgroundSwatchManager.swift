import Foundation
import SwiftUI

/// RGBA color model that is Codable for UserDefaults persistence
struct CodableColor: Codable, Equatable, Identifiable {
    let id: UUID
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var ciColor: CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    init(id: UUID = UUID(), red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.id = id
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        self.id = UUID()
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }
}

/// Manages background color swatches for background removal feature.
/// Provides preset colors and persists user-added custom colors.
class BackgroundSwatchManager: ObservableObject {
    static let shared = BackgroundSwatchManager()

    @Published private(set) var customColors: [CodableColor] = []

    // Persistent BG removal settings (restored across sessions)
    @Published var savedEdgeFeathering: Float = 0.3

    /// Fixed preset colors (white first, then common product photo backgrounds)
    let presetColors: [CodableColor] = [
        CodableColor(red: 1.0, green: 1.0, blue: 1.0),       // White
        CodableColor(red: 0.0, green: 0.0, blue: 0.0),       // Black
        CodableColor(red: 0.3, green: 0.3, blue: 0.3),       // Dark gray
        CodableColor(red: 0.7, green: 0.7, blue: 0.7),       // Light gray
        CodableColor(red: 0.96, green: 0.93, blue: 0.88),    // Cream
        CodableColor(red: 0.85, green: 0.91, blue: 0.97),    // Light blue
        CodableColor(red: 0.96, green: 0.87, blue: 0.90),    // Soft pink
    ]

    /// Default white background
    static let defaultWhite = CodableColor(red: 1.0, green: 1.0, blue: 1.0)

    private let storageKey = "com.joylabs.camera.customBackgroundColors"
    private let edgeFeatheringKey = "com.joylabs.camera.edgeFeathering"
    private let maxCustomColors = 12

    private init() {
        loadColors()
        loadSettings()
    }

    // MARK: - Custom Color Management

    /// Add a custom color (prepends to list, persists)
    func addCustomColor(_ color: Color) {
        let codable = CodableColor(color: color)

        // Don't add duplicates (within tolerance)
        let isDuplicate = customColors.contains { existing in
            abs(existing.red - codable.red) < 0.02 &&
            abs(existing.green - codable.green) < 0.02 &&
            abs(existing.blue - codable.blue) < 0.02
        }
        guard !isDuplicate else { return }

        customColors.insert(codable, at: 0)

        // Drop oldest if over limit
        if customColors.count > maxCustomColors {
            customColors = Array(customColors.prefix(maxCustomColors))
        }

        persistColors()
    }

    /// Remove a custom color by ID
    func removeCustomColor(id: UUID) {
        customColors.removeAll { $0.id == id }
        persistColors()
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: edgeFeatheringKey) != nil {
            savedEdgeFeathering = defaults.float(forKey: edgeFeatheringKey)
        }
    }

    func saveEdgeFeathering(_ value: Float) {
        savedEdgeFeathering = value
        UserDefaults.standard.set(value, forKey: edgeFeatheringKey)
    }

    // MARK: - Color Persistence

    private func loadColors() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            customColors = try JSONDecoder().decode([CodableColor].self, from: data)
        } catch {
            print("[BackgroundSwatchManager] Failed to load custom colors: \(error)")
        }
    }

    private func persistColors() {
        do {
            let data = try JSONEncoder().encode(customColors)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[BackgroundSwatchManager] Failed to save custom colors: \(error)")
        }
    }
}
