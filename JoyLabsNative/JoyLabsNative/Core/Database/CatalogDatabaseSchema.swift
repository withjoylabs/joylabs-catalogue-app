import Foundation
import SQLite3

/// Enhanced database schema for Square catalog sync with full API coverage
/// Based on Square API documentation and React Native implementation analysis
class CatalogDatabaseSchema {
    
    // MARK: - Database Schema Constants
    
    /// Current database version for migration management
    static let currentVersion = 1
    
    // MARK: - Table Creation SQL
    
    /// Main catalog items table with comprehensive Square API field coverage
    static let createCatalogItemsTable = """
        CREATE TABLE IF NOT EXISTS catalog_items (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,
            
            -- CatalogItem specific fields
            name TEXT NOT NULL,
            description TEXT,
            description_html TEXT,
            description_plaintext TEXT,
            abbreviation TEXT,
            label_color TEXT,
            is_taxable INTEGER DEFAULT 1,
            category_id TEXT,
            tax_ids TEXT, -- JSON array of tax IDs
            product_type TEXT,
            skip_modifier_screen INTEGER DEFAULT 0,
            ecom_uri TEXT,
            ecom_image_uris TEXT, -- JSON array of URIs
            image_ids TEXT, -- JSON array of image IDs
            sort_name TEXT,
            categories TEXT, -- JSON array of category objects
            channels TEXT, -- JSON array of channel IDs
            is_archived INTEGER DEFAULT 0,
            is_alcoholic INTEGER DEFAULT 0,
            
            -- Food and beverage details (JSON)
            food_and_beverage_details TEXT,
            
            -- SEO data (JSON)
            ecom_seo_data TEXT,
            
            -- Reporting category (JSON)
            reporting_category TEXT,
            
            -- Modifier list info (JSON array)
            modifier_list_info TEXT,
            
            -- Item options (JSON array)
            item_options TEXT,
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1,
            
            -- Search optimization
            search_text TEXT, -- Computed field for full-text search
            
            FOREIGN KEY (category_id) REFERENCES categories(id)
        );
        """
    
    /// Item variations table for size/price variations
    static let createItemVariationsTable = """
        CREATE TABLE IF NOT EXISTS item_variations (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,
            
            -- CatalogItemVariation specific fields
            item_id TEXT NOT NULL,
            name TEXT,
            sku TEXT,
            upc TEXT,
            ordinal INTEGER,
            pricing_type TEXT,
            price_money_amount INTEGER,
            price_money_currency TEXT DEFAULT 'USD',
            location_overrides TEXT, -- JSON array
            track_inventory INTEGER DEFAULT 0,
            inventory_alert_type TEXT,
            inventory_alert_threshold INTEGER,
            user_data TEXT,
            service_duration INTEGER,
            available_for_booking INTEGER DEFAULT 0,
            item_option_values TEXT, -- JSON array
            measurement_unit_id TEXT,
            sellable INTEGER DEFAULT 1,
            stockable INTEGER DEFAULT 1,
            image_ids TEXT, -- JSON array
            team_member_ids TEXT, -- JSON array
            stockable_conversion TEXT, -- JSON object
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1,
            
            FOREIGN KEY (item_id) REFERENCES catalog_items(id)
        );
        """
    
    /// Categories table for product organization
    static let createCategoriesTable = """
        CREATE TABLE IF NOT EXISTS categories (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,
            
            -- CatalogCategory specific fields
            name TEXT NOT NULL,
            image_ids TEXT, -- JSON array
            category_type TEXT,
            parent_category TEXT, -- JSON object
            is_top_level INTEGER DEFAULT 0,
            channels TEXT, -- JSON array
            availability_period_ids TEXT, -- JSON array
            online_visibility INTEGER DEFAULT 1,
            root_category TEXT,
            ecom_seo_data TEXT, -- JSON object
            path_to_root TEXT, -- JSON array
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1,
            
            -- Search optimization
            search_text TEXT
        );
        """
    
    /// Images table for product images (NEW - not in React Native)
    static let createImagesTable = """
        CREATE TABLE IF NOT EXISTS images (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            
            -- CatalogImage specific fields
            name TEXT,
            url TEXT,
            caption TEXT,
            photo_studio_order_id TEXT,
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1
        );
        """
    
    /// Taxes table for tax information
    static let createTaxesTable = """
        CREATE TABLE IF NOT EXISTS taxes (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,
            
            -- CatalogTax specific fields
            name TEXT NOT NULL,
            calculation_phase TEXT,
            inclusion_type TEXT,
            percentage TEXT,
            applies_to_custom_amounts INTEGER DEFAULT 1,
            enabled INTEGER DEFAULT 1,
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1
        );
        """
    
    /// Discounts table for discount rules
    static let createDiscountsTable = """
        CREATE TABLE IF NOT EXISTS discounts (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,
            
            -- CatalogDiscount specific fields
            name TEXT,
            discount_type TEXT,
            percentage TEXT,
            amount_money_amount INTEGER,
            amount_money_currency TEXT DEFAULT 'USD',
            pin_required INTEGER DEFAULT 0,
            label_color TEXT,
            modify_tax_basis TEXT,
            maximum_amount_money_amount INTEGER,
            maximum_amount_money_currency TEXT DEFAULT 'USD',
            
            -- Custom attributes (JSON)
            custom_attributes TEXT,
            
            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1
        );
        """

    /// Modifier lists table for modifier groups
    static let createModifierListsTable = """
        CREATE TABLE IF NOT EXISTS modifier_lists (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,

            -- CatalogModifierList specific fields
            name TEXT NOT NULL,
            ordinal INTEGER,
            selection_type TEXT,
            modifiers TEXT, -- JSON array of modifier objects
            image_ids TEXT, -- JSON array

            -- Custom attributes (JSON)
            custom_attributes TEXT,

            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1
        );
        """

