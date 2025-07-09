import Foundation
import OSLog

/// Data Validation & Security Layer - Comprehensive validation for Square API data and user inputs
/// Uses 2025 industry standards: Result types, structured error handling, input sanitization
struct DataValidator {
    
    private static let logger = Logger(subsystem: "com.joylabs.native", category: "DataValidation")
    
    // MARK: - Square API Data Validation
    
    /// Validates Square catalog object data before database storage
    static func validateSquareCatalogObject(_ data: [String: Any]) -> Result<ValidatedCatalogObject, ValidationError> {
        logger.debug("Validating Square catalog object")
        
        // Required fields validation
        guard let id = data["id"] as? String, !id.isEmpty else {
            return .failure(.missingRequiredField("id"))
        }
        
        guard let type = data["type"] as? String, !type.isEmpty else {
            return .failure(.missingRequiredField("type"))
        }
        
        guard let updatedAt = data["updated_at"] as? String, !updatedAt.isEmpty else {
            return .failure(.missingRequiredField("updated_at"))
        }
        
        guard let version = data["version"] as? Int64 else {
            return .failure(.missingRequiredField("version"))
        }
        
        // Validate ID format (Square IDs are alphanumeric with specific patterns)
        guard validateSquareId(id) else {
            return .failure(.invalidFormat("id", "Square ID must be alphanumeric"))
        }
        
        // Validate timestamp format
        guard validateISO8601Timestamp(updatedAt) else {
            return .failure(.invalidFormat("updated_at", "Must be valid ISO8601 timestamp"))
        }
        
        // Validate version (must be positive)
        guard version > 0 else {
            return .failure(.invalidValue("version", "Version must be positive"))
        }
        
        // Type-specific validation
        switch type {
        case "ITEM":
            return validateItemData(data, id: id, updatedAt: updatedAt, version: version)
        case "ITEM_VARIATION":
            return validateItemVariationData(data, id: id, updatedAt: updatedAt, version: version)
        case "CATEGORY":
            return validateCategoryData(data, id: id, updatedAt: updatedAt, version: version)
        default:
            return .failure(.unsupportedType(type))
        }
    }
    
    /// Validates Square item data
    private static func validateItemData(_ data: [String: Any], id: String, updatedAt: String, version: Int64) -> Result<ValidatedCatalogObject, ValidationError> {
        guard let itemData = data["item_data"] as? [String: Any] else {
            return .failure(.missingRequiredField("item_data"))
        }
        
        // Validate name if present
        if let name = itemData["name"] as? String {
            guard validateProductName(name) else {
                return .failure(.invalidFormat("name", "Product name contains invalid characters"))
            }
        }
        
        // Validate category_id if present
        if let categoryId = itemData["category_id"] as? String {
            guard validateSquareId(categoryId) else {
                return .failure(.invalidFormat("category_id", "Invalid category ID format"))
            }
        }
        
        return .success(ValidatedCatalogObject(
            id: id,
            type: "ITEM",
            updatedAt: updatedAt,
            version: String(version),
            data: data
        ))
    }
    
    /// Validates Square item variation data
    private static func validateItemVariationData(_ data: [String: Any], id: String, updatedAt: String, version: Int64) -> Result<ValidatedCatalogObject, ValidationError> {
        guard let variationData = data["item_variation_data"] as? [String: Any] else {
            return .failure(.missingRequiredField("item_variation_data"))
        }
        
        guard let itemId = variationData["item_id"] as? String, !itemId.isEmpty else {
            return .failure(.missingRequiredField("item_id"))
        }
        
        guard validateSquareId(itemId) else {
            return .failure(.invalidFormat("item_id", "Invalid item ID format"))
        }
        
        // Validate SKU if present
        if let sku = variationData["sku"] as? String {
            guard validateSKU(sku) else {
                return .failure(.invalidFormat("sku", "SKU contains invalid characters"))
            }
        }
        
        // Validate pricing data if present
        if let pricingType = variationData["pricing_type"] as? String {
            guard ["FIXED_PRICING", "VARIABLE_PRICING"].contains(pricingType) else {
                return .failure(.invalidValue("pricing_type", "Must be FIXED_PRICING or VARIABLE_PRICING"))
            }
        }
        
        return .success(ValidatedCatalogObject(
            id: id,
            type: "ITEM_VARIATION",
            updatedAt: updatedAt,
            version: String(version),
            data: data
        ))
    }
    
    /// Validates Square category data
    private static func validateCategoryData(_ data: [String: Any], id: String, updatedAt: String, version: Int64) -> Result<ValidatedCatalogObject, ValidationError> {
        guard let categoryData = data["category_data"] as? [String: Any] else {
            return .failure(.missingRequiredField("category_data"))
        }
        
        // Validate name if present
        if let name = categoryData["name"] as? String {
            guard validateCategoryName(name) else {
                return .failure(.invalidFormat("name", "Category name contains invalid characters"))
            }
        }
        
        return .success(ValidatedCatalogObject(
            id: id,
            type: "CATEGORY",
            updatedAt: updatedAt,
            version: String(version),
            data: data
        ))
    }
    
