import Foundation
import UIKit
import Combine

/// A saved photo adjustment preset with thumbnail
struct PhotoPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var adjustments: PhotoAdjustments
    var thumbnailData: Data?  // JPEG thumbnail (small, ~50x50)
    let createdAt: Date

    init(id: UUID = UUID(), name: String, adjustments: PhotoAdjustments, thumbnail: UIImage? = nil) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
        self.createdAt = Date()

        // Create small thumbnail for storage efficiency
        if let thumbnail = thumbnail {
            let size = CGSize(width: 100, height: 100)  // 2x for retina
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in
                thumbnail.draw(in: CGRect(origin: .zero, size: size))
            }
            self.thumbnailData = resized.jpegData(compressionQuality: 0.7)
        } else {
            self.thumbnailData = nil
        }
    }

    var thumbnail: UIImage? {
        guard let data = thumbnailData else { return nil }
        return UIImage(data: data)
    }
}

/// Manages multiple photo adjustment presets with persistence
class PhotoPresetManager: ObservableObject {
    static let shared = PhotoPresetManager()

    @Published private(set) var presets: [PhotoPreset] = []

    private let storageKey = "com.joylabs.camera.photoPresets"
    private let maxPresets = 50

    private init() {
        loadPresets()
    }

    // MARK: - CRUD Operations

    /// Save a new preset
    func savePreset(name: String, adjustments: PhotoAdjustments, thumbnail: UIImage?) -> Bool {
        guard presets.count < maxPresets else {
            return false  // At capacity
        }

        let preset = PhotoPreset(name: name, adjustments: adjustments, thumbnail: thumbnail)
        presets.append(preset)
        persistPresets()
        return true
    }

    /// Delete a preset by ID
    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persistPresets()
    }

    /// Update an existing preset's name
    func renamePreset(id: UUID, newName: String) {
        if let index = presets.firstIndex(where: { $0.id == id }) {
            presets[index].name = newName
            persistPresets()
        }
    }

    /// Check if more presets can be added
    var canAddMore: Bool {
        presets.count < maxPresets
    }

    // MARK: - Persistence

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            presets = try JSONDecoder().decode([PhotoPreset].self, from: data)
        } catch {
            print("[PhotoPresetManager] Failed to load presets: \(error)")
        }
    }

    private func persistPresets() {
        do {
            let data = try JSONEncoder().encode(presets)
            UserDefaults.standard.set(data, forKey: storageKey)
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        } catch {
            print("[PhotoPresetManager] Failed to save presets: \(error)")
        }
    }
}
