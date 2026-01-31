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
    private let clarityFilter = CIFilter.unsharpMask()  // Separate instance for positive clarity
    private let gaussianBlur = CIFilter.gaussianBlur()  // For negative sharpness
    private let clarityBlur = CIFilter.gaussianBlur()   // For negative clarity (separate instance)

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
        // All ranges halved for finer control with same -100 to +100 UI

        // Exposure: -1...1 → -1.5...+1.5 EV (halved from ±3)
        if adjustments.exposure != 0 {
            exposureFilter.inputImage = output
            exposureFilter.ev = adjustments.exposure * 1.5
            if let result = exposureFilter.outputImage {
                output = result
            }
        }

        // Brightness + Contrast + Saturation (CIColorControls)
        if adjustments.brightness != 0 || adjustments.contrast != 0 || adjustments.saturation != 0 {
            colorControls.inputImage = output
            colorControls.brightness = adjustments.brightness * 0.25  // Halved from 0.5
            colorControls.contrast = 1.0 + (adjustments.contrast * 0.25)  // -1...1 → 0.75...1.25 (halved)
            colorControls.saturation = 1.0 + (adjustments.saturation * 0.5)  // -1...1 → 0.5...1.5
            if let result = colorControls.outputImage {
                output = result
            }
        }

        // Highlights & Shadows
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            highlightShadow.inputImage = output
            // CIHighlightShadowAdjust:
            // - highlightAmount: 0-1 (1 = no change, 0 = reduce highlights completely)
            // - shadowAmount: default 0 (0 = no change, positive = brighten shadows, negative = darken)
            let highlightValue = 1.0 - (adjustments.highlights * 0.25)
            highlightShadow.highlightAmount = max(0, min(1, highlightValue))  // Clamp to valid 0-1 range
            highlightShadow.shadowAmount = adjustments.shadows * 0.5  // -0.5...+0.5, 0 = no change
            if let result = highlightShadow.outputImage {
                output = result
            }
        }

        // MARK: - Color Adjustments

        // Vibrance (CIVibrance - intelligent color boost, protects skin tones)
        if adjustments.vibrance != 0 {
            vibranceFilter.inputImage = output
            vibranceFilter.amount = adjustments.vibrance * 0.5  // Halved
            if let result = vibranceFilter.outputImage {
                output = result
            }
        }

        // Warmth + Tint (CITemperatureAndTint)
        if adjustments.warmth != 0 || adjustments.tint != 0 {
            tempAndTint.inputImage = output
            // Warmth: -1...1 → 5250K...7750K (halved from 4000K-9000K, neutral = 6500K)
            let temp = 6500 + (adjustments.warmth * 1250)
            // Tint: -1...1 → -50...+50 (halved from ±100)
            let tintValue = adjustments.tint * 50
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
                unsharpMask.intensity = adjustments.sharpness * 1.0  // Halved from 2.0
                if let result = unsharpMask.outputImage {
                    output = result
                }
            } else {
                // Negative sharpness = blur
                gaussianBlur.inputImage = output
                gaussianBlur.radius = abs(adjustments.sharpness) * 2.5  // Halved from 5.0
                if let result = gaussianBlur.outputImage {
                    output = result
                }
            }
        }

        // Clarity: positive = local contrast boost (unsharp mask), negative = soften (blur)
        if adjustments.clarity > 0 {
            clarityFilter.inputImage = output
            clarityFilter.radius = 20  // Large radius for local contrast
            clarityFilter.intensity = adjustments.clarity * 0.75  // Max 0.75 intensity
            if let result = clarityFilter.outputImage {
                output = result
            }
        } else if adjustments.clarity < 0 {
            // Negative clarity = softening effect via blur
            clarityBlur.inputImage = output
            clarityBlur.radius = abs(adjustments.clarity) * 5  // Max 5px blur at -100%
            if let result = clarityBlur.outputImage {
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
