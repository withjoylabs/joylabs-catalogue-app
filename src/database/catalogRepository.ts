import { Platform } from 'react-native';
import api from '../api';
import logger from '../utils/logger';
import { SQLiteDatabase } from 'expo-sqlite';
import * as modernDb from './modernDb';

// Define category interface
export interface Category {
  id: string;
  name: string;
  image_url?: string;
  description?: string;
  available?: boolean;
  sort_order?: number;
  updated_at?: string;
}

// Define catalog item interface
export interface CatalogItem {
  id: string;
  name: string;
  description?: string;
  category_id?: string;
  price?: number;
  image_url?: string;
  version?: number;
  updated_at?: string;
  available?: boolean;
  type?: string;
  data?: any;
  sort_order?: number;
}

// Search options interface
export interface SearchOptions {
  term?: string;
  category_id?: string;
  limit?: number;
  offset?: number;
  sort_by?: 'name' | 'price' | 'updated_at';
  sort_order?: 'asc' | 'desc';
}

// Repository responsible for retrieving catalog data from SQLite and/or API
class CatalogRepository {
  private static instance: CatalogRepository;
  private db: SQLiteDatabase | null = null;

  private constructor() {
    // Private constructor to enforce singleton
  }

  /**
   * Get singleton instance
   */
  public static getInstance(): CatalogRepository {
    if (!CatalogRepository.instance) {
      CatalogRepository.instance = new CatalogRepository();
    }
    return CatalogRepository.instance;
  }

