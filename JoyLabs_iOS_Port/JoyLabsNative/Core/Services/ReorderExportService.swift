import Foundation
import UIKit

enum ExportFormat {
    case csv
    case pdfGrid3
    case pdfGrid5
    case pdfGrid7
    case pdfList
    
    var displayName: String {
        switch self {
        case .csv:
            return "CSV (Spreadsheet)"
        case .pdfGrid3:
            return "PDF Grid - 3 per row"
        case .pdfGrid5:
            return "PDF Grid - 5 per row"
        case .pdfGrid7:
            return "PDF Grid - 7 per row"
        case .pdfList:
            return "PDF List (Detailed)"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .csv:
            return "csv"
        case .pdfGrid3, .pdfGrid5, .pdfGrid7, .pdfList:
            return "pdf"
        }
    }
}

@MainActor
class ReorderExportService: ObservableObject {
    static let shared = ReorderExportService()
    
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatus: String = ""
    
    private init() {}
    
    // MARK: - Export Functions
    func exportReorderList(items: [ReorderItem], format: ExportFormat) async -> URL? {
        guard !items.isEmpty else {
            ToastNotificationService.shared.showWarning("No items to export")
            return nil
        }
        
        isExporting = true
        exportProgress = 0
        exportStatus = "Preparing export..."
        
        defer {
            isExporting = false
            exportProgress = 0
            exportStatus = ""
        }
        
        // For PDFs with images, we need to pre-download images
        if format != .csv {
            exportStatus = "Loading images..."
            await preloadImages(for: items)
        }
        
        exportStatus = "Generating \(format.displayName)..."
        exportProgress = 0.5
        
        let fileURL: URL?
        
        switch format {
        case .csv:
            fileURL = CSVGenerator.createCSVFile(from: items)
            
        case .pdfGrid3:
            fileURL = PDFGenerator.createPDFFile(from: items, layout: .grid3)
            
        case .pdfGrid5:
            fileURL = PDFGenerator.createPDFFile(from: items, layout: .grid5)
            
        case .pdfGrid7:
            fileURL = PDFGenerator.createPDFFile(from: items, layout: .grid7)
            
        case .pdfList:
            fileURL = PDFGenerator.createPDFFile(from: items, layout: .list)
        }
        
        exportProgress = 1.0
        
        if fileURL != nil {
            exportStatus = "Export complete!"
            ToastNotificationService.shared.showSuccess("Export generated successfully")
            
            // Clean up old export files after successful export
            Task.detached(priority: .background) {
                await MainActor.run {
                    self.cleanupOldExportFiles()
                }
            }
        } else {
            ToastNotificationService.shared.showError("Failed to generate export")
        }
        
        return fileURL
    }
    
    // MARK: - Quick Export Functions (for direct actions)
    func quickExportCSV(items: [ReorderItem]) -> URL? {
        guard !items.isEmpty else {
            ToastNotificationService.shared.showWarning("No items to export")
            return nil
        }
        
        if let fileURL = CSVGenerator.createCSVFile(from: items) {
            ToastNotificationService.shared.showSuccess("CSV export ready")
            return fileURL
        } else {
            ToastNotificationService.shared.showError("Failed to generate CSV")
            return nil
        }
    }
    
    func quickExportPDFList(items: [ReorderItem]) async -> URL? {
        guard !items.isEmpty else {
            ToastNotificationService.shared.showWarning("No items to export")
            return nil
        }
        
        // Preload images for better quality
        await preloadImages(for: items)
        
        if let fileURL = PDFGenerator.createPDFFile(from: items, layout: .list) {
            ToastNotificationService.shared.showSuccess("PDF export ready")
            return fileURL
        } else {
            ToastNotificationService.shared.showError("Failed to generate PDF")
            return nil
        }
    }
    
    // MARK: - Image Preloading
    private func preloadImages(for items: [ReorderItem]) async {
        let imageURLs = items.compactMap { $0.imageUrl }.filter { !$0.isEmpty }
        let uniqueURLs = Array(Set(imageURLs))
        
        guard !uniqueURLs.isEmpty else { return }
        
        let session = URLSession.shared
        let cache = URLCache.shared
        
        // Preload images into URLCache
        await withTaskGroup(of: Void.self) { group in
            for urlString in uniqueURLs {
                group.addTask {
                    guard let url = URL(string: urlString) else { return }
                    
                    // Check if already cached
                    let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                    if cache.cachedResponse(for: request) != nil {
                        return
                    }
                    
                    // Download and cache
                    do {
                        let (data, response) = try await session.data(for: request)
                        let cachedResponse = CachedURLResponse(response: response, data: data)
                        cache.storeCachedResponse(cachedResponse, for: request)
                    } catch {
                        print("[ReorderExportService] Failed to preload image: \(error)")
                    }
                }
            }
        }
        
        exportProgress = 0.3
    }
    
    // MARK: - Export Statistics
    func getExportStatistics(for items: [ReorderItem]) -> (itemCount: Int, totalQuantity: Int, totalValue: Double, categories: Int) {
        let itemCount = items.count
        let totalQuantity = items.reduce(0) { $0 + $1.quantity }
        let totalValue = items.reduce(0.0) { total, item in
            total + (item.price ?? 0) * Double(item.quantity)
        }
        let categories = Set(items.compactMap { $0.categoryName }).count
        
        return (itemCount, totalQuantity, totalValue, categories)
    }
    
    // MARK: - File Cleanup
    /// Clean up old export files to prevent storage buildup
    /// Keeps only the most recent 10 files and removes files older than 7 days
    func cleanupOldExportFiles() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: exportsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            
            // Filter to only export files (CSV and PDF)
            let exportFiles = fileURLs.filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "csv" || ext == "pdf"
            }
            
            // Sort by creation date (newest first)
            let sortedFiles = exportFiles.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
            
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            var deletedCount = 0
            
            // Remove files beyond the 10 most recent OR older than 7 days
            for (index, fileURL) in sortedFiles.enumerated() {
                let shouldDelete = index >= 10 // Keep only 10 most recent
                
                if !shouldDelete {
                    // Also check age
                    if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < sevenDaysAgo {
                        // File is older than 7 days
                    } else {
                        continue // Keep this file
                    }
                }
                
                // Delete the file
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                    print("🗑️ [ReorderExportService] Cleaned up old export file: \(fileURL.lastPathComponent)")
                } catch {
                    print("❌ [ReorderExportService] Failed to delete export file \(fileURL.lastPathComponent): \(error)")
                }
            }
            
            if deletedCount > 0 {
                print("✅ [ReorderExportService] Cleaned up \(deletedCount) old export files")
            }
            
        } catch {
            print("❌ [ReorderExportService] Failed to cleanup export files: \(error)")
        }
    }
}