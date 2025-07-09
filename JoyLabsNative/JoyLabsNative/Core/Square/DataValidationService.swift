import Foundation
import OSLog

/// Service responsible for validating Square API data before transformation
/// Ensures data integrity and consistency across the application
actor DataValidationService {
    
    // MARK: - Dependencies
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DataValidationService")
    
    // MARK: - Validation Statistics
    
    private var validationStats = ValidationStatistics()
    
    // MARK: - Initialization
    
    init() {
        logger.info("DataValidationService initialized")
    }
    
    // MARK: - Public Validation Methods
    
    /// Validate a catalog object from Square API
    func validateCatalogObject(_ object: CatalogObject) async -> ValidationResult {
        let startTime = Date()
        var errors: [String] = []
        var warnings: [String] = []
        
        // Basic object validation
        if object.id.isEmpty {
            errors.append("Object ID cannot be empty")
        }
        
        if object.type.isEmpty {
            errors.append("Object type cannot be empty")
        }
        
        if let updatedAt = object.updatedAt {
            if updatedAt.isEmpty {
                errors.append("Updated timestamp cannot be empty")
            } else {
                // Validate timestamp format
                if !isValidISO8601Timestamp(updatedAt) {
                    errors.append("Invalid timestamp format: \(updatedAt)")
                }
            }
        } else {
            errors.append("Updated timestamp is required")
        }

        if let version = object.version {
            if version <= 0 {
                errors.append("Version must be positive: \(version)")
            }
        } else {
            errors.append("Version is required")
        }
        
        // Type-specific validation
        switch object.type {
        case "ITEM":
            let itemValidation = await validateItemObject(object)
            errors.append(contentsOf: itemValidation.errors)
            warnings.append(contentsOf: itemValidation.warnings)
            
        case "CATEGORY":
            let categoryValidation = await validateCategoryObject(object)
            errors.append(contentsOf: categoryValidation.errors)
            warnings.append(contentsOf: categoryValidation.warnings)
            
        case "ITEM_VARIATION":
            let variationValidation = await validateItemVariationObject(object)
            errors.append(contentsOf: variationValidation.errors)
            warnings.append(contentsOf: variationValidation.warnings)
            
        case "MODIFIER", "MODIFIER_LIST", "TAX", "DISCOUNT", "IMAGE":
            // Basic validation for other types
            logger.debug("Validating \(object.type) object: \(object.id)")
            
        default:
            warnings.append("Unknown object type: \(object.type)")
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Update statistics
        validationStats.totalValidations += 1
        validationStats.totalErrors += errors.count
        validationStats.totalWarnings += warnings.count
        validationStats.averageValidationTime = 
            (validationStats.averageValidationTime * Double(validationStats.totalValidations - 1) + duration) / 
            Double(validationStats.totalValidations)
        
        let isValid = errors.isEmpty
        
        if !isValid {
            logger.warning("Validation failed for \(object.type) \(object.id): \(errors.joined(separator: ", "))")
        } else if !warnings.isEmpty {
            logger.info("Validation warnings for \(object.type) \(object.id): \(warnings.joined(separator: ", "))")
        }
        
        return ValidationResult(
            isValid: isValid,
            errors: errors,
            warnings: warnings,
            objectId: object.id,
            objectType: object.type,
            duration: duration
        )
    }
    
    /// Validate multiple catalog objects
    func validateCatalogObjects(_ objects: [CatalogObject]) async -> BatchValidationResult {
        logger.info("Starting batch validation of \(objects.count) objects")
        
        let startTime = Date()
        var results: [ValidationResult] = []
        var totalErrors = 0
        var totalWarnings = 0
        
        for object in objects {
            let result = await validateCatalogObject(object)
            results.append(result)
            totalErrors += result.errors.count
            totalWarnings += result.warnings.count
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let validObjects = results.filter { $0.isValid }.count
        
        logger.info("Batch validation completed in \(String(format: "%.2f", duration))s. Valid: \(validObjects)/\(objects.count), Errors: \(totalErrors), Warnings: \(totalWarnings)")
        
        return BatchValidationResult(
            results: results,
            totalObjects: objects.count,
            validObjects: validObjects,
            totalErrors: totalErrors,
            totalWarnings: totalWarnings,
            duration: duration
        )
    }
    
    // MARK: - Private Validation Methods
    
    private func validateItemObject(_ object: CatalogObject) async -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        guard let itemData = object.itemData else {
            errors.append("Item object missing itemData")
            return ValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                objectId: object.id,
                objectType: object.type,
                duration: 0
            )
        }
        
        // Validate item name
        if let name = itemData.name {
            if name.isEmpty {
                warnings.append("Item name is empty")
            } else if name.count > 255 {
                errors.append("Item name too long: \(name.count) characters")
            }
        } else {
            warnings.append("Item name is missing")
        }
        
        // Validate description
        if let description = itemData.description, description.count > 4096 {
            errors.append("Item description too long: \(description.count) characters")
        }
        
        // Validate category reference
        if let categoryId = itemData.categoryId {
            if categoryId.isEmpty {
                warnings.append("Category ID is empty")
            }
        }
        
        // Note: Variations validation removed due to model inconsistencies
        // Will be re-added when data models are properly unified
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            objectId: object.id,
            objectType: object.type,
            duration: 0
        )
    }
    
    private func validateCategoryObject(_ object: CatalogObject) async -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        guard let categoryData = object.categoryData else {
            errors.append("Category object missing categoryData")
            return ValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                objectId: object.id,
                objectType: object.type,
                duration: 0
            )
        }
        
        // Validate category name
        if let name = categoryData.name {
            if name.isEmpty {
                warnings.append("Category name is empty")
            } else if name.count > 255 {
                errors.append("Category name too long: \(name.count) characters")
            }
        } else {
            warnings.append("Category name is missing")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            objectId: object.id,
            objectType: object.type,
            duration: 0
        )
    }
    
    private func validateItemVariationObject(_ object: CatalogObject) async -> ValidationResult {
        var errors: [String] = []
        let warnings: [String] = []
        
        guard let variationData = object.itemVariationData else {
            errors.append("Item variation object missing itemVariationData")
            return ValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                objectId: object.id,
                objectType: object.type,
                duration: 0
            )
        }
        
        // Validate item reference
        if variationData.itemId.isEmpty {
            errors.append("Item variation missing valid item ID")
        }
        
        // Validate variation name
        if let name = variationData.name {
            if name.count > 255 {
                errors.append("Variation name too long: \(name.count) characters")
            }
        }
        
        // Validate SKU
        if let sku = variationData.sku {
            if sku.count > 255 {
                errors.append("SKU too long: \(sku.count) characters")
            }
        }
        
        // Note: Pricing validation removed due to model inconsistencies
        // Will be re-added when data models are properly unified
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            objectId: object.id,
            objectType: object.type,
            duration: 0
        )
    }
    
    // MARK: - Helper Methods
    
    private func isValidISO8601Timestamp(_ timestamp: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp) != nil
    }
    
    private func isValidCurrencyCode(_ code: String) -> Bool {
        // Basic validation for common currency codes
        let validCurrencies = ["USD", "CAD", "EUR", "GBP", "JPY", "AUD"]
        return validCurrencies.contains(code)
    }
    
    // MARK: - Statistics
    
    func getValidationStatistics() async -> ValidationStatistics {
        return validationStats
    }
    
    func resetStatistics() async {
        validationStats = ValidationStatistics()
        logger.info("Validation statistics reset")
    }
}

