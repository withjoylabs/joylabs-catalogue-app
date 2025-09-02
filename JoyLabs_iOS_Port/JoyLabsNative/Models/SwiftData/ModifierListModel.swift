import Foundation
import SwiftData

// MARK: - SwiftData Model for Modifier Lists
// Replaces SQLite.swift modifier_lists table with native SwiftData persistence
@Model
final class ModifierListModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Modifier list fields
    var name: String?
    var selectionType: String?  // SINGLE, MULTIPLE
    var ordinal: Int?
    var modifierIds: [String]?  // IDs of modifiers in this list
    var imageIds: [String]?  // Image IDs from Square API
    
    // Store complete modifier list data as JSON for complex operations
    var dataJson: String?
    
    // Relationships
    @Relationship var modifiers: [ModifierModel]?
    @Relationship(inverse: \CatalogItemModel.modifierLists) var items: [CatalogItemModel]?
    
    // Computed properties
    var modifierCount: Int {
        return modifiers?.count ?? 0
    }
    
    var hasImages: Bool {
        return !(imageIds?.isEmpty ?? true)
    }
    
    var allowsMultiple: Bool {
        return selectionType == "MULTIPLE"
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
        
        if let modifierListData = object.modifierListData {
            self.name = modifierListData.name
            self.selectionType = modifierListData.selectionType
            self.ordinal = modifierListData.ordinal
            self.modifierIds = modifierListData.modifiers?.map { $0.id }
            self.imageIds = modifierListData.imageIds
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(modifierListData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to ModifierListData when needed
    func toModifierListData() -> ModifierListData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(ModifierListData.self, from: jsonData)
    }
}