import Foundation

/// Photo adjustment parameters for CIFilter processing
/// Uses professional-grade filters for natural results
struct PhotoAdjustments: Codable, Equatable {
    var exposure: Float = 0.0     // -3 to +3 EV (CIExposureAdjust - simulates camera F-stop)
    var contrast: Float = 1.0     // 0.5 to 1.5 (CIColorControls)
    var vibrance: Float = 0.0     // -1 to +1 (CIVibrance - intelligent color boost)
    var warmth: Float = 0.0       // -1 to +1 (CITemperatureAndTint)
    var sharpness: Float = 0.0    // 0 to 1 (CISharpenLuminance)

    static let `default` = PhotoAdjustments()

    var isDefault: Bool {
        self == PhotoAdjustments.default
    }
}

/// Manages saving and loading photo adjustment presets
class PhotoAdjustmentsPresetManager {
    static let shared = PhotoAdjustmentsPresetManager()
    private let defaultsKey = "com.joylabs.camera.photoPreset"

    private init() {}

    var savedPreset: PhotoAdjustments? {
        get {
            guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
            return try? JSONDecoder().decode(PhotoAdjustments.self, from: data)
        }
        set {
            if let newValue = newValue {
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: defaultsKey)
                    // Force immediate write to disk for persistence across app restarts
                    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            }
        }
    }

    var hasPreset: Bool { savedPreset != nil }

    func clearPreset() {
        savedPreset = nil
    }
}
