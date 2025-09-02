import Foundation
import SwiftData
import os.log

/// Simple, elegant service for bidirectional ID↔Name conversion
/// Extends existing database patterns without breaking current sync functionality
/// Used for CRUD operations to convert UI selections (names) back to Square IDs
class SquareDataConverter {
    private let databaseManager: SwiftDataCatalogManager
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareDataConverter")
    
    // MARK: - Initialization
    
    init(databaseManager: SwiftDataCatalogManager) {
        self.databaseManager = databaseManager
        logger.info("SquareDataConverter initialized")
    }
    
    // MARK: - Name → ID Conversion (for CRUD operations)
    
    /// Convert category name to Square category ID
    /// Used when preparing data for Square API calls
    @MainActor
    func getCategoryId(byName name: String) -> String? {
        let context = databaseManager.getContext()
        
        guard !name.isEmpty else {
            logger.warning("Empty category name provided")
            return nil
        }
        
        do {
            let descriptor = FetchDescriptor<CategoryModel>(
                predicate: #Predicate { category in
                    category.name == name && !category.isDeleted
                }
            )
            
            let categories = try context.fetch(descriptor)
            if let category = categories.first {
                logger.debug("Found category ID '\(category.id)' for name '\(name)'")
                return category.id
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
    @MainActor
    func getTaxIds(byNames names: [String]) -> [String] {
        let context = databaseManager.getContext()
        
        guard !names.isEmpty else {
            return []
        }
        
        var taxIds: [String] = []
        
        for name in names {
            guard !name.isEmpty else { continue }
            
            do {
                let descriptor = FetchDescriptor<TaxModel>(
                    predicate: #Predicate { tax in
                        tax.name == name && !tax.isDeleted && (tax.enabled ?? false)
                    }
                )
                
                let taxes = try context.fetch(descriptor)
                if let tax = taxes.first {
                    taxIds.append(tax.id)
                    logger.debug("Found tax ID '\(tax.id)' for name '\(name)'")
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
    @MainActor
    func getModifierListIds(byNames names: [String]) -> [String] {
        let context = databaseManager.getContext()
        
        guard !names.isEmpty else {
            return []
        }
        
        var modifierIds: [String] = []
        
        for name in names {
            guard !name.isEmpty else { continue }
            
            do {
                let descriptor = FetchDescriptor<ModifierListModel>(
                    predicate: #Predicate { modifierList in
                        modifierList.name == name && !modifierList.isDeleted
                    }
                )
                
                let modifierLists = try context.fetch(descriptor)
                if let modifierList = modifierLists.first {
                    modifierIds.append(modifierList.id)
                    logger.debug("Found modifier list ID '\(modifierList.id)' for name '\(name)'")
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
    @MainActor
    func validateCategoryExists(id: String) -> Bool {
        let context = databaseManager.getContext()
        
        guard !id.isEmpty else {
            return false
        }
        
        do {
            let descriptor = FetchDescriptor<CategoryModel>(
                predicate: #Predicate { category in
                    category.id == id && !category.isDeleted
                }
            )
            
            let categories = try context.fetch(descriptor)
            let exists = !categories.isEmpty
            logger.debug("Category ID '\(id)' validation: \(exists)")
            return exists
        } catch {
            logger.error("Failed to validate category ID '\(id)': \(error)")
            return false
        }
    }

    /// Check if a single tax ID exists and is enabled
    /// Used to validate individual tax references before sending to Square API
    @MainActor
    func validateTaxExists(id: String) -> Bool {
        let context = databaseManager.getContext()

        guard !id.isEmpty else { return false }

        do {
            let descriptor = FetchDescriptor<TaxModel>(
                predicate: #Predicate { tax in
                    tax.id == id && !tax.isDeleted && (tax.enabled ?? false)
                }
            )

            let taxes = try context.fetch(descriptor)
            let exists = !taxes.isEmpty
            logger.debug("Tax ID '\(id)' validation: \(exists)")
            return exists
        } catch {
            logger.error("Failed to validate tax ID '\(id)': \(error)")
            return false
        }
    }

    /// Check if tax IDs exist and are enabled
    /// Used to validate references before sending to Square API
    @MainActor
    func validateTaxIds(_ ids: [String]) -> [String] {
        let context = databaseManager.getContext()
        
        var validIds: [String] = []
        
        for id in ids {
            guard !id.isEmpty else { continue }
            
            do {
                let descriptor = FetchDescriptor<TaxModel>(
                    predicate: #Predicate { tax in
                        tax.id == id && !tax.isDeleted && (tax.enabled ?? false)
                    }
                )
                
                let taxes = try context.fetch(descriptor)
                if !taxes.isEmpty {
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
    @MainActor
    func validateModifierListIds(_ ids: [String]) -> [String] {
        let context = databaseManager.getContext()
        
        var validIds: [String] = []
        
        for id in ids {
            guard !id.isEmpty else { continue }
            
            do {
                let descriptor = FetchDescriptor<ModifierListModel>(
                    predicate: #Predicate { modifierList in
                        modifierList.id == id && !modifierList.isDeleted
                    }
                )
                
                let modifierLists = try context.fetch(descriptor)
                if !modifierLists.isEmpty {
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
