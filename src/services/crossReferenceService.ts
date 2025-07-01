import { ConvertedItem } from '../types/api';
import { TeamData } from '../types/teamData';
import { ReorderItem, DisplayReorderItem } from './reorderService';
import { getDatabase } from '../database/modernDb';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';
import logger from '../utils/logger';

// Extend global for debugging flags
declare global {
  interface Window {
    _crossRefLoggedNoTeamTable?: boolean;
  }
}

/**
 * Cross-Reference Service
 * 
 * This service handles cross-referencing minimal reorder data with:
 * 1. Square catalog data (for item details like name, price, barcode)
 * 2. Team data (for vendor, cost, received history)
 * 
 * This enables the local-first architecture where reorder records store
 * only minimal data (itemId, quantity, status) and all item details
 * are looked up from the local Square catalog in real-time.
 */
class CrossReferenceService {
  private squareItemCache = new Map<string, { data: ConvertedItem; timestamp: number; accessCount: number }>();
  private teamDataCache = new Map<string, { data: TeamData | null; timestamp: number; accessCount: number }>();
  private readonly CACHE_DURATION = 5 * 60 * 1000; // 5 minutes
  private readonly MAX_CACHE_SIZE = 1000; // Maximum items per cache
  private readonly MEMORY_CHECK_INTERVAL = 30 * 1000; // Check memory every 30 seconds
  private memoryCheckTimer: NodeJS.Timeout | null = null;

  constructor() {
    // Start memory monitoring
    this.startMemoryMonitoring();
  }