    /// Individual modifiers table
    static let createModifiersTable = """
        CREATE TABLE IF NOT EXISTS modifiers (
            -- Core Square API fields
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            updated_at TEXT,
            created_at TEXT,
            version INTEGER,
            is_deleted INTEGER DEFAULT 0,
            present_at_all_locations INTEGER DEFAULT 1,
            present_at_location_ids TEXT,
            absent_at_location_ids TEXT,

            -- CatalogModifier specific fields
            name TEXT,
            price_money_amount INTEGER,
            price_money_currency TEXT DEFAULT 'USD',
            ordinal INTEGER,
            modifier_list_id TEXT,
            location_overrides TEXT, -- JSON array
            image_ids TEXT, -- JSON array

            -- Custom attributes (JSON)
            custom_attributes TEXT,

            -- Sync metadata
            last_synced_at TEXT,
            sync_version INTEGER DEFAULT 1,

            FOREIGN KEY (modifier_list_id) REFERENCES modifier_lists(id)
        );
        """

    /// Sync metadata table for tracking sync state
    static let createSyncMetadataTable = """
        CREATE TABLE IF NOT EXISTS sync_metadata (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_type TEXT NOT NULL, -- 'full' or 'incremental'
            started_at TEXT NOT NULL,
            completed_at TEXT,
            last_cursor TEXT,
            last_updated_at TEXT,
            total_objects INTEGER DEFAULT 0,
            synced_objects INTEGER DEFAULT 0,
            failed_objects INTEGER DEFAULT 0,
            error_message TEXT,
            status TEXT NOT NULL DEFAULT 'in_progress' -- 'in_progress', 'completed', 'failed'
        );
        """

    // MARK: - Index Creation SQL

    /// Performance indexes for fast search and retrieval
    static let createIndexes = [
        // Catalog items indexes
        "CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items(name);",
        "CREATE INDEX IF NOT EXISTS idx_catalog_items_category_id ON catalog_items(category_id);",
        "CREATE INDEX IF NOT EXISTS idx_catalog_items_updated_at ON catalog_items(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_catalog_items_search_text ON catalog_items(search_text);",
        "CREATE INDEX IF NOT EXISTS idx_catalog_items_is_deleted ON catalog_items(is_deleted);",

        // Item variations indexes
        "CREATE INDEX IF NOT EXISTS idx_item_variations_item_id ON item_variations(item_id);",
        "CREATE INDEX IF NOT EXISTS idx_item_variations_sku ON item_variations(sku);",
        "CREATE INDEX IF NOT EXISTS idx_item_variations_updated_at ON item_variations(updated_at);",

        // Categories indexes
        "CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name);",
        "CREATE INDEX IF NOT EXISTS idx_categories_is_top_level ON categories(is_top_level);",
        "CREATE INDEX IF NOT EXISTS idx_categories_updated_at ON categories(updated_at);",

        // Images indexes
        "CREATE INDEX IF NOT EXISTS idx_images_updated_at ON images(updated_at);",

        // Taxes indexes
        "CREATE INDEX IF NOT EXISTS idx_taxes_name ON taxes(name);",
        "CREATE INDEX IF NOT EXISTS idx_taxes_enabled ON taxes(enabled);",

        // Discounts indexes
        "CREATE INDEX IF NOT EXISTS idx_discounts_name ON discounts(name);",
        "CREATE INDEX IF NOT EXISTS idx_discounts_discount_type ON discounts(discount_type);",

        // Modifier lists indexes
        "CREATE INDEX IF NOT EXISTS idx_modifier_lists_name ON modifier_lists(name);",

        // Modifiers indexes
        "CREATE INDEX IF NOT EXISTS idx_modifiers_modifier_list_id ON modifiers(modifier_list_id);",
        "CREATE INDEX IF NOT EXISTS idx_modifiers_name ON modifiers(name);",

        // Sync metadata indexes
        "CREATE INDEX IF NOT EXISTS idx_sync_metadata_started_at ON sync_metadata(started_at);",
        "CREATE INDEX IF NOT EXISTS idx_sync_metadata_status ON sync_metadata(status);"
    ]

    // MARK: - Full-Text Search Setup

    /// Virtual table for full-text search on catalog items
    static let createSearchTable = """
        CREATE VIRTUAL TABLE IF NOT EXISTS catalog_search USING fts5(
            id,
            name,
            description,
            search_text,
            content='catalog_items',
            content_rowid='rowid'
        );
        """

    /// Trigger to keep search table in sync
    static let createSearchTriggers = [
        """
        CREATE TRIGGER IF NOT EXISTS catalog_search_insert AFTER INSERT ON catalog_items BEGIN
            INSERT INTO catalog_search(id, name, description, search_text)
            VALUES (new.id, new.name, new.description, new.search_text);
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS catalog_search_update AFTER UPDATE ON catalog_items BEGIN
            UPDATE catalog_search SET
                name = new.name,
                description = new.description,
                search_text = new.search_text
            WHERE id = new.id;
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS catalog_search_delete AFTER DELETE ON catalog_items BEGIN
            DELETE FROM catalog_search WHERE id = old.id;
        END;
        """
    ]

    // MARK: - Database Initialization

    /// All table creation statements in dependency order
    static let allTableCreationStatements = [
        createCategoriesTable,
        createImagesTable,
        createTaxesTable,
        createDiscountsTable,
        createModifierListsTable,
        createModifiersTable,
        createCatalogItemsTable,
        createItemVariationsTable,
        createSyncMetadataTable,
        createSearchTable
    ]
}
