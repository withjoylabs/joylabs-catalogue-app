import SwiftUI

// BACKUP SOLUTION: ExportOptionsModal without NavigationView wrapper
struct ExportOptionsModalBackup: View {
    @Binding var isPresented: Bool
    let items: [ReorderItem]
    let onExport: (ExportFormat) async -> Void
    
    @StateObject private var exportService = ReorderExportService.shared
    @State private var selectedFormat: ExportFormat?
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header with Cancel Button
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.body)
                
                Spacer()
                
                Text("Export Options")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Invisible button for balance
                Button("Cancel") {
                    isPresented = false
                }
                .font(.body)
                .opacity(0)
                .disabled(true)
            }
            .padding()
            .background(Color(.systemBackground))
            
            Divider()
            
            // Statistics Header
            statisticsHeader
            
            Divider()
            
            // Export Options - Should work without NavigationView constraints
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(exportOptions, id: \.format) { option in
                        exportOptionCard(option: option)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Export Progress (if exporting)
            if exportService.isExporting {
                Divider()
                exportProgressView
            }
        }
        .shareSheet(
            isPresented: $showShareSheet,
            items: exportedFileURL.map { [$0] } ?? [],
            onComplete: { success in
                if success {
                    isPresented = false
                }
            }
        )
    }
    
    // Same helper methods as original...
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
    
    private func performExport(format: ExportFormat) async {
        selectedFormat = format
        
        let fileURL = await exportService.exportReorderList(items: items, format: format)
        
        if let fileURL = fileURL {
            await MainActor.run {
                exportedFileURL = fileURL
                showShareSheet = true
            }
        }
        
        await onExport(format)
    }
}