  /**
   * Get Square catalog item by itemId
   * Returns item details like name, price, barcode, category
   */
  async getSquareItem(itemId: string): Promise<ConvertedItem | null> {
    try {
      // Check cache first
      const cached = this.squareItemCache.get(itemId);
      if (cached && (Date.now() - cached.timestamp) < this.CACHE_DURATION) {
        // Update access tracking for LRU
        cached.accessCount++;
        cached.timestamp = Date.now();
        return cached.data;
      }

      // Query local Square catalog database
      const db = await getDatabase();
      
      // Simplified query - get item first, then variation separately

      // First, get the basic item info
      const itemQuery = `
        SELECT
          ci.id as item_id,
          ci.name as item_name,
          ci.description,
          ci.category_id,
          ci.data_json as item_data_json,
          c.name as category_name
        FROM catalog_items ci
        LEFT JOIN categories c ON ci.category_id = c.id
        WHERE ci.id = ? AND ci.is_deleted = 0
      `;

      let itemRow;
      try {
        itemRow = await db.getFirstAsync<any>(itemQuery, itemId);
      } catch (itemQueryError) {
        logger.error('[CrossReferenceService]', 'Item query failed', { itemQueryError, itemQuery, itemId });
        throw itemQueryError;
      }

      if (!itemRow) {
        logger.warn('[CrossReferenceService]', 'Square item not found in local catalog', { itemId });

        // Let's also check if the item exists at all
        const existsCheck = await db.getFirstAsync<any>(
          'SELECT id, name, is_deleted FROM catalog_items WHERE id = ?',
          itemId
        );

        return null;
      }

      // Then get the primary variation
      const variationQuery = `
        SELECT
          id as variation_id,
          name as variation_name,
          sku,
          pricing_type,
          price_amount,
          price_currency,
          data_json as variation_data_json
        FROM item_variations
        WHERE item_id = ? AND is_deleted = 0
        ORDER BY updated_at ASC
        LIMIT 1
      `;

      let variationRow;
      try {
        variationRow = await db.getFirstAsync<any>(variationQuery, itemId);
      } catch (variationQueryError) {
        logger.error('[CrossReferenceService]', 'Variation query failed', { variationQueryError, variationQuery, itemId });
        // Don't throw here - variations are optional
        variationRow = null;
      }

      // Combine the results
      const row = {
        ...itemRow,
        ...variationRow
      };


      // Transform database row to ConvertedItem format
      const itemData = JSON.parse(row.item_data_json || '{}');
      const variationData = row.variation_data_json ? JSON.parse(row.variation_data_json) : null;



      // Reconstruct catalog object for transformer
      const catalogObject = {
        id: row.item_id,
        type: 'ITEM',
        updated_at: itemData.updated_at || new Date().toISOString(),
        version: itemData.version || 0,
        is_deleted: false,
        item_data: {
          // Use itemData.item_data if it exists, otherwise use itemData directly
          ...(itemData.item_data || itemData),
          name: row.item_name,
          description: row.description,
          category_id: row.category_id,
          variations: variationData ? [{
            id: row.variation_id,
            type: 'ITEM_VARIATION',
            updated_at: variationData.updated_at || new Date().toISOString(),
            version: variationData.version || 0,
            item_variation_data: {
              // Use variationData.item_variation_data if it exists, otherwise use variationData directly
              ...(variationData.item_variation_data || variationData),
              name: row.variation_name,
              sku: row.sku,
              pricing_type: row.pricing_type,
              price_money: row.price_amount ? {
                amount: row.price_amount,
                currency: row.price_currency || 'USD'
              } : undefined
            }
          }] : []
        }
      };

      // Use existing transformer

      const convertedItem = transformCatalogItemToItem(catalogObject);

      if (!convertedItem) {
        logger.error('[CrossReferenceService]', 'transformCatalogItemToItem returned null, using fallback', {
          itemId
        });

        // Fallback: create ConvertedItem directly from database row
        let categoryName = row.category_name || 'Unknown';

        // If no category name from join, try to look it up
        if (!row.category_name && row.category_id) {
          try {
            const db = await getDatabase();
            const categoryRow = await db.getFirstAsync<{ name: string }>(
              'SELECT name FROM categories WHERE id = ? AND is_deleted = 0',
              row.category_id
            );
            if (categoryRow) {
              categoryName = categoryRow.name;
            }
          } catch (categoryError) {
            logger.warn('[CrossReferenceService]', 'Failed to lookup category for fallback item', {
              categoryId: row.category_id,
              categoryError
            });
          }
        }

        const fallbackItem: ConvertedItem = {
          id: row.item_id,
          name: row.item_name || 'Unknown Item',
          description: row.description || '',
          price: row.price_amount ? row.price_amount / 100 : undefined,
          sku: row.sku || null,
          barcode: undefined, // Will be extracted from variation data if available
          category: categoryName,
          categoryId: row.category_id,
          isActive: true,
          variations: [],
          images: [],
          taxIds: [],
          modifierListIds: [],
          abbreviation: '',
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        };



        // Cache the fallback result
        this.addToSquareItemCache(itemId, fallbackItem);
        return fallbackItem;
      }

      // CRITICAL FIX: Ensure category name is properly set
      // The transformer only sets categoryId, not the category name
      let categoryName = row.category_name || 'Unknown';

      // If no category name from join, try to look it up from categoryId or reporting_category_id
      if (!row.category_name) {
        const categoryId = convertedItem.categoryId || convertedItem.reporting_category_id;
        if (categoryId) {
          try {
            const db = await getDatabase();
            const categoryRow = await db.getFirstAsync<{ name: string }>(
              'SELECT name FROM categories WHERE id = ? AND is_deleted = 0',
              categoryId
            );
            if (categoryRow) {
              categoryName = categoryRow.name;
            }
          } catch (categoryError) {
            logger.warn('[CrossReferenceService]', 'Failed to lookup category name', {
              categoryId,
              categoryError
            });
          }
        }
      }

      // Set the category name on the converted item
      convertedItem.category = categoryName;

      // Cache the result with LRU tracking
      this.addToSquareItemCache(itemId, convertedItem);



      return convertedItem;

    } catch (error) {
      logger.error('[CrossReferenceService]', 'Error getting Square item', { error, itemId });

      // Try a simple fallback query
      try {

        const db = await getDatabase();
        const simpleRow = await db.getFirstAsync<any>(
          `SELECT ci.id, ci.name, ci.description, ci.category_id, c.name as category_name
           FROM catalog_items ci
           LEFT JOIN categories c ON ci.category_id = c.id
           WHERE ci.id = ? AND ci.is_deleted = 0`,
          itemId
        );

        if (simpleRow) {
          const fallbackItem: ConvertedItem = {
            id: simpleRow.id,
            name: simpleRow.name || 'Unknown Item',
            description: simpleRow.description || '',
            price: undefined,
            sku: null,
            barcode: undefined,
            category: simpleRow.category_name || 'Unknown',
            categoryId: simpleRow.category_id,
            isActive: true,
            variations: [],
            images: [],
            taxIds: [],
            modifierListIds: [],
            abbreviation: '',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
          };

          // Cache the fallback result
          this.addToSquareItemCache(itemId, fallbackItem);
          return fallbackItem;
        }
      } catch (fallbackError) {
        logger.error('[CrossReferenceService]', 'Fallback query also failed', { fallbackError, itemId });
      }

      return null;
    }
  }

