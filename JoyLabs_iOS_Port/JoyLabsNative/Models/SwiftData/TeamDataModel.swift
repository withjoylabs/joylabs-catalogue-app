import Foundation
import SwiftData

// MARK: - SwiftData Model for Team Data
// Replaces SQLite.swift team_data table with native SwiftData persistence
// This syncs with AWS AppSync for team-specific data
@Model
final class TeamDataModel {
    // Core identifiers
    @Attribute(.unique) var itemId: String  // Primary key, links to CatalogItemModel
    var createdAt: Date
    var updatedAt: Date
    var lastSyncAt: Date?
    
    // Team-specific fields
    var caseUpc: String?
    var caseCost: Double?
    var caseQuantity: Int?
    var vendor: String?
    var discontinued: Bool
    var notes: String?  // Simple string for notes
    var owner: String?  // User who created/owns this data
    
    // Sync management
    var pendingSync: Bool  // Whether this needs to sync to AppSync
    var syncError: String?  // Last sync error if any
    
    // Relationship to the catalog item
    @Relationship(inverse: \CatalogItemModel.teamData) var catalogItem: CatalogItemModel?
    
    // Computed properties
    var unitCost: Double? {
        guard let caseCost = caseCost,
              let caseQuantity = caseQuantity,
              caseQuantity > 0 else { return nil }
        return caseCost / Double(caseQuantity)
    }
    
    var formattedCaseCost: String? {
        guard let cost = caseCost else { return nil }
        return String(format: "$%.2f", cost)
    }
    
    var formattedUnitCost: String? {
        guard let cost = unitCost else { return nil }
        return String(format: "$%.2f", cost)
    }
    
    var hasUnsyncedChanges: Bool {
        return pendingSync
    }
    
    init(
        itemId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        discontinued: Bool = false,
        pendingSync: Bool = false
    ) {
        self.itemId = itemId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.discontinued = discontinued
        self.pendingSync = pendingSync
    }
    
    // Update team data fields
    func updateTeamData(
        caseUpc: String? = nil,
        caseCost: Double? = nil,
        caseQuantity: Int? = nil,
        vendor: String? = nil,
        discontinued: Bool? = nil,
        notes: String? = nil
    ) {
        if let caseUpc = caseUpc { self.caseUpc = caseUpc }
        if let caseCost = caseCost { self.caseCost = caseCost }
        if let caseQuantity = caseQuantity { self.caseQuantity = caseQuantity }
        if let vendor = vendor { self.vendor = vendor }
        if let discontinued = discontinued { self.discontinued = discontinued }
        if let notes = notes { self.notes = notes }
        
        self.updatedAt = Date()
        self.pendingSync = true
    }
    
    // Mark as synced with AppSync
    func markAsSynced() {
        self.lastSyncAt = Date()
        self.pendingSync = false
        self.syncError = nil
    }
    
    // Mark sync failure
    func markSyncFailed(error: String) {
        self.syncError = error
        // Keep pendingSync = true to retry later
    }
    
    // Convert to dictionary for AppSync
    func toAppSyncDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "itemId": itemId,
            "discontinued": discontinued,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]
        
        if let caseUpc = caseUpc { dict["caseUpc"] = caseUpc }
        if let caseCost = caseCost { dict["caseCost"] = caseCost }
        if let caseQuantity = caseQuantity { dict["caseQuantity"] = caseQuantity }
        if let vendor = vendor { dict["vendor"] = vendor }
        if let notes = notes { dict["notes"] = notes }
        if let owner = owner { dict["owner"] = owner }
        if let lastSyncAt = lastSyncAt {
            dict["lastSyncAt"] = ISO8601DateFormatter().string(from: lastSyncAt)
        }
        
        return dict
    }
}