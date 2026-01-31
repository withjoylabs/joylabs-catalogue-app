import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// High-performance service for applying photo adjustments using CIFilters
/// All adjustment values expected in -1 to +1 range (displayed as -100 to +100)
class PhotoFilterService {
    static let shared = PhotoFilterService()

    // Metal-backed context for GPU acceleration
    private let context: CIContext

    // Reusable filters (avoid allocation on each call)
    private let exposureFilter = CIFilter.exposureAdjust()
    private let colorControls = CIFilter.colorControls()
    private let vibranceFilter = CIFilter.vibrance()
    private let tempAndTint = CIFilter.temperatureAndTint()
    private let highlightShadow = CIFilter.highlightShadowAdjust()
    private let unsharpMask = CIFilter.unsharpMask()
    private let clarityFilter = CIFilter.unsharpMask()  // Separate instance for clarity
    private let gaussianBlur = CIFilter.gaussianBlur()  // For negative sharpness

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

        // MARK: - Light Adjustments

        // Exposure: -1...1 → -3...+3 EV
        if adjustments.exposure != 0 {
            exposureFilter.inputImage = output
            exposureFilter.ev = adjustments.exposure * 3.0
            if let result = exposureFilter.outputImage {
                output = result
            }
        }

        // Brightness + Contrast (CIColorControls)
        if adjustments.brightness != 0 || adjustments.contrast != 0 {
            colorControls.inputImage = output
            colorControls.brightness = adjustments.brightness * 0.5  // Scale for natural look
            colorControls.contrast = 1.0 + (adjustments.contrast * 0.5)  // -1...1 → 0.5...1.5
            colorControls.saturation = 1.0  // Don't affect saturation here
            if let result = colorControls.outputImage {
                output = result
            }
        }

        // Highlights & Shadows
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            highlightShadow.inputImage = output
            // CIHighlightShadowAdjust: highlightAmount 0-1 (1 = no change, 0 = reduce)
            // shadowAmount 0-2 (0 = no change, positive = brighten shadows)
            highlightShadow.highlightAmount = 1.0 - (adjustments.highlights * 0.5)  // Reduce highlights when positive
            highlightShadow.shadowAmount = adjustments.shadows + 1.0  // Brighten shadows when positive
            if let result = highlightShadow.outputImage {
                output = result
            }
        }

        // MARK: - Color Adjustments

        // Vibrance (CIVibrance - intelligent color boost, protects skin tones)
        if adjustments.vibrance != 0 {
            vibranceFilter.inputImage = output
            vibranceFilter.amount = adjustments.vibrance
            if let result = vibranceFilter.outputImage {
                output = result
            }
        }

        // Warmth + Tint (CITemperatureAndTint)
        if adjustments.warmth != 0 || adjustments.tint != 0 {
            tempAndTint.inputImage = output
            // Warmth: -1...1 → 4000K...9000K (neutral = 6500K)
            let temp = 6500 + (adjustments.warmth * 2500)
            // Tint: -1...1 → -100...+100 (green to magenta)
            let tintValue = adjustments.tint * 100
            tempAndTint.neutral = CIVector(x: CGFloat(temp), y: CGFloat(tintValue))
            if let result = tempAndTint.outputImage {
                output = result
            }
        }

        // MARK: - Detail Adjustments

        // Sharpness: positive = sharpen, negative = blur
        if adjustments.sharpness != 0 {
            if adjustments.sharpness > 0 {
                unsharpMask.inputImage = output
                unsharpMask.radius = 2.5
                unsharpMask.intensity = adjustments.sharpness * 2.0
                if let result = unsharpMask.outputImage {
                    output = result
                }
            } else {
                // Negative sharpness = blur
                gaussianBlur.inputImage = output
                gaussianBlur.radius = abs(adjustments.sharpness) * 5.0  // Max 5px blur
                if let result = gaussianBlur.outputImage {
                    output = result
                }
            }
        }

        // Clarity: large-radius unsharp mask for micro-contrast
        if adjustments.clarity != 0 {
            clarityFilter.inputImage = output
            clarityFilter.radius = 20  // Large radius for local contrast
            clarityFilter.intensity = adjustments.clarity * 1.5  // Subtle effect
            if let result = clarityFilter.outputImage {
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