  /**
   * Get team data by itemId
   * Returns vendor, cost, received history, etc.
   */
  async getTeamData(itemId: string): Promise<TeamData | null> {
    try {
      // Check cache first
      const cached = this.teamDataCache.get(itemId);
      if (cached && (Date.now() - cached.timestamp) < this.CACHE_DURATION) {
        // Update access tracking for LRU
        cached.accessCount++;
        cached.timestamp = Date.now();
        return cached.data;
      }

      // Query local team data database with proper error handling
      const db = await getDatabase();

      // First check if team_data table exists and has data
      try {
        const tableExists = await db.getFirstAsync<{ count: number }>(
          "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='team_data'"
        );

        if (!tableExists || tableExists.count === 0) {
          // Reduce console spam by only logging once per session
          if (!window._crossRefLoggedNoTeamTable) {
            logger.debug('[CrossReferenceService]', 'Team data table does not exist - user not signed in', { itemId });
            window._crossRefLoggedNoTeamTable = true;
          }
          return null;
        }
      } catch (tableCheckError) {
        logger.warn('[CrossReferenceService]', 'Could not check team_data table existence', {
          error: tableCheckError,
          itemId
        });
        return null;
      }

      const row = await db.getFirstAsync<any>(
        'SELECT * FROM team_data WHERE item_id = ?',
        itemId
      );

      if (!row) {
        // Cache null result to avoid repeated queries
        this.addToTeamDataCache(itemId, null);
        return null;
      }

      // Parse team data using actual database schema
      const teamData: TeamData = {
        itemId: row.item_id,
        vendor: row.vendor,
        // Note: 'cost' field doesn't exist in DB schema, using case_cost instead
        cost: row.case_cost,
        caseUpc: row.case_upc,
        caseQuantity: row.case_quantity,
        notes: row.notes,
        // Note: 'history' field doesn't exist in DB schema, using empty array
        history: [],
        // Note: using correct column names from actual schema
        lastUpdated: row.updated_at,
        updatedBy: row.owner
      };

      // Cache the result with LRU tracking
      this.addToTeamDataCache(itemId, teamData);

      logger.debug('[CrossReferenceService]', 'Team data found and cached', {
        itemId,
        vendor: teamData.vendor
      });

      return teamData;

    } catch (error) {
      logger.warn('[CrossReferenceService]', 'Team data unavailable (user may not be signed in)', {
        error: error instanceof Error ? error.message : 'Unknown error',
        itemId
      });
      // Cache null result to avoid repeated failed queries
      this.addToTeamDataCache(itemId, null);
      return null;
    }
  }

