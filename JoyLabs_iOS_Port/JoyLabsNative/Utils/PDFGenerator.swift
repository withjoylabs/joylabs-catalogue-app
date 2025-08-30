import UIKit
import PDFKit

enum PDFLayout {
    case grid3 // 3 items per row
    case grid5 // 5 items per row  
    case grid7 // 7 items per row
    case list  // Detailed list format
}

class PDFGenerator {
    
    // MARK: - Category Grouping and Sorting (shared with CSVGenerator)
    static func groupAndSortItems(_ items: [ReorderItem]) -> [(category: String, items: [ReorderItem])] {
        // Group items by category
        let grouped = Dictionary(grouping: items) { item in
            item.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Uncategorized"
        }
        
        // Sort categories alphabetically and items within each category
        return grouped.map { category, categoryItems in
            let sortedItems = categoryItems.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return (category: category, items: sortedItems)
        }.sorted { lhs, rhs in
            // Put "Uncategorized" last
            if lhs.category == "Uncategorized" { return false }
            if rhs.category == "Uncategorized" { return true }
            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }
    
    // MARK: - Main PDF Generation
    static func generateReorderPDF(from items: [ReorderItem], layout: PDFLayout) -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter in points
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        
        return renderer.pdfData { context in
            // Group and sort items by category
            let groupedItems = groupAndSortItems(items)
            let totalItems = items.count
            
            switch layout {
            case .grid3:
                renderGridLayoutWithCategories(groupedItems: groupedItems, context: context, columns: 3, totalItems: totalItems)
            case .grid5:
                renderGridLayoutWithCategories(groupedItems: groupedItems, context: context, columns: 5, totalItems: totalItems)
            case .grid7:
                renderGridLayoutWithCategories(groupedItems: groupedItems, context: context, columns: 7, totalItems: totalItems)
            case .list:
                renderListLayoutWithCategories(groupedItems: groupedItems, context: context, totalItems: totalItems)
            }
        }
    }
    
