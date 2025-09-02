import Foundation
import SwiftData

// MARK: - SwiftData Model for Discounts
// Replaces SQLite.swift discounts table with native SwiftData persistence
@Model
final class DiscountModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Discount fields
    var name: String?
    
    // Store complete discount data as JSON for complex operations
    var dataJson: String?
    
    // Computed properties
    var hasName: Bool {
        return name != nil && !name!.isEmpty
    }
    
    init(
        id: String,
        updatedAt: Date = Date(),
        version: String = "0",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.version = version
        self.isDeleted = isDeleted
    }
    
    // Update from Square API CatalogObject
    func updateFromCatalogObject(_ object: CatalogObject) {
        self.updatedAt = Date()
        self.version = String(object.version ?? 0)
        self.isDeleted = object.isDeleted ?? false
        
        if let discountData = object.discountData {
            self.name = discountData.name
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(discountData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to DiscountData when needed
    func toDiscountData() -> DiscountData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(DiscountData.self, from: jsonData)
    }
}