import { SQLiteDatabase, openDatabaseAsync } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system';
import logger from '../utils/logger';

// Constants
const DATABASE_NAME = 'joylabs.db';
const DATABASE_VERSION = 1; // Increment this when changing schema
let db: SQLiteDatabase | null = null;

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
    
    // Check if database needs migration
    const needsMigration = await checkDatabaseMigration(db);
    if (needsMigration) {
      logger.warn('Database', 'Database needs migration, recreating schema');
      await resetDatabase();
      // Re-fetch the db reference after reset
      db = await openDatabaseAsync(DATABASE_NAME);
    } else {
      // Just initialize schema if no migration needed
      await initializeSchema(db);
    }
    
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
export async function initializeSchema(db: SQLiteDatabase): Promise<void> {
  try {
    // Create tables within a transaction
    await db.withTransactionAsync(async () => {
      // Sync status table
      await db.runAsync(`
        CREATE TABLE IF NOT EXISTS sync_status (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          last_sync_time TEXT,
          is_syncing INTEGER DEFAULT 0,
          sync_error TEXT,
          sync_progress INTEGER DEFAULT 0,
          sync_total INTEGER DEFAULT 0,
          sync_type TEXT,
          last_sync_attempt TEXT,
          sync_attempt_count INTEGER DEFAULT 0
        )
      `);

      // Check if sync_status has data, initialize if not
      const syncStatus = await db.getFirstAsync<{ count: number }>('SELECT COUNT(*) as count FROM sync_status');
      if (syncStatus && syncStatus.count === 0) {
        await db.runAsync(`
          INSERT INTO sync_status (
            id, last_sync_time, is_syncing, sync_error, sync_progress, 
            sync_total, sync_type, last_sync_attempt, sync_attempt_count
          ) VALUES (1, NULL, 0, NULL, 0, 0, NULL, NULL, 0)
        `);
      }

      // Categories table
      await db.runAsync(`
        CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          image_url TEXT,
          description TEXT,
          available INTEGER DEFAULT 1,
          sort_order INTEGER DEFAULT 0,
          updated_at TEXT
        )
      `);

      // Catalog items table
      await db.runAsync(`
        CREATE TABLE IF NOT EXISTS catalog_items (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          category_id TEXT,
          price REAL DEFAULT 0,
          image_url TEXT,
          version INTEGER DEFAULT 1,
          updated_at TEXT,
          available INTEGER DEFAULT 1,
          type TEXT DEFAULT 'ITEM',
          data TEXT,
          sort_order INTEGER DEFAULT 0,
          FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
        )
      `);

      // Create indexes for better performance
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_catalog_items_category ON catalog_items (category_id)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items (name)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_catalog_items_type ON catalog_items (type)');
      await db.runAsync('CREATE INDEX IF NOT EXISTS idx_categories_name ON categories (name)');
      
      // Create version table to track schema version
      await db.runAsync(`
        CREATE TABLE IF NOT EXISTS db_version (
          id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
          version INTEGER NOT NULL,
          updated_at TEXT
        )
      `);
      
      // Update version info
      await db.runAsync(`
        INSERT OR REPLACE INTO db_version (id, version, updated_at)
        VALUES (1, ?, ?)
      `, DATABASE_VERSION, new Date().toISOString());
    });

    logger.info('Database', 'Schema initialized successfully');
  } catch (error) {
    logger.error('Database', 'Failed to initialize schema', { error });
    throw error;
  }
}

/**
 * Reset the database by recreating all tables
 */
