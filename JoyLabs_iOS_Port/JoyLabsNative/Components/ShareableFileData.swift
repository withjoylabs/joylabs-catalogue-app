import Foundation
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

class ShareableFileData: NSObject, UIActivityItemSource {
    private let data: Data
    private let filename: String
    private let mimeType: String
    private let utType: UTType
    
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
        
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return utType.identifier
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
        metadata.originalURL = URL(string: "file://\(filename)")
        
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