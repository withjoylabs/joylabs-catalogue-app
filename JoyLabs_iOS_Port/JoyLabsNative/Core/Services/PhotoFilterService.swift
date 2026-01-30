import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// High-performance service for applying photo adjustments using CIFilters
/// Uses professional-grade filters: CIExposureAdjust, CIVibrance for natural results
class PhotoFilterService {
    static let shared = PhotoFilterService()

    // Metal-backed context for GPU acceleration
    private let context: CIContext

    // Reusable filters (avoid allocation on each call)
    private let exposureFilter = CIFilter.exposureAdjust()
    private let colorControls = CIFilter.colorControls()
    private let vibranceFilter = CIFilter.vibrance()
    private let tempAndTint = CIFilter.temperatureAndTint()
    private let unsharpMask = CIFilter.unsharpMask()

    private init() {
        // Use Metal for GPU-accelerated rendering
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,  // Don't cache intermediates (saves memory)
                .priorityRequestLow: false   // High priority rendering
            ])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    /// Apply adjustments to CIImage (stays in GPU memory - use for preview)
    func applyToCIImage(_ adjustments: PhotoAdjustments, ciImage: CIImage) -> CIImage {
        guard !adjustments.isDefault else { return ciImage }

        var output = ciImage

        // Exposure (CIExposureAdjust - simulates camera F-stop, much more natural than brightness)
        if adjustments.exposure != 0 {
            exposureFilter.inputImage = output
            exposureFilter.ev = adjustments.exposure
            if let result = exposureFilter.outputImage {
                output = result
            }
        }

        // Contrast only (using colorControls but NOT its brightness/saturation)
        if adjustments.contrast != 1.0 {
            colorControls.inputImage = output
            colorControls.brightness = 0      // Don't use - we have exposure
            colorControls.contrast = adjustments.contrast
            colorControls.saturation = 1      // Don't use - we have vibrance
            if let result = colorControls.outputImage {
                output = result
            }
        }

        // Vibrance (CIVibrance - intelligent color boost, protects skin tones)
        if adjustments.vibrance != 0 {
            vibranceFilter.inputImage = output
            vibranceFilter.amount = adjustments.vibrance
            if let result = vibranceFilter.outputImage {
                output = result
            }
        }

        // Warmth (temperature)
        if adjustments.warmth != 0 {
            tempAndTint.inputImage = output
            // Map -1...1 to 4000K...9000K (neutral = 6500K)
            let temp = 6500 + (adjustments.warmth * 2500)
            tempAndTint.neutral = CIVector(x: CGFloat(temp), y: 0)
            if let result = tempAndTint.outputImage {
                output = result
            }
        }

        // Sharpness (CIUnsharpMask - industry standard, more visible than CISharpenLuminance)
        if adjustments.sharpness > 0 {
            unsharpMask.inputImage = output
            unsharpMask.radius = 2.5  // Pixel radius for edge detection
            unsharpMask.intensity = adjustments.sharpness * 2.0  // Map 0-1 to 0-2 for visible effect
            if let result = unsharpMask.outputImage {
                output = result
            }
        }

        return output
    }

    /// Render CIImage to UIImage (final output - triggers GPU computation)
    func renderToUIImage(_ ciImage: CIImage, scale: CGFloat, orientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }

    /// Convenience: Apply adjustments to UIImage and render (for final export/preset auto-apply)
    func apply(_ adjustments: PhotoAdjustments, to image: UIImage) -> UIImage {
        guard !adjustments.isDefault else { return image }
        guard let ciImage = CIImage(image: image) else { return image }

        let processed = applyToCIImage(adjustments, ciImage: ciImage)
        return renderToUIImage(processed, scale: image.scale, orientation: image.imageOrientation) ?? image
    }
}
