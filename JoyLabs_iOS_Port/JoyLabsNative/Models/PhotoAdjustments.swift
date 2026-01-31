import Foundation

/// Photo adjustment parameters for CIFilter processing
/// All values use -1 to +1 range, displayed as -100 to +100 in UI
struct PhotoAdjustments: Codable, Equatable {
    // Light adjustments
    var exposure: Float = 0.0     // -1 to +1 → maps to -3 to +3 EV (CIExposureAdjust)
    var brightness: Float = 0.0   // -1 to +1 (CIColorControls.brightness)
    var highlights: Float = 0.0   // -1 to +1 (CIHighlightShadowAdjust)
    var shadows: Float = 0.0      // -1 to +1 (CIHighlightShadowAdjust)

    // Color adjustments
    var contrast: Float = 0.0     // -1 to +1 → maps to 0.5 to 1.5 (CIColorControls)
    var vibrance: Float = 0.0     // -1 to +1 (CIVibrance - intelligent color boost)
    var warmth: Float = 0.0       // -1 to +1 (CITemperatureAndTint.neutral)
    var tint: Float = 0.0         // -1 to +1 (CITemperatureAndTint.tint - green to magenta)

    // Detail adjustments
    var sharpness: Float = 0.0    // -1 to +1 (CIUnsharpMask - negative = blur)
    var clarity: Float = 0.0      // -1 to +1 (large-radius unsharp mask for micro-contrast)

    static let `default` = PhotoAdjustments()

    var isDefault: Bool {
        self == PhotoAdjustments.default
    }
}

// PhotoAdjustmentsPresetManager has been replaced by PhotoPresetManager
// which supports multiple named presets with thumbnails
