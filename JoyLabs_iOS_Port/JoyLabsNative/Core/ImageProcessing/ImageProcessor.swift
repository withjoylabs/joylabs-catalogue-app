import Foundation
import UIKit
import OSLog

/// Image processing service following Instagram-style architecture
/// Takes original image + transform matrix → processes on background thread
/// Uses Core Graphics for memory efficiency
class ImageProcessor {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImageProcessor")
    
    // Square's image size limit
    private let maxImageSize: CGFloat = 4096
    
    /// Process image with transform matrix (Instagram model)
    /// All processing happens on background thread with Core Graphics
    func processImage(_ image: UIImage, with transform: ImageTransform) async throws -> ProcessedImageResult {
        logger.info("[ImageProcessor] Starting Instagram-style processing")
        logger.info("[ImageProcessor] Transform: \(transform.description)")
        logger.info("[ImageProcessor] Original image: \(String(format: "%.0fx%.0f", image.size.width, image.size.height))")
        
        return try await Task.detached(priority: .userInitiated) { [self] in
            return try await self.processImageOnBackground(image, transform: transform)
        }.value
    }
    
    private func processImageOnBackground(_ image: UIImage, transform: ImageTransform) async throws -> ProcessedImageResult {
        // Step 1: Calculate crop area from transform matrix
        let cropArea = calculateCropArea(from: transform, imageSize: image.size)
        logger.info("[ImageProcessor] Crop area: \(String(describing: cropArea))")
        
        // Step 2: Extract square crop using Core Graphics (memory efficient)
        let croppedImage = try extractSquareCrop(from: image, cropArea: cropArea)
        logger.info("[ImageProcessor] Extracted square: \(String(format: "%.0fx%.0f", croppedImage.size.width, croppedImage.size.height))")
        
        // Step 3: Resize if needed (≤4096px requirement)
        let finalImage = try resizeIfNeeded(croppedImage)
        logger.info("[ImageProcessor] Final size: \(String(format: "%.0fx%.0f", finalImage.size.width, finalImage.size.height))")
        
        // Step 4: Generate optimized data format - preserve original format
        let format: SimpleImageService.ImageFormat = finalImage.hasAlphaChannel ? SimpleImageService.ImageFormat.png : SimpleImageService.ImageFormat.jpeg
        let imageData = try generateImageData(from: finalImage, format: format)
        logger.info("[ImageProcessor] Selected format: \(String(describing: format)) (preserving original format characteristics)")
        
        logger.info("[ImageProcessor] Completed processing - \(imageData.count) bytes")
        
        return ProcessedImageResult(
            image: finalImage,
            data: imageData,
            format: format,
            originalSize: image.size,
            finalSize: finalImage.size
        )
    }
    
    /// Calculate actual crop area from UIScrollView transform matrix
    private func calculateCropArea(from transform: ImageTransform, imageSize: CGSize) -> CGRect {
        logger.info("[ImageProcessor] UIScrollView transform - scale: \(String(format: "%.2f", transform.scale)), offset: (\(String(format: "%.1f", transform.offset.width)), \(String(format: "%.1f", transform.offset.height)))")
        
        // Calculate how image is displayed in UIScrollView (Instagram model)
        let imageAspectRatio = imageSize.width / imageSize.height
        let squareSize = transform.squareSize
        
        // Initial display size (entire image visible)
        let displaySize: CGSize
        if imageAspectRatio > 1.0 {
            // Wide image - scaled to fit height (height fills square)
            let scale = squareSize / imageSize.height
            displaySize = CGSize(width: imageSize.width * scale, height: squareSize)
        } else {
            // Tall image - scaled to fit width (width fills square)
            let scale = squareSize / imageSize.width
            displaySize = CGSize(width: squareSize, height: imageSize.height * scale)
        }
        
        // Calculate scale factor: how much the image was scaled to fit in the display
        logger.info("[ImageProcessor] imageSize: \(String(format: "%.0fx%.0f", imageSize.width, imageSize.height))")
        logger.info("[ImageProcessor] displaySize: \(String(format: "%.1fx%.1f", displaySize.width, displaySize.height))")
        logger.info("[ImageProcessor] imageAspectRatio: \(String(format: "%.2f", imageAspectRatio))")
        
        let displayToImageScale: CGFloat
        if imageAspectRatio > 1.0 {
            // Wide image - scaled to fit height
            displayToImageScale = imageSize.height / displaySize.height
            logger.info("[ImageProcessor] Wide image: \(String(format: "%.0f", imageSize.height)) / \(String(format: "%.1f", displaySize.height)) = \(String(format: "%.2f", displayToImageScale))")
        } else {
            // Tall image - scaled to fit width  
            displayToImageScale = imageSize.width / displaySize.width
            logger.info("[ImageProcessor] Tall image: \(String(format: "%.0f", imageSize.width)) / \(String(format: "%.1f", displaySize.width)) = \(String(format: "%.2f", displayToImageScale))")
        }
        
        // UIScrollView visible rect (what user sees in square)
        // The offset is the contentOffset from UIScrollView
        // The scale is the zoomScale from UIScrollView
        let visibleRect = CGRect(
            x: transform.offset.width / transform.scale,
            y: transform.offset.height / transform.scale,
            width: squareSize / transform.scale,
            height: squareSize / transform.scale
        )
        
        logger.info("[ImageProcessor] Display scale factor: \(String(format: "%.2f", displayToImageScale))")
        logger.info("[ImageProcessor] Visible rect in display: x=\(String(format: "%.1f", visibleRect.origin.x)), y=\(String(format: "%.1f", visibleRect.origin.y)), w=\(String(format: "%.1f", visibleRect.width)), h=\(String(format: "%.1f", visibleRect.height))")
        
        // Convert to image coordinates - this should give us a SQUARE crop
        let imageCropRect = CGRect(
            x: visibleRect.origin.x * displayToImageScale,
            y: visibleRect.origin.y * displayToImageScale,
            width: visibleRect.size.width * displayToImageScale,
            height: visibleRect.size.height * displayToImageScale
        )
        
        logger.info("[ImageProcessor] Crop rect in image: x=\(String(format: "%.1f", imageCropRect.origin.x)), y=\(String(format: "%.1f", imageCropRect.origin.y)), w=\(String(format: "%.1f", imageCropRect.width)), h=\(String(format: "%.1f", imageCropRect.height))")
        
        // Safety: Clamp to image bounds
        let clampedRect = imageCropRect.intersection(CGRect(origin: .zero, size: imageSize))
        
        // Safety: Ensure minimum size
        if clampedRect.width < 10 || clampedRect.height < 10 {
            logger.warning("[ImageProcessor] Crop rect too small, using full image")
            return CGRect(origin: .zero, size: imageSize)
        }
        
        // Safety: Cap maximum size to prevent memory issues
        if clampedRect.width > 4096 || clampedRect.height > 4096 {
            logger.warning("[ImageProcessor] Crop rect too large (\(clampedRect.width)x\(clampedRect.height)), capping to 4096")
            let scale = min(4096 / clampedRect.width, 4096 / clampedRect.height)
            return CGRect(
                x: clampedRect.origin.x,
                y: clampedRect.origin.y,
                width: clampedRect.width * scale,
                height: clampedRect.height * scale
            )
        }
        
        // Ensure even pixel dimensions to prevent odd sizing issues
        let roundedRect = CGRect(
            x: floor(clampedRect.origin.x),
            y: floor(clampedRect.origin.y), 
            width: floor(clampedRect.width),
            height: floor(clampedRect.height)
        )
        
        return roundedRect
    }
    
