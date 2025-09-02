import Foundation
import SwiftData

// MARK: - SwiftData Model for Categories
// Replaces SQLite.swift categories table with native SwiftData persistence
@Model
final class CategoryModel {
    // Core identifiers
    @Attribute(.unique) var id: String
    var updatedAt: Date
    var version: String
    var isDeleted: Bool
    
    // Category fields
    var name: String?
    var imageUrl: String?
    var pathToRoot: [String]?  // Store as array
    var rootCategory: String?  // Root category string from Square API
    var isTopLevel: Bool?
    
    // Store complete category data as JSON for complex operations
    var dataJson: String?
    
    // Relationships
    @Relationship(inverse: \CatalogItemModel.category) var items: [CatalogItemModel]?
    @Relationship(inverse: \CatalogItemModel.reportingCategory) var reportingItems: [CatalogItemModel]?
    
    // Computed properties
    var itemCount: Int {
        return items?.count ?? 0
    }
    
    var hasImage: Bool {
        return imageUrl != nil && !imageUrl!.isEmpty
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
        
        if let categoryData = object.categoryData {
            self.name = categoryData.name
            self.imageUrl = categoryData.imageUrl
            
            // Convert PathToRootCategory array to string array
            if let pathToRootCategories = categoryData.pathToRoot {
                self.pathToRoot = pathToRootCategories.compactMap { $0.categoryId }
            }
            
            self.rootCategory = categoryData.rootCategory
            self.isTopLevel = categoryData.isTopLevel
            
            // Store full JSON for complex operations
            if let jsonData = try? JSONEncoder().encode(categoryData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.dataJson = jsonString
            }
        }
    }
    
    // Convert to CategoryData when needed
    func toCategoryData() -> CategoryData? {
        guard let jsonString = dataJson,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(CategoryData.self, from: jsonData)
    }
}