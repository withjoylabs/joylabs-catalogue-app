import Foundation
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

class ShareableFileData: NSObject, UIActivityItemSource {
    private let data: Data
    private let filename: String
    private let mimeType: String
    private let utType: UTType
    private let temporaryFileURL: URL?
    
    init(data: Data, filename: String, fileExtension: String) {
        self.data = data
        self.filename = filename
        
        switch fileExtension.lowercased() {
        case "csv":
            self.mimeType = "text/csv"
            self.utType = UTType.commaSeparatedText
        case "pdf":
            self.mimeType = "application/pdf" 
            self.utType = UTType.pdf
        default:
            self.mimeType = "application/octet-stream"
            self.utType = UTType.data
        }
        
        // Create temporary file with proper filename for sharing
        self.temporaryFileURL = Self.createTemporaryFile(data: data, filename: filename)
        
        super.init()
    }
    
    // MARK: - Temporary File Management
    private static func createTemporaryFile(data: Data, filename: String) -> URL? {
        // Create a temporary directory for sharing files
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ShareableFiles", isDirectory: true)
        
        do {
            // Ensure temp directory exists
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            
            // Create file with proper filename
            let fileURL = tempDirectory.appendingPathComponent(filename)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            // Write data to file
            try data.write(to: fileURL)
            
            print("✅ [ShareableFileData] Created temporary file: \(filename)")
            return fileURL
            
        } catch {
            print("❌ [ShareableFileData] Failed to create temporary file: \(error)")
            return nil
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        guard let fileURL = temporaryFileURL else { return }
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("✅ [ShareableFileData] Cleaned up temporary file: \(filename)")
            }
        } catch {
            print("❌ [ShareableFileData] Failed to cleanup temporary file: \(error)")
        }
    }
    
    // Clean up all temporary share files (call on app launch)
    static func cleanupAllTemporaryFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ShareableFiles", isDirectory: true)
        
        do {
            if FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.removeItem(at: tempDirectory)
                print("✅ [ShareableFileData] Cleaned up all temporary share files")
            }
        } catch {
            print("❌ [ShareableFileData] Failed to cleanup temporary directory: \(error)")
        }
    }
    
    deinit {
        // Auto-cleanup when object is deallocated
        cleanup()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // Return file URL if available, fallback to data
        return temporaryFileURL ?? data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // Return file URL if available, fallback to data for compatibility
        return temporaryFileURL ?? data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Return appropriate UTType identifier based on whether we're sharing a file URL or data
        if temporaryFileURL != nil {
            // For file URLs, use the file's UTType
            return utType.identifier
        } else {
            // For raw data, use the data UTType
            return utType.identifier
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        switch utType {
        case UTType.pdf:
            return UIImage(systemName: "doc.fill")
        case UTType.commaSeparatedText:
            return UIImage(systemName: "tablecells.fill")
        default:
            return UIImage(systemName: "doc")
        }
    }
    
    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = filename
        
        // Use actual file URL if available, otherwise create a file:// URL with filename
        if let fileURL = temporaryFileURL {
            metadata.originalURL = fileURL
        } else {
            metadata.originalURL = URL(string: "file://\(filename)")
        }
        
        if let thumbnail = self.activityViewController(activityViewController, thumbnailImageForActivityType: nil, suggestedSize: CGSize(width: 60, height: 60)) {
            metadata.iconProvider = NSItemProvider(object: thumbnail)
        }
        
        return metadata
    }
}

extension ShareableFileData {
    static func createCSV(data: Data, filename: String) -> ShareableFileData {
        return ShareableFileData(data: data, filename: filename, fileExtension: "csv")
    }
    
    static func createPDF(data: Data, filename: String) -> ShareableFileData {
        return ShareableFileData(data: data, filename: filename, fileExtension: "pdf")
    }
}