    /// Extract square crop using Core Graphics (memory efficient)
    private func extractSquareCrop(from image: UIImage, cropArea: CGRect) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw ImageProcessingError.cropFailed
        }
        
        // Crop using Core Graphics
        guard let croppedCGImage = cgImage.cropping(to: cropArea) else {
            throw ImageProcessingError.cropFailed
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Make perfectly square by centering in square canvas
        let maxDimension = max(croppedImage.size.width, croppedImage.size.height)
        
        return autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = !croppedImage.hasAlphaChannel
            format.scale = 1.0
            format.preferredRange = .standard
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxDimension, height: maxDimension), format: format)
            return renderer.image { context in
                let drawRect = CGRect(
                    x: (maxDimension - croppedImage.size.width) / 2,
                    y: (maxDimension - croppedImage.size.height) / 2,
                    width: croppedImage.size.width,
                    height: croppedImage.size.height
                )
                croppedImage.draw(in: drawRect)
            }
        }
    }
    
    /// Resize if needed to meet Square's ≤4096px requirement
    private func resizeIfNeeded(_ image: UIImage) throws -> UIImage {
        let maxDimension = max(image.size.width, image.size.height)
        
        // If within Square's limits, return as-is
        guard maxDimension > maxImageSize else {
            return image
        }
        
        let scale = maxImageSize / maxDimension
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        logger.info("[ImageProcessor] Resizing from \(String(format: "%.0f", maxDimension)) to \(String(format: "%.0f", self.maxImageSize))")
        
        return autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = !image.hasAlphaChannel
            format.scale = 1.0
            format.preferredRange = .standard
            
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
    
    /// Generate optimized image data (JPEG for photos, PNG for transparency)
    private func generateImageData(from image: UIImage, format: SimpleImageService.ImageFormat) throws -> Data {
        switch format {
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                throw ImageProcessingError.jpegCompressionFailed
            }
            logger.info("[ImageProcessor] Generated JPEG: \(data.count) bytes at 90% quality")
            return data
        case .png:
            // Use compressed PNG generation to reduce file size while preserving transparency
            let format = UIGraphicsImageRendererFormat()
            format.opaque = !image.hasAlphaChannel  // Optimize for opaque images
            format.scale = 1.0  // Use 1.0 scale to avoid size changes
            format.preferredRange = .standard  // Standard color range for better compression
            
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            let data = renderer.pngData { context in
                image.draw(at: .zero)
            }
            
            logger.info("[ImageProcessor] Generated compressed PNG: \(data.count) bytes (preserving transparency)")
            return data
        }
    }
}

// MARK: - Supporting Types

/// Result of Instagram-style image processing
struct ProcessedImageResult {
    let image: UIImage
    let data: Data
    let format: SimpleImageService.ImageFormat
    let originalSize: CGSize
    let finalSize: CGSize
}

/// Image processing errors
enum ImageProcessingError: LocalizedError {
    case invalidCropRect
    case cropRectOutOfBounds
    case cropFailed
    case jpegCompressionFailed
    case pngCompressionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidCropRect:
            return "Invalid crop rectangle"
        case .cropRectOutOfBounds:
            return "Crop rectangle is outside image bounds"
        case .cropFailed:
            return "Failed to crop image"
        case .jpegCompressionFailed:
            return "Failed to compress image as JPEG"
        case .pngCompressionFailed:
            return "Failed to compress image as PNG"
        }
    }
}