  /**
   * Build display item by cross-referencing minimal reorder data
   * This is the core function that transforms ReorderItem → DisplayReorderItem
   */
  async buildDisplayItem(reorderItem: ReorderItem): Promise<DisplayReorderItem> {
    try {
      // Handle custom items (get details from team_data table)
      if (reorderItem.itemId.startsWith('custom-')) {
        const teamData = await this.getTeamData(reorderItem.itemId);

        let itemName = `Custom Item ${reorderItem.itemId.split('-')[1]}`;
        let itemCategory = 'Custom';

        // Extract custom item details from team_data notes field
        if (teamData?.notes) {
          try {
            const customDetails = JSON.parse(teamData.notes);
            if (customDetails.isCustom) {
              itemName = customDetails.itemName || itemName;
              itemCategory = customDetails.itemCategory || itemCategory;
            }
          } catch (error) {
            logger.warn('[CrossReferenceService]', 'Failed to parse custom item details', { error });
          }
        }

        return {
          ...reorderItem,
          itemName,
          itemBarcode: undefined,
          itemCategory,
          itemPrice: undefined,
          teamData,
          item: undefined,
          missingSquareData: false,
          missingTeamData: !teamData,
          isCustom: true
        };
      }

      // Cross-reference with Square catalog
      const squareItem = await this.getSquareItem(reorderItem.itemId);

      // Cross-reference with team data
      const teamData = await this.getTeamData(reorderItem.itemId);

      // Build display item
      const displayItem: DisplayReorderItem = {
        ...reorderItem,
        // Square catalog data
        itemName: squareItem?.name || `Unknown Item (${reorderItem.itemId})`,
        itemBarcode: squareItem?.barcode || undefined,
        itemCategory: squareItem?.category || 'Unknown',
        itemPrice: squareItem?.price || undefined,
        // Team data - show "N/A" instead of "Team Data Missing"
        teamData: teamData || undefined,
        item: squareItem || undefined,
        // Status indicators - don't show missing team data as an error for now
        missingSquareData: !squareItem,
        missingTeamData: false // Set to false to avoid "Team Data Missing" spam
      };

      return displayItem;

    } catch (error) {
      logger.error('[CrossReferenceService]', 'Error building display item', { 
        error, 
        itemId: reorderItem.itemId 
      });

      // Return fallback display item
      return {
        ...reorderItem,
        itemName: `Error Loading Item (${reorderItem.itemId})`,
        itemBarcode: undefined,
        itemCategory: 'Error',
        itemPrice: undefined,
        teamData: undefined,
        item: undefined,
        missingSquareData: true,
        missingTeamData: true
      };
    }
  }

  /**
   * Build multiple display items efficiently
   * Uses batch processing for better performance
   */
  async buildDisplayItems(reorderItems: ReorderItem[]): Promise<DisplayReorderItem[]> {
    try {
      const displayItems = await Promise.all(
        reorderItems.map(item => this.buildDisplayItem(item))
      );

      return displayItems;

    } catch (error) {
      logger.error('[CrossReferenceService]', 'Error building display items', { error });
      return [];
    }
  }

  /**
   * Clear caches (useful for testing or memory management)
   */
  clearCaches(): void {
    this.squareItemCache.clear();
    this.teamDataCache.clear();
    logger.debug('[CrossReferenceService]', 'Caches cleared');
  }

  /**
   * Get cache statistics with memory usage
   */
  getCacheStats() {
    return {
      squareItemCacheSize: this.squareItemCache.size,
      teamDataCacheSize: this.teamDataCache.size,
      totalCacheSize: this.squareItemCache.size + this.teamDataCache.size,
      maxCacheSize: this.MAX_CACHE_SIZE,
      memoryPressure: this.squareItemCache.size > this.MAX_CACHE_SIZE * 0.8
    };
  }

  /**
   * Start memory monitoring
   */
  private startMemoryMonitoring(): void {
    this.memoryCheckTimer = setInterval(() => {
      this.performMemoryOptimization();
    }, this.MEMORY_CHECK_INTERVAL);

    logger.debug('[CrossReferenceService]', 'Memory monitoring started');
  }

  /**
   * Stop memory monitoring
   */
  private stopMemoryMonitoring(): void {
    if (this.memoryCheckTimer) {
      clearInterval(this.memoryCheckTimer);
      this.memoryCheckTimer = null;
    }
    logger.debug('[CrossReferenceService]', 'Memory monitoring stopped');
  }

  /**
   * Perform memory optimization using LRU eviction
   */
  private performMemoryOptimization(): void {
    const totalSize = this.squareItemCache.size + this.teamDataCache.size;

    if (totalSize > this.MAX_CACHE_SIZE) {
      logger.info('[CrossReferenceService]', `Memory optimization triggered: ${totalSize} items in cache`);

      // Evict least recently used items from Square cache
      this.evictLRUItems(this.squareItemCache, Math.floor(this.MAX_CACHE_SIZE * 0.4));

      // Evict least recently used items from team data cache
      this.evictLRUItems(this.teamDataCache, Math.floor(this.MAX_CACHE_SIZE * 0.4));

      const newSize = this.squareItemCache.size + this.teamDataCache.size;
      logger.info('[CrossReferenceService]', `Memory optimization complete: ${totalSize} → ${newSize} items`);
    }
  }