    // MARK: - Grid Layout Rendering with Categories
    private static func renderGridLayoutWithCategories(groupedItems: [(category: String, items: [ReorderItem])], context: UIGraphicsPDFRendererContext, columns: Int, totalItems: Int) {
        let pageSize = context.format.bounds.size
        let margin: CGFloat = 36 // 0.5 inch margins
        let spacing: CGFloat = 8 // Reduced spacing since no borders/padding
        let contentWidth = pageSize.width - (margin * 2)
        let itemWidth = (contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let baseImageHeight = itemWidth * 0.7 // Base image size
        let actualImageHeight = baseImageHeight * 1.2 // 20% larger images
        let textHeight: CGFloat = columns == 3 ? 65 : 50 // More text space needed for wrapping
        let itemHeight = actualImageHeight + textHeight
        let categoryHeaderHeight: CGFloat = 25 // Space for category headers
        
        // REDUCED: Header height from 60 to 40 for better space efficiency
        let headerHeight: CGFloat = 40
        
        var currentY: CGFloat = margin + headerHeight
        var currentPage = 0
        
        // Calculate available content height
        let _ = pageSize.height - margin * 2 - headerHeight // Remove unused variable
        
        for categoryGroup in groupedItems {
            let itemsInCategory = categoryGroup.items.count
            let minItemsToShow = min(3, itemsInCategory) // Show at least 3 items or all if less
            let minItemsHeight = CGFloat(minItemsToShow) * (itemHeight + spacing) / CGFloat(columns)
            
            // Check if we need a new page for category header + minimum items
            if currentY + categoryHeaderHeight + minItemsHeight > pageSize.height - margin {
                context.beginPage()
                currentPage += 1
                currentY = margin + headerHeight
                drawGridHeader(context: context, pageNumber: currentPage + 1, totalItems: totalItems, layout: columns)
            }
            
            // Draw category header
            if currentPage == 0 && categoryGroup.category == groupedItems.first?.category {
                // First page, draw main header
                context.beginPage()
                currentPage = 1
                drawGridHeader(context: context, pageNumber: currentPage, totalItems: totalItems, layout: columns)
            }
            
            drawCategoryHeader(categoryName: categoryGroup.category, y: currentY, pageWidth: pageSize.width, margin: margin)
            currentY += categoryHeaderHeight
            
            // Draw items in this category
            var itemIndex = 0
            let categoryItems = categoryGroup.items
            
            while itemIndex < categoryItems.count {
                let itemsPerRow = columns
                let rowsRemaining = Int(ceil(Double(categoryItems.count - itemIndex) / Double(itemsPerRow)))
                let spaceNeeded = CGFloat(rowsRemaining) * (itemHeight + spacing)
                
                // Check if we need a new page
                if currentY + spaceNeeded > pageSize.height - margin {
                    context.beginPage()
                    currentPage += 1
                    currentY = margin + headerHeight
                    drawGridHeader(context: context, pageNumber: currentPage, totalItems: totalItems, layout: columns)
                }
                
                // Draw items in current row
                for col in 0..<itemsPerRow {
                    if itemIndex >= categoryItems.count { break }
                    
                    let x = margin + CGFloat(col) * (itemWidth + spacing)
                    
                    drawGridItemWithoutIndex(
                        item: categoryItems[itemIndex],
                        rect: CGRect(x: x, y: currentY, width: itemWidth, height: itemHeight),
                        imageSize: baseImageHeight,
                        fontSize: getFontSize(for: columns)
                    )
                    
                    itemIndex += 1
                }
                
                currentY += itemHeight + spacing
                if itemIndex >= categoryItems.count { break }
            }
            
            // Add extra space after category
            currentY += 10
        }
    }
    
    // MARK: - Grid Layout Rendering (Legacy)
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
    
    // MARK: - Grid Item Drawing (Without Index Numbers for space efficiency)
    private static func drawGridItemWithoutIndex(item: ReorderItem, rect: CGRect, imageSize: CGFloat, fontSize: CGFloat) {
        // NO BORDERS OR ROUNDED CORNERS - completely removed for clean look
        
        // Calculate larger image size using recovered space from removed padding
        let largerImageSize = imageSize * 1.2 // 20% larger images
        
        // Draw image or placeholder - LEFT ALIGNED with no padding
        let imageRect = CGRect(
            x: rect.minX, // Left aligned, no padding
            y: rect.minY, // No top margin
            width: largerImageSize,
            height: largerImageSize
        )
        
        if let imageUrl = item.imageUrl,
           let url = URL(string: imageUrl),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            image.draw(in: imageRect)
        } else {
            // Draw white placeholder with light border (ink-efficient for printing)
            UIColor.white.setFill()
            UIBezierPath(rect: imageRect).fill() // No rounded corners
            
            // Draw very light border
            UIColor.systemGray5.setStroke()
            let borderPath = UIBezierPath(rect: imageRect)
            borderPath.lineWidth = 0.5
            borderPath.stroke()
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
            UIColor.white.setStroke()
            let checkPath = UIBezierPath()
            checkPath.move(to: CGPoint(x: checkRect.minX + 5, y: checkRect.midY))
            checkPath.addLine(to: CGPoint(x: checkRect.midX - 1, y: checkRect.maxY - 6))
            checkPath.addLine(to: CGPoint(x: checkRect.maxX - 4, y: checkRect.minY + 5))
            checkPath.lineWidth = 2
            checkPath.stroke()
        }
        
        // Draw text below image - LEFT ALIGNED with image, no padding
        let textY = imageRect.maxY + 2
        let availableWidth = rect.width
        
        // For 3-grid: Show name (wrapped), UPC line 1, price left + qty right line 2
        if fontSize >= 11 { // 3-grid layout
            let nameFont = UIFont.systemFont(ofSize: fontSize - 1, weight: .medium)
            let detailFont = UIFont.systemFont(ofSize: fontSize - 2)
            let lineHeight = fontSize + 1
            
            var currentY = textY
            
            // Item Name with text wrapping (no truncation)
            let nameHeight = lineHeight * 2 // Allow 2 lines for name
            let nameRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: nameHeight)
            drawWrappingText(text: item.name, rect: nameRect, font: nameFont)
            currentY += nameHeight
            
            // UPC (line 1) 
            if let upc = item.barcode, !upc.isEmpty {
                let upcRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: lineHeight)
                upc.draw(in: upcRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.systemGray])
                currentY += lineHeight
            }
            
            // Price (left) and Qty (right) on same line (line 2)
            let priceQtyRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: lineHeight)
            if let price = item.price {
                let priceText = String(format: "$%.2f", price)
                priceText.draw(in: priceQtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
                
                let qtyText = "\(item.quantity)"
                let qtySize = qtyText.size(withAttributes: [.font: detailFont])
                let qtyRect = CGRect(x: rect.maxX - qtySize.width, y: currentY, width: qtySize.width, height: lineHeight)
                qtyText.draw(in: qtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
            } else {
                "\(item.quantity)".draw(in: priceQtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
            }
            
        } else {
            // For 5-grid and 7-grid: Same pattern
            let nameFont = UIFont.systemFont(ofSize: fontSize, weight: .medium) 
            let detailFont = UIFont.systemFont(ofSize: fontSize - 1)
            let lineHeight = fontSize + 1
            
            var currentY = textY
            
            // Item Name with text wrapping (no truncation)
            let nameHeight = lineHeight * 2
            let nameRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: nameHeight)
            drawWrappingText(text: item.name, rect: nameRect, font: nameFont)
            currentY += nameHeight
            
            // UPC (line 1)
            if let upc = item.barcode, !upc.isEmpty {
                let upcRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: lineHeight)
                upc.draw(in: upcRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.systemGray])
                currentY += lineHeight
            }
            
            // Price (left) and Qty (right) on same line (line 2)
            let priceQtyRect = CGRect(x: rect.minX, y: currentY, width: availableWidth, height: lineHeight)
            if let price = item.price {
                let priceText = String(format: "$%.2f", price)
                priceText.draw(in: priceQtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
                
                let qtyText = "\(item.quantity)"
                let qtySize = qtyText.size(withAttributes: [.font: detailFont])
                let qtyRect = CGRect(x: rect.maxX - qtySize.width, y: currentY, width: qtySize.width, height: lineHeight)
                qtyText.draw(in: qtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
            } else {
                "\(item.quantity)".draw(in: priceQtyRect, withAttributes: [.font: detailFont, .foregroundColor: UIColor.black])
            }
        }
    }
    
    // MARK: - Text Wrapping Helper
    private static func drawWrappingText(text: String, rect: CGRect, font: UIFont) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        text.draw(in: rect, withAttributes: attributes)
    }
    
    // MARK: - Category Header Drawing
    private static func drawCategoryHeader(categoryName: String, y: CGFloat, pageWidth: CGFloat, margin: CGFloat) {
        let headerRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 20)
        
        // Draw category name
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        
        categoryName.uppercased().draw(in: headerRect, withAttributes: headerAttributes)
        
        // Draw underline
        UIColor.systemGray3.setStroke()
        let underlinePath = UIBezierPath()
        underlinePath.move(to: CGPoint(x: margin, y: y + 18))
        underlinePath.addLine(to: CGPoint(x: pageWidth - margin, y: y + 18))
        underlinePath.lineWidth = 0.5
        underlinePath.stroke()
    }
    
    // MARK: - List Layout Rendering with Categories
    private static func renderListLayoutWithCategories(groupedItems: [(category: String, items: [ReorderItem])], context: UIGraphicsPDFRendererContext, totalItems: Int) {
        let pageSize = context.format.bounds.size
        let margin: CGFloat = 36
        let rowHeight: CGFloat = 50
        let headerHeight: CGFloat = 40 // REDUCED from 80
        let tableHeaderHeight: CGFloat = 18 // Further reduced for tighter spacing
        let categoryHeaderHeight: CGFloat = 25
        
        let contentHeight = pageSize.height - margin * 2 - headerHeight - tableHeaderHeight
        let _ = Int(contentHeight / rowHeight) // Remove unused variable
        
        var currentPage = 0
        var currentY: CGFloat = margin + headerHeight
        
        for categoryGroup in groupedItems {
            let itemsInCategory = categoryGroup.items.count
            let minItemsToShow = min(3, itemsInCategory) // Show at least 3 items or all if less
            let minItemsHeight = CGFloat(minItemsToShow) * rowHeight
            
            // Check if we need a new page for category header + minimum items
            if currentY + categoryHeaderHeight + tableHeaderHeight + minItemsHeight > pageSize.height - margin {
                context.beginPage()
                currentPage += 1
                currentY = margin + headerHeight
                drawListHeader(context: context, pageNumber: currentPage + 1, totalPages: 0, totalItems: totalItems)
            }
            
            // Draw main header on first page
            if currentPage == 0 && categoryGroup.category == groupedItems.first?.category {
                context.beginPage()
                currentPage = 1
                drawListHeader(context: context, pageNumber: currentPage, totalPages: 0, totalItems: totalItems)
            }
            
            // Draw category header
            drawCategoryHeader(categoryName: categoryGroup.category, y: currentY, pageWidth: pageSize.width, margin: margin)
            currentY += categoryHeaderHeight
            
            // Draw table header
            drawListTableHeader(y: currentY, margin: margin)
            currentY += tableHeaderHeight
            
            // Draw items in this category
            var itemIndex = 0
            let categoryItems = categoryGroup.items
            
            for item in categoryItems {
                // Check if we need a new page
                if currentY + rowHeight > pageSize.height - margin {
                    context.beginPage()
                    currentPage += 1
                    currentY = margin + headerHeight
                    drawListHeader(context: context, pageNumber: currentPage, totalPages: 0, totalItems: totalItems)
                    
                    // Redraw category header and table header on new page
                    drawCategoryHeader(categoryName: categoryGroup.category, y: currentY, pageWidth: pageSize.width, margin: margin)
                    currentY += categoryHeaderHeight
                    drawListTableHeader(y: currentY, margin: margin)
                    currentY += tableHeaderHeight
                }
                
                drawListItem(item: item, y: currentY, isEvenRow: itemIndex % 2 == 0)
                currentY += rowHeight
                itemIndex += 1
            }
            
            // Add extra space after category
            currentY += 10
        }
    }
    
    // MARK: - List Layout Rendering (Legacy)
    private static func renderListLayout(items: [ReorderItem], context: UIGraphicsPDFRendererContext) {
        let pageSize = context.format.bounds.size
        let margin: CGFloat = 36
        let rowHeight: CGFloat = 50
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
            // Draw white placeholder with light border (ink-efficient for printing)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: imageRect, cornerRadius: 4).fill()
            
            // Draw very light border
            UIColor.systemGray5.setStroke()
            let borderPath = UIBezierPath(roundedRect: imageRect, cornerRadius: 4)
            borderPath.lineWidth = 0.5
            borderPath.stroke()
            
            // No placeholder icon - just clean white square to save ink
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
    private static func drawListItem(item: ReorderItem, y: CGFloat, isEvenRow: Bool) {
        let margin: CGFloat = 36
        let pageWidth: CGFloat = 612
        let contentWidth = pageWidth - margin * 2
        let rowHeight: CGFloat = 50 // Reduced from 60 to tighten rows
        
        // Very subtle alternating row background (ink-efficient)
        if isEvenRow {
            // Use extremely light gray (almost white) to save ink
            UIColor(white: 0.97, alpha: 1.0).setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)).fill()
        }
        
        // New column widths: Image, Name, UPC, SKU, Retail, Qty (Variation removed and merged with name)
        let imageWidth: CGFloat = 50
        let nameWidth: CGFloat = 240    // +60pt from removed variation + existing space
        let upcWidth: CGFloat = 90      // +20pt wider for UPC codes
        let skuWidth: CGFloat = 60
        let priceWidth: CGFloat = 70
        let qtyWidth: CGFloat = contentWidth - imageWidth - nameWidth - upcWidth - skuWidth - priceWidth
        
        var x = margin
        let upcFontSize: CGFloat = 9 // Use UPC font size for all elements
        
        // Image - 1:1 aspect ratio (square), centered vertically, aligned with margin
        let imageSize: CGFloat = 36 // Reduced to fit tighter rows
        let imagePadding = (rowHeight - imageSize) / 2
        let imageRect = CGRect(x: x, y: y + imagePadding, width: imageSize, height: imageSize)
        if let imageUrl = item.imageUrl,
           let url = URL(string: imageUrl),
           let imageData = try? Data(contentsOf: url),
           let image = UIImage(data: imageData) {
            image.draw(in: imageRect)
        } else {
            // White background for missing images (ink-efficient)
            UIColor.white.setFill()
            UIBezierPath(rect: imageRect).fill()
            
            // Very light border
            UIColor.systemGray5.setStroke()
            let borderPath = UIBezierPath(rect: imageRect)
            borderPath.lineWidth = 0.5
            borderPath.stroke()
        }
        x += imageWidth
        
        // Item Name with variation appended - with text wrapping support
        let itemNameWithVariation = formatDisplayName(item: item)
        drawTableCellCentered(text: itemNameWithVariation, x: x, y: y, width: nameWidth, height: rowHeight, fontSize: upcFontSize, allowWrapping: true)
        x += nameWidth
        
        // UPC - centered vertically
        drawTableCellCentered(text: item.barcode ?? "", x: x, y: y, width: upcWidth, height: rowHeight, fontSize: upcFontSize)
        x += upcWidth
        
        // SKU - centered vertically
        drawTableCellCentered(text: item.sku ?? "", x: x, y: y, width: skuWidth, height: rowHeight, fontSize: upcFontSize)
        x += skuWidth
        
        // Retail Price - centered vertically
        let priceText = item.price != nil ? String(format: "$%.2f", item.price!) : ""
        drawTableCellCentered(text: priceText, x: x, y: y, width: priceWidth, height: rowHeight, fontSize: upcFontSize, alignment: .right)
        x += priceWidth
        
        // Qty - centered vertically
        drawTableCellCentered(text: "\(item.quantity)", x: x, y: y, width: qtyWidth, height: rowHeight, fontSize: upcFontSize, alignment: .center)
    }
    
    // MARK: - Headers
    private static func drawGridHeader(context: UIGraphicsPDFRendererContext, pageNumber: Int, totalItems: Int, layout: Int) {
        let margin: CGFloat = 36
        let pageWidth = context.format.bounds.size.width
        
        // Title - REDUCED font size for better space efficiency
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
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
        pageText.draw(at: CGPoint(x: pageWidth - margin - pageSize.width, y: margin + 2), withAttributes: infoAttributes)
    }
    
    private static func drawListHeader(context: UIGraphicsPDFRendererContext, pageNumber: Int, totalPages: Int, totalItems: Int) {
        let margin: CGFloat = 36
        let pageWidth = context.format.bounds.size.width
        
        // Title - REDUCED font size for space efficiency
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        "Reorder List".draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)
        
        // Date and page info in single line - REDUCED spacing
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.systemGray
        ]
        let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let pageText = "Page \(pageNumber) | \(totalItems) items | \(dateText)"
        let pageSize = pageText.size(withAttributes: subtitleAttributes)
        pageText.draw(at: CGPoint(x: pageWidth - margin - pageSize.width, y: margin + 2), withAttributes: subtitleAttributes)
    }
    
    private static func drawListTableHeader(y: CGFloat, margin: CGFloat) {
        let pageWidth: CGFloat = 612
        let contentWidth = pageWidth - margin * 2
        
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold), // Same size as UPC font, but bold
            .foregroundColor: UIColor.black
        ]
        
        // New column layout: Image, Name, UPC, SKU, Retail, Qty (Variation merged with name)
        var x = margin
        drawTableCell(text: "Image", x: x, y: y, width: 50, height: 18, attributes: headerAttributes, alignment: .center)
        x += 50
        drawTableCell(text: "Item Name", x: x, y: y, width: 240, height: 18, attributes: headerAttributes)
        x += 240
        drawTableCell(text: "UPC", x: x, y: y, width: 90, height: 18, attributes: headerAttributes)
        x += 90
        drawTableCell(text: "SKU", x: x, y: y, width: 60, height: 18, attributes: headerAttributes)
        x += 60
        drawTableCell(text: "Retail", x: x, y: y, width: 70, height: 18, attributes: headerAttributes, alignment: .right)
        x += 70
        
        let remainingWidth = contentWidth - (x - margin)
        drawTableCell(text: "Qty", x: x, y: y, width: remainingWidth, height: 18, attributes: headerAttributes, alignment: .center)
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
    
    // MARK: - Table Cell with Text Wrapping
    private static func drawTableCellWithWrapping(
        text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat = 11,
        alignment: NSTextAlignment = .left
    ) {
        let mutableAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        var mutableAttributesCopy = mutableAttributes
        mutableAttributesCopy[.paragraphStyle] = paragraphStyle
        
        let rect = CGRect(x: x + 4, y: y + 2, width: width - 8, height: height - 4)
        text.draw(in: rect, withAttributes: mutableAttributesCopy)
    }
    
    // MARK: - Table Cell with Vertical Centering
    private static func drawTableCellCentered(
        text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat = 10,
        alignment: NSTextAlignment = .left,
        allowWrapping: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = allowWrapping ? .byWordWrapping : .byTruncatingTail
        
        var mutableAttributes = attributes
        mutableAttributes[.paragraphStyle] = paragraphStyle
        
        if allowWrapping {
            // For wrapped text, use the full height and let it flow naturally
            let rect = CGRect(x: x + 4, y: y + 2, width: width - 8, height: height - 4)
            text.draw(in: rect, withAttributes: mutableAttributes)
        } else {
            // For single line text, center vertically
            let textSize = text.size(withAttributes: mutableAttributes)
            let verticalPadding = (height - textSize.height) / 2
            let rect = CGRect(x: x + 4, y: y + verticalPadding, width: width - 8, height: textSize.height)
            text.draw(in: rect, withAttributes: mutableAttributes)
        }
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
        
        let finalFileName = fileName ?? generateDescriptiveFilename(for: layout)
        
        return ShareableFileData.createPDF(data: pdfData, filename: finalFileName)
    }
    
    // MARK: - Descriptive Filename Generation
    private static func generateDescriptiveFilename(for layout: PDFLayout) -> String {
        // Format: [Business Name] Reorder List - [YYYY-MM-DD] - [Layout Option].pdf
        let businessName = UserDefaults.standard.string(forKey: "businessName") ?? "Business"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        let layoutOption: String
        switch layout {
        case .grid3: layoutOption = "3 Per Row Grid"
        case .grid5: layoutOption = "5 Per Row Grid"
        case .grid7: layoutOption = "7 Per Row Grid"
        case .list: layoutOption = "Detailed List"
        }
        
        return "\(businessName) Reorder List - \(dateString) - \(layoutOption).pdf"
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