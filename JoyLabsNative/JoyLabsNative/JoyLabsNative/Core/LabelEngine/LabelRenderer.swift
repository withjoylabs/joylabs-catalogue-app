import Foundation
import UIKit
import CoreGraphics
import CoreImage

/// LabelRenderer - High-quality label rendering engine
/// Converts label templates into printable images and PDFs
class LabelRenderer {
    
    // MARK: - Properties
    private let defaultDPI: CGFloat = 300.0 // High quality for printing
    private let barcodeGenerator = BarcodeGenerator()
    private let qrCodeGenerator = QRCodeGenerator()
    
    // MARK: - Public Methods
    
    /// Render a label template to image and PDF
    func renderLabel(_ template: LabelTemplate, dpi: CGFloat? = nil) async throws -> LabelOutput {
        let startTime = Date()
        let renderDPI = dpi ?? defaultDPI
        
        Logger.info("LabelRenderer", "Rendering label: \(template.name) at \(renderDPI) DPI")
        
        // Calculate render size based on DPI
        let scale = renderDPI / 72.0 // 72 points per inch
        let renderSize = CGSize(
            width: template.size.width * scale,
            height: template.size.height * scale
        )
        
        // Create graphics context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw LabelError.renderingFailed
        }
        
        // Set up context
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: template.size.displaySize))
        
        // Sort elements by z-index
        let sortedElements = template.elements.sorted { $0.zIndex < $1.zIndex }
        
        // Render each element
        for element in sortedElements {
            guard element.isVisible else { continue }
            
            try await renderElement(element, in: context, scale: scale)
        }
        
        // Create UIImage from context
        guard let cgImage = context.makeImage() else {
            throw LabelError.renderingFailed
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // Generate PDF data
        let pdfData = try generatePDFData(for: template, image: image)
        
        let renderTime = Date().timeIntervalSince(startTime)
        let imageData = image.pngData() ?? Data()
        
        let renderingInfo = LabelRenderingInfo(
            resolution: renderSize,
            dpi: renderDPI,
            renderTime: renderTime,
            fileSize: imageData.count + (pdfData?.count ?? 0),
            format: .png
        )
        
        Logger.info("LabelRenderer", "Label rendered in \(String(format: "%.3f", renderTime))s")
        
        return LabelOutput(
            image: image,
            pdfData: pdfData,
            template: template,
            renderingInfo: renderingInfo
        )
    }
    
    // MARK: - Private Rendering Methods
    
    private func renderElement(_ element: LabelElement, in context: CGContext, scale: CGFloat) async throws {
        context.saveGState()
        
        // Apply transformations
        if element.style.rotation != 0 {
            let centerX = element.frame.midX
            let centerY = element.frame.midY
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: element.style.rotation * .pi / 180)
            context.translateBy(x: -centerX, y: -centerY)
        }
        
        // Apply opacity
        context.setAlpha(element.style.opacity)
        
        // Render based on element type
        switch element.type {
        case .text:
            try renderTextElement(element, in: context)
            
        case .barcode:
            try await renderBarcodeElement(element, in: context, scale: scale)
            
        case .qrCode:
            try await renderQRCodeElement(element, in: context, scale: scale)
            
        case .image:
            try renderImageElement(element, in: context)
            
        case .line:
            renderLineElement(element, in: context)
            
        case .rectangle:
            renderRectangleElement(element, in: context)
        }
        
        context.restoreGState()
    }
    
    private func renderTextElement(_ element: LabelElement, in context: CGContext) throws {
        guard let text = element.content as? String, !text.isEmpty else { return }
        
        // Create attributed string
        let attributes = createTextAttributes(from: element.style)
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        
        // Calculate text frame
        let textFrame = element.frame
        
        // Draw background if needed
        if element.style.backgroundColor.alpha > 0 {
            context.setFillColor(element.style.backgroundColor.uiColor.cgColor)
            context.fill(textFrame)
        }
        
        // Draw border if needed
        if element.style.borderWidth > 0 {
            context.setStrokeColor(element.style.borderColor.uiColor.cgColor)
            context.setLineWidth(element.style.borderWidth)
            context.stroke(textFrame)
        }
        
        // Draw text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: textFrame, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
    }
    
    private func renderBarcodeElement(_ element: LabelElement, in context: CGContext, scale: CGFloat) async throws {
        guard let barcodeData = element.content as? String, !barcodeData.isEmpty else { return }
        
        let barcodeImage = try await barcodeGenerator.generateBarcode(
            data: barcodeData,
            size: element.frame.size,
            scale: scale
        )
        
        context.draw(barcodeImage, in: element.frame)
    }
    
    private func renderQRCodeElement(_ element: LabelElement, in context: CGContext, scale: CGFloat) async throws {
        guard let qrData = element.content as? String, !qrData.isEmpty else { return }
        
        let qrImage = try await qrCodeGenerator.generateQRCode(
            data: qrData,
            size: element.frame.size,
            scale: scale
        )
        
        context.draw(qrImage, in: element.frame)
    }
    
    private func renderImageElement(_ element: LabelElement, in context: CGContext) throws {
        // Placeholder for image rendering
        // In a real implementation, this would load and render actual images
        
        // Draw placeholder rectangle
        context.setFillColor(UIColor.lightGray.cgColor)
        context.fill(element.frame)
        
        // Draw "Image" text
        let attributes = createTextAttributes(from: element.style)
        let attributedString = NSAttributedString(string: "Image", attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: element.frame, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
    }
    
    private func renderLineElement(_ element: LabelElement, in context: CGContext) {
        context.setStrokeColor(element.style.borderColor.uiColor.cgColor)
        context.setLineWidth(element.style.borderWidth > 0 ? element.style.borderWidth : 1.0)
        
        context.move(to: CGPoint(x: element.frame.minX, y: element.frame.minY))
        context.addLine(to: CGPoint(x: element.frame.maxX, y: element.frame.maxY))
        context.strokePath()
    }
    
    private func renderRectangleElement(_ element: LabelElement, in context: CGContext) {
        // Fill background
        if element.style.backgroundColor.alpha > 0 {
            context.setFillColor(element.style.backgroundColor.uiColor.cgColor)
            
            if element.style.cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: element.frame, cornerRadius: element.style.cornerRadius)
                context.addPath(path.cgPath)
                context.fillPath()
            } else {
                context.fill(element.frame)
            }
        }
        
        // Draw border
        if element.style.borderWidth > 0 {
            context.setStrokeColor(element.style.borderColor.uiColor.cgColor)
            context.setLineWidth(element.style.borderWidth)
            
            if element.style.cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: element.frame, cornerRadius: element.style.cornerRadius)
                context.addPath(path.cgPath)
                context.strokePath()
            } else {
                context.stroke(element.frame)
            }
        }
    }
    
    private func createTextAttributes(from style: LabelElementStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        // Font
        let fontDescriptor = UIFontDescriptor(name: style.fontFamily, size: style.fontSize)
        let font = UIFont(descriptor: fontDescriptor, size: style.fontSize)
        attributes[.font] = font
        
        // Color
        attributes[.foregroundColor] = style.textColor.uiColor
        
        // Paragraph style for alignment
        let paragraphStyle = NSMutableParagraphStyle()
        switch style.textAlignment {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        case .justified:
            paragraphStyle.alignment = .justified
        }
        attributes[.paragraphStyle] = paragraphStyle
        
        return attributes
    }
    
    private func generatePDFData(for template: LabelTemplate, image: UIImage) throws -> Data {
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData) else {
            throw LabelError.renderingFailed
        }
        
        let mediaBox = CGRect(origin: .zero, size: template.size.displaySize)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw LabelError.renderingFailed
        }
        
        pdfContext.beginPDFPage(nil)
        
        if let cgImage = image.cgImage {
            pdfContext.draw(cgImage, in: mediaBox)
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return pdfData as Data
    }
}

