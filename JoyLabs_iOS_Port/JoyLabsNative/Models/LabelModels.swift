import Foundation
import SwiftUI

// MARK: - Label Template Model
struct LabelTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let size: String
    let category: String
    var isCustom: Bool = false
    var createdDate: Date = Date()
    
    init(id: String, name: String, size: String, category: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.size = size
        self.category = category
        self.isCustom = isCustom
        self.createdDate = Date()
    }
}

// MARK: - Recent Label Model
struct RecentLabel: Identifiable, Codable {
    let id: String
    let name: String
    let template: String
    let createdDate: Date
    var printCount: Int = 1
    var lastPrintDate: Date?
    
    init(id: String, name: String, template: String, createdDate: Date, printCount: Int = 1) {
        self.id = id
        self.name = name
        self.template = template
        self.createdDate = createdDate
        self.printCount = printCount
        self.lastPrintDate = nil
    }
}

#Preview("Label Template") {
    let template = LabelTemplate(id: "1", name: "Product Label", size: "2x1 inch", category: "Product")
    Text("Template: \(template.name)")
}

#Preview("Recent Label") {
    let label = RecentLabel(id: "1", name: "Coffee Label", template: "Product Label", createdDate: Date())
    Text("Label: \(label.name)")
}
