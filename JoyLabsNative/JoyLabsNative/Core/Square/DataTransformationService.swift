import Foundation
import OSLog

/// Service responsible for transforming Square API responses to local database format
/// Handles object relationships, data validation, and format conversion
actor DataTransformationService {
    
    // MARK: - Dependencies
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DataTransformationService")
    private let dataValidator: DataValidationService
    
    // MARK: - Transformation Statistics
    
    private var transformationStats = TransformationStatistics()
    
    // MARK: - Initialization
    
    init(dataValidator: DataValidationService) {
        self.dataValidator = dataValidator
        logger.info("DataTransformationService initialized")
    }
    
    // MARK: - Public Transformation Methods
    
    /// Transform Square catalog objects to database format
    func transformCatalogObjects(_ objects: [CatalogObject]) async throws -> TransformationResult {
        logger.info("Starting transformation of \(objects.count) catalog objects")
        
        let startTime = Date()
        var transformedItems: [CatalogItemRow] = []
        var transformedCategories: [CategoryRow] = []
        var transformedVariations: [ItemVariationRow] = []
        var errors: [TransformationError] = []
        
        // Group objects by type for efficient processing
        let groupedObjects = Dictionary(grouping: objects) { $0.type }
        
        // Transform categories first (needed for item relationships)
        if let categories = groupedObjects["CATEGORY"] {
            logger.debug("Transforming \(categories.count) categories")
            
            for categoryObject in categories {
                do {
                    let categoryRow = try await transformCategoryObject(categoryObject)
                    transformedCategories.append(categoryRow)
                } catch {
                    errors.append(TransformationError(
                        objectId: categoryObject.id,
                        objectType: "CATEGORY",
                        error: error,
                        context: "Category transformation failed"
                    ))
                }
            }
        }
        
        // Transform items
        if let items = groupedObjects["ITEM"] {
            logger.debug("Transforming \(items.count) items")
            
            for itemObject in items {
                do {
                    let itemRow = try await transformItemObject(itemObject)
                    transformedItems.append(itemRow)
                } catch {
                    errors.append(TransformationError(
                        objectId: itemObject.id,
                        objectType: "ITEM",
                        error: error,
                        context: "Item transformation failed"
                    ))
                }
            }
        }
        
        // Transform item variations
        if let variations = groupedObjects["ITEM_VARIATION"] {
            logger.debug("Transforming \(variations.count) item variations")
            
            for variationObject in variations {
                do {
                    let variationRow = try await transformItemVariationObject(variationObject)
                    transformedVariations.append(variationRow)
                } catch {
                    errors.append(TransformationError(
                        objectId: variationObject.id,
                        objectType: "ITEM_VARIATION",
                        error: error,
                        context: "Item variation transformation failed"
                    ))
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Update statistics
        transformationStats.totalTransformations += 1
        transformationStats.totalObjectsProcessed += objects.count
        transformationStats.totalErrors += errors.count
        transformationStats.averageTransformationTime = 
            (transformationStats.averageTransformationTime * Double(transformationStats.totalTransformations - 1) + duration) / 
            Double(transformationStats.totalTransformations)
        
        logger.info("Transformation completed in \(String(format: "%.2f", duration))s. Items: \(transformedItems.count), Categories: \(transformedCategories.count), Variations: \(transformedVariations.count), Errors: \(errors.count)")
        
        return TransformationResult(
            items: transformedItems,
            categories: transformedCategories,
            variations: transformedVariations,
            errors: errors,
            duration: duration,
            totalProcessed: objects.count
        )
    }
    
    // MARK: - Private Transformation Methods
    
    private func transformCategoryObject(_ object: CatalogObject) async throws -> CategoryRow {
        // Validate the object
        let validationResult = await dataValidator.validateCatalogObject(object)
        guard validationResult.isValid else {
            throw TransformationServiceError.validationFailed(validationResult.errors.joined(separator: ", "))
        }
        
        guard let categoryData = object.categoryData else {
            throw TransformationServiceError.missingRequiredData("categoryData")
        }
        
        // Convert to JSON for storage
        let jsonData = try JSONEncoder().encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return CategoryRow(
            id: object.id,
            updatedAt: object.updatedAt ?? "",
            version: String(object.version ?? 0),
            isDeleted: (object.isDeleted ?? false) ? 1 : 0,
            name: categoryData.name,
            dataJson: jsonString
        )
    }
    
    private func transformItemObject(_ object: CatalogObject) async throws -> CatalogItemRow {
        // Validate the object
        let validationResult = await dataValidator.validateCatalogObject(object)
        guard validationResult.isValid else {
            throw TransformationServiceError.validationFailed(validationResult.errors.joined(separator: ", "))
        }
        
        guard let itemData = object.itemData else {
            throw TransformationServiceError.missingRequiredData("itemData")
        }
        
        // Convert to JSON for storage
        let jsonData = try JSONEncoder().encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return CatalogItemRow(
            id: object.id,
            updatedAt: object.updatedAt ?? "",
            version: String(object.version ?? 0),
            isDeleted: (object.isDeleted ?? false) ? 1 : 0,
            presentAtAllLocations: (object.presentAtAllLocations ?? false) ? 1 : nil,
            name: itemData.name,
            description: itemData.description,
            categoryId: itemData.categoryId,
            dataJson: jsonString
        )
    }
    
    private func transformItemVariationObject(_ object: CatalogObject) async throws -> ItemVariationRow {
        // Validate the object
        let validationResult = await dataValidator.validateCatalogObject(object)
        guard validationResult.isValid else {
            throw TransformationServiceError.validationFailed(validationResult.errors.joined(separator: ", "))
        }
        
        guard let variationData = object.itemVariationData else {
            throw TransformationServiceError.missingRequiredData("itemVariationData")
        }
        
        // Convert to JSON for storage
        let jsonData = try JSONEncoder().encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Extract price information
        // Note: priceMoney property access removed due to model inconsistencies
        // Will be re-added when data models are properly unified
        let priceAmount: Int64? = nil
        let priceCurrency: String? = nil
        
        return ItemVariationRow(
            id: object.id,
            updatedAt: object.updatedAt ?? "",
            version: String(object.version ?? 0),
            isDeleted: (object.isDeleted ?? false) ? 1 : 0,
            itemId: variationData.itemId ?? "",
            name: variationData.name,
            sku: variationData.sku,
            upc: variationData.upc,
            ordinal: variationData.ordinal.map { Int($0) },
            pricingType: variationData.pricingType,
            priceAmount: priceAmount,
            priceCurrency: priceCurrency,
            dataJson: jsonString
        )
    }
    
    // MARK: - Statistics
    
    func getTransformationStatistics() async -> TransformationStatistics {
        return transformationStats
    }
    
    func resetStatistics() async {
        transformationStats = TransformationStatistics()
        logger.info("Transformation statistics reset")
    }
}

// MARK: - Supporting Types

struct TransformationResult {
    let items: [CatalogItemRow]
    let categories: [CategoryRow]
    let variations: [ItemVariationRow]
    let errors: [TransformationError]
    let duration: TimeInterval
    let totalProcessed: Int
    
    var successRate: Double {
        guard totalProcessed > 0 else { return 0.0 }
        let successful = totalProcessed - errors.count
        return Double(successful) / Double(totalProcessed)
    }
    
    var summary: String {
        return "Processed \(totalProcessed) objects in \(String(format: "%.2f", duration))s. Success rate: \(String(format: "%.1f", successRate * 100))%"
    }
}

struct TransformationError {
    let objectId: String
    let objectType: String
    let error: Error
    let context: String
    let timestamp: Date = Date()
    
    var description: String {
        return "[\(objectType)] \(objectId): \(context) - \(error.localizedDescription)"
    }
}

struct TransformationStatistics {
    var totalTransformations: Int = 0
    var totalObjectsProcessed: Int = 0
    var totalErrors: Int = 0
    var averageTransformationTime: TimeInterval = 0.0
    
    var errorRate: Double {
        guard totalObjectsProcessed > 0 else { return 0.0 }
        return Double(totalErrors) / Double(totalObjectsProcessed)
    }
    
    var formattedErrorRate: String {
        return String(format: "%.2f%%", errorRate * 100)
    }
    
    var formattedAverageTime: String {
        return String(format: "%.2fs", averageTransformationTime)
    }
}

enum TransformationServiceError: LocalizedError {
    case validationFailed(String)
    case missingRequiredData(String)
    case encodingFailed(String)
    case invalidObjectType(String)
    case relationshipError(String)
    
    var errorDescription: String? {
        switch self {
        case .validationFailed(let details):
            return "Validation failed: \(details)"
        case .missingRequiredData(let field):
            return "Missing required data: \(field)"
        case .encodingFailed(let details):
            return "JSON encoding failed: \(details)"
        case .invalidObjectType(let type):
            return "Invalid object type: \(type)"
        case .relationshipError(let details):
            return "Relationship error: \(details)"
        }
    }
}