  /**
   * Check if the database is initialized
   */
  private async isDatabaseReady(): Promise<boolean> {
    if (Platform.OS === 'web') {
      return false; // SQLite not supported on web
    }

    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      const result = await this.db.getAllAsync<{ name: string }>(
        'SELECT name FROM sqlite_master WHERE type="table" AND name="catalog_items"'
      );
      return result.length > 0;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to check database status', { error });
      return false;
    }
  }

  /**
   * Get all categories
   */
  public async getCategories(): Promise<Category[]> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready, fetching categories from API');
        return this.syncCategories();
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      const result = await this.db.getAllAsync<Category>(
        `SELECT id, name, image_url, description, 
                available, sort_order, updated_at 
         FROM categories 
         ORDER BY sort_order ASC, name ASC`
      );
      
      const categories = result.map(row => ({
        ...row,
        available: !!row.available
      }));
      
      logger.debug('CatalogRepository', `Retrieved ${categories.length} categories from database`);
      return categories;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to get categories', { error });
      return this.syncCategories();
    }
  }

  /**
   * Sync categories from API and save to database
   */
  public async syncCategories(): Promise<Category[]> {
    try {
      logger.info('CatalogRepository', 'Syncing categories from API');
      const response = await api.catalog.getCategories();
      
      if (!response || !response.data || !Array.isArray(response.data.categories)) {
        throw new Error('Invalid categories response from API');
      }
      
      const categories = response.data.categories;
      
      // Save to database if it's ready
      if (await this.isDatabaseReady()) {
        try {
          if (!this.db) {
            this.db = await modernDb.getDatabase();
          }
          
          await this.db.withTransactionAsync(async () => {
            // Clear existing categories
            await this.db!.runAsync('DELETE FROM categories');
            
            // Insert new categories
            for (let i = 0; i < categories.length; i++) {
              const category = categories[i];
              await this.db!.runAsync(
                `INSERT INTO categories (id, name, image_url, description, available, sort_order, updated_at) 
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                [
                  category.id,
                  category.name,
                  category.image_url || null,
                  category.description || null,
                  category.available ? 1 : 0,
                  category.sort_order || i,
                  new Date().toISOString()
                ]
              );
            }
          });
          
          logger.info('CatalogRepository', `Saved ${categories.length} categories to database`);
        } catch (dbError) {
          logger.error('CatalogRepository', 'Failed to save categories to database', { error: dbError });
        }
      }
      
      return categories;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to sync categories', { error });
      return [];
    }
  }

  /**
   * Get catalog items, optionally filtered by category
   */
  public async getItems(
    page: number = 1,
    limit: number = 20,
    categoryId?: string
  ): Promise<{ items: CatalogItem[]; cursor: string | null; hasMore: boolean }> {
    try {
      // Check if we can use the local database
      const useDatabase = await this.isDatabaseReady();
      const offset = (page - 1) * limit;

      if (useDatabase) {
        // Build query based on filters
        let sql = `
          SELECT ci.*, c.name as category_name
          FROM catalog_items ci
          LEFT JOIN categories c ON JSON_EXTRACT(ci.item_data, '$.category_id') = c.id
          WHERE ci.type = 'ITEM' AND ci.is_deleted = 0
        `;
        const params: any[] = [];

        if (categoryId) {
          sql += ' AND JSON_EXTRACT(ci.item_data, "$.category_id") = ?';
          params.push(categoryId);
        }

        sql += ' ORDER BY JSON_EXTRACT(ci.item_data, "$.name") COLLATE NOCASE ASC';
        sql += ' LIMIT ? OFFSET ?';
        params.push(limit, offset);

        // Query total count for pagination
        let countSql = `
          SELECT COUNT(*) as total
          FROM catalog_items ci
          WHERE ci.type = 'ITEM' AND ci.is_deleted = 0
        `;
        const countParams: any[] = [];

        if (categoryId) {
          countSql += ' AND JSON_EXTRACT(ci.item_data, "$.category_id") = ?';
          countParams.push(categoryId);
        }

        // Execute queries
        const result = await this.db!.getAllAsync<any>(sql, params);
        const countResult = await this.db!.getFirstAsync<{ total: number }>(countSql, countParams);
        const total = countResult?.total || 0;

        // Parse results
        const items: CatalogItem[] = [];
        for (const row of result) {
          const itemData = JSON.parse(row.item_data || '{}');

          items.push({
            id: row.id,
            name: itemData.name || '',
            description: itemData.description || '',
            price: this.parsePrice(itemData.variations?.[0]?.item_variation_data?.price_money?.amount),
            category_id: itemData.category_id || null,
            updated_at: row.updated_at,
            available: !Boolean(row.is_deleted),
            data: itemData
          });
        }

        // Determine if there are more items
        const hasMore = offset + items.length < total;
        const cursor = hasMore ? String(page + 1) : null;

        return { items, cursor, hasMore };
      }

      // Fall back to API if database isn't ready
      logger.info('CatalogRepository', 'Fetching items from API');
      const response = await api.catalog.getItems(page, limit);

      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to fetch catalog items');
      }

      const items: CatalogItem[] = [];
      if (Array.isArray(response.objects)) {
        for (const obj of response.objects) {
          if (obj.type === 'ITEM' && obj.item_data && !obj.is_deleted) {
            // Skip items not in the specified category if a categoryId was provided
            if (categoryId && obj.item_data.category_id !== categoryId) {
              continue;
            }

            items.push({
              id: obj.id,
              name: obj.item_data.name || '',
              description: obj.item_data.description || '',
              price: this.parsePrice(obj.item_data.variations?.[0]?.item_variation_data?.price_money?.amount),
              category_id: obj.item_data.category_id || null,
              available: !Boolean(obj.is_deleted),
              updated_at: new Date().toISOString(),
              data: obj.item_data
            });
          }
        }
      }

      return {
        items,
        cursor: response.cursor || null,
        hasMore: !!response.cursor
      };
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to get items', { error });
      throw error;
    }
  }

  /**
   * Get a single item by ID
   */
  public async getItemById(id: string): Promise<CatalogItem | null> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready to get item');
        return null;
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      const result = await this.db.getFirstAsync<CatalogItem>(
        `SELECT id, name, description, category_id, price, 
                image_url, version, updated_at, available, 
                type, data, sort_order
         FROM catalog_items
         WHERE id = ?`,
        [id]
      );
      
      if (!result) {
        return null;
      }
      
      return {
        ...result,
        available: !!result.available,
        data: result.data ? JSON.parse(result.data) : undefined
      };
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to get item by ID', { error, id });
      return null;
    }
  }

  /**
   * Get items by search query
   */
  public async searchItems(options: SearchOptions): Promise<{ items: CatalogItem[]; total: number }> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready for search');
        return { items: [], total: 0 };
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      // Prepare SQL query with conditions
      let conditions = ['1=1']; // Always true condition to simplify query building
      const params: any[] = [];
      
      if (options.term) {
        conditions.push(`(name LIKE ? OR description LIKE ?)`);
        const term = `%${options.term}%`;
        params.push(term, term);
      }
      
      if (options.category_id) {
        conditions.push('category_id = ?');
        params.push(options.category_id);
      }
      
      // Sorting
      const sortBy = options.sort_by || 'name';
      const sortOrder = options.sort_order || 'asc';
      const orderClause = `ORDER BY ${sortBy} ${sortOrder.toUpperCase()}`;
      
      // Pagination
      const limit = options.limit || 20;
      const offset = options.offset || 0;
      const limitClause = 'LIMIT ? OFFSET ?';
      params.push(limit, offset);
      
      const sql = `
        SELECT id, name, description, category_id, price, 
               image_url, version, updated_at, available, 
               type, data, sort_order
        FROM catalog_items
        WHERE ${conditions.join(' AND ')}
        ${orderClause}
        ${limitClause}
      `;
      
      const countSql = `
        SELECT COUNT(*) as total
        FROM catalog_items
        WHERE ${conditions.join(' AND ')}
      `;
      
      const countParams = params.slice(0, params.length - 2); // Remove limit and offset
      
      // Execute queries
      const result = await this.db.getAllAsync<CatalogItem>(sql, params);
      const countResult = await this.db.getFirstAsync<{ total: number }>(countSql, countParams);
      
      const items = result.map(row => ({
        ...row,
        available: !!row.available,
        data: row.data ? JSON.parse(row.data) : undefined
      }));
      
      logger.debug('CatalogRepository', `Search returned ${items.length} items`, { options });
      
      return {
        items,
        total: countResult?.total || 0
      };
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to search items', { error, options });
      return { items: [], total: 0 };
    }
  }

  /**
   * Get items by category ID
   */
  public async getItemsByCategory(categoryId: string, limit = 50, offset = 0): Promise<CatalogItem[]> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready to get items by category');
        return [];
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      const result = await this.db.getAllAsync<CatalogItem>(
        `SELECT id, name, description, category_id, price, 
                image_url, version, updated_at, available, 
                type, data, sort_order
         FROM catalog_items
         WHERE category_id = ?
         ORDER BY sort_order ASC, name ASC
         LIMIT ? OFFSET ?`,
        [categoryId, limit, offset]
      );
      
      const items = result.map(row => ({
        ...row,
        available: !!row.available,
        data: row.data ? JSON.parse(row.data) : undefined
      }));
      
      logger.debug('CatalogRepository', `Retrieved ${items.length} items for category ${categoryId}`);
      
      return items;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to get items by category', { error, categoryId });
      return [];
    }
  }

  /**
   * Save catalog items to database
   */
  public async saveItems(items: CatalogItem[]): Promise<boolean> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready to save items');
        return false;
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      // Save in chunks to avoid memory issues
      const chunkSize = 100;
      for (let i = 0; i < items.length; i += chunkSize) {
        const chunk = items.slice(i, i + chunkSize);
        
        await this.db.withTransactionAsync(async () => {
          for (const item of chunk) {
            await this.db!.runAsync(
              `INSERT OR REPLACE INTO catalog_items 
               (id, name, description, category_id, price, image_url, 
                version, updated_at, available, type, data, sort_order)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [
                item.id,
                item.name,
                item.description || null,
                item.category_id || null,
                item.price || 0,
                item.image_url || null,
                item.version || 1,
                item.updated_at || new Date().toISOString(),
                item.available ? 1 : 0,
                item.type || 'ITEM',
                item.data ? JSON.stringify(item.data) : null,
                item.sort_order || 0
              ]
            );
          }
        });
        
        logger.debug('CatalogRepository', `Saved chunk of ${chunk.length} items`);
      }
      
      logger.info('CatalogRepository', `Successfully saved ${items.length} items to database`);
      return true;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to save items', { error });
      return false;
    }
  }

  /**
   * Clear all items
   */
  public async clearItems(): Promise<boolean> {
    try {
      if (!await this.isDatabaseReady()) {
        logger.warn('CatalogRepository', 'Database not ready to clear items');
        return false;
      }

      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      await this.db.runAsync('DELETE FROM catalog_items');
      
      logger.info('CatalogRepository', 'Cleared all catalog items');
      return true;
    } catch (error) {
      logger.error('CatalogRepository', 'Failed to clear items', { error });
      return false;
    }
  }

  /**
   * Helper to safely parse price from cents to dollars
   */
  private parsePrice(cents: number | string | undefined): number {
    if (cents === undefined || cents === null) {
      return 0;
    }
    
    const numericValue = typeof cents === 'string' ? parseInt(cents, 10) : cents;
    if (isNaN(numericValue)) {
      return 0;
    }
    
    return numericValue / 100;
  }
}

// Export a singleton instance
export const catalogRepository = CatalogRepository.getInstance();

export default catalogRepository; 