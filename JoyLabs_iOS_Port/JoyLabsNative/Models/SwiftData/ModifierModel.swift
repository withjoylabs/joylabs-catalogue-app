import Foundation
import SwiftData

// MARK: - SwiftData Model for Modifiers
// Replaces SQLite.swift modifiers table with native SwiftData persistence
@Model
final class ModifierModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Modifier fields
    var name: String?
    var priceAmount: Int64?  // Amount in cents
    var priceCurrency: String?  // USD, etc.
    var onByDefault: Bool?
    var ordinal: Int?
    
    // Store complete modifier data as JSON for complex operations
    var dataJson: String?
    
    // Relationships
    @Relationship(inverse: \ModifierListModel.modifiers) var modifierList: ModifierListModel?
    
    // Computed properties
    var priceAmountAsDouble: Double? {
        guard let priceAmount = priceAmount else { return nil }
        return Double(priceAmount) / 100.0  // Convert cents to dollars
    }
    
    // MARK: - Initialization
    
    init(id: String = UUID().uuidString,
         updatedAt: Date = Date(),
         version: String = "1",
         isDeleted: Bool = false) {
        self.id = id
        self.updatedAt = updatedAt
        self.version = version
        self.isDeleted = isDeleted
    }
    
    // MARK: - Update Methods
    
    /// Update modifier data from Square API CatalogObject
    func updateFromSquareData(_ modifier: CatalogObject) {
        guard modifier.type == "MODIFIER", let modifierData = modifier.modifierData else {
            return
        }
        
        // Update basic fields
        self.name = modifierData.name
        self.onByDefault = modifierData.onByDefault
        self.ordinal = modifierData.ordinal
        
        // Update price if present
        if let priceMoney = modifierData.priceMoney {
            self.priceAmount = Int64(priceMoney.amount ?? 0)
            self.priceCurrency = priceMoney.currency ?? "USD"
        }
        
        // Update metadata - convert String to Date if needed
        if let updatedAtString = modifier.updatedAt {
            self.updatedAt = ISO8601DateFormatter().date(from: updatedAtString) ?? Date()
        } else {
            self.updatedAt = Date()
        }
        self.version = modifier.version?.description ?? "1"
        self.isDeleted = modifier.safeIsDeleted
        
        // Store complete JSON for complex operations
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(modifier)
            self.dataJson = String(data: data, encoding: .utf8)
        } catch {
            print("Failed to encode modifier JSON: \(error)")
            self.dataJson = nil
        }
    }
    
    /// Update from Square API CatalogObject - alias for backward compatibility
    func updateFromCatalogObject(_ catalogObject: CatalogObject) {
        updateFromSquareData(catalogObject)
    }
    
    /// Get display name for UI
    var displayName: String {
        return name ?? "Unnamed Modifier"
    }
    
    /// Get formatted price for display
    var formattedPrice: String? {
        guard let amount = priceAmountAsDouble else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = priceCurrency ?? "USD"
        return formatter.string(from: NSNumber(value: amount))
    }
}