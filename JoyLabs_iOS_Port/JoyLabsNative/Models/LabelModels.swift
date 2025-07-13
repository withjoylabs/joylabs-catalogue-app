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

// MARK: - Reorder Item Model
struct ReorderItem: Identifiable, Codable {
    let id: String
    let name: String
    let sku: String
    var quantity: Int
    let lastOrderDate: Date
    var notes: String?
    var priority: ReorderPriority = .normal
    
    init(id: String, name: String, sku: String, quantity: Int, lastOrderDate: Date, notes: String? = nil) {
        self.id = id
        self.name = name
        self.sku = sku
        self.quantity = quantity
        self.lastOrderDate = lastOrderDate
        self.notes = notes
    }
}

// MARK: - Reorder Priority
enum ReorderPriority: String, CaseIterable, Codable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"
    
    var color: String {
        switch self {
        case .low: return "gray"
        case .normal: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
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

#Preview("Reorder Item") {
    let item = ReorderItem(id: "1", name: "Coffee Beans", sku: "COF001", quantity: 5, lastOrderDate: Date())
    Text("Item: \(item.name) - Qty: \(item.quantity)")
}