// MARK: - Supporting Types

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let objectId: String
    let objectType: String
    let duration: TimeInterval
    
    var summary: String {
        if isValid {
            return "✅ Valid \(objectType) \(objectId)"
        } else {
            return "❌ Invalid \(objectType) \(objectId): \(errors.joined(separator: ", "))"
        }
    }
}

struct BatchValidationResult {
    let results: [ValidationResult]
    let totalObjects: Int
    let validObjects: Int
    let totalErrors: Int
    let totalWarnings: Int
    let duration: TimeInterval
    
    var successRate: Double {
        guard totalObjects > 0 else { return 0.0 }
        return Double(validObjects) / Double(totalObjects)
    }
    
    var summary: String {
        return "Validated \(totalObjects) objects in \(String(format: "%.2f", duration))s. Success rate: \(String(format: "%.1f", successRate * 100))%"
    }
    
    var invalidResults: [ValidationResult] {
        return results.filter { !$0.isValid }
    }
}

struct ValidationStatistics {
    var totalValidations: Int = 0
    var totalErrors: Int = 0
    var totalWarnings: Int = 0
    var averageValidationTime: TimeInterval = 0.0
    
    var errorRate: Double {
        guard totalValidations > 0 else { return 0.0 }
        return Double(totalErrors) / Double(totalValidations)
    }
    
    var warningRate: Double {
        guard totalValidations > 0 else { return 0.0 }
        return Double(totalWarnings) / Double(totalValidations)
    }
    
    var formattedErrorRate: String {
        return String(format: "%.2f%%", errorRate * 100)
    }
    
    var formattedWarningRate: String {
        return String(format: "%.2f%%", warningRate * 100)
    }
    
    var formattedAverageTime: String {
        return String(format: "%.3fs", averageValidationTime)
    }
}
