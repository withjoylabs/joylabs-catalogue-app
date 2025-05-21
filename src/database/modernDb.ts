import { SQLiteDatabase, openDatabaseAsync, SQLiteBindValue } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system';
import logger from '../utils/logger';
import { ConvertedItem } from '../types/api';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';

// Constants
const DATABASE_NAME = 'joylabs.db';
const DATABASE_VERSION = 2; // Increment version due to schema change
let db: SQLiteDatabase | null = null;

// Define a helper type for Catalog Objects from API
// (This is simplified; a more specific type based on Square docs would be better)
type CatalogObjectFromApi = {
  type: string;
  id: string;
  updated_at: string;
  version: number | string; // Version can be number or string depending on context?
  is_deleted?: boolean;
  present_at_all_locations?: boolean;
  item_data?: any; // Replace with specific types later
  category_data?: any;
  tax_data?: any;
  discount_data?: any;
  modifier_list_data?: any;
  modifier_data?: any;
  item_variation_data?: any;
  image_data?: any;
  // Add other potential *_data fields
};

/**
 * Initializes the database connection and schema
 */
export async function initDatabase(): Promise<SQLiteDatabase> {
  try {
    logger.info('Database', 'Initializing database');
    
    if (db) {
      logger.debug('Database', 'Database already initialized');
      return db;
    }
    
    // Open or create database
    db = await openDatabaseAsync(DATABASE_NAME);
    logger.info('Database', 'Database opened successfully');
    
    // Get current database version
    let currentVersion = 0;
    try {
      const versionRow = await db.getFirstAsync<{ version: number }>(
        'SELECT version FROM db_version WHERE id = 1'
      );
      currentVersion = versionRow?.version || 0;
    } catch (e) {
      // Table might not exist yet
      currentVersion = 0;
    }

    // Check if migration is needed
    if (currentVersion < DATABASE_VERSION) {
      logger.info('Database', `Needs migration from v${currentVersion} to v${DATABASE_VERSION}`);
      // Perform migration (or full reset for simplicity)
      await resetDatabase(); // Resets and sets the version
    } else {
      // Just initialize schema if no migration needed
      await initializeSchema();
    }
    
    // Ensure the locations table is properly set up
    await ensureLocationsTable();
    
    logger.info('Database', 'Database initialized successfully');
    
    return db;
  } catch (error) {
    logger.error('Database', 'Failed to initialize database', { error });
    throw new Error(`Failed to initialize database: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Check if database needs migration by verifying table structure
 */
async function checkDatabaseMigration(db: SQLiteDatabase): Promise<boolean> {
  try {
    // Check if we have a version table
    const versionTable = await db.getAllAsync<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='db_version'"
    );
    
    // If no version table, we need migration
    if (versionTable.length === 0) {
      logger.info('Database', 'No version table found, migration needed');
      return true;
    }
    
    // Check version
    const versionRow = await db.getFirstAsync<{ version: number }>(
      "SELECT version FROM db_version WHERE id = 1"
    );
    
    if (!versionRow || versionRow.version < DATABASE_VERSION) {
      logger.info('Database', `Database version ${versionRow?.version || 'unknown'} is outdated, current version is ${DATABASE_VERSION}`);
      return true;
    }
    
    // Check if sync_status table has all required columns
    try {
      // Try a simple query that will fail if any of these columns is missing
      await db.getFirstAsync(`SELECT 
        id, last_sync_time, is_syncing, sync_error, sync_progress, 
        sync_total, sync_type, last_sync_attempt, sync_attempt_count 
        FROM sync_status WHERE id = 1`);
      
      logger.info('Database', 'Schema validation successful');
      return false;
    } catch (error) {
      // If this fails, the schema is invalid
      logger.warn('Database', 'Schema validation failed, migration needed', { error });
      return true;
    }
  } catch (error) {
    // On any error, assume migration is needed
    logger.warn('Database', 'Error checking migration status, will recreate schema', { error });
    return true;
  }
}

/**
 * Initialize database schema - creates tables if they don't exist
 */
export async function initializeSchema(): Promise<void> {
  logger.info('Database', 'Initializing database schema...');
  const db = await getDatabase();
  let currentVersion = 0;

  // Check if db_version table exists and get current version
  try {
    const versionRow = await db.getFirstAsync<{ version: number }>(
      'SELECT version FROM db_version WHERE id = 1'
    );
    currentVersion = versionRow?.version || 0;
    logger.info('Database', `Current DB version: ${currentVersion}`);
  } catch (error) {
    logger.warn('Database', 'db_version table not found or error reading version, assuming version 0.', { error });
    currentVersion = 0;
  }

  if (currentVersion < DATABASE_VERSION) {
    logger.info('Database', `Schema outdated (Current: ${currentVersion}, Required: ${DATABASE_VERSION}). Applying migrations/recreating...`);
    
    // --- Migration Logic (Simplified: Recreate all tables) ---
    // In a real app, you'd run specific ALTER TABLE statements based on version diffs.
    // For now, we drop and recreate everything if version is outdated.
    await db.withTransactionAsync(async () => {
      logger.info('Schema Init', 'Starting schema creation/update transaction...');
      
      // Drop existing tables (optional, safer to only drop if version is 0 or very old)
      // For simplicity, we drop them all if outdated
      logger.info('Schema Init', 'Dropping existing tables (part of update)...');
      try {
        await db.runAsync('DROP TABLE IF EXISTS sync_status');
        await db.runAsync('DROP TABLE IF EXISTS categories');
        await db.runAsync('DROP TABLE IF EXISTS catalog_items');
        await db.runAsync('DROP TABLE IF EXISTS item_variations');
        await db.runAsync('DROP TABLE IF EXISTS modifier_lists');
        await db.runAsync('DROP TABLE IF EXISTS modifiers');
        await db.runAsync('DROP TABLE IF EXISTS taxes');
        await db.runAsync('DROP TABLE IF EXISTS discounts');
        await db.runAsync('DROP TABLE IF EXISTS images');
        await db.runAsync('DROP TABLE IF EXISTS merchant_info');
        await db.runAsync('DROP TABLE IF EXISTS locations');
        await db.runAsync('DROP TABLE IF EXISTS sync_logs');
        await db.runAsync('DROP TABLE IF EXISTS db_version');
        logger.info('Schema Init', 'Existing tables dropped successfully (part of update).');
      } catch(dropError) {
        logger.error('Schema Init', 'Error dropping tables during update', { dropError });
        throw dropError;
      }

      logger.info('Schema Init', 'Creating tables...');
      try {
        // Create sync_status table
        await db.runAsync(`CREATE TABLE sync_status (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          last_sync_time TEXT,
          is_syncing INTEGER NOT NULL DEFAULT 0,
          sync_error TEXT,
          sync_progress INTEGER NOT NULL DEFAULT 0,
          sync_total INTEGER NOT NULL DEFAULT 0, -- Consider removing if progress is page-based
          sync_type TEXT, -- e.g., 'full', 'delta'
          last_page_cursor TEXT, -- Store cursor for resuming
          last_sync_attempt TEXT,
          sync_attempt_count INTEGER NOT NULL DEFAULT 0,
          last_incremental_sync_cursor TEXT
        )`);
        await db.runAsync(`INSERT INTO sync_status (id) VALUES (1)`);
        logger.debug('Schema Init', 'Created sync_status table.');
        
        // Create categories table
        await db.runAsync(`CREATE TABLE categories (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL, -- Store as TEXT since it can be large number string
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          data_json TEXT -- Store the raw category_data JSON
        )`);
        logger.debug('Schema Init', 'Created categories table.');
        await db.runAsync(`CREATE TABLE catalog_items (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          present_at_all_locations INTEGER DEFAULT 1,
          name TEXT,
          description TEXT,
          category_id TEXT, -- Reference categories table
          data_json TEXT -- Store the raw item_data JSON
        )`);
        logger.debug('Schema Init', 'Created catalog_items table.');
        await db.runAsync(`CREATE TABLE item_variations (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          item_id TEXT NOT NULL, -- Reference items table
          name TEXT,
          sku TEXT,
          pricing_type TEXT,
          price_amount INTEGER, -- Store amount in cents/smallest unit
          price_currency TEXT,
          data_json TEXT -- Store the raw item_variation_data JSON
        )`);
        logger.debug('Schema Init', 'Created item_variations table.');
        await db.runAsync(`CREATE TABLE modifier_lists (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          selection_type TEXT, -- SINGLE or MULTIPLE
          data_json TEXT -- Store the raw modifier_list_data JSON
        )`);
        logger.debug('Schema Init', 'Created modifier_lists table.');
        await db.runAsync(`CREATE TABLE modifiers (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          modifier_list_id TEXT NOT NULL, -- Reference modifier_lists table
          name TEXT,
          price_amount INTEGER,
          price_currency TEXT,
          ordinal INTEGER,
          data_json TEXT -- Store the raw modifier_data JSON
        )`);
        logger.debug('Schema Init', 'Created modifiers table.');
        await db.runAsync(`CREATE TABLE taxes (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          calculation_phase TEXT, -- SUBTOTAL_PHASE, TOTAL_PHASE
          inclusion_type TEXT, -- ADDITIVE, INCLUSIVE
          percentage TEXT, -- Store as string as it can be like "7.25"
          applies_to_custom_amounts INTEGER,
          enabled INTEGER,
          data_json TEXT -- Store the raw tax_data JSON
        )`);
        logger.debug('Schema Init', 'Created taxes table.');
        await db.runAsync(`CREATE TABLE discounts (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          discount_type TEXT, -- FIXED_PERCENTAGE, FIXED_AMOUNT, VARIABLE_PERCENTAGE, VARIABLE_AMOUNT
          percentage TEXT,
          amount INTEGER,
          currency TEXT,
          pin_required INTEGER,
          label_color TEXT,
          modify_tax_basis TEXT, -- MODIFY_TAX_BASIS, DO_NOT_MODIFY_TAX_BASIS
          data_json TEXT -- Store the raw discount_data JSON
        )`);
        logger.debug('Schema Init', 'Created discounts table.');
        await db.runAsync(`CREATE TABLE images (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          url TEXT,
          caption TEXT,
          type TEXT DEFAULT 'IMAGE', -- Keep track of object type
          data_json TEXT -- Store the raw image_data JSON
        )`);
        logger.debug('Schema Init', 'Created images table.');
        
        // --- Recreate Other Tables ---
        await db.runAsync(`CREATE TABLE merchant_info (
          id TEXT PRIMARY KEY NOT NULL,
          business_name TEXT,
          country TEXT,
          language_code TEXT,
          currency TEXT,
          status TEXT,
          main_location_id TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          logo_url TEXT,
          data TEXT
        )`);
        logger.debug('Schema Init', 'Created merchant_info table.');
        await db.runAsync(`CREATE TABLE locations (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT,
          merchant_id TEXT,
          address TEXT,
          timezone TEXT,
          phone_number TEXT,
          business_name TEXT,
          business_email TEXT,
          website_url TEXT,
          description TEXT,
          status TEXT,
          type TEXT,
          logo_url TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          data TEXT
        )`);
        logger.debug('Schema Init', 'Created locations table.');
        await db.runAsync(`CREATE TABLE sync_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          data TEXT
        )`);
        logger.debug('Schema Init', 'Created sync_logs table.');
        await db.runAsync(`CREATE TABLE db_version (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          version INTEGER NOT NULL,
          updated_at TEXT
        )`);
        await db.runAsync(`INSERT INTO db_version (id, version, updated_at) VALUES (1, ?, ?)`, DATABASE_VERSION, new Date().toISOString());
        logger.debug('Schema Init', 'Created db_version table.');
        
        logger.info('Schema Init', 'All tables created successfully.');
      } catch (createError) {
        logger.error('Schema Init', 'Error creating tables', { createError });
        throw createError;
      }

      logger.info('Schema Init', 'Creating indexes...');
      try {
        // --- Create Indexes --- 
        // Catalog Items
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_name ON catalog_items (name)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_category_id ON catalog_items (category_id)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_deleted ON catalog_items (is_deleted)');
        // Variations
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_item_id ON item_variations (item_id)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_sku ON item_variations (sku)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_deleted ON item_variations (is_deleted)');
        // Categories
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_categories_name ON categories (name)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_categories_deleted ON categories (is_deleted)');
        // Modifiers
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifiers_list_id ON modifiers (modifier_list_id)');
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifiers_deleted ON modifiers (is_deleted)');
        // Modifier Lists
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifier_lists_deleted ON modifier_lists (is_deleted)');
        // Taxes
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_taxes_deleted ON taxes (is_deleted)');
        // Discounts
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_discounts_deleted ON discounts (is_deleted)');
        // Images
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_images_deleted ON images (is_deleted)');
        // Locations
        await db.runAsync('CREATE INDEX IF NOT EXISTS idx_locations_merchant_id ON locations (merchant_id)');
        
        logger.info('Schema Init', 'Indexes created successfully.');
      } catch (indexError) {
        logger.error('Schema Init', 'Error creating indexes', { indexError });
        throw indexError;
      }
      
      // Update the database version number
      // Embedding value as runAsync parameter passing seems problematic
      await db.runAsync(`UPDATE db_version SET version = ${DATABASE_VERSION} WHERE id = 1`);
      logger.info('Schema Init', `Database version updated to ${DATABASE_VERSION}. Schema update transaction committed.`);
    });
  } else {
    logger.info('Database', 'Schema is up-to-date.');
  }
  
  // Enable foreign keys after initialization
  try {
    await db.runAsync('PRAGMA foreign_keys = ON;'); 
    logger.info('Database', 'Foreign key support enabled.');
  } catch (fkError) {
    logger.error('Database', 'Failed to enable foreign keys', { fkError });
    // Decide if this is critical; maybe throw?
  }

  logger.info('Database', 'Schema initialization completed.');
}

/**
 * Reset the database by recreating all tables according to the latest schema.
 */
export async function resetDatabase(): Promise<void> {
  logger.info('Database', 'Resetting database...');
  const db = await getDatabase();

  // Create tables in a transaction for atomicity
  await db.withTransactionAsync(async () => {
    logger.info('Database Reset', 'Starting transaction...'); // Log transaction start
    
    logger.info('Database Reset', 'Dropping existing tables...');
    try {
      await db.runAsync('DROP TABLE IF EXISTS sync_status');
      await db.runAsync('DROP TABLE IF EXISTS categories');
      await db.runAsync('DROP TABLE IF EXISTS catalog_items');
      await db.runAsync('DROP TABLE IF EXISTS item_variations');
      await db.runAsync('DROP TABLE IF EXISTS modifier_lists');
      await db.runAsync('DROP TABLE IF EXISTS modifiers');
      await db.runAsync('DROP TABLE IF EXISTS taxes');
      await db.runAsync('DROP TABLE IF EXISTS discounts');
      await db.runAsync('DROP TABLE IF EXISTS images');
      await db.runAsync('DROP TABLE IF EXISTS merchant_info');
      await db.runAsync('DROP TABLE IF EXISTS locations');
      await db.runAsync('DROP TABLE IF EXISTS sync_logs');
      await db.runAsync('DROP TABLE IF EXISTS db_version');
      logger.info('Database Reset', 'Existing tables dropped successfully.');
    } catch (dropError) {
      logger.error('Database Reset', 'Error dropping tables', { dropError });
      throw dropError; // Ensure transaction rolls back on drop error
    }

    logger.info('Database Reset', 'Creating new tables...');
    try {
      // Create sync_status table
      await db.runAsync(`CREATE TABLE sync_status (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          last_sync_time TEXT,
          is_syncing INTEGER NOT NULL DEFAULT 0,
          sync_error TEXT,
          sync_progress INTEGER NOT NULL DEFAULT 0,
          sync_total INTEGER NOT NULL DEFAULT 0, -- Consider removing if progress is page-based
          sync_type TEXT, -- e.g., 'full', 'delta'
          last_page_cursor TEXT, -- Store cursor for resuming
          last_sync_attempt TEXT,
          sync_attempt_count INTEGER NOT NULL DEFAULT 0,
          last_incremental_sync_cursor TEXT
        )`);
      await db.runAsync(`INSERT INTO sync_status (id) VALUES (1)`);
      logger.debug('Database Reset', 'Created sync_status table.');
      
      // Create categories table
      await db.runAsync(`CREATE TABLE categories (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL, -- Store as TEXT since it can be large number string
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          data_json TEXT -- Store the raw category_data JSON
        )`);
      logger.debug('Database Reset', 'Created categories table.');
      await db.runAsync(`CREATE TABLE catalog_items (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          present_at_all_locations INTEGER DEFAULT 1,
          name TEXT,
          description TEXT,
          category_id TEXT, -- Reference categories table
          data_json TEXT -- Store the raw item_data JSON
        )`);
      logger.debug('Database Reset', 'Created catalog_items table.');
      await db.runAsync(`CREATE TABLE item_variations (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          item_id TEXT NOT NULL, -- Reference items table
          name TEXT,
          sku TEXT,
          pricing_type TEXT,
          price_amount INTEGER, -- Store amount in cents/smallest unit
          price_currency TEXT,
          data_json TEXT -- Store the raw item_variation_data JSON
        )`);
      logger.debug('Database Reset', 'Created item_variations table.');
      await db.runAsync(`CREATE TABLE modifier_lists (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          selection_type TEXT, -- SINGLE or MULTIPLE
          data_json TEXT -- Store the raw modifier_list_data JSON
        )`);
      logger.debug('Database Reset', 'Created modifier_lists table.');
      await db.runAsync(`CREATE TABLE modifiers (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          modifier_list_id TEXT NOT NULL, -- Reference modifier_lists table
          name TEXT,
          price_amount INTEGER,
          price_currency TEXT,
          ordinal INTEGER,
          data_json TEXT -- Store the raw modifier_data JSON
        )`);
      logger.debug('Database Reset', 'Created modifiers table.');
      await db.runAsync(`CREATE TABLE taxes (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          calculation_phase TEXT, -- SUBTOTAL_PHASE, TOTAL_PHASE
          inclusion_type TEXT, -- ADDITIVE, INCLUSIVE
          percentage TEXT, -- Store as string as it can be like "7.25"
          applies_to_custom_amounts INTEGER,
          enabled INTEGER,
          data_json TEXT -- Store the raw tax_data JSON
        )`);
      logger.debug('Database Reset', 'Created taxes table.');
      await db.runAsync(`CREATE TABLE discounts (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          discount_type TEXT, -- FIXED_PERCENTAGE, FIXED_AMOUNT, VARIABLE_PERCENTAGE, VARIABLE_AMOUNT
          percentage TEXT,
          amount INTEGER,
          currency TEXT,
          pin_required INTEGER,
          label_color TEXT,
          modify_tax_basis TEXT, -- MODIFY_TAX_BASIS, DO_NOT_MODIFY_TAX_BASIS
          data_json TEXT -- Store the raw discount_data JSON
        )`);
      logger.debug('Database Reset', 'Created discounts table.');
      await db.runAsync(`CREATE TABLE images (
          id TEXT PRIMARY KEY NOT NULL,
          updated_at TEXT NOT NULL,
          version TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          name TEXT,
          url TEXT,
          caption TEXT,
          type TEXT DEFAULT 'IMAGE', -- Keep track of object type
          data_json TEXT -- Store the raw image_data JSON
        )`);
      logger.debug('Database Reset', 'Created images table.');
      
      // --- Recreate Other Tables ---
      await db.runAsync(`CREATE TABLE merchant_info (
          id TEXT PRIMARY KEY NOT NULL,
          business_name TEXT,
          country TEXT,
          language_code TEXT,
          currency TEXT,
          status TEXT,
          main_location_id TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          logo_url TEXT,
          data TEXT
        )`);
      logger.debug('Database Reset', 'Created merchant_info table.');
      await db.runAsync(`CREATE TABLE locations (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT,
          merchant_id TEXT,
          address TEXT,
          timezone TEXT,
          phone_number TEXT,
          business_name TEXT,
          business_email TEXT,
          website_url TEXT,
          description TEXT,
          status TEXT,
          type TEXT,
          logo_url TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          data TEXT
        )`);
      logger.debug('Database Reset', 'Created locations table.');
      await db.runAsync(`CREATE TABLE sync_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          data TEXT
        )`);
      logger.debug('Database Reset', 'Created sync_logs table.');
      await db.runAsync(`CREATE TABLE db_version (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          version INTEGER NOT NULL,
          updated_at TEXT
        )`);
      await db.runAsync(`INSERT INTO db_version (id, version, updated_at) VALUES (1, ?, ?)`, DATABASE_VERSION, new Date().toISOString());
      logger.debug('Database Reset', 'Created db_version table.');
      
      logger.info('Database Reset', 'All tables created successfully.');

    } catch (createError) {
      logger.error('Database Reset', 'Error creating tables', { createError });
      throw createError; // Ensure transaction rolls back on create error
    }
    
    logger.info('Database Reset', 'Creating indexes...');
    try {
      // --- Create Indexes --- 
      // Catalog Items
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_name ON catalog_items (name)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_category_id ON catalog_items (category_id)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_items_deleted ON catalog_items (is_deleted)');
      // Variations
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_item_id ON item_variations (item_id)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_sku ON item_variations (sku)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_variations_deleted ON item_variations (is_deleted)');
      // Categories
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_categories_name ON categories (name)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_categories_deleted ON categories (is_deleted)');
      // Modifiers
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifiers_list_id ON modifiers (modifier_list_id)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifiers_deleted ON modifiers (is_deleted)');
      // Modifier Lists
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_modifier_lists_deleted ON modifier_lists (is_deleted)');
      // Taxes
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_taxes_deleted ON taxes (is_deleted)');
      // Discounts
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_discounts_deleted ON discounts (is_deleted)');
      // Images
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_images_deleted ON images (is_deleted)');
      // Locations
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_locations_merchant_id ON locations (merchant_id)');
      
      logger.info('Database Reset', 'Indexes created successfully.');
    } catch (indexError) {
       logger.error('Database Reset', 'Error creating indexes', { indexError });
      throw indexError; // Ensure transaction rolls back on index error
    }
  });
  logger.info('Database', 'Database reset completed.');
}

/**
 * Close the database connection
 */
export async function closeDatabase(): Promise<void> {
  try {
    if (db) {
      await db.closeAsync();
      db = null;
      logger.info('Database', 'Database closed successfully');
    }
  } catch (error) {
    logger.error('Database', 'Failed to close database', { error });
    throw new Error(`Failed to close database: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Gets the database instance, initializing it if needed
 */
export async function getDatabase(): Promise<SQLiteDatabase> {
  if (!db) {
    logger.warn('Database', 'Database accessed before initialization. Initializing now...');
    return await initDatabase();
  }
  return db;
}

/**
 * Upserts catalog objects into the database.
 * Takes an array of objects from the API.
 */
export async function upsertCatalogObjects(objects: CatalogObjectFromApi[]): Promise<void> {
  if (!objects || objects.length === 0) {
    return;
  }
  const db = await getDatabase();

  // Prepare statements for different object types (improves performance)
  // We will store the main identifying fields and the raw JSON data
  const statements = {
    ITEM: await db.prepareAsync(
      `INSERT OR REPLACE INTO catalog_items (id, updated_at, version, is_deleted, present_at_all_locations, name, description, category_id, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    CATEGORY: await db.prepareAsync(
      `INSERT OR REPLACE INTO categories (id, updated_at, version, is_deleted, name, data_json) 
       VALUES (?, ?, ?, ?, ?, ?)`
    ),
    ITEM_VARIATION: await db.prepareAsync(
      `INSERT OR REPLACE INTO item_variations (id, updated_at, version, is_deleted, item_id, name, sku, pricing_type, price_amount, price_currency, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    MODIFIER_LIST: await db.prepareAsync(
      `INSERT OR REPLACE INTO modifier_lists (id, updated_at, version, is_deleted, name, selection_type, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ),
    MODIFIER: await db.prepareAsync(
      `INSERT OR REPLACE INTO modifiers (id, updated_at, version, is_deleted, modifier_list_id, name, price_amount, price_currency, ordinal, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    TAX: await db.prepareAsync(
      `INSERT OR REPLACE INTO taxes (id, updated_at, version, is_deleted, name, calculation_phase, inclusion_type, percentage, applies_to_custom_amounts, enabled, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    DISCOUNT: await db.prepareAsync(
      `INSERT OR REPLACE INTO discounts (id, updated_at, version, is_deleted, name, discount_type, percentage, amount, currency, pin_required, label_color, modify_tax_basis, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    IMAGE: await db.prepareAsync(
      `INSERT OR REPLACE INTO images (id, updated_at, version, is_deleted, name, url, caption, type, data_json) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
  };

  try {
    await db.withTransactionAsync(async () => {
      for (const obj of objects) {
        const versionStr = String(obj.version); // Ensure version is string
        const isDeleted = obj.is_deleted ? 1 : 0;
        const dataJson = JSON.stringify(obj); // Store the whole object

        // ---- REMOVE TEMPORARY DEBUG LOGGING ----
        /*
        const targetId = 'VMQX2FPCHRX6N5KT2KVKIQ23';
        if (obj.id === targetId) {
          // Log basic info when the target ID is processed
          logger.warn('Database', `*** Processing upsert for target ID ${targetId} ***`, { objectType: obj.type, isDeleted: isDeleted });
        }
        */
        // ---- END REMOVED TEMPORARY DEBUG LOGGING ----

        switch (obj.type) {
          case 'ITEM':
            // First, insert the main item data
            await statements.ITEM.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.present_at_all_locations ? 1 : 0,
              obj.item_data?.name,
              obj.item_data?.description,
              obj.item_data?.category_id,
              dataJson // Store the full original object JSON for the item row
            );
            
            // **NEW: Process nested variations for this item**
            if (obj.item_data?.variations && Array.isArray(obj.item_data.variations)) {
              for (const variation of obj.item_data.variations) {
                // Ensure variation has necessary data and type
                if (variation && variation.type === 'ITEM_VARIATION' && variation.item_variation_data) {
                  const variationVersionStr = String(variation.version);
                  const variationIsDeleted = variation.is_deleted ? 1 : 0;
                  // Store the full original variation object JSON for the variation row
                  const variationDataJson = JSON.stringify(variation);
                  
                  // Use the ITEM_VARIATION prepared statement
                  try {
                    // Log parameters BEFORE attempting execution
                    logger.debug('Database::Upsert::Variation', 'Attempting variation insert', {
                      variationId: variation.id,
                      itemId: obj.id, // Explicitly use parent item ID
                      updated_at: variation.updated_at,
                      version: variationVersionStr,
                      isDeleted: variationIsDeleted,
                      name: variation.item_variation_data.name,
                      sku: variation.item_variation_data.sku,
                      pricing_type: variation.item_variation_data.pricing_type,
                      price_amount: variation.item_variation_data.price_money?.amount,
                      price_currency: variation.item_variation_data.price_money?.currency,
                      dataJsonLength: variationDataJson.length
                    });
                    
                     await statements.ITEM_VARIATION.executeAsync(
                      variation.id,                         // PK
                      variation.updated_at,
                      variationVersionStr,
                      variationIsDeleted,
                      obj.id,                               // FK - Explicitly use parent obj.id
                      variation.item_variation_data.name,
                      variation.item_variation_data.sku,
                      variation.item_variation_data.pricing_type,
                      variation.item_variation_data.price_money?.amount,
                      variation.item_variation_data.price_money?.currency,
                      variationDataJson                   // Full variation JSON
                    );
                  } catch (nestedVariationError) {
                     const errorMsg = nestedVariationError instanceof Error ? nestedVariationError.message : String(nestedVariationError);
                     logger.error('Database', 'Failed to insert/update nested ITEM_VARIATION', { 
                        variationId: variation.id, 
                        itemId: obj.id, 
                        error: errorMsg,
                        // Log all parameters attempted for insert
                        attemptedParams: {
                          id: variation.id,
                          updated_at: variation.updated_at,
                          version: variationVersionStr,
                          isDeleted: variationIsDeleted,
                          item_id: obj.id,
                          name: variation.item_variation_data.name,
                          sku: variation.item_variation_data.sku,
                          pricing_type: variation.item_variation_data.pricing_type,
                          price_amount: variation.item_variation_data.price_money?.amount,
                          price_currency: variation.item_variation_data.price_money?.currency,
                          dataJsonLength: variationDataJson.length
                        },
                        variationObject: variationDataJson // Log the variation JSON
                     });
                     // Decide if we should throw/rollback the whole transaction or continue
                     // For now, we log and continue to try and save other variations/items
                  }
                }
              }
            }
            break;
          case 'CATEGORY':
            await statements.CATEGORY.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.category_data?.name,
              dataJson
            );
            break;
          case 'ITEM_VARIATION':
            // Wrap the execution in a try/catch to isolate variation errors
            try {
              // DEBUG: Log variation data before inserting, especially for the problematic UPC
              if (obj.item_variation_data?.upc === '827680191749') {
                logger.debug('Database::Upsert', '[Debug] Inserting variation with target UPC', { 
                  variationId: obj.id, 
                  itemId: obj.item_variation_data?.item_id,
                  sku: obj.item_variation_data?.sku,
                  upc: obj.item_variation_data?.upc,
                  data_json_to_insert: dataJson // Log the full JSON string being inserted
                });
              }
              await statements.ITEM_VARIATION.executeAsync(
                obj.id,
                obj.updated_at,
                versionStr,
                isDeleted,
                obj.item_variation_data?.item_id,
                obj.item_variation_data?.name,
                obj.item_variation_data?.sku,
                obj.item_variation_data?.pricing_type,
                obj.item_variation_data?.price_money?.amount,
                obj.item_variation_data?.price_money?.currency,
                dataJson
              );
            } catch (variationError) {
              // Log the specific error and the variation that caused it
              logger.error('Database', 'Failed to insert/update ITEM_VARIATION', { 
                variationId: obj.id, 
                itemId: obj.item_variation_data?.item_id,
                error: variationError instanceof Error ? variationError.message : String(variationError),
                variationObject: JSON.stringify(obj) // Log the problematic object
              });
              // NOTE: For debugging, we are NOT re-throwing here. In production,
              // you might want to re-throw to ensure transaction integrity.
              // throw variationError;
            }
            break;
          case 'MODIFIER_LIST':
            await statements.MODIFIER_LIST.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.modifier_list_data?.name,
              obj.modifier_list_data?.selection_type,
              dataJson
            );
            break;
          case 'MODIFIER':
            await statements.MODIFIER.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.modifier_data?.modifier_list_id,
              obj.modifier_data?.name,
              obj.modifier_data?.price_money?.amount,
              obj.modifier_data?.price_money?.currency,
              obj.modifier_data?.ordinal,
              dataJson
            );
            break;
          case 'TAX':
            await statements.TAX.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.tax_data?.name,
              obj.tax_data?.calculation_phase,
              obj.tax_data?.inclusion_type,
              obj.tax_data?.percentage,
              obj.tax_data?.applies_to_custom_amounts ? 1 : 0,
              obj.tax_data?.enabled ? 1 : 0,
              dataJson
            );
            break;
          case 'DISCOUNT':
            await statements.DISCOUNT.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.discount_data?.name,
              obj.discount_data?.discount_type,
              obj.discount_data?.percentage,
              obj.discount_data?.amount_money?.amount,
              obj.discount_data?.amount_money?.currency,
              obj.discount_data?.pin_required ? 1 : 0,
              obj.discount_data?.label_color,
              obj.discount_data?.modify_tax_basis,
              dataJson
            );
            break;
          case 'IMAGE':
             await statements.IMAGE.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.image_data?.name,
              obj.image_data?.url,
              obj.image_data?.caption,
              obj.type, // Store IMAGE type
              dataJson
            );
            break;
          default:
            // Log unsupported type? Or ignore?
             logger.warn('Database', `Unsupported catalog object type encountered: ${obj.type}`, { id: obj.id });
            break;
        }
      }
    });
  } catch (error) {
     logger.error('Database', 'Error during catalog object upsert transaction', { error });
     throw error; // Re-throw to allow calling function to handle
  } finally {
    // Finalize prepared statements
    await Promise.all(Object.values(statements).map(stmt => stmt.finalizeAsync()));
  }
}

/**
 * Clears all catalog-related tables.
 */
export async function clearCatalogData(): Promise<void> {
  logger.info('Database', 'Clearing all catalog data...');
  const db = await getDatabase();
  await db.withTransactionAsync(async () => {
    await db.runAsync('DELETE FROM categories');
    await db.runAsync('DELETE FROM catalog_items');
    await db.runAsync('DELETE FROM item_variations');
    await db.runAsync('DELETE FROM modifier_lists');
    await db.runAsync('DELETE FROM modifiers');
    await db.runAsync('DELETE FROM taxes');
    await db.runAsync('DELETE FROM discounts');
    await db.runAsync('DELETE FROM images');
    // Optionally reset sync status related to catalog
    await db.runAsync('UPDATE sync_status SET last_sync_time = NULL, last_page_cursor = NULL WHERE id = 1');
  });
   logger.info('Database', 'Catalog data cleared.');
}

/**
 * Fetches the current sync status from the database.
 */
export async function getSyncStatus(): Promise<any> { // Replace 'any' with a specific SyncStatus type
  const db = await getDatabase();
  const status = await db.getFirstAsync('SELECT * FROM sync_status WHERE id = 1');
  return status;
}

/**
 * Updates specific fields in the sync status table.
 */
export async function updateSyncStatus(updates: Partial<{ /* Define SyncStatus type here */ }>): Promise<void> {
  const db = await getDatabase();
  const fields = Object.keys(updates);
  const values = Object.values(updates);
  
  if (fields.length === 0) return;
  
  const setClause = fields.map(field => `${field} = ?`).join(', ');
  const sql = `UPDATE sync_status SET ${setClause} WHERE id = 1`;
  
  // Cast values to the expected type
  await db.runAsync(sql, ...(values as SQLiteBindValue[]));
}

/**
 * Checks the content of the database for debugging.
 */
export async function checkDatabaseContent() {
  const db = await getDatabase();
  
  // Define expected row structure for counts
  type CountRow = { table_name: string; count: number };

  // Cast the result of the query to CountRow[]
  const counts = await db.getAllAsync<CountRow>(`
    SELECT 'categories' as table_name, COUNT(*) as count FROM categories
    UNION ALL
    SELECT 'catalog_items', COUNT(*) FROM catalog_items
    UNION ALL
    SELECT 'item_variations', COUNT(*) FROM item_variations
    UNION ALL
    SELECT 'modifier_lists', COUNT(*) FROM modifier_lists
    UNION ALL
    SELECT 'modifiers', COUNT(*) FROM modifiers
    UNION ALL
    SELECT 'taxes', COUNT(*) FROM taxes
    UNION ALL
    SELECT 'discounts', COUNT(*) FROM discounts
    UNION ALL
    SELECT 'images', COUNT(*) FROM images
    UNION ALL
    SELECT 'merchant', COUNT(*) FROM merchant_info
    UNION ALL
    SELECT 'locations', COUNT(*) FROM locations
  `);

  const samples = {
    // Cast sample results as well if needed, or use specific queries
    categories: await db.getAllAsync<{id: string, name: string}>('SELECT id, name FROM categories LIMIT 5'),
    items: await db.getAllAsync<{id: string, name: string}>('SELECT id, name FROM catalog_items LIMIT 5'),
    variations: await db.getAllAsync<{id: string, name: string, item_id: string}>('SELECT id, name, item_id FROM item_variations LIMIT 5'),
    // Add samples for other tables if needed
  };
  
  // The return type here should reflect the structure including CountRow
  return { counts: counts || [], samples }; // Ensure counts is always an array
}

/**
 * Searches local catalog items and variations for a given query term.
 * Performs a case-insensitive search across name, SKU, and GTIN (UPC).
 * @param query The search term.
 * @returns A promise resolving to an array of matching ConvertedItem objects.
 */
export async function searchLocalItems(query: string): Promise<ConvertedItem[]> {
  const db = await getDatabase();
  const searchTerm = `%${query}%`; // Prepare for LIKE query
  const exactQuery = query; // Keep original query for exact UPC match
  logger.info('Database', 'Searching local catalog', { query });

  try {
    // Broad SQL Query: Fetch if name, SKU, OR the variation JSON string matches
    // Using LIKE on data_json is a broad filter to ensure rows with potential UPC matches are included
    const results = await db.getAllAsync<any>(`
      SELECT 
        ci.id as item_id, 
        ci.data_json as item_data_json, 
        iv.data_json as variation_data_json, 
        iv.id as variation_id, /* Also fetch variation ID */
        ci.updated_at as item_updated_at
      FROM catalog_items ci
      JOIN item_variations iv ON ci.id = iv.item_id
      WHERE ci.is_deleted = 0 AND iv.is_deleted = 0
      AND (
        ci.name LIKE ? COLLATE NOCASE OR
        iv.sku LIKE ? COLLATE NOCASE OR
        iv.data_json LIKE ? /* Broad check for UPC within JSON */
      )
      ORDER BY ci.name COLLATE NOCASE ASC
    `, [searchTerm, searchTerm, searchTerm]); // Need searchTerm three times

    logger.debug('Database', `Local SQL search (name/sku/json) found ${results.length} potential matches`);

    // Refined TypeScript Filtering: Check name, SKU, and exact UPC
    const filteredResults = results.filter(row => {
      try {
        const itemData = JSON.parse(row.item_data_json || '{}');
        const variationData = JSON.parse(row.variation_data_json || '{}');
        
        // Check Name (case-insensitive contains)
        if (itemData.item_data?.name?.toLowerCase().includes(exactQuery.toLowerCase())) {
          return true; 
        }
        
        // Check SKU (case-insensitive contains)
        if (variationData.item_variation_data?.sku?.toLowerCase().includes(exactQuery.toLowerCase())) {
          return true; 
        }
        
        // Check UPC (exact match)
        const upc = variationData.item_variation_data?.upc;
        if (upc && upc === exactQuery) {
          logger.debug('Database', 'Found exact match via UPC check in code', { variationId: row.variation_id, upc });
          return true; 
        }
        
      } catch (parseError) {
        logger.error('Database', 'Error parsing JSON during filtering', { variationId: row.variation_id, error: parseError });
        return false; // Exclude if JSON parsing fails
      }
      return false; // Exclude if no fields matched
    });
    
    logger.debug('Database', `Filtered to ${filteredResults.length} matches after filtering`);

    // --- Transformation Logic (using filteredResults) --- 
    const transformedItemsMap = new Map<string, ConvertedItem>();

    // Loop through FILTERED results and transform
    for (const row of filteredResults) {
      try {
        const itemData = JSON.parse(row.item_data_json || '{}');
        const variationData = JSON.parse(row.variation_data_json || '{}');
        
        // --- Start: Determine CRV Type --- 
        let crvType: 'CRV5' | 'CRV10' | undefined = undefined;
        const modifierListInfo = itemData?.item_data?.modifier_list_info;
        
        // Check if modifier info exists and has IDs
        if (modifierListInfo && Array.isArray(modifierListInfo) && modifierListInfo.length > 0) {
          const modifierListIds = modifierListInfo
            .map((info: any) => info?.modifier_list_id)
            .filter((id: any): id is string => typeof id === 'string'); 

          if (modifierListIds.length > 0) {
            try {
              const placeholders = modifierListIds.map(() => '?').join(',');
              const modifierLists = await db.getAllAsync<{ name: string }>(
                `SELECT name FROM modifier_lists WHERE id IN (${placeholders})`,
                modifierListIds
              );

              // Check names for CRV types
              for (const list of modifierLists) {
                if (list.name === "Modifier Set - CRV10 >24oz") {
                  crvType = 'CRV10';
                  break; // Found CRV10, prioritize it
                }
                if (list.name === "Modifier Set - CRV5 <24oz") {
                  crvType = 'CRV5';
                }
              }
            } catch (dbError) {
              logger.error('Database', 'Error querying modifier_lists during search', { itemId: row.item_id, modifierListIds, error: dbError });
            }
          }
        }
        // --- End: Determine CRV Type ---
        
        // Reconstruct a partial CatalogObject structure for the transformer
        const reconstructedCatalogObject: Partial<CatalogObjectFromApi> & { id: string } = {
          id: row.item_id,
          type: 'ITEM',
          updated_at: row.item_updated_at,
          version: itemData.version || '0', 
          is_deleted: false,
          item_data: {
            // Spread the original item_data properties from the parsed item JSON
            ...(itemData.item_data || {}),
            // Ensure tax_ids are carried over if they exist at the item_data level
            tax_ids: itemData?.item_data?.tax_ids || [], 
            variations: [{ // Create the variation object structure
              id: variationData.id, 
              type: 'ITEM_VARIATION',
              updated_at: variationData.updated_at, // Need variation updated_at
              version: variationData.version, // Need variation version
              // Correctly nest the variation-specific data
              item_variation_data: variationData.item_variation_data || {}
            }]
          }
        };

        // Log the object being passed to the transformer
        logger.debug('Database::searchLocalItems', 'Reconstructed object for transformer:', { 
            itemId: reconstructedCatalogObject.id, 
            // Log specific parts to avoid overly large logs, or stringify if necessary
            itemDataName: reconstructedCatalogObject.item_data?.name,
            variationId: reconstructedCatalogObject.item_data?.variations?.[0]?.id,
            variationSku: reconstructedCatalogObject.item_data?.variations?.[0]?.item_variation_data?.sku,
            variationUpc: reconstructedCatalogObject.item_data?.variations?.[0]?.item_variation_data?.upc,
            taxIds: reconstructedCatalogObject.item_data?.tax_ids,
            crvType 
        });

        // Pass crvType to the transformer
        const transformed = transformCatalogItemToItem(reconstructedCatalogObject as any);

        // Log the result from the transformer
        logger.debug('Database::searchLocalItems', 'Transformed item result:', transformed); 
        
        if (transformed && !transformedItemsMap.has(transformed.id)) {
           transformedItemsMap.set(transformed.id, transformed);
        }
      } catch (parseError) {
        logger.error('Database', 'Failed to parse or transform local search result row', { 
          itemId: row.item_id, 
          error: parseError 
        });
      }
    }
    
    const uniqueItems = Array.from(transformedItemsMap.values());
    logger.info('Database', `Local search returning ${uniqueItems.length} unique items after transformation`);
    return uniqueItems;

  } catch (error) {
    logger.error('Database', 'Failed to execute local item search', { error, query });
    return []; // Return empty array on error
  }
}

/**
 * Fetches the raw data for the first 10 rows from the catalog_items table.
 * Useful for debugging purposes.
 */
export async function getFirstTenItemsRaw(): Promise<any[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching first 10 raw catalog items for inspection');
  try {
    // Fetching all columns to see the raw structure
    const results = await db.getAllAsync<any>(`
      SELECT * 
      FROM catalog_items 
      WHERE is_deleted = 0
      LIMIT 10
    `);
    logger.info('Database', `Fetched ${results.length} raw items`);
    return results;
  } catch (error) {
    logger.error('Database', 'Failed to fetch raw items for inspection', { error });
    throw error; // Re-throw the error to be caught by the caller
  }
}

/**
 * Fetches the raw row data for a specific item or variation by its ID.
 * @param id The ID of the item or variation.
 * @returns A promise resolving to the raw row data or null if not found.
 */
export async function getItemOrVariationRawById(id: string): Promise<any | null> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching raw item/variation by ID', { id });
  try {
    // Try finding in catalog_items first
    let result = await db.getFirstAsync<any>(
      `SELECT *, 'item' as found_in FROM catalog_items WHERE id = ?`,
      [id]
    );

    if (result) {
      logger.info('Database', 'Found item by ID', { id });
      return result;
    }

    // If not found in items, try variations
    result = await db.getFirstAsync<any>(
      `SELECT *, 'variation' as found_in FROM item_variations WHERE id = ?`,
      [id]
    );

    if (result) {
      logger.info('Database', 'Found variation by ID', { id });
      return result;
    } 

    logger.warn('Database', 'Item/variation not found by ID', { id });
    return null; // Not found in either table

  } catch (error) {
    logger.error('Database', 'Failed to fetch item/variation by ID', { id, error });
    throw error; // Re-throw error
  }
}

/**
 * Fetches the raw data for the first 10 rows from the item_variations table.
 * Useful for debugging purposes.
 */
export async function getFirstTenVariationsRaw(): Promise<any[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching first 10 raw item variations for inspection');
  try {
    // Fetching all columns to see the raw structure
    const results = await db.getAllAsync<any>(`
      SELECT * 
      FROM item_variations 
      WHERE is_deleted = 0
      LIMIT 10
    `);
    logger.info('Database', `Fetched ${results.length} raw variations`);
    return results;
  } catch (error) {
    logger.error('Database', 'Failed to fetch raw variations for inspection', { error });
    throw error; // Re-throw the error to be caught by the caller
  }
}

/**
 * Fetches all categories (ID and Name) from the database.
 * @returns A promise resolving to an array of categories { id: string, name: string }.
 */
export async function getAllCategories(): Promise<{ id: string; name: string }[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching all categories');
  try {
    const results = await db.getAllAsync<{ id: string; name: string }>(`
      SELECT id, name 
      FROM categories 
      WHERE is_deleted = 0 
      ORDER BY name ASC
    `);
    logger.info('Database', `Fetched ${results.length} categories`);
    return results || []; // Ensure we return an empty array if null/undefined
  } catch (error) {
    logger.error('Database', 'Failed to fetch categories', { error });
    throw error; // Re-throw the error
  }
}

/**
 * Fetches all non-deleted taxes (ID, Name, and Percentage) from the database.
 * @returns A promise resolving to an array of taxes { id: string, name: string, percentage: string | null }.
 */
export async function getAllTaxes(): Promise<{ id: string; name: string; percentage: string | null }[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching all taxes with percentages');
  try {
    // Fetch id, name, and the full data_json
    const results = await db.getAllAsync<{ id: string; name: string; data_json: string }>(`
      SELECT id, name, data_json 
      FROM taxes 
      WHERE is_deleted = 0 AND enabled = 1
      ORDER BY name ASC
    `);
    logger.info('Database', `Fetched ${results.length} enabled taxes`);

    // Parse the JSON and extract the percentage
    const taxesWithPercentage = results.map(tax => {
      let percentage: string | null = null;
      try {
        if (tax.data_json) {
          const taxData = JSON.parse(tax.data_json);
          // Access percentage within the nested tax_data object
          percentage = taxData?.tax_data?.percentage || null; 
        }
      } catch (parseError) {
        logger.error('Database::getAllTaxes', 'Failed to parse tax_data JSON', { taxId: tax.id, error: parseError });
      }
      return { id: tax.id, name: tax.name, percentage };
    });

    return taxesWithPercentage || [];
  } catch (error) {
    logger.error('Database', 'Failed to fetch taxes', { error });
    throw error;
  }
}

/**
 * Fetches all non-deleted modifier lists (ID and Name) from the database.
 * @returns A promise resolving to an array of modifier lists { id: string, name: string }.
 */
export async function getAllModifierLists(): Promise<{ id: string; name: string }[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching all modifier lists');
  try {
    const results = await db.getAllAsync<{ id: string; name: string }>(`
      SELECT id, name 
      FROM modifier_lists 
      WHERE is_deleted = 0
      ORDER BY name ASC
    `);
    logger.info('Database', `Fetched ${results.length} modifier lists`);
    return results || [];
  } catch (error) {
    logger.error('Database', 'Failed to fetch modifier lists', { error });
    throw error;
  }
}

/**
 * Ensure the locations table exists and has default data
 */
export async function ensureLocationsTable(): Promise<void> {
  try {
    const db = await getDatabase();
    logger.info('Database', 'Ensuring locations table exists and has data');
    
    // Create the locations table directly with "IF NOT EXISTS" instead of checking first
    await db.runAsync(`CREATE TABLE IF NOT EXISTS locations (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT,
      merchant_id TEXT,
      address TEXT,
      timezone TEXT,
      phone_number TEXT,
      business_name TEXT,
      business_email TEXT,
      website_url TEXT,
      description TEXT,
      status TEXT,
      type TEXT,
      logo_url TEXT,
      created_at TEXT,
      last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      data TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )`);
    
    // Create index on merchant_id (also using IF NOT EXISTS)
    await db.runAsync('CREATE INDEX IF NOT EXISTS idx_locations_merchant_id ON locations (merchant_id)');
    
    logger.info('Database', 'Successfully ensured locations table exists');
  } catch (error) {
    logger.error('Database', 'Error ensuring locations table', { error });
    throw error;
  }
}

/**
 * Fetches all locations (ID and Name) from the database.
 * @returns A promise resolving to an array of locations { id: string, name: string }.
 */
export async function getAllLocations(): Promise<{ id: string; name: string }[]> {
  const db = await getDatabase();
  logger.info('Database', 'Fetching all locations');
  
  try {
    // First ensure the locations table exists
    await ensureLocationsTable();
    
    // Now try to fetch locations
    const results = await db.getAllAsync<{ id: string; name: string }>(`
      SELECT id, name 
      FROM locations 
      WHERE is_deleted = 0 
      ORDER BY name ASC
    `);
    
    logger.info('Database', `Fetched ${results.length} locations`);
    return results;
  } catch (error) {
    logger.error('Database', 'Error fetching locations', { error });
    // Return empty array instead of fallbacks
    return [];
  }
}

// Export default object with all methods
export default {
  initDatabase,
  resetDatabase,
  closeDatabase,
  getDatabase,
  upsertCatalogObjects,
  clearCatalogData,
  getSyncStatus,
  updateSyncStatus,
  checkDatabaseContent,
  getFirstTenItemsRaw,
  getItemOrVariationRawById,
  getFirstTenVariationsRaw,
  getAllCategories,
  getAllTaxes,
  getAllModifierLists,
  getAllLocations
}; 

// --- New Functions for Incremental Sync Cursor --- 

/**
 * Gets the cursor stored from the last successful incremental sync.
 */
export async function getLastIncrementalSyncCursor(): Promise<string | null> {
  try {
    const db = await getDatabase();
    // Use getFirstAsync which returns the first row or null
    const row = await db.getFirstAsync<{ last_incremental_sync_cursor: string | null }>(
      'SELECT last_incremental_sync_cursor FROM sync_status WHERE id = 1'
    );
    // Return the cursor value, which can be null if not set or row doesn't exist
    return row?.last_incremental_sync_cursor ?? null;
  } catch (error) {
    logger.error('Database', 'Error getting last incremental sync cursor', { error });
    // Decide on error handling: return null or throw? Returning null might be safer.
    return null;
  }
}

/**
 * Updates the cursor stored after a successful incremental sync.
 */
export async function updateLastIncrementalSyncCursor(cursor: string | null): Promise<void> {
  try {
    const db = await getDatabase();
    await db.runAsync(
      'UPDATE sync_status SET last_incremental_sync_cursor = ? WHERE id = 1',
      [cursor] // Pass cursor directly, it handles null correctly
    );
    logger.debug('Database', 'Updated last incremental sync cursor', { cursor });
  } catch (error) {
    logger.error('Database', 'Error updating last incremental sync cursor', { error, cursor });
    // Consider re-throwing or specific error handling if update fails
    throw error;
  }
}

// --- New Function for Deleting Objects ---

/**
 * Deletes a catalog object and its associated data (like variations) by ID.
 * Note: This currently targets items and variations. Extend if other types need specific deletion logic.
 */
export async function deleteCatalogObjectById(objectId: string): Promise<void> {
  if (!objectId) {
    logger.warn('Database', 'Attempted to delete object with null/empty ID');
    return;
  }
  
  logger.info('Database', 'Deleting catalog object by ID', { objectId });
  const db = await getDatabase();
  
  try {
    await db.withTransactionAsync(async () => {
      // Check if it's an item (and delete its variations first)
      const item = await db.getFirstAsync<{ id: string }>('SELECT id FROM catalog_items WHERE id = ?', [objectId]);
      if (item) {
        logger.debug('Database', 'Deleting variations for item', { objectId });
        await db.runAsync('DELETE FROM item_variations WHERE item_id = ?', [objectId]);
        logger.debug('Database', 'Deleting item itself', { objectId });
        await db.runAsync('DELETE FROM catalog_items WHERE id = ?', [objectId]);
        logger.info('Database', 'Successfully deleted item and its variations', { objectId });
        return; // Exit transaction early if item found and deleted
      }
      
      // Check if it's a variation (delete directly)
      const variation = await db.getFirstAsync<{ id: string }>('SELECT id FROM item_variations WHERE id = ?', [objectId]);
      if (variation) {
        logger.debug('Database', 'Deleting variation', { objectId });
        await db.runAsync('DELETE FROM item_variations WHERE id = ?', [objectId]);
        logger.info('Database', 'Successfully deleted variation', { objectId });
        return;
      }
      
      // Check if it's a category (delete directly)
      const category = await db.getFirstAsync<{ id: string }>('SELECT id FROM categories WHERE id = ?', [objectId]);
      if (category) {
        logger.debug('Database', 'Deleting category', { objectId });
        // Note: We might need to handle items associated with this category (set category_id to null?)
        // For now, just delete the category record.
        // await db.runAsync('UPDATE catalog_items SET category_id = NULL WHERE category_id = ?', [objectId]);
        await db.runAsync('DELETE FROM categories WHERE id = ?', [objectId]);
        logger.info('Database', 'Successfully deleted category', { objectId });
        return;
      }

      // TODO: Add checks and deletions for other types (Taxes, Modifiers, Discounts, Images) if they are stored in separate tables and need explicit deletion.
      // Example for Tax:
      // const tax = await db.getFirstAsync<{ id: string }>('SELECT id FROM taxes WHERE id = ?', [objectId]);
      // if (tax) {
      //   await db.runAsync('DELETE FROM taxes WHERE id = ?', [objectId]);
      //   logger.info('Database', 'Successfully deleted tax', { objectId });
      //   return;
      // }

      logger.warn('Database', 'Object ID not found in known deletable tables (item, variation, category)', { objectId });
      
    }); // End transaction
  } catch (error) {
    logger.error('Database', 'Error deleting catalog object by ID', { objectId, error });
    // Re-throw the error to be handled by the caller (e.g., the sync process)
    throw error;
  }
}

export interface SearchFilters {
  name: boolean;
  sku: boolean;
  barcode: boolean;
  category: boolean;
}

export interface RawSearchResult {
  id: string; // This will be the item ID
  data_json: string; // The data_json of the main catalog_item
  match_type: 'name' | 'sku' | 'barcode' | 'category';
  match_context: string; // e.g., the actual SKU value, category name, etc.
}

export async function searchCatalogItems(
  searchTerm: string,
  filters: SearchFilters
): Promise<RawSearchResult[]> {
  if (!searchTerm.trim()) {
    return [];
  }

  const db = await getDatabase();
  const likeTerm = `%${searchTerm}%`;
  const queries: string[] = [];
  const params: SQLiteBindValue[] = [];
  const resultsById: { [key: string]: RawSearchResult } = {};

  logger.debug('searchCatalogItems', 'Starting search', { searchTerm, filters });

  // 1. Search by Item Name
  if (filters.name) {
    const nameQuery = `
      SELECT
        ci.id,
        ci.data_json,
        'name' as match_type,
        ci.name as match_context
      FROM catalog_items ci
      WHERE ci.name LIKE ? AND ci.is_deleted = 0
    `;
    queries.push(nameQuery);
    params.push(likeTerm);
    logger.debug('searchCatalogItems', 'Added name query');
  }

  // 2. Search by SKU in Item Variations
  if (filters.sku) {
    const skuQuery = `
      SELECT
        iv.item_id as id,
        ci.data_json,
        'sku' as match_type,
        iv.sku as match_context
      FROM item_variations iv
      JOIN catalog_items ci ON iv.item_id = ci.id
      WHERE iv.sku LIKE ? AND iv.is_deleted = 0 AND ci.is_deleted = 0
    `;
    queries.push(skuQuery);
    params.push(likeTerm);
    logger.debug('searchCatalogItems', 'Added SKU query');
  }

  // 3. Search by Barcode (UPC) in Item Variations (data_json)
  if (filters.barcode) {
    // Note: json_extract might be slow on large datasets without specific indexing.
    // Square stores UPC in item_variation_data.upc
    const barcodeQuery = `
      SELECT
        iv.item_id as id,
        ci.data_json,
        'barcode' as match_type,
        json_extract(iv.data_json, '$.item_variation_data.upc') as match_context
      FROM item_variations iv
      JOIN catalog_items ci ON iv.item_id = ci.id
      WHERE json_extract(iv.data_json, '$.item_variation_data.upc') LIKE ?
        AND iv.is_deleted = 0 AND ci.is_deleted = 0
    `;
    // Make sure the path '$.item_variation_data.upc' is correct based on your JSON structure
    // For initial search, we assume it is. If no results, this might need adjustment or broader JSON search.
    queries.push(barcodeQuery);
    params.push(likeTerm);
    logger.debug('searchCatalogItems', 'Added barcode query');
  }

  // 4. Search by Category Name
  if (filters.category) {
    // First, find matching category IDs
    const matchingCategories = await db.getAllAsync<{ id: string }>(
      `SELECT id FROM categories WHERE name LIKE ? AND is_deleted = 0`,
      [likeTerm]
    );

    if (matchingCategories.length > 0) {
      const categoryIds = matchingCategories.map(c => c.id);
      const placeholders = categoryIds.map(() => '?').join(',');
      const categoryQuery = `
        SELECT
          ci.id,
          ci.data_json,
          'category' as match_type,
          cat.name as match_context
        FROM catalog_items ci
        JOIN categories cat ON ci.category_id = cat.id
        WHERE ci.category_id IN (${placeholders}) AND ci.is_deleted = 0
      `;
      queries.push(categoryQuery);
      params.push(...categoryIds);
      logger.debug('searchCatalogItems', 'Added category query for IDs:', { categoryIds });
    }
  }

  if (queries.length === 0) {
    logger.debug('searchCatalogItems', 'No active filters, returning empty results.');
    return [];
  }

  const fullQuery = queries.join('\nUNION\n') + '\nLIMIT 50;'; // Combine queries and limit results
  logger.debug('searchCatalogItems', 'Executing combined query', { query: fullQuery, params });

  try {
    const rawResults = await db.getAllAsync<RawSearchResult>(fullQuery, params);
    logger.debug('searchCatalogItems', `Raw query returned ${rawResults.length} results.`);

    // Deduplicate results, preferring the first encountered match for an item ID
    rawResults.forEach(row => {
      if (row && row.id && row.data_json) { // Ensure essential fields are present
        if (!resultsById[row.id]) {
          resultsById[row.id] = row;
        }
      } else {
        logger.warn('searchCatalogItems', 'Skipping invalid row from DB search', { row });
      }
    });
    
    const finalResults = Object.values(resultsById);
    logger.info('searchCatalogItems', `Search for '${searchTerm}' found ${finalResults.length} unique items.`);
    return finalResults;

  } catch (error) {
    logger.error('searchCatalogItems', 'Error executing search query', { error, query: fullQuery });
    throw error; // Re-throw to be handled by the calling hook
  }
} 