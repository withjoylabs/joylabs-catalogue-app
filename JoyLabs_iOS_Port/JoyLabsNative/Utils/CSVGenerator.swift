import Foundation

class CSVGenerator {
    
    // MARK: - Generate CSV for Reorder Items
    static func generateReorderCSV(from items: [ReorderItem]) -> Data? {
        var csvString = ""
        
        // Add headers
        let headers = ["Index", "Item Name", "Variation Name", "Category", "UPC", "SKU", "Price", "Quantity", "Status"]
        csvString.append(headers.map { escapeCSVField($0) }.joined(separator: ","))
        csvString.append("\n")
        
        // Add data rows
        for (index, item) in items.enumerated() {
            let row = [
                String(index + 1),
                item.name,
                item.variationName ?? "",
                item.categoryName ?? "",
                item.barcode ?? "",
                item.sku ?? "",
                formatPrice(item.price),
                String(item.quantity),
                item.status.displayName
            ]
            
            csvString.append(row.map { escapeCSVField($0) }.joined(separator: ","))
            csvString.append("\n")
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
    
    // MARK: - File Creation
    static func createCSVFile(from items: [ReorderItem], fileName: String? = nil) -> URL? {
        guard let csvData = generateReorderCSV(from: items) else { return nil }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let finalFileName = fileName ?? "reorder-list-\(timestamp).csv"
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(finalFileName)
        
        do {
            try csvData.write(to: fileURL)
            return fileURL
        } catch {
            print("[CSVGenerator] Failed to write CSV file: \(error)")
            return nil
        }
    }
}