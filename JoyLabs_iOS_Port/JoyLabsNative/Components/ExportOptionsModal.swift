import SwiftUI

struct ExportOptionsModal: View {
    @Binding var isPresented: Bool
    let items: [ReorderItem]
    let onExport: (ExportFormat) async -> Void
    
    @StateObject private var exportService = ReorderExportService.shared
    @State private var selectedFormat: ExportFormat?
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var shareableFiles: [ShareableFileData] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Statistics Header
                statisticsHeader
                
                Divider()
                
                // Export Options - Fixed Layout
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(exportOptions, id: \.format) { option in
                            exportOptionCard(option: option)
                        }
                    }
                    .padding()
                }
                .layoutPriority(1) // Give ScrollView layout priority
                
                // Export Progress (if exporting)
                if exportService.isExporting {
                    exportProgressView
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .shareSheet(
            isPresented: $showShareSheet,
            shareableFiles: shareableFiles,
            onComplete: { success in
                if success {
                    isPresented = false
                }
            }
        )
    }
    
    // MARK: - Statistics Header
    private var statisticsHeader: some View {
        let stats = exportService.getExportStatistics(for: items)
        
        return VStack(spacing: 8) {
            HStack(spacing: 20) {
                statisticItem(title: "Items", value: "\(stats.itemCount)")
                statisticItem(title: "Quantity", value: "\(stats.totalQuantity)")
                statisticItem(title: "Categories", value: "\(stats.categories)")
                statisticItem(title: "Total Value", value: String(format: "$%.2f", stats.totalValue))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGray6))
    }
    
    private func statisticItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Export Options
    private var exportOptions: [(format: ExportFormat, icon: String, description: String)] {
        [
            (.csv, "tablecells", "Export as CSV for spreadsheet applications. Includes all item details in a tabular format."),
            (.pdfList, "doc.text", "Detailed list format with images. Perfect for purchase orders and inventory reports."),
            (.pdfGrid3, "square.grid.3x3", "Visual catalog with 3 items per row. Large images for easy identification."),
            (.pdfGrid5, "square.grid.3x3.fill", "Compact grid with 5 items per row. Balance between detail and overview."),
            (.pdfGrid7, "square.grid.4x3.fill", "Overview grid with 7 items per row. Maximum items per page.")
        ]
    }
    
    private func exportOptionCard(option: (format: ExportFormat, icon: String, description: String)) -> some View {
        Button(action: {
            Task {
                await performExport(format: option.format)
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: option.icon)
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.format.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(option.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .disabled(exportService.isExporting)
    }
    
    // MARK: - Export Progress
    private var exportProgressView: some View {
        VStack(spacing: 8) {
            ProgressView(value: exportService.exportProgress)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text(exportService.exportStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Export Function (SECURE: Data-based sharing bypasses iOS file restrictions)
    private func performExport(format: ExportFormat) async {
        selectedFormat = format
        
        // Create shareable data objects (bypasses iOS file security issues)
        await MainActor.run {
            exportService.exportProgress = 0.3
            exportService.exportStatus = "Preparing secure export..."
        }
        
        let shareableFile: ShareableFileData?
        
        switch format {
        case .csv:
            shareableFile = CSVGenerator.createShareableCSV(from: items)
            
        case .pdfGrid3:
            shareableFile = PDFGenerator.createShareablePDF(from: items, layout: .grid3)
            
        case .pdfGrid5:
            shareableFile = PDFGenerator.createShareablePDF(from: items, layout: .grid5)
            
        case .pdfGrid7:
            shareableFile = PDFGenerator.createShareablePDF(from: items, layout: .grid7)
            
        case .pdfList:
            shareableFile = PDFGenerator.createShareablePDF(from: items, layout: .list)
        }
        
        await MainActor.run {
            if let shareableFile = shareableFile {
                shareableFiles = [shareableFile]
                exportService.exportProgress = 1.0
                exportService.exportStatus = "Export complete!"
                ToastNotificationService.shared.showSuccess("Export generated successfully")
                
                // Present ShareSheet immediately - no file verification needed
                showShareSheet = true
            } else {
                ToastNotificationService.shared.showError("Failed to generate export")
            }
        }
        
        await onExport(format)
    }
    
    // MARK: - File Verification
    private func verifyFileForSharing(_ fileURL: URL) -> Bool {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ [ExportOptionsModal] File does not exist: \(fileURL.path)")
            return false
        }
        
        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            print("❌ [ExportOptionsModal] File is not readable: \(fileURL.path)")
            return false
        }
        
        // Check file size (should not be empty)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            guard fileSize > 0 else {
                print("❌ [ExportOptionsModal] File is empty: \(fileURL.path)")
                return false
            }
            
            print("✅ [ExportOptionsModal] File verified for sharing: \(fileURL.lastPathComponent) (\(fileSize) bytes)")
            return true
            
        } catch {
            print("❌ [ExportOptionsModal] Failed to get file attributes: \(error)")
            return false
        }
    }
}

// MARK: - Preview
struct ExportOptionsModal_Previews: PreviewProvider {
    static var previews: some View {
        ExportOptionsModal(
            isPresented: .constant(true),
            items: [
                ReorderItem(
                    id: "1",
                    itemId: "ITEM1",
                    name: "Sample Item",
                    quantity: 5,
                    status: .added
                )
            ],
            onExport: { _ in }
        )
    }
}