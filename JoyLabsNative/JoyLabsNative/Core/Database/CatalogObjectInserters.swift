import Foundation
import SQLite
import os.log

/// Handles insertion of specific catalog object types
/// Separated from main manager for better organization and maintainability
class CatalogObjectInserters {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogObjectInserters")
    
    /// Comprehensive category insertion with full Square API data extraction
    func insertCategoryObject(_ object: CatalogObject, timestamp: String, in db: Connection) throws {
        guard let categoryData = object.categoryData else {
            logger.warning("Category object \(object.id) missing categoryData - skipping")
            return
        }

        // Extract comprehensive category information
        let categoryName = categoryData.name ?? "Category \(object.id)"
        let imageUrl = categoryData.imageUrl

        // Encode category data as JSON for full preservation
        let categoryDataJson = try encodeJSON(categoryData)

        let insert = CatalogTableDefinitions.categories.insert(or: .replace,
            CatalogTableDefinitions.categoryId <- object.id,
            CatalogTableDefinitions.categoryName <- categoryName,
            CatalogTableDefinitions.categoryImageUrl <- imageUrl,
            CatalogTableDefinitions.categoryIsDeleted <- (object.isDeleted ?? false),
            CatalogTableDefinitions.categoryUpdatedAt <- timestamp,
            CatalogTableDefinitions.categoryVersion <- String(object.version ?? 1),
            CatalogTableDefinitions.categoryDataJson <- categoryDataJson
        )

        try db.run(insert)
        logger.debug("Inserted category: \(categoryName) (ID: \(object.id))")
    }

    /// Comprehensive tax insertion with full Square API data extraction
    func insertTaxObject(_ object: CatalogObject, timestamp: String, in db: Connection) throws {
        guard let taxData = object.taxData else {
            logger.warning("Tax object \(object.id) missing taxData - skipping")
            return
        }

        // Extract comprehensive tax information
        let taxName = taxData.name ?? "Tax \(object.id)"
        let calculationPhase = taxData.calculationPhase
        let inclusionType = taxData.inclusionType
        let percentage = taxData.percentage
        let appliesToCustomAmounts = taxData.appliesToCustomAmounts
        let enabled = taxData.enabled

        // Encode tax data as JSON for full preservation
        let taxDataJson = try encodeJSON(taxData)

        let insert = CatalogTableDefinitions.taxes.insert(or: .replace,
            CatalogTableDefinitions.taxId <- object.id,
            CatalogTableDefinitions.taxName <- taxName,
            CatalogTableDefinitions.taxCalculationPhase <- calculationPhase,
            CatalogTableDefinitions.taxInclusionType <- inclusionType,
            CatalogTableDefinitions.taxPercentage <- percentage,
            CatalogTableDefinitions.taxAppliesToCustomAmounts <- appliesToCustomAmounts,
            CatalogTableDefinitions.taxEnabled <- enabled,
            CatalogTableDefinitions.taxIsDeleted <- (object.isDeleted ?? false),
            CatalogTableDefinitions.taxUpdatedAt <- timestamp,
            CatalogTableDefinitions.taxVersion <- String(object.version ?? 1),
            CatalogTableDefinitions.taxDataJson <- taxDataJson
        )

        try db.run(insert)
        logger.debug("Inserted tax: \(taxName) (ID: \(object.id))")
    }

    /// Comprehensive modifier insertion with full Square API data extraction
    func insertModifierObject(_ object: CatalogObject, timestamp: String, in db: Connection) throws {
        guard let modifierData = object.modifierData else {
            logger.warning("Modifier object \(object.id) missing modifierData - skipping")
            return
        }

        // Extract comprehensive modifier information
        let modifierName = modifierData.name ?? "Modifier \(object.id)"
        let modifierListId = modifierData.modifierListId
        let priceMoney = modifierData.priceMoney
        let ordinal = modifierData.ordinal
        let onByDefault = modifierData.onByDefault

        // Encode modifier data as JSON for full preservation
        let modifierDataJson = try encodeJSON(modifierData)

        let insert = CatalogTableDefinitions.modifiers.insert(or: .replace,
            CatalogTableDefinitions.modifierId <- object.id,
            CatalogTableDefinitions.modifierName <- modifierName,
            CatalogTableDefinitions.modifierListId <- modifierListId,
            CatalogTableDefinitions.modifierPriceAmount <- priceMoney?.amount,
            CatalogTableDefinitions.modifierPriceCurrency <- priceMoney?.currency,
            CatalogTableDefinitions.modifierOrdinal <- ordinal.map { Int64($0) },
            CatalogTableDefinitions.modifierOnByDefault <- onByDefault,
            CatalogTableDefinitions.modifierIsDeleted <- (object.isDeleted ?? false),
            CatalogTableDefinitions.modifierUpdatedAt <- timestamp,
            CatalogTableDefinitions.modifierVersion <- String(object.version ?? 1),
            CatalogTableDefinitions.modifierDataJson <- modifierDataJson
        )

        try db.run(insert)
        logger.debug("Inserted modifier: \(modifierName) (ID: \(object.id))")
    }

    /// Comprehensive modifier list insertion with full Square API data extraction
    func insertModifierListObject(_ object: CatalogObject, timestamp: String, in db: Connection) throws {
        guard let modifierListData = object.modifierListData else {
            logger.warning("ModifierList object \(object.id) missing modifierListData - skipping")
            return
        }

        // Extract comprehensive modifier list information
        let modifierListName = modifierListData.name ?? "Modifier List \(object.id)"
        let selectionType = modifierListData.selectionType
        let ordinal = modifierListData.ordinal

        // Encode modifier list data as JSON for full preservation
        let modifierListDataJson = try encodeJSON(modifierListData)

        let insert = CatalogTableDefinitions.modifierLists.insert(or: .replace,
            CatalogTableDefinitions.modifierListPrimaryId <- object.id,
            CatalogTableDefinitions.modifierListName <- modifierListName,
            CatalogTableDefinitions.modifierListSelectionType <- selectionType,
            CatalogTableDefinitions.modifierListOrdinal <- ordinal.map { Int64($0) },
            CatalogTableDefinitions.modifierListIsDeleted <- (object.isDeleted ?? false),
            CatalogTableDefinitions.modifierListUpdatedAt <- timestamp,
            CatalogTableDefinitions.modifierListVersion <- String(object.version ?? 1),
            CatalogTableDefinitions.modifierListDataJson <- modifierListDataJson
        )

        try db.run(insert)
        logger.debug("Inserted modifier list: \(modifierListName) (ID: \(object.id))")
    }
    
    // MARK: - Helper Methods
    
    /// Encodes any Codable object to JSON string
    private func encodeJSON<T: Codable>(_ object: T) -> String {
        do {
            let data = try JSONEncoder().encode(object)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to encode object to JSON: \(error)")
            return "{}"
        }
    }
}
