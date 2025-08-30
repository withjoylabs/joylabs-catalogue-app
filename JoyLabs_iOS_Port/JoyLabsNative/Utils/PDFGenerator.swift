import UIKit
import PDFKit

enum PDFLayout {
    case grid3 // 3 items per row
    case grid5 // 5 items per row  
    case grid7 // 7 items per row
    case list  // Detailed list format
}

class PDFGenerator {
    
    // MARK: - Main PDF Generation
    static func generateReorderPDF(from items: [ReorderItem], layout: PDFLayout) -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter in points
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        
        return renderer.pdfData { context in
            switch layout {
            case .grid3:
                renderGridLayout(items: items, context: context, columns: 3)
            case .grid5:
                renderGridLayout(items: items, context: context, columns: 5)
            case .grid7:
                renderGridLayout(items: items, context: context, columns: 7)
            case .list:
                renderListLayout(items: items, context: context)
            }
        }
    }
    
    // MARK: - Grid Layout Rendering
    private static func renderGridLayout(items: [ReorderItem], context: UIGraphicsPDFRendererContext, columns: Int) {
        let pageSize = context.format.bounds.size
        let margin: CGFloat = 36 // 0.5 inch margins
        let spacing: CGFloat = 12
        let contentWidth = pageSize.width - (margin * 2)
        let itemWidth = (contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let imageHeight = itemWidth // Square images
        let textHeight: CGFloat = getFontSize(for: columns) * 5 + 10 // Adjust based on columns
        let itemHeight = imageHeight + textHeight
        
        let rowsPerPage = Int((pageSize.height - margin * 2 - 60) / (itemHeight + spacing)) // 60 for header
        
        var currentPage = 0
        var itemIndex = 0
        
        while itemIndex < items.count {
            // Start new page
            if itemIndex > 0 {
                context.beginPage()
            } else {
                context.beginPage()
            }
            currentPage += 1
            
            // Draw header
            drawGridHeader(
                context: context,
                pageNumber: currentPage,
                totalItems: items.count,
                layout: columns
            )
            
            // Draw items
            for row in 0..<rowsPerPage {
                for col in 0..<columns {
                    if itemIndex >= items.count { break }
                    
                    let x = margin + CGFloat(col) * (itemWidth + spacing)
                    let y = margin + 60 + CGFloat(row) * (itemHeight + spacing)
                    
                    drawGridItem(
                        item: items[itemIndex],
                        index: itemIndex + 1,
                        rect: CGRect(x: x, y: y, width: itemWidth, height: itemHeight),
                        imageSize: imageHeight,
                        fontSize: getFontSize(for: columns)
                    )
                    
                    itemIndex += 1
                }
                if itemIndex >= items.count { break }
            }
        }
    }
    
    // MARK: - List Layout Rendering
    private static func renderListLayout(items: [ReorderItem], context: UIGraphicsPDFRendererContext) {
        let pageSize = context.format.bounds.size
        let margin: CGFloat = 36
        let rowHeight: CGFloat = 60
        let headerHeight: CGFloat = 80
        let tableHeaderHeight: CGFloat = 30
        
        let contentHeight = pageSize.height - margin * 2 - headerHeight - tableHeaderHeight
        let rowsPerPage = Int(contentHeight / rowHeight)
        
        var currentPage = 0
        var itemIndex = 0
        
        while itemIndex < items.count {
            // Start new page
            if itemIndex > 0 {
                context.beginPage()
            } else {
                context.beginPage()
            }
            currentPage += 1
            
            // Draw page header
            drawListHeader(
                context: context,
                pageNumber: currentPage,
                totalPages: Int(ceil(Double(items.count) / Double(rowsPerPage))),
                totalItems: items.count
            )
            
            // Draw table header
            drawTableHeader(context: context, y: margin + headerHeight)
            
            // Draw items
            var y = margin + headerHeight + tableHeaderHeight
            for _ in 0..<rowsPerPage {
                if itemIndex >= items.count { break }
                
                drawListItem(
                    item: items[itemIndex],
                    index: itemIndex + 1,
                    y: y,
                    isEvenRow: itemIndex % 2 == 0
                )
                
                y += rowHeight
                itemIndex += 1
            }
            
            // Draw totals on last page
            if itemIndex >= items.count {
                drawListTotals(items: items, y: y, context: context)
            }
        }
    }
    
    // MARK: - Grid Item Drawing
    private static func drawGridItem(item: ReorderItem, index: Int, rect: CGRect, imageSize: CGFloat, fontSize: CGFloat) {
        // Draw border
        UIColor.systemGray4.setStroke()
        let borderPath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
        
        // Draw index number (top-left corner)
        let indexRect = CGRect(x: rect.minX + 4, y: rect.minY + 4, width: 24, height: 16)
        let indexAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.systemGray
        ]
        "\(index)".draw(in: indexRect, withAttributes: indexAttributes)
        
        // Draw image or placeholder
        let imageRect = CGRect(
            x: rect.minX + (rect.width - imageSize) / 2,
            y: rect.minY + 20,
            width: imageSize,
            height: imageSize
        )
        
        if let imageUrl = item.imageUrl,
           let url = URL(string: imageUrl),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            image.draw(in: imageRect)
        } else {
            // Draw placeholder
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: imageRect, cornerRadius: 4).fill()
            
            // Draw placeholder icon
            let iconSize: CGFloat = imageSize * 0.3
            let iconRect = CGRect(
                x: imageRect.midX - iconSize/2,
                y: imageRect.midY - iconSize/2,
                width: iconSize,
                height: iconSize
            )
            if let photoIcon = UIImage(systemName: "photo") {
                photoIcon.withTintColor(.systemGray3).draw(in: iconRect)
            }
        }
        
        // Draw status indicator
        if item.status == .purchased {
            let checkSize: CGFloat = 20
            let checkRect = CGRect(
                x: imageRect.minX + 4,
                y: imageRect.minY + 4,
                width: checkSize,
                height: checkSize
            )
            UIColor.systemGreen.setFill()
            UIBezierPath(ovalIn: checkRect).fill()
            
            // Draw checkmark
            if let checkmark = UIImage(systemName: "checkmark") {
                checkmark.withTintColor(.white).draw(in: checkRect.insetBy(dx: 4, dy: 4))
            }
        }
        
        // Draw text details below image
        let textY = imageRect.maxY + 4
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        let smallAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize - 1),
            .foregroundColor: UIColor.systemGray
        ]
        
        // Item name
        let nameRect = CGRect(x: rect.minX + 4, y: textY, width: rect.width - 8, height: fontSize + 2)
        let displayName = formatDisplayName(item: item)
        displayName.draw(in: nameRect, withAttributes: textAttributes)
        
        // Category & Price
        if fontSize > 8 { // Only show for larger grids
            let categoryRect = CGRect(x: rect.minX + 4, y: textY + fontSize + 2, width: rect.width - 8, height: fontSize)
            (item.categoryName ?? "").draw(in: categoryRect, withAttributes: smallAttributes)
            
            if let price = item.price {
                let priceText = String(format: "$%.2f × %d", price, item.quantity)
                let priceRect = CGRect(x: rect.minX + 4, y: textY + (fontSize + 2) * 2, width: rect.width - 8, height: fontSize)
                priceText.draw(in: priceRect, withAttributes: smallAttributes)
            }
        }
    }
    
    // MARK: - List Item Drawing
    private static func drawListItem(item: ReorderItem, index: Int, y: CGFloat, isEvenRow: Bool) {
        let margin: CGFloat = 36
        let pageWidth: CGFloat = 612
        let contentWidth = pageWidth - margin * 2
        
        // Alternating row background
        if isEvenRow {
            UIColor.systemGray6.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 60)).fill()
        }
        
        // Column widths
        let indexWidth: CGFloat = 40
        let imageWidth: CGFloat = 50
        let nameWidth: CGFloat = 150
        let variationWidth: CGFloat = 80
        let categoryWidth: CGFloat = 80
        let upcWidth: CGFloat = 80
        let skuWidth: CGFloat = 60
        let priceWidth: CGFloat = contentWidth - indexWidth - imageWidth - nameWidth - variationWidth - categoryWidth - upcWidth - skuWidth
        
        var x = margin
        
        // Index
        drawTableCell(text: "\(index)", x: x, y: y, width: indexWidth, height: 60, alignment: .center)
        x += indexWidth
        
        // Image
        let imageRect = CGRect(x: x + 5, y: y + 5, width: 40, height: 50)
        if let imageUrl = item.imageUrl,
           let url = URL(string: imageUrl),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            image.draw(in: imageRect)
        } else {
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: imageRect).fill()
        }
        x += imageWidth
        
        // Item Name
        drawTableCell(text: item.name, x: x, y: y, width: nameWidth, height: 60)
        x += nameWidth
        
        // Variation
        drawTableCell(text: item.variationName ?? "", x: x, y: y, width: variationWidth, height: 60)
        x += variationWidth
        
        // Category
        drawTableCell(text: item.categoryName ?? "", x: x, y: y, width: categoryWidth, height: 60)
        x += categoryWidth
        
        // UPC
        drawTableCell(text: item.barcode ?? "", x: x, y: y, width: upcWidth, height: 60, fontSize: 9)
        x += upcWidth
        
        // SKU
        drawTableCell(text: item.sku ?? "", x: x, y: y, width: skuWidth, height: 60, fontSize: 9)
        x += skuWidth
        
        // Price × Qty
        let priceText: String
        if let price = item.price {
            priceText = String(format: "$%.2f × %d", price, item.quantity)
        } else {
            priceText = "× \(item.quantity)"
        }
        drawTableCell(text: priceText, x: x, y: y, width: priceWidth, height: 60, alignment: .right)
    }
    
    // MARK: - Headers
    private static func drawGridHeader(context: UIGraphicsPDFRendererContext, pageNumber: Int, totalItems: Int, layout: Int) {
        let margin: CGFloat = 36
        let pageWidth = context.format.bounds.size.width
        
        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let title = "Reorder List - \(layout) per Row"
        title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)
        
        // Date and page
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.systemGray
        ]
        let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let pageText = "Page \(pageNumber) | \(totalItems) items | \(dateText)"
        let pageSize = pageText.size(withAttributes: infoAttributes)
        pageText.draw(at: CGPoint(x: pageWidth - margin - pageSize.width, y: margin), withAttributes: infoAttributes)
    }
    
    private static func drawListHeader(context: UIGraphicsPDFRendererContext, pageNumber: Int, totalPages: Int, totalItems: Int) {
        let margin: CGFloat = 36
        let pageWidth = context.format.bounds.size.width
        
        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        "Reorder List".draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)
        
        // Subtitle with date
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.systemGray
        ]
        let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        dateText.draw(at: CGPoint(x: margin, y: margin + 25), withAttributes: subtitleAttributes)
        
        // Page info
        let pageText = "Page \(pageNumber) of \(totalPages) | Total Items: \(totalItems)"
        let pageSize = pageText.size(withAttributes: subtitleAttributes)
        pageText.draw(at: CGPoint(x: pageWidth - margin - pageSize.width, y: margin + 25), withAttributes: subtitleAttributes)
    }
    
    private static func drawTableHeader(context: UIGraphicsPDFRendererContext, y: CGFloat) {
        let margin: CGFloat = 36
        let pageWidth: CGFloat = 612
        let contentWidth = pageWidth - margin * 2
        
        // Header background
        UIColor.systemGray.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 30)).fill()
        
        // Column headers
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        
        var x = margin
        drawTableCell(text: "#", x: x, y: y, width: 40, height: 30, attributes: headerAttributes, alignment: .center)
        x += 40
        drawTableCell(text: "Image", x: x, y: y, width: 50, height: 30, attributes: headerAttributes, alignment: .center)
        x += 50
        drawTableCell(text: "Item Name", x: x, y: y, width: 150, height: 30, attributes: headerAttributes)
        x += 150
        drawTableCell(text: "Variation", x: x, y: y, width: 80, height: 30, attributes: headerAttributes)
        x += 80
        drawTableCell(text: "Category", x: x, y: y, width: 80, height: 30, attributes: headerAttributes)
        x += 80
        drawTableCell(text: "UPC", x: x, y: y, width: 80, height: 30, attributes: headerAttributes)
        x += 80
        drawTableCell(text: "SKU", x: x, y: y, width: 60, height: 30, attributes: headerAttributes)
        x += 60
        
        let remainingWidth = contentWidth - (x - margin)
        drawTableCell(text: "Price × Qty", x: x, y: y, width: remainingWidth, height: 30, attributes: headerAttributes, alignment: .right)
    }
    
    private static func drawListTotals(items: [ReorderItem], y: CGFloat, context: UIGraphicsPDFRendererContext) {
        let margin: CGFloat = 36
        let pageWidth: CGFloat = 612
        let contentWidth = pageWidth - margin * 2
        
        // Separator line
        UIColor.systemGray.setStroke()
        let separatorPath = UIBezierPath()
        separatorPath.move(to: CGPoint(x: margin, y: y))
        separatorPath.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        separatorPath.lineWidth = 1
        separatorPath.stroke()
        
        // Calculate totals
        let totalQuantity = items.reduce(0) { $0 + $1.quantity }
        let totalValue = items.reduce(0.0) { total, item in
            total + (item.price ?? 0) * Double(item.quantity)
        }
        
        let totalsAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        // Total items
        let itemsText = "Total Items: \(items.count)"
        itemsText.draw(at: CGPoint(x: margin, y: y + 10), withAttributes: totalsAttributes)
        
        // Total quantity
        let quantityText = "Total Quantity: \(totalQuantity)"
        quantityText.draw(at: CGPoint(x: margin + 200, y: y + 10), withAttributes: totalsAttributes)
        
        // Total value
        let valueText = String(format: "Total Value: $%.2f", totalValue)
        let valueSize = valueText.size(withAttributes: totalsAttributes)
        valueText.draw(at: CGPoint(x: margin + contentWidth - valueSize.width, y: y + 10), withAttributes: totalsAttributes)
    }
    
    // MARK: - Helper Functions
    private static func drawTableCell(
        text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any]? = nil,
        alignment: NSTextAlignment = .left,
        fontSize: CGFloat = 10
    ) {
        let finalAttributes = attributes ?? [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        var mutableAttributes = finalAttributes
        mutableAttributes[.paragraphStyle] = paragraphStyle
        
        let rect = CGRect(x: x + 4, y: y, width: width - 8, height: height)
        text.draw(in: rect, withAttributes: mutableAttributes)
    }
    
    private static func getFontSize(for columns: Int) -> CGFloat {
        switch columns {
        case 3: return 11
        case 5: return 9
        case 7: return 7
        default: return 10
        }
    }
    
    private static func formatDisplayName(item: ReorderItem) -> String {
        var name = item.name
        if let variation = item.variationName, !variation.isEmpty {
            name = "\(name) • \(variation)"
        }
        return name
    }
    
    // MARK: - Data for Sharing (Bypasses iOS File Security Issues)
    static func createShareablePDF(from items: [ReorderItem], layout: PDFLayout, fileName: String? = nil) -> ShareableFileData? {
        let pdfData = generateReorderPDF(from: items, layout: layout)
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        
        let layoutSuffix: String
        switch layout {
        case .grid3: layoutSuffix = "grid-3"
        case .grid5: layoutSuffix = "grid-5"
        case .grid7: layoutSuffix = "grid-7"
        case .list: layoutSuffix = "list"
        }
        
        let finalFileName = fileName ?? "reorder-\(layoutSuffix)-\(timestamp).pdf"
        
        return ShareableFileData.createPDF(data: pdfData, filename: finalFileName)
    }
    
    // MARK: - File Creation (FIXED: Documents Directory + File Security)
    static func createPDFFile(from items: [ReorderItem], layout: PDFLayout, fileName: String? = nil) -> URL? {
        let pdfData = generateReorderPDF(from: items, layout: layout)
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        
        let layoutSuffix: String
        switch layout {
        case .grid3: layoutSuffix = "grid-3"
        case .grid5: layoutSuffix = "grid-5"
        case .grid7: layoutSuffix = "grid-7"
        case .list: layoutSuffix = "list"
        }
        
        let finalFileName = fileName ?? "reorder-\(layoutSuffix)-\(timestamp).pdf"
        
        // FIXED: Use Documents directory instead of temp directory for proper sharing permissions
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[PDFGenerator] Failed to access Documents directory")
            return nil
        }
        
        // Create Exports subdirectory for organization
        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports")
        
        do {
            // Ensure Exports directory exists
            try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
            
            var fileURL = exportsDirectory.appendingPathComponent(finalFileName)
            
            // Write file with proper attributes for sharing
            try pdfData.write(to: fileURL, options: [.atomic])
            
            // Set file attributes for sharing (readable by other apps)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true // Don't backup export files
            try fileURL.setResourceValues(resourceValues)
            
            print("✅ [PDFGenerator] PDF file created successfully at: \(fileURL.lastPathComponent)")
            return fileURL
            
        } catch {
            print("❌ [PDFGenerator] Failed to write PDF file: \(error)")
            return nil
        }
    }
}