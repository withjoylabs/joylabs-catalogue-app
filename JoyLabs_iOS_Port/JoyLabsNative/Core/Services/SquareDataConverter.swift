import Foundation
import SQLite
import os.log

/// Simple, elegant service for bidirectional ID↔Name conversion
/// Extends existing database patterns without breaking current sync functionality
/// Used for CRUD operations to convert UI selections (names) back to Square IDs
class SquareDataConverter {
    private let databaseManager: SQLiteSwiftCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareDataConverter")
    
    // MARK: - Initialization
    
    init(databaseManager: SQLiteSwiftCatalogManager) {
        self.databaseManager = databaseManager
        logger.info("SquareDataConverter initialized")
    }
    
    // MARK: - Name → ID Conversion (for CRUD operations)
    
    /// Convert category name to Square category ID
    /// Used when preparing data for Square API calls
    func getCategoryId(byName name: String) -> String? {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for category lookup")
            return nil
        }
        
        guard !name.isEmpty else {
            logger.warning("Empty category name provided")
            return nil
        }
        
        do {
            let query = CatalogTableDefinitions.categories
                .select(CatalogTableDefinitions.categoryId)
                .filter(CatalogTableDefinitions.categoryName == name && 
                       CatalogTableDefinitions.categoryIsDeleted == false)
            
            if let row = try db.pluck(query) {
                let categoryId = try row.get(CatalogTableDefinitions.categoryId)
                logger.debug("Found category ID '\(categoryId)' for name '\(name)'")
                return categoryId
            } else {
                logger.warning("No category found for name '\(name)'")
            }
        } catch {
            logger.error("Failed to get category ID for name '\(name)': \(error)")
        }
        return nil
    }
    
    /// Convert tax names to Square tax IDs
    /// Used when preparing data for Square API calls
    func getTaxIds(byNames names: [String]) -> [String] {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for tax lookup")
            return []
        }
        
        guard !names.isEmpty else {
            return []
        }
        
        var taxIds: [String] = []
        
        for name in names {
            guard !name.isEmpty else { continue }
            
            do {
                let query = CatalogTableDefinitions.taxes
                    .select(CatalogTableDefinitions.taxId)
                    .filter(CatalogTableDefinitions.taxName == name && 
                           CatalogTableDefinitions.taxIsDeleted == false &&
                           CatalogTableDefinitions.taxEnabled == true)
                
                if let row = try db.pluck(query) {
                    let taxId = try row.get(CatalogTableDefinitions.taxId)
                    taxIds.append(taxId)
                    logger.debug("Found tax ID '\(taxId)' for name '\(name)'")
                } else {
                    logger.warning("No tax found for name '\(name)'")
                }
            } catch {
                logger.error("Failed to get tax ID for name '\(name)': \(error)")
            }
        }
        
        logger.info("Converted \(names.count) tax names to \(taxIds.count) tax IDs")
        return taxIds
    }
    
    /// Convert modifier list names to Square modifier list IDs
    /// Used when preparing data for Square API calls
    func getModifierListIds(byNames names: [String]) -> [String] {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for modifier lookup")
            return []
        }
        
        guard !names.isEmpty else {
            return []
        }
        
        var modifierIds: [String] = []
        
        for name in names {
            guard !name.isEmpty else { continue }
            
            do {
                let query = CatalogTableDefinitions.modifierLists
                    .select(CatalogTableDefinitions.modifierListPrimaryId)
                    .filter(CatalogTableDefinitions.modifierListName == name && 
                           CatalogTableDefinitions.modifierListIsDeleted == false)
                
                if let row = try db.pluck(query) {
                    let modifierId = try row.get(CatalogTableDefinitions.modifierListPrimaryId)
                    modifierIds.append(modifierId)
                    logger.debug("Found modifier list ID '\(modifierId)' for name '\(name)'")
                } else {
                    logger.warning("No modifier list found for name '\(name)'")
                }
            } catch {
                logger.error("Failed to get modifier list ID for name '\(name)': \(error)")
            }
        }
        
        logger.info("Converted \(names.count) modifier names to \(modifierIds.count) modifier IDs")
        return modifierIds
    }
    
    // MARK: - Simple Validation Methods
    
    /// Check if a category ID exists and is not deleted
    /// Used to validate references before sending to Square API
    func validateCategoryExists(id: String) -> Bool {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for category validation")
            return false
        }
        
        guard !id.isEmpty else {
            return false
        }
        
        do {
            let query = CatalogTableDefinitions.categories
                .filter(CatalogTableDefinitions.categoryId == id && 
                       CatalogTableDefinitions.categoryIsDeleted == false)
            
            let exists = try db.pluck(query) != nil
            logger.debug("Category ID '\(id)' validation: \(exists)")
            return exists
        } catch {
            logger.error("Failed to validate category ID '\(id)': \(error)")
            return false
        }
    }

    /// Check if a single tax ID exists and is enabled
    /// Used to validate individual tax references before sending to Square API
    func validateTaxExists(id: String) -> Bool {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for tax validation")
            return false
        }

        guard !id.isEmpty else { return false }

        do {
            let query = CatalogTableDefinitions.taxes
                .filter(CatalogTableDefinitions.taxId == id &&
                       CatalogTableDefinitions.taxIsDeleted == false &&
                       CatalogTableDefinitions.taxEnabled == true)

            let exists = try db.pluck(query) != nil
            logger.debug("Tax ID '\(id)' validation: \(exists)")
            return exists
        } catch {
            logger.error("Failed to validate tax ID '\(id)': \(error)")
            return false
        }
    }

    /// Check if tax IDs exist and are enabled
    /// Used to validate references before sending to Square API
    func validateTaxIds(_ ids: [String]) -> [String] {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for tax validation")
            return []
        }
        
        var validIds: [String] = []
        
        for id in ids {
            guard !id.isEmpty else { continue }
            
            do {
                let query = CatalogTableDefinitions.taxes
                    .filter(CatalogTableDefinitions.taxId == id && 
                           CatalogTableDefinitions.taxIsDeleted == false &&
                           CatalogTableDefinitions.taxEnabled == true)
                
                if try db.pluck(query) != nil {
                    validIds.append(id)
                    logger.debug("Tax ID '\(id)' is valid")
                } else {
                    logger.warning("Tax ID '\(id)' is invalid or disabled")
                }
            } catch {
                logger.error("Failed to validate tax ID '\(id)': \(error)")
            }
        }
        
        logger.info("Validated \(ids.count) tax IDs, \(validIds.count) are valid")
        return validIds
    }
    
    /// Check if modifier list IDs exist and are not deleted
    /// Used to validate references before sending to Square API
    func validateModifierListIds(_ ids: [String]) -> [String] {
        guard let db = databaseManager.getConnection() else {
            logger.error("No database connection available for modifier validation")
            return []
        }
        
        var validIds: [String] = []
        
        for id in ids {
            guard !id.isEmpty else { continue }
            
            do {
                let query = CatalogTableDefinitions.modifierLists
                    .filter(CatalogTableDefinitions.modifierListPrimaryId == id && 
                           CatalogTableDefinitions.modifierListIsDeleted == false)
                
                if try db.pluck(query) != nil {
                    validIds.append(id)
                    logger.debug("Modifier list ID '\(id)' is valid")
                } else {
                    logger.warning("Modifier list ID '\(id)' is invalid or deleted")
                }
            } catch {
                logger.error("Failed to validate modifier list ID '\(id)': \(error)")
            }
        }
        
        logger.info("Validated \(ids.count) modifier list IDs, \(validIds.count) are valid")
        return validIds
    }
    
    // MARK: - UPC/SKU Duplicate Checking (Future Implementation)

    /// Check for duplicate UPC codes (business logic requirement)
    /// Note: Square allows duplicate UPCs but business may want to warn users
    func findExistingItemByUPC(_ upc: String) -> String? {
        // TODO: Implement UPC duplicate checking if needed for business logic
        return nil
    }

    /// Check for duplicate SKU codes (business logic requirement)
    /// Note: Square allows duplicate SKUs but business may want to warn users
    func findExistingItemBySKU(_ sku: String) -> String? {
        // TODO: Implement SKU duplicate checking if needed for business logic
        return nil
    }
}
