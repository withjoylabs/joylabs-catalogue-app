import Foundation

class CSVGenerator {
    
    // MARK: - Category Grouping and Sorting
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
    
    // MARK: - Generate CSV for Reorder Items
    static func generateReorderCSV(from items: [ReorderItem]) -> Data? {
        var csvString = ""
        
        // Add headers
        let headers = ["Category", "Item Name", "Variation Name", "UPC", "SKU", "Price", "Quantity", "Status"]
        csvString.append(headers.map { escapeCSVField($0) }.joined(separator: ","))
        csvString.append("\n")
        
        // Group and sort items by category
        let groupedItems = groupAndSortItems(items)
        
        // Add data rows organized by category
        for categoryGroup in groupedItems {
            // Add category section header
            csvString.append("\n")
            csvString.append("--- \(categoryGroup.category.uppercased()) ---,,,,,,,\n")
            
            // Add items for this category
            for item in categoryGroup.items {
                let row = [
                    item.categoryName ?? "",
                    item.name,
                    item.variationName ?? "",
                    item.barcode ?? "",
                    item.sku ?? "",
                    formatPrice(item.price),
                    String(item.quantity),
                    item.status.displayName
                ]
                
                csvString.append(row.map { escapeCSVField($0) }.joined(separator: ","))
                csvString.append("\n")
            }
        }
        
        // Add summary row
        let totalQuantity = items.reduce(0) { $0 + $1.quantity }
        let totalValue = items.reduce(0.0) { total, item in
            total + (item.price ?? 0) * Double(item.quantity)
        }
        
        csvString.append("\n")
        csvString.append(",,,,,,,,\n")
        csvString.append("Total Items:,\(items.count),,,,,Total Quantity:,\(totalQuantity),\n")
        csvString.append(",,,,,,Total Value:,\(formatPrice(totalValue)),,\n")
        csvString.append("Generated:,\(formatDate(Date())),,,,,,,\n")
        
        return csvString.data(using: .utf8)
    }
    
    // MARK: - CSV Field Escaping
    private static func escapeCSVField(_ field: String) -> String {
        // Check if field needs escaping
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            // Escape quotes by doubling them
            let escapedQuotes = field.replacingOccurrences(of: "\"", with: "\"\"")
            // Wrap in quotes
            return "\"\(escapedQuotes)\""
        }
        return field
    }
    
    // MARK: - Formatting Helpers
    private static func formatPrice(_ price: Double?) -> String {
        guard let price = price else { return "" }
        return String(format: "$%.2f", price)
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Data for Sharing (Bypasses iOS File Security Issues)
    static func createShareableCSV(from items: [ReorderItem], fileName: String? = nil) -> ShareableFileData? {
        guard let csvData = generateReorderCSV(from: items) else { return nil }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let finalFileName = fileName ?? "reorder-list-\(timestamp).csv"
        
        return ShareableFileData.createCSV(data: csvData, filename: finalFileName)
    }
    
    // MARK: - File Creation (FIXED: Documents Directory + File Security)
    static func createCSVFile(from items: [ReorderItem], fileName: String? = nil) -> URL? {
        guard let csvData = generateReorderCSV(from: items) else { return nil }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let finalFileName = fileName ?? "reorder-list-\(timestamp).csv"
        
        // FIXED: Use Documents directory instead of temp directory for proper sharing permissions
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[CSVGenerator] Failed to access Documents directory")
            return nil
        }
        
        // Create Exports subdirectory for organization
        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports")
        
        do {
            // Ensure Exports directory exists
            try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
            
            var fileURL = exportsDirectory.appendingPathComponent(finalFileName)
            
            // Write file with proper attributes for sharing
            try csvData.write(to: fileURL, options: [.atomic])
            
            // Set file attributes for sharing (readable by other apps)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true // Don't backup export files
            try fileURL.setResourceValues(resourceValues)
            
            print("✅ [CSVGenerator] CSV file created successfully at: \(fileURL.lastPathComponent)")
            return fileURL
            
        } catch {
            print("❌ [CSVGenerator] Failed to write CSV file: \(error)")
            return nil
        }
    }
}