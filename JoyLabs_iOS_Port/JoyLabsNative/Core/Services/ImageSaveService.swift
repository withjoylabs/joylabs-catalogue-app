import Foundation
import Combine
import UIKit
import Photos
import OSLog

/// Options for long press image behavior
public enum LongPressImageAction: String, CaseIterable {
    case camera = "camera"
    case imagePicker = "image_picker"

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .imagePicker: return "Image Picker"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .imagePicker: return "photo.on.rectangle"
        }
    }
}

/// Service for managing processed image saving to camera roll
@MainActor
public class ImageSaveService: ObservableObject {

    // MARK: - Singleton
    static let shared = ImageSaveService()

    // MARK: - Published Properties
    @Published var saveProcessedImages = false
    @Published var longPressImageAction: LongPressImageAction = .imagePicker

    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageSave")

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let saveProcessedImages = "save_processed_images"
        static let longPressImageAction = "long_press_image_action"
    }

    // MARK: - Initialization
    private init() {
        loadSettings()
        logger.info("[ImageSave] ImageSaveService initialized")
    }

    // MARK: - Public Methods

    /// Load settings from UserDefaults
    func loadSettings() {
        saveProcessedImages = userDefaults.bool(forKey: Keys.saveProcessedImages)
        if let actionString = userDefaults.string(forKey: Keys.longPressImageAction),
           let action = LongPressImageAction(rawValue: actionString) {
            longPressImageAction = action
        }
        logger.info("[ImageSave] Loaded settings - saveProcessedImages: \(self.saveProcessedImages), longPressAction: \(self.longPressImageAction.rawValue)")
    }

    /// Save settings to UserDefaults
    func saveSettings() {
        userDefaults.set(saveProcessedImages, forKey: Keys.saveProcessedImages)
        userDefaults.set(longPressImageAction.rawValue, forKey: Keys.longPressImageAction)
        logger.info("[ImageSave] Saved settings - saveProcessedImages: \(self.saveProcessedImages), longPressAction: \(self.longPressImageAction.rawValue)")
    }

    /// Save processed image to camera roll with metadata
    func saveProcessedImage(
        _ image: UIImage,
        fileName: String? = nil
    ) {
        guard saveProcessedImages else { return }

        // Request photo library permission if needed
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.performImageSave(image, fileName: fileName)
            }
        }
    }

    // MARK: - Private Methods

    private func performImageSave(
        _ image: UIImage,
        fileName: String?
    ) {
        let status = PHPhotoLibrary.authorizationStatus()
        guard status == .authorized || status == .limited else {
            logger.warning("[ImageSave] Photo library access not authorized")
            return
        }

        // Save to photo library
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: image.jpegData(compressionQuality: 0.9)!, options: nil)
            request.creationDate = Date()

        } completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    let details = "Size: \(Int(image.size.width))×\(Int(image.size.height))px"
                    self?.logger.info("[ImageSave] Successfully saved image to camera roll - \(details)")
                } else {
                    self?.logger.error("[ImageSave] Failed to save image: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
}
