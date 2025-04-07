import { SQLiteDatabase, openDatabaseAsync, SQLiteBindValue } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system';
import logger from '../utils/logger';

// Constants
const DATABASE_NAME = 'joylabs.db';
const DATABASE_VERSION = 1; // Increment this when changing schema
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
          sync_attempt_count INTEGER NOT NULL DEFAULT 0
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
      
      // Update version number after successful creation/migration
      await db.runAsync('UPDATE db_version SET version = ?, updated_at = ? WHERE id = 1', DATABASE_VERSION, new Date().toISOString());
      logger.info('Database', `Schema updated/created to version ${DATABASE_VERSION}`);
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
          sync_attempt_count INTEGER NOT NULL DEFAULT 0
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

        switch (obj.type) {
          case 'ITEM':
            await statements.ITEM.executeAsync(
              obj.id,
              obj.updated_at,
              versionStr,
              isDeleted,
              obj.present_at_all_locations ? 1 : 0,
              obj.item_data?.name,
              obj.item_data?.description,
              obj.item_data?.category_id,
              dataJson
            );
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
  checkDatabaseContent
}; 