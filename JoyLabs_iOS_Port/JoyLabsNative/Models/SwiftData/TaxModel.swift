import Foundation
import SwiftData

// MARK: - SwiftData Model for Taxes
// Replaces SQLite.swift taxes table with native SwiftData persistence
@Model
final class TaxModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Tax fields
    var name: String?
    var calculationPhase: String?  // TAX_SUBTOTAL_PHASE or TAX_TOTAL_PHASE
    var inclusionType: String?  // ADDITIVE or INCLUSIVE
    var percentage: String?  // Stored as string like "8.5"
    var appliesToCustomAmounts: Bool?
    var enabled: Bool?
    
    // Store complete tax data as JSON for complex operations
    var dataJson: String?
    
    // Relationships
    @Relationship(inverse: \CatalogItemModel.taxes) var items: [CatalogItemModel]?
    
    // Computed properties
    var percentageAsDouble: Double? {
        guard let percentage = percentage else { return nil }
        return Double(percentage)
    }
    
    var formattedPercentage: String {
        guard let percentage = percentage else { return "0%" }
        return "\(percentage)%"
    }
    
    var isActive: Bool {
        return (enabled ?? false) && !isDeleted
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
        
        if let taxData = object.taxData {
            self.name = taxData.name
            self.calculationPhase = taxData.calculationPhase
            self.inclusionType = taxData.inclusionType
            self.percentage = taxData.percentage
            self.appliesToCustomAmounts = taxData.appliesToCustomAmounts
            self.enabled = taxData.enabled
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(taxData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to TaxData when needed
    func toTaxData() -> TaxData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(TaxData.self, from: jsonData)
    }
}