  /**
   * Evict least recently used items from cache
   */
  private evictLRUItems<T>(cache: Map<string, { data: T; timestamp: number; accessCount: number }>, maxSize: number): void {
    if (cache.size <= maxSize) return;

    // Sort by access count (ascending) and timestamp (ascending) for LRU
    const entries = Array.from(cache.entries()).sort((a, b) => {
      const aScore = a[1].accessCount + (a[1].timestamp / 1000000); // Combine access count and recency
      const bScore = b[1].accessCount + (b[1].timestamp / 1000000);
      return aScore - bScore;
    });

    // Remove oldest/least accessed items
    const itemsToRemove = entries.length - maxSize;
    for (let i = 0; i < itemsToRemove; i++) {
      cache.delete(entries[i][0]);
    }

    logger.debug('[CrossReferenceService]', `Evicted ${itemsToRemove} LRU items from cache`);
  }

  /**
   * Add item to Square cache with LRU tracking
   */
  private addToSquareItemCache(itemId: string, item: ConvertedItem): void {
    // Check if we need to make room
    if (this.squareItemCache.size >= this.MAX_CACHE_SIZE) {
      this.evictLRUItems(this.squareItemCache, this.MAX_CACHE_SIZE - 1);
    }

    this.squareItemCache.set(itemId, {
      data: item,
      timestamp: Date.now(),
      accessCount: 1
    });
  }

  /**
   * Add item to team data cache with LRU tracking
   */
  private addToTeamDataCache(itemId: string, teamData: TeamData | null): void {
    // Check if we need to make room
    if (this.teamDataCache.size >= this.MAX_CACHE_SIZE) {
      this.evictLRUItems(this.teamDataCache, this.MAX_CACHE_SIZE - 1);
    }

    this.teamDataCache.set(itemId, {
      data: teamData,
      timestamp: Date.now(),
      accessCount: 1
    });
  }

  /**
   * Debug method to test cross-referencing for a specific item
   */
  async debugCrossReference(itemId: string): Promise<void> {
    logger.info('[CrossReferenceService]', `🔍 DEBUG: Testing cross-reference for item ${itemId}`);

    try {
      const squareItem = await this.getSquareItem(itemId);
      const teamData = await this.getTeamData(itemId);

      logger.info('[CrossReferenceService]', 'DEBUG: Cross-reference results', {
        itemId,
        squareItem: squareItem ? {
          name: squareItem.name,
          price: squareItem.price,
          category: squareItem.category
        } : null,
        teamData: teamData ? {
          vendor: teamData.vendor,
          discontinued: teamData.discontinued
        } : null
      });
    } catch (error) {
      logger.error('[CrossReferenceService]', 'DEBUG: Cross-reference failed', { itemId, error });
    }
  }

  /**
   * Check database health for debugging
   */
  async checkDatabaseHealth(): Promise<{
    catalogItemsCount: number;
    teamDataCount: number;
    teamDataTableExists: boolean;
    error?: string;
  }> {
    try {
      const db = await getDatabase();

      // Check if team_data table exists
      const tableCheck = await db.getFirstAsync<{ count: number }>(
        "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='team_data'"
      );
      const teamDataTableExists = (tableCheck?.count || 0) > 0;

      // Count catalog items
      const catalogCount = await db.getFirstAsync<{ count: number }>(
        'SELECT COUNT(*) as count FROM catalog_items WHERE is_deleted = 0'
      );

      // Count team data (only if table exists)
      let teamDataCount = 0;
      if (teamDataTableExists) {
        const teamCount = await db.getFirstAsync<{ count: number }>(
          'SELECT COUNT(*) as count FROM team_data'
        );
        teamDataCount = teamCount?.count || 0;
      }

      return {
        catalogItemsCount: catalogCount?.count || 0,
        teamDataCount,
        teamDataTableExists
      };
    } catch (error) {
      return {
        catalogItemsCount: 0,
        teamDataCount: 0,
        teamDataTableExists: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Cleanup method for proper resource management
   */
  cleanup(): void {
    this.stopMemoryMonitoring();
    this.clearCaches();
    logger.info('[CrossReferenceService]', 'Cleanup completed');
  }
}

// Export singleton instance
export const crossReferenceService = new CrossReferenceService();
export default crossReferenceService;