// MARK: - Barcode Generator
class BarcodeGenerator {
    func generateBarcode(data: String, size: CGSize, scale: CGFloat) async throws -> CGImage {
        // Use Core Image to generate barcode
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else {
            throw LabelError.renderingFailed
        }
        
        let data = data.data(using: .ascii) ?? Data()
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else {
            throw LabelError.renderingFailed
        }
        
        // Scale the barcode to fit the desired size
        let scaleX = size.width * scale / outputImage.extent.width
        let scaleY = size.height * scale / outputImage.extent.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw LabelError.renderingFailed
        }
        
        return cgImage
    }
}

// MARK: - QR Code Generator
class QRCodeGenerator {
    func generateQRCode(data: String, size: CGSize, scale: CGFloat) async throws -> CGImage {
        // Use Core Image to generate QR code
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw LabelError.renderingFailed
        }
        
        let data = data.data(using: .utf8) ?? Data()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else {
            throw LabelError.renderingFailed
        }
        
        // Scale the QR code to fit the desired size
        let scaleX = size.width * scale / outputImage.extent.width
        let scaleY = size.height * scale / outputImage.extent.height
        let scale = min(scaleX, scaleY) // Maintain aspect ratio
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw LabelError.renderingFailed
        }
        
        return cgImage
    }
}
