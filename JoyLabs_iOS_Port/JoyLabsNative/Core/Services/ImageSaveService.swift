import Foundation
import Combine
import UIKit
import Photos
import OSLog

/// Service for managing processed image saving to camera roll
@MainActor
public class ImageSaveService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ImageSaveService()
    
    // MARK: - Published Properties
    @Published var saveProcessedImages = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageSave")
    
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let saveProcessedImages = "save_processed_images"
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
        logger.info("[ImageSave] Loaded settings - saveProcessedImages: \(self.saveProcessedImages)")
    }
    
    /// Save settings to UserDefaults
    func saveSettings() {
        userDefaults.set(saveProcessedImages, forKey: Keys.saveProcessedImages)
        logger.info("[ImageSave] Saved settings - saveProcessedImages: \(self.saveProcessedImages)")
    }
    
    /// Save processed image to camera roll with metadata
    func saveProcessedImage(
        _ image: UIImage,
        originalSize: CGSize,
        cropTransform: ImageTransform,
        previewSize: CGSize,
        fileName: String? = nil
    ) {
        guard saveProcessedImages else { return }
        
        // Request photo library permission if needed
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.performImageSave(
                    image,
                    originalSize: originalSize,
                    cropTransform: cropTransform,
                    previewSize: previewSize,
                    fileName: fileName
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performImageSave(
        _ image: UIImage,
        originalSize: CGSize,
        cropTransform: ImageTransform,
        previewSize: CGSize,
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
                    let details = "Original: \(Int(originalSize.width))×\(Int(originalSize.height))px, Scale: \(String(format: "%.2f", cropTransform.scale))x, Offset: (\(Int(cropTransform.offset.width)), \(Int(cropTransform.offset.height)))px"
                    self?.logger.info("[ImageSave] Successfully saved processed image to camera roll - \(details)")
                } else {
                    self?.logger.error("[ImageSave] Failed to save image: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
}