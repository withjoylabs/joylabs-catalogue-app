import Foundation
import UIKit
import OSLog

/// Manager for handling deferred image uploads for new items
/// When creating a new item, images are held locally until the item gets a Square ID
@MainActor
class DeferredImageUploadManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = DeferredImageUploadManager()
    
    // MARK: - Dependencies
    private let imageService: SimpleImageService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DeferredImageUploadManager")
    
    // MARK: - State
    @Published private(set) var pendingUploads: [String: DeferredImageUpload] = [:]
    
    // MARK: - Initialization
    private init() {
        self.imageService = SimpleImageService.shared
        logger.info("[DeferredImageUpload] DeferredImageUploadManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Process any deferred uploads for a newly created item
    func processDeferredUploads(for itemId: String, base64ImageURL: String?) async throws -> String? {
        guard let base64ImageURL = base64ImageURL,
              base64ImageURL.hasPrefix("data:image") else {
            // No deferred upload needed
            return base64ImageURL
        }
        
        logger.info("🔄 Processing deferred upload for item: \(itemId)")
        logger.info("📁 Base64 data URL detected")
        
        // Extract image data from base64 data URL
        guard let imageData = extractImageDataFromBase64URL(base64ImageURL) else {
            logger.error("❌ Failed to extract image data from base64 URL")
            throw DeferredImageError.failedToReadImageData
        }
        
        // Generate proper filename
        let fileName = "joylabs_image_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg"
        
        do {
            // Upload the deferred image
            let awsURL = try await imageService.uploadImage(
                imageData: imageData,
                fileName: fileName,
                itemId: itemId
            )
            
            logger.info("✅ Deferred image upload completed successfully")
            logger.info("🌐 AWS URL: \(awsURL)")
            
            return awsURL
            
        } catch {
            logger.error("❌ Failed to upload deferred image: \(error)")
            throw error
        }
    }
    
    /// Check if URL represents a deferred upload (base64 data URL)
    func isDeferredUpload(_ imageURL: String?) -> Bool {
        guard let imageURL = imageURL else { return false }
        return imageURL.hasPrefix("data:image")
    }
    
    /// Extract image data from base64 data URL
    private func extractImageDataFromBase64URL(_ dataURL: String) -> Data? {
        // Extract base64 data from data URL format: data:image/jpeg;base64,<base64-data>
        guard let commaRange = dataURL.range(of: ",") else { return nil }
        let base64String = String(dataURL[commaRange.upperBound...])
        return Data(base64Encoded: base64String)
    }
    
    /// Clean up any orphaned temporary files
    func cleanupTempFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory
        
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(
                at: tempDirectory, 
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix("deferred_image") }
            
            for file in tempFiles {
                // Remove files older than 1 hour
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   Date().timeIntervalSince(creationDate) > 3600 {
                    try? FileManager.default.removeItem(at: file)
                    logger.debug("🗑️ Cleaned up old temp file: \(file.lastPathComponent)")
                }
            }
        } catch {
            logger.error("Failed to cleanup temp files: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct DeferredImageUpload {
    let tempURL: String
    let fileName: String
    let createdAt: Date
}

enum DeferredImageError: LocalizedError {
    case failedToReadImageData
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .failedToReadImageData:
            return "Failed to read deferred image data"
        case .uploadFailed:
            return "Failed to upload deferred image"
        }
    }
}