    // MARK: - User Input Validation
    
    /// Sanitizes and validates search input
    static func validateSearchInput(_ input: String) -> Result<String, ValidationError> {
        logger.debug("Validating search input")
        
        // Remove potentially dangerous characters
        let sanitized = sanitizeSearchInput(input)
        
        // Check length constraints
        guard sanitized.count <= 100 else {
            return .failure(.invalidValue("search", "Search query too long (max 100 characters)"))
        }
        
        guard !sanitized.isEmpty else {
            return .failure(.invalidValue("search", "Search query cannot be empty"))
        }
        
        return .success(sanitized)
    }
    
    /// Validates team data input
    static func validateTeamDataInput(_ teamData: TeamData) -> Result<TeamData, ValidationError> {
        logger.debug("Validating team data input")
        
        // Validate item_id
        guard validateSquareId(teamData.itemId) else {
            return .failure(.invalidFormat("item_id", "Invalid item ID format"))
        }
        
        // Validate case UPC if present
        if let caseUpc = teamData.caseUpc {
            guard validateUPC(caseUpc) else {
                return .failure(.invalidFormat("case_upc", "Invalid UPC format"))
            }
        }
        
        // Validate case cost if present
        if let caseCost = teamData.caseCost {
            guard caseCost >= 0 else {
                return .failure(.invalidValue("case_cost", "Case cost must be non-negative"))
            }
        }
        
        // Validate case quantity if present
        if let caseQuantity = teamData.caseQuantity {
            guard caseQuantity > 0 else {
                return .failure(.invalidValue("case_quantity", "Case quantity must be positive"))
            }
        }
        
        // Validate vendor name if present
        if let vendor = teamData.vendor {
            guard validateVendorName(vendor) else {
                return .failure(.invalidFormat("vendor", "Vendor name contains invalid characters"))
            }
        }
        
        // Validate notes if present
        if let notes = teamData.notes {
            guard notes.count <= 500 else {
                return .failure(.invalidValue("notes", "Notes too long (max 500 characters)"))
            }
        }
        
        return .success(teamData)
    }
    
    // MARK: - Format Validators
    
    /// Validates Square ID format (alphanumeric, specific length)
    private static func validateSquareId(_ id: String) -> Bool {
        let pattern = "^[A-Za-z0-9_-]{1,255}$"
        return id.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Validates ISO8601 timestamp format
    private static func validateISO8601Timestamp(_ timestamp: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) != nil
    }
    
    /// Validates product name (alphanumeric, spaces, common punctuation)
    private static func validateProductName(_ name: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\s\\-_.,()&'\"]+$"
        return name.range(of: pattern, options: .regularExpression) != nil && name.count <= 255
    }
    
    /// Validates SKU format
    private static func validateSKU(_ sku: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\-_]{1,50}$"
        return sku.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Validates category name
    private static func validateCategoryName(_ name: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\s\\-_.,()&'\"]+$"
        return name.range(of: pattern, options: .regularExpression) != nil && name.count <= 100
    }
    
    /// Validates UPC format (12 digits)
    private static func validateUPC(_ upc: String) -> Bool {
        let pattern = "^\\d{12}$"
        return upc.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Validates vendor name
    private static func validateVendorName(_ vendor: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\s\\-_.,()&'\"]+$"
        return vendor.range(of: pattern, options: .regularExpression) != nil && vendor.count <= 100
    }
    
    // MARK: - Input Sanitization
    
    /// Sanitizes search input to prevent injection attacks
    static func sanitizeSearchInput(_ input: String) -> String {
        // Remove SQL injection patterns
        var sanitized = input
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "--", with: "")
            .replacingOccurrences(of: "/*", with: "")
            .replacingOccurrences(of: "*/", with: "")
        
        // Remove excessive whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return sanitized
    }
}

// MARK: - Validation Models

/// Validated catalog object ready for database storage
struct ValidatedCatalogObject {
    let id: String
    let type: String
    let updatedAt: String
    let version: String
    let data: [String: Any]
}

/// Comprehensive validation errors
enum ValidationError: LocalizedError, Equatable {
    case missingRequiredField(String)
    case invalidFormat(String, String)
    case invalidValue(String, String)
    case unsupportedType(String)
    case dataCorrupted(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidFormat(let field, let reason):
            return "Invalid format for \(field): \(reason)"
        case .invalidValue(let field, let reason):
            return "Invalid value for \(field): \(reason)"
        case .unsupportedType(let type):
            return "Unsupported object type: \(type)"
        case .dataCorrupted(let reason):
            return "Data corrupted: \(reason)"
        }
    }
    
    static func == (lhs: ValidationError, rhs: ValidationError) -> Bool {
        switch (lhs, rhs) {
        case (.missingRequiredField(let a), .missingRequiredField(let b)):
            return a == b
        case (.invalidFormat(let a1, let a2), .invalidFormat(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.invalidValue(let a1, let a2), .invalidValue(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.unsupportedType(let a), .unsupportedType(let b)):
            return a == b
        case (.dataCorrupted(let a), .dataCorrupted(let b)):
            return a == b
        default:
            return false
        }
    }
}
