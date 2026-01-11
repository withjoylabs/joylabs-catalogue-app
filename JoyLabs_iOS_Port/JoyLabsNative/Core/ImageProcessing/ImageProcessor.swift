import Foundation
import UIKit
import OSLog

/// Simplified image processor - no cropping, just format conversion and size validation
/// Square handles all image optimization server-side (15MB limit, no dimension limits)
class ImageProcessor {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageProcessor")

    // Square's file size limit
    private let maxFileSizeMB: Double = 15.0
    private let maxFileSizeBytes: Int = 15 * 1024 * 1024 // 15MB

    /// Process image for Square upload - just validate size and convert to appropriate format
    func processImage(_ image: UIImage) async throws -> ProcessedImageResult {
        logger.info("[ImageProcessor] Starting image processing")
        logger.info("[ImageProcessor] Original image: \(String(format: "%.0fx%.0f", image.size.width, image.size.height))")

        return try await Task.detached(priority: .userInitiated) { [self] in
            return try await self.processImageOnBackground(image)
        }.value
    }

    private func processImageOnBackground(_ image: UIImage) async throws -> ProcessedImageResult {
        // Determine optimal format based on image characteristics
        let format: SimpleImageService.ImageFormat = image.hasAlphaChannel ? .png : .jpeg
        logger.info("[ImageProcessor] Selected format: \(String(describing: format))")

        // Generate image data
        let imageData = try generateImageData(from: image, format: format)
        logger.info("[ImageProcessor] Generated data: \(imageData.count) bytes (\(String(format: "%.2f", Double(imageData.count) / 1024.0 / 1024.0))MB)")

        // Validate file size (Square's 15MB limit)
        guard imageData.count <= maxFileSizeBytes else {
            let sizeMB = Double(imageData.count) / 1024.0 / 1024.0
            logger.error("[ImageProcessor] Image too large: \(String(format: "%.2f", sizeMB))MB (max 15MB)")
            throw ImageProcessingError.fileTooLarge(sizeMB: sizeMB)
        }

        logger.info("[ImageProcessor] Image processing completed successfully")

        return ProcessedImageResult(
            image: image,
            data: imageData,
            format: format,
            originalSize: image.size,
            finalSize: image.size
        )
    }

    /// Generate optimized image data (JPEG for photos, PNG for transparency)
    private func generateImageData(from image: UIImage, format: SimpleImageService.ImageFormat) throws -> Data {
        switch format {
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: 1.0) else {
                throw ImageProcessingError.jpegCompressionFailed
            }
            logger.info("[ImageProcessor] Generated JPEG: \(data.count) bytes at 100% quality (no compression)")
            return data
        case .png:
            // Use PNG generation preserving original resolution and transparency
            let renderFormat = UIGraphicsImageRendererFormat()
            renderFormat.opaque = !image.hasAlphaChannel
            renderFormat.scale = image.scale  // Preserve original Retina resolution (2x/3x)
            renderFormat.preferredRange = .standard

            let renderer = UIGraphicsImageRenderer(size: image.size, format: renderFormat)
            let data = renderer.pngData { context in
                image.draw(at: .zero)
            }

            logger.info("[ImageProcessor] Generated PNG: \(data.count) bytes at \(image.scale)x scale")
            return data
        }
    }
}

// MARK: - Supporting Types

/// Result of image processing
struct ProcessedImageResult {
    let image: UIImage
    let data: Data
    let format: SimpleImageService.ImageFormat
    let originalSize: CGSize
    let finalSize: CGSize
}

/// Image processing errors
enum ImageProcessingError: LocalizedError {
    case fileTooLarge(sizeMB: Double)
    case jpegCompressionFailed
    case pngCompressionFailed

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let sizeMB):
            return "Image file too large (\(String(format: "%.2f", sizeMB))MB). Maximum allowed is 15MB."
        case .jpegCompressionFailed:
            return "Failed to compress image as JPEG"
        case .pngCompressionFailed:
            return "Failed to compress image as PNG"
        }
    }
}
