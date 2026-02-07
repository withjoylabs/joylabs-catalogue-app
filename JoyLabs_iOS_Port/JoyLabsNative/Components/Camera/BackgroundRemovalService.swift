import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import os.log

/// On-device background removal using Vision framework with CIImage compositing.
/// Generates foreground masks, applies them to images, and composites with custom backgrounds.
class BackgroundRemovalService {
    static let shared = BackgroundRemovalService()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "BackgroundRemoval")

    // Metal-backed context (same pattern as PhotoFilterService)
    private let context: CIContext

    // Reusable filters
    private let blendWithMask = CIFilter.blendWithMask()

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    // MARK: - Mask Generation

    /// Generate a foreground segmentation mask from an image using Vision framework.
    /// Returns a CIImage mask at the same resolution as the input (white = foreground, black = background).
    func generateMask(from image: UIImage) async throws -> CIImage {
        guard let cgImage = image.cgImage else {
            throw BackgroundRemovalError.invalidImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try handler.perform([request])

        guard let result = request.results?.first else {
            throw BackgroundRemovalError.noSubjectDetected
        }

        // Get raw mask at Vision's native resolution (~512x512) — NOT upscaled
        let maskPixelBuffer = try result.generateMask(forInstances: result.allInstances)
        let rawMask = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Original photo as guide for edge-preserve upsampling
        let guideImage = CIImage(cgImage: cgImage)
        let targetSize = CGSize(width: cgImage.width, height: cgImage.height)
        logger.info("[BG Removal] Raw mask: \(rawMask.extent.width)x\(rawMask.extent.height), target: \(targetSize.width)x\(targetSize.height)")

        return antialiasAndUpscale(rawMask, toSize: targetSize, guide: guideImage)
    }

    // MARK: - Mask Anti-Aliasing & Upscaling

    /// Anti-alias at native resolution, sharpen with sigmoid tone curve, then
    /// edge-preserve upsample using the original photo as a guide.
    private func antialiasAndUpscale(_ rawMask: CIImage, toSize targetSize: CGSize, guide: CIImage) -> CIImage {
        let maskExtent = rawMask.extent

        // Step 1: Small Gaussian blur at native ~512px for initial AA
        let smooth = CIFilter.gaussianBlur()
        smooth.inputImage = rawMask
        smooth.radius = 1.2
        guard let blurred = smooth.outputImage?.cropped(to: maskExtent) else { return rawMask }

        // Step 2: Sigmoid tone curve — defines edges sharply without wavy contours
        // S-curve pushes values toward 0 or 1; transition zone around 0.5 = AA edge
        let sigmoid = CIFilter.toneCurve()
        sigmoid.inputImage = blurred
        sigmoid.point0 = CGPoint(x: 0.0, y: 0.0)
        sigmoid.point1 = CGPoint(x: 0.25, y: 0.01)
        sigmoid.point2 = CGPoint(x: 0.5, y: 0.5)
        sigmoid.point3 = CGPoint(x: 0.75, y: 0.99)
        sigmoid.point4 = CGPoint(x: 1.0, y: 1.0)
        guard let curved = sigmoid.outputImage?.cropped(to: maskExtent) else { return blurred }

        // Step 3: Clamp to [0,1]
        let clamp = CIFilter(name: "CIColorClamp")!
        clamp.setValue(curved, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")
        guard let clamped = clamp.outputImage?.cropped(to: maskExtent) else { return curved }

        // Step 4: Edge-preserve upsample — photo's real edges guide the mask upscaling
        let upsample = CIFilter.edgePreserveUpsample()
        upsample.inputImage = guide
        upsample.smallImage = clamped
        upsample.lumaSigma = 0.15
        upsample.spatialSigma = 3.0

        if let upsampled = upsample.outputImage {
            logger.info("[BG Removal] Guided upsample: \(Int(maskExtent.width))x\(Int(maskExtent.height)) -> \(Int(upsampled.extent.width))x\(Int(upsampled.extent.height))")
            return upsampled
        }

        // Fallback: Lanczos if edge-preserve fails
        logger.warning("[BG Removal] Edge-preserve upsample failed, falling back to Lanczos")
        let scaleX = targetSize.width / maskExtent.width
        let scaleY = targetSize.height / maskExtent.height
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = clamped
        lanczos.scale = Float(scaleY)
        lanczos.aspectRatio = Float(scaleX / scaleY)
        return lanczos.outputImage ?? clamped
    }

    // MARK: - Compositing

    /// Composite a filtered image with mask and background color.
    /// - Parameters:
    ///   - filteredImage: The CIImage after photo adjustments (filters applied)
    ///   - mask: Foreground mask (white = keep, black = remove)
    ///   - backgroundColor: Solid background color, or nil for transparent
    ///   - edgeFeathering: Edge softness (0 = crisp, 1 = soft)
    /// - Returns: Composited CIImage
    func composite(
        filteredImage: CIImage,
        mask: CIImage,
        backgroundColor: CIColor?,
        edgeFeathering: Float = 0.3
    ) -> CIImage {
        let extent = filteredImage.extent

        // Scale mask to match the filtered image dimensions if needed
        let scaledMask = scaleMask(mask, toFit: extent)

        // User-controllable edge feathering (on top of already-refined mask)
        let featheredMask: CIImage
        if edgeFeathering > 0.01 {
            let feather = CIFilter.gaussianBlur()
            feather.inputImage = scaledMask
            feather.radius = Float(max(extent.width, extent.height) * 0.003 * CGFloat(edgeFeathering))
            featheredMask = feather.outputImage?.cropped(to: extent) ?? scaledMask
        } else {
            featheredMask = scaledMask
        }

        // Create background layer
        let background: CIImage
        if let bgColor = backgroundColor {
            background = CIImage(color: bgColor).cropped(to: extent)
        } else {
            // Transparent background
            background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        }

        // Blend foreground over background using feathered mask
        blendWithMask.inputImage = filteredImage
        blendWithMask.backgroundImage = background
        blendWithMask.maskImage = featheredMask

        guard let masked = blendWithMask.outputImage else {
            logger.error("[BG Removal] Blend with mask failed")
            return filteredImage
        }

        return masked.cropped(to: extent)
    }

    // MARK: - Mask Scaling

    /// Scale a mask CIImage to match a target extent using Lanczos resampling.
    func scaleMask(_ mask: CIImage, toFit targetExtent: CGRect) -> CIImage {
        let maskExtent = mask.extent
        guard maskExtent.width > 0 && maskExtent.height > 0 else { return mask }

        let scaleX = targetExtent.width / maskExtent.width
        let scaleY = targetExtent.height / maskExtent.height

        // If already matching, skip
        if abs(scaleX - 1.0) < 0.001 && abs(scaleY - 1.0) < 0.001 {
            return mask
        }

        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = mask
        lanczos.scale = Float(scaleY)
        lanczos.aspectRatio = Float(scaleX / scaleY)
        return lanczos.outputImage ?? mask
    }

    // MARK: - Rendering

    /// Render a CIImage to UIImage (preserves alpha for transparent backgrounds)
    func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Errors

enum BackgroundRemovalError: LocalizedError {
    case invalidImage
    case noSubjectDetected

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .noSubjectDetected:
            return "No subject detected in the image"
        }
    }
}