export async function resetDatabase(): Promise<void> {
  const db = await getDatabase();
  
  // Create tables in a transaction for atomicity
  await db.withTransactionAsync(async () => {
    // Drop existing tables if they exist
    await db.execAsync([
      { sql: 'DROP TABLE IF EXISTS sync_status', args: [] },
      { sql: 'DROP TABLE IF EXISTS categories', args: [] },
      { sql: 'DROP TABLE IF EXISTS catalog_items', args: [] },
      { sql: 'DROP TABLE IF EXISTS catalog_taxes', args: [] },
      { sql: 'DROP TABLE IF EXISTS catalog_modifiers', args: [] },
      { sql: 'DROP TABLE IF EXISTS merchant_info', args: [] },
      { sql: 'DROP TABLE IF EXISTS locations', args: [] },
      { sql: 'DROP TABLE IF EXISTS sync_logs', args: [] },
    ], false);
    
    // Create sync_status table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS sync_status (
        id INTEGER PRIMARY KEY NOT NULL,
        last_sync_time TEXT,
        is_syncing INTEGER NOT NULL DEFAULT 0,
        sync_error TEXT,
        sync_progress INTEGER NOT NULL DEFAULT 0,
        sync_total INTEGER NOT NULL DEFAULT 0,
        sync_type TEXT,
        last_sync_attempt TEXT,
        sync_attempt_count INTEGER NOT NULL DEFAULT 0
      )`, args: [] }
    ], false);
    
    // Create categories table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        image_url TEXT,
        description TEXT,
        available INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        version TEXT,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        parent_category_id TEXT,
        ordinal INTEGER,
        category_type TEXT,
        is_top_level INTEGER
      )`, args: [] }
    ], false);
    
    // Create catalog_items table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS catalog_items (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        category_id TEXT,
        price TEXT,
        image_url TEXT,
        version TEXT,
        updated_at TEXT NOT NULL,
        available INTEGER NOT NULL DEFAULT 1,
        type TEXT NOT NULL DEFAULT 'ITEM',
        data TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_taxable INTEGER,
        tax_ids TEXT,
        ecom_available INTEGER,
        product_type TEXT,
        skip_modifier_screen INTEGER
      )`, args: [] }
    ], false);
    
    // Create catalog_taxes table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS catalog_taxes (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        calculation_phase TEXT,
        inclusion_type TEXT,
        percentage TEXT,
        applies_to_custom_amounts INTEGER,
        enabled INTEGER NOT NULL DEFAULT 1,
        tax_type_id TEXT,
        tax_type_name TEXT,
        version TEXT,
        updated_at TEXT NOT NULL,
        created_at TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'TAX',
        data TEXT
      )`, args: [] }
    ], false);
    
    // Create catalog_modifiers table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS catalog_modifiers (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        price_amount INTEGER,
        price_currency TEXT,
        on_by_default INTEGER,
        ordinal INTEGER,
        modifier_list_id TEXT,
        version TEXT,
        updated_at TEXT NOT NULL,
        created_at TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'MODIFIER',
        data TEXT
      )`, args: [] }
    ], false);
    
    // Create merchant_info table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS merchant_info (
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
      )`, args: [] }
    ], false);
    
    // Create locations table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS locations (
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
      )`, args: [] }
    ], false);
    
    // Create sync_logs table
    await db.execAsync([
      { sql: `CREATE TABLE IF NOT EXISTS sync_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT
      )`, args: [] }
    ], false);
    
    // Create indexes for performance
    await db.execAsync([
      { sql: 'CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_items_category_id ON catalog_items(category_id)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_items_name ON catalog_items(name)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_items_type ON catalog_items(type)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_taxes_name ON catalog_taxes(name)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_modifiers_name ON catalog_modifiers(name)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_catalog_modifiers_list_id ON catalog_modifiers(modifier_list_id)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_sync_logs_timestamp ON sync_logs(timestamp)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_sync_logs_level ON sync_logs(level)', args: [] },
      { sql: 'CREATE INDEX IF NOT EXISTS idx_locations_merchant_id ON locations(merchant_id)', args: [] }
    ], false);
    
    // Insert default sync status
    await db.execAsync([
      { sql: `INSERT OR REPLACE INTO sync_status (
        id, last_sync_time, is_syncing, sync_error, sync_progress, sync_total, sync_type, sync_attempt_count
      ) VALUES (
        1, NULL, 0, NULL, 0, 0, NULL, 0
      )`, args: [] }
    ], false);
  });
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
    return await initDatabase();
  }
  return db;
}

// Export default object with all methods
export default {
  initDatabase,
  resetDatabase,
  closeDatabase,
  getDatabase
};

/**
 * Check database content for debugging
 */
export async function checkDatabaseContent(): Promise<{
  categories: { count: number; sample: any[] },
  items: { count: number; sample: any[] },
  taxes: { count: number; sample: any[] },
  modifiers: { count: number; sample: any[] },
  merchant: { count: number; sample: any[] },
  locations: { count: number; sample: any[] }
}> {
  const db = await getDatabase();
  
  try {
    // Get category stats
    const categoryCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM categories');
    const categorySamples = await db.getAllAsync('SELECT id, name, parent_category_id, updated_at FROM categories LIMIT 5');
    
    // Get item stats
    const itemCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM catalog_items');
    const itemSamples = await db.getAllAsync('SELECT id, name, type, category_id, updated_at FROM catalog_items LIMIT 5');
    
    // Get tax stats
    const taxCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM catalog_taxes');
    const taxSamples = await db.getAllAsync('SELECT id, name, percentage, tax_type_name, updated_at FROM catalog_taxes LIMIT 5');
    
    // Get modifier stats
    const modifierCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM catalog_modifiers');
    const modifierSamples = await db.getAllAsync('SELECT id, name, price_amount, price_currency, updated_at FROM catalog_modifiers LIMIT 5');
    
    // Get merchant stats
    const merchantCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM merchant_info');
    const merchantSamples = await db.getAllAsync('SELECT id, business_name, status, main_location_id FROM merchant_info LIMIT 5');
    
    // Get location stats
    const locationCount = await db.getFirstAsync<{count: number}>('SELECT COUNT(*) as count FROM locations');
    const locationSamples = await db.getAllAsync('SELECT id, name, business_name, merchant_id FROM locations LIMIT 5');
    
    // Log the results
    logger.info('ModernDB', 'Database content check', {
      categories: categoryCount?.count || 0,
      items: itemCount?.count || 0,
      taxes: taxCount?.count || 0,
      modifiers: modifierCount?.count || 0,
      merchant: merchantCount?.count || 0,
      locations: locationCount?.count || 0
    });
    
    return {
      categories: { 
        count: categoryCount?.count || 0, 
        sample: categorySamples 
      },
      items: { 
        count: itemCount?.count || 0, 
        sample: itemSamples 
      },
      taxes: { 
        count: taxCount?.count || 0, 
        sample: taxSamples 
      },
      modifiers: { 
        count: modifierCount?.count || 0, 
        sample: modifierSamples 
      },
      merchant: {
        count: merchantCount?.count || 0,
        sample: merchantSamples
      },
      locations: {
        count: locationCount?.count || 0,
        sample: locationSamples
      }
    };
  } catch (error) {
    logger.error('ModernDB', 'Error checking database content', { error });
    
    // Return empty data on error
    return {
      categories: { count: 0, sample: [] },
      items: { count: 0, sample: [] },
      taxes: { count: 0, sample: [] },
      modifiers: { count: 0, sample: [] },
      merchant: { count: 0, sample: [] },
      locations: { count: 0, sample: [] }
    };
  }
} 