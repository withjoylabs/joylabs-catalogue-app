import Foundation
import SQLite
import os.log

/// Handles creation of all catalog database tables
/// Separated from main manager for better organization
class CatalogTableCreator {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogTableCreator")
    
    /// Creates all catalog tables in the database
    func createTables(in db: Connection) throws {
        // First, try to add missing columns to existing tables
        try addMissingColumnsIfNeeded(db)
        // Create categories table
        try db.run(CatalogTableDefinitions.categories.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.categoryId, primaryKey: true)
            t.column(CatalogTableDefinitions.categoryName)
            t.column(CatalogTableDefinitions.categoryImageUrl)
            t.column(CatalogTableDefinitions.categoryIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.categoryUpdatedAt)
            t.column(CatalogTableDefinitions.categoryVersion)
            t.column(CatalogTableDefinitions.categoryDataJson)
        })
        
        // Create catalog_items table
        try db.run(CatalogTableDefinitions.catalogItems.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.itemId, primaryKey: true)
            t.column(CatalogTableDefinitions.itemName)
            t.column(CatalogTableDefinitions.itemDescription)
            t.column(CatalogTableDefinitions.itemCategoryId)
            t.column(CatalogTableDefinitions.itemCategoryName)
            t.column(CatalogTableDefinitions.itemReportingCategoryName)
            t.column(CatalogTableDefinitions.itemTaxNames, defaultValue: nil) // Pre-resolved tax names for performance
            t.column(CatalogTableDefinitions.itemModifierNames, defaultValue: nil) // Pre-resolved modifier names for performance
            t.column(CatalogTableDefinitions.itemPresentAtAllLocations, defaultValue: nil) // Location availability setting
            t.column(CatalogTableDefinitions.itemPresentAtLocationIds, defaultValue: nil) // JSON array of specific location IDs where item is present
            t.column(CatalogTableDefinitions.itemAbsentAtLocationIds, defaultValue: nil) // JSON array of specific location IDs where item is absent
            t.column(CatalogTableDefinitions.itemIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.itemUpdatedAt)
            t.column(CatalogTableDefinitions.itemVersion)
            t.column(CatalogTableDefinitions.itemDataJson)
            
            // Foreign key constraint
            t.foreignKey(CatalogTableDefinitions.itemCategoryId, references: CatalogTableDefinitions.categories, CatalogTableDefinitions.categoryId)
        })

        // Create item_variations table
        try db.run(CatalogTableDefinitions.itemVariations.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.variationId, primaryKey: true)
            t.column(CatalogTableDefinitions.variationItemId)
            t.column(CatalogTableDefinitions.variationName)
            t.column(CatalogTableDefinitions.variationSku)
            t.column(CatalogTableDefinitions.variationUpc)
            t.column(CatalogTableDefinitions.variationOrdinal)
            t.column(CatalogTableDefinitions.variationPricingType)
            t.column(CatalogTableDefinitions.variationPriceAmount)
            t.column(CatalogTableDefinitions.variationPriceCurrency)
            t.column(CatalogTableDefinitions.variationPresentAtAllLocations, defaultValue: nil) // Variation location availability
            t.column(CatalogTableDefinitions.variationPresentAtLocationIds, defaultValue: nil) // JSON array of specific location IDs for variation
            t.column(CatalogTableDefinitions.variationAbsentAtLocationIds, defaultValue: nil) // JSON array of absent location IDs for variation
            t.column(CatalogTableDefinitions.variationIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.variationUpdatedAt)
            t.column(CatalogTableDefinitions.variationVersion)
            t.column(CatalogTableDefinitions.variationDataJson)
            
            // Foreign key constraint
            t.foreignKey(CatalogTableDefinitions.variationItemId, references: CatalogTableDefinitions.catalogItems, CatalogTableDefinitions.itemId)
        })
        
        // Create taxes table
        try db.run(CatalogTableDefinitions.taxes.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.taxId, primaryKey: true)
            t.column(CatalogTableDefinitions.taxUpdatedAt)
            t.column(CatalogTableDefinitions.taxVersion)
            t.column(CatalogTableDefinitions.taxIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.taxName)
            t.column(CatalogTableDefinitions.taxCalculationPhase)
            t.column(CatalogTableDefinitions.taxInclusionType)
            t.column(CatalogTableDefinitions.taxPercentage)
            t.column(CatalogTableDefinitions.taxAppliesToCustomAmounts)
            t.column(CatalogTableDefinitions.taxEnabled)
            t.column(CatalogTableDefinitions.taxDataJson)
        })

        // Create modifiers table
        try db.run(CatalogTableDefinitions.modifiers.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.modifierId, primaryKey: true)
            t.column(CatalogTableDefinitions.modifierUpdatedAt)
            t.column(CatalogTableDefinitions.modifierVersion)
            t.column(CatalogTableDefinitions.modifierIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.modifierName)
            t.column(CatalogTableDefinitions.modifierListId)
            t.column(CatalogTableDefinitions.modifierPriceAmount)
            t.column(CatalogTableDefinitions.modifierPriceCurrency)
            t.column(CatalogTableDefinitions.modifierOrdinal)
            t.column(CatalogTableDefinitions.modifierOnByDefault)
            t.column(CatalogTableDefinitions.modifierDataJson)
        })

        // Create modifier_lists table
        try db.run(CatalogTableDefinitions.modifierLists.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.modifierListPrimaryId, primaryKey: true)
            t.column(CatalogTableDefinitions.modifierListUpdatedAt)
            t.column(CatalogTableDefinitions.modifierListVersion)
            t.column(CatalogTableDefinitions.modifierListIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.modifierListName)
            t.column(CatalogTableDefinitions.modifierListSelectionType)
            t.column(CatalogTableDefinitions.modifierListOrdinal)
            t.column(CatalogTableDefinitions.modifierListDataJson)
        })

        // Create discounts table
        try db.run(CatalogTableDefinitions.discounts.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.discountId, primaryKey: true)
            t.column(CatalogTableDefinitions.discountName)
            t.column(CatalogTableDefinitions.discountIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.discountUpdatedAt)
            t.column(CatalogTableDefinitions.discountVersion)
            t.column(CatalogTableDefinitions.discountDataJson)
        })
        
        // Create images table
        try db.run(CatalogTableDefinitions.images.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.imageId, primaryKey: true)
            t.column(CatalogTableDefinitions.imageName)
            t.column(CatalogTableDefinitions.imageUrl)
            t.column(CatalogTableDefinitions.imageCaption)
            t.column(CatalogTableDefinitions.imageIsDeleted, defaultValue: false)
            t.column(CatalogTableDefinitions.imageUpdatedAt)
            t.column(CatalogTableDefinitions.imageVersion)
            t.column(CatalogTableDefinitions.imageDataJson)
        })
        
        // Create team_data table (AppSync Integration)
        try db.run(CatalogTableDefinitions.teamData.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.teamDataItemId, primaryKey: true)
            t.column(CatalogTableDefinitions.teamCaseUpc)
            t.column(CatalogTableDefinitions.teamCaseCost)
            t.column(CatalogTableDefinitions.teamCaseQuantity)
            t.column(CatalogTableDefinitions.teamVendor)
            t.column(CatalogTableDefinitions.teamDiscontinued, defaultValue: false)
            t.column(CatalogTableDefinitions.teamNotes)
            t.column(CatalogTableDefinitions.teamCreatedAt)
            t.column(CatalogTableDefinitions.teamUpdatedAt)
            t.column(CatalogTableDefinitions.teamLastSyncAt)
            t.column(CatalogTableDefinitions.teamOwner)

            // Foreign key constraint to catalog_items
            t.foreignKey(CatalogTableDefinitions.teamDataItemId, references: CatalogTableDefinitions.catalogItems, CatalogTableDefinitions.itemId, update: .cascade, delete: .cascade)
        })
        
        // Create sync_status table
        try db.run(CatalogTableDefinitions.syncStatus.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.syncKey, primaryKey: true)
            t.column(CatalogTableDefinitions.syncValue)
            t.column(CatalogTableDefinitions.syncUpdatedAt)
        })

        // Create locations table
        try db.run(CatalogTableDefinitions.locations.create(ifNotExists: true) { t in
            t.column(CatalogTableDefinitions.locationId, primaryKey: true)
            t.column(CatalogTableDefinitions.locationName)
            t.column(CatalogTableDefinitions.locationMerchantId)
            t.column(CatalogTableDefinitions.locationAddress)
            t.column(CatalogTableDefinitions.locationTimezone)
            t.column(CatalogTableDefinitions.locationPhoneNumber)
            t.column(CatalogTableDefinitions.locationBusinessName)
            t.column(CatalogTableDefinitions.locationBusinessEmail)
            t.column(CatalogTableDefinitions.locationWebsiteUrl)
            t.column(CatalogTableDefinitions.locationDescription)
            t.column(CatalogTableDefinitions.locationStatus)
            t.column(CatalogTableDefinitions.locationLogoUrl)
            t.column(CatalogTableDefinitions.locationCreatedAt)
            t.column(CatalogTableDefinitions.locationLastUpdated)
            t.column(CatalogTableDefinitions.locationData)
            t.column(CatalogTableDefinitions.locationIsDeleted, defaultValue: false)
        })

        logger.info("All catalog tables created successfully")
    }

    /// Add missing columns to existing databases
    private func addMissingColumnsIfNeeded(_ db: Connection) throws {
        // Add tax_names column if missing
        do {
            try db.run("ALTER TABLE catalog_items ADD COLUMN tax_names TEXT")
            logger.debug("Added tax_names column to catalog_items")
        } catch {
            // Column already exists or other error - continue
            logger.debug("tax_names column already exists: \(error)")
        }

        // Add modifier_names column if missing
        do {
            try db.run("ALTER TABLE catalog_items ADD COLUMN modifier_names TEXT")
            logger.debug("Added modifier_names column to catalog_items")
        } catch {
            // Column already exists or other error - continue
            logger.debug("modifier_names column already exists: \(error)")
        }

        // Add present_at_all_locations column if missing
        do {
            try db.run("ALTER TABLE catalog_items ADD COLUMN present_at_all_locations INTEGER")
            logger.debug("Added present_at_all_locations column to catalog_items")
        } catch {
            // Column already exists or other error - continue
            logger.debug("present_at_all_locations column already exists: \(error)")
        }

        // Add present_at_location_ids column if missing
        do {
            try db.run("ALTER TABLE catalog_items ADD COLUMN present_at_location_ids TEXT")
            logger.debug("Added present_at_location_ids column to catalog_items")
        } catch {
            // Column already exists or other error - continue
            logger.debug("present_at_location_ids column already exists: \(error)")
        }

        // Add absent_at_location_ids column if missing
        do {
            try db.run("ALTER TABLE catalog_items ADD COLUMN absent_at_location_ids TEXT")
            logger.debug("Added absent_at_location_ids column to catalog_items")
        } catch {
            // Column already exists or other error - continue
            logger.debug("absent_at_location_ids column already exists: \(error)")
        }

        // Add variation location columns if missing
        do {
            try db.run("ALTER TABLE item_variations ADD COLUMN present_at_all_locations INTEGER")
            logger.debug("Added present_at_all_locations column to item_variations")
        } catch {
            logger.debug("present_at_all_locations column already exists in item_variations: \(error)")
        }

        do {
            try db.run("ALTER TABLE item_variations ADD COLUMN present_at_location_ids TEXT")
            logger.debug("Added present_at_location_ids column to item_variations")
        } catch {
            logger.debug("present_at_location_ids column already exists in item_variations: \(error)")
        }

        do {
            try db.run("ALTER TABLE item_variations ADD COLUMN absent_at_location_ids TEXT")
            logger.debug("Added absent_at_location_ids column to item_variations")
        } catch {
            logger.debug("absent_at_location_ids column already exists in item_variations: \(error)")
        }
    }
}
