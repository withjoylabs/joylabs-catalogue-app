import * as Network from 'expo-network';
import { SQLiteDatabase } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system';
import logger from '../utils/logger';
import * as modernDb from './modernDb';
import * as SecureStore from 'expo-secure-store';
import { api } from '../api';

// Constants for token storage to check validity
const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';
const TOKEN_EXPIRY_KEY = 'square_token_expiry';
const MIN_CHECK_INTERVAL = 5 * 60 * 1000; // 5 minutes
const AUTO_SYNC_INTERVAL = 60 * 60 * 1000; // 1 hour

// Constants for sync operations
const SYNC_INTERVAL = 24 * 60 * 60 * 1000; // 24 hours
const MAX_SYNC_ATTEMPTS = 3;
const INITIAL_SYNC_ITEMS_PER_BATCH = 100;

// Sync status interface
export interface SyncStatus {
  lastSyncTime: string | null;
  isSyncing: boolean;
  syncError: string | null;
  syncProgress: number;
  syncTotal: number;
  syncType: string | null;
  lastSyncAttempt: string | null;
  syncAttemptCount: number;
  last_page_cursor?: string | null;
}

/**
 * Service for catalog synchronization operations
 */
export class CatalogSyncService {
  private static instance: CatalogSyncService;
  private db: SQLiteDatabase | null = null;
  private syncTimer: NodeJS.Timeout | null = null;
  private autoSyncEnabled: boolean = false; // Default to no automatic syncing
  
  /**
   * Get the singleton instance of the CatalogSyncService
   */
  public static getInstance(): CatalogSyncService {
    if (!CatalogSyncService.instance) {
      CatalogSyncService.instance = new CatalogSyncService();
    }
    return CatalogSyncService.instance;
  }
  
  /**
   * Initialize the sync service
   */
  public async initialize(): Promise<void> {
    try {
      logger.info('CatalogSync', 'Initializing sync service');
      this.db = await modernDb.getDatabase();
      
      // Check sync status
      const status = await this.getSyncStatus();
      
      // If syncing was interrupted, reset status
      if (status.isSyncing) {
        logger.warn('CatalogSync', 'Previous sync was interrupted - resetting status');
        await this.updateSyncStatus({
          isSyncing: false,
          syncError: 'Previous sync was interrupted',
          syncProgress: 0,
          syncTotal: 0
        });
      }
      
      // Don't schedule automatic syncs by default
      // this.scheduleNextSync();
      
      logger.info('CatalogSync', 'Sync service initialized successfully');
    } catch (error) {
      logger.error('CatalogSync', 'Failed to initialize sync service', { error });
      throw new Error(`Failed to initialize sync service: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  
  /**
   * Enable or disable automatic sync scheduling
   */
  public setAutoSync(enabled: boolean): void {
    this.autoSyncEnabled = enabled;
    logger.info('CatalogSync', `Auto sync ${enabled ? 'enabled' : 'disabled'}`);
    
    // Clear any existing timers
    if (this.syncTimer) {
      clearTimeout(this.syncTimer);
      this.syncTimer = null;
    }
    
    // If enabling, schedule the next sync
    if (enabled) {
      this.scheduleNextSync();
    }
  }
  
  /**
   * Schedule the next sync based on last sync time
   */
  public scheduleNextSync(): void {
    // If auto sync is disabled, don't schedule anything
    if (!this.autoSyncEnabled) {
      logger.info('CatalogSync', 'Automatic sync is disabled - not scheduling next sync');
      return;
    }
    
    // Clear any existing timer
    if (this.syncTimer) {
      clearTimeout(this.syncTimer);
      this.syncTimer = null;
    }
    
    // Calculate next sync time
    this.getSyncStatus().then(status => {
      if (!status.lastSyncTime) {
        // If never synced, schedule for a future time rather than immediately
        logger.info('CatalogSync', 'Never synced - scheduling sync in 1 hour');
        this.syncTimer = setTimeout(() => this.startBackgroundSync(), 60 * 60 * 1000); // 1 hour
        return;
      }
      
      const lastSync = new Date(status.lastSyncTime).getTime();
      const now = Date.now();
      const elapsed = now - lastSync;
      
      if (elapsed >= SYNC_INTERVAL) {
        // If interval passed, schedule for a reasonable future time
        logger.info('CatalogSync', 'Sync interval passed - scheduling sync in 10 minutes');
        this.syncTimer = setTimeout(() => this.startBackgroundSync(), 10 * 60 * 1000); // 10 minutes
      } else {
        // Schedule for next interval
        const timeUntilNextSync = SYNC_INTERVAL - elapsed;
        logger.info('CatalogSync', `Scheduling next sync in ${Math.round(timeUntilNextSync / (60 * 1000))} minutes`);
        this.syncTimer = setTimeout(() => this.startBackgroundSync(), timeUntilNextSync);
      }
    }).catch(error => {
      logger.error('CatalogSync', 'Failed to schedule next sync', { error });
      // Schedule retry in 30 minutes
      this.syncTimer = setTimeout(() => this.scheduleNextSync(), 30 * 60 * 1000);
    });
  }
  
  /**
   * Get the current sync status
   */
  public async getSyncStatus(): Promise<SyncStatus> {
    try {
      // Don't do any API refreshes or extra work here - purely get the status from database
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      // Try to get sync status
      try {
        const result = await this.db.getFirstAsync<{
          last_sync_time: string | null;
          is_syncing: number;
          sync_error: string | null;
          sync_progress: number;
          sync_total: number;
          sync_type: string | null;
          last_sync_attempt: string | null;
          sync_attempt_count: number;
          last_page_cursor?: string | null;
        }>('SELECT * FROM sync_status WHERE id = 1');
        
        if (!result) {
          throw new Error('No sync status record found');
        }
        
        return {
          lastSyncTime: result.last_sync_time,
          isSyncing: result.is_syncing === 1,
          syncError: result.sync_error,
          syncProgress: result.sync_progress,
          syncTotal: result.sync_total,
          syncType: result.sync_type,
          lastSyncAttempt: result.last_sync_attempt,
          syncAttemptCount: result.sync_attempt_count,
          last_page_cursor: result.last_page_cursor,
        };
      } catch (dbError) {
        // If there's an error, it might be a schema issue - reset the database
        logger.warn('CatalogSync', 'Failed to get sync status, resetting database', { error: dbError });
        await modernDb.resetDatabase();
        this.db = await modernDb.getDatabase();
        
        // Return default status
        return {
          lastSyncTime: null,
          isSyncing: false,
          syncError: 'Database was reset due to errors',
          syncProgress: 0,
          syncTotal: 0,
          syncType: null,
          lastSyncAttempt: null,
          syncAttemptCount: 0,
          last_page_cursor: undefined,
        };
      }
    } catch (error) {
      logger.error('CatalogSync', 'Failed to get sync status', { error });
      
      // Return default status on error
      return {
        lastSyncTime: null,
        isSyncing: false,
        syncError: `Failed to get sync status: ${error instanceof Error ? error.message : String(error)}`,
        syncProgress: 0,
        syncTotal: 0,
        syncType: null,
        lastSyncAttempt: null,
        syncAttemptCount: 0,
        last_page_cursor: undefined,
      };
    }
  }
  
  /**
   * Update the sync status
   */
  public async updateSyncStatus(updates: Partial<SyncStatus>): Promise<void> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      const setValues: string[] = [];
      const params: any[] = [];
      
      if (updates.lastSyncTime !== undefined) {
        setValues.push('last_sync_time = ?');
        params.push(updates.lastSyncTime);
      }
      
      if (updates.isSyncing !== undefined) {
        setValues.push('is_syncing = ?');
        params.push(updates.isSyncing ? 1 : 0);
      }
      
      if (updates.syncError !== undefined) {
        setValues.push('sync_error = ?');
        params.push(updates.syncError);
      }
      
      if (updates.syncProgress !== undefined) {
        setValues.push('sync_progress = ?');
        params.push(updates.syncProgress);
      }
      
      if (updates.syncTotal !== undefined) {
        setValues.push('sync_total = ?');
        params.push(updates.syncTotal);
      }
      
      if (updates.syncType !== undefined) {
        setValues.push('sync_type = ?');
        params.push(updates.syncType);
      }
      
      if (updates.lastSyncAttempt !== undefined) {
        setValues.push('last_sync_attempt = ?');
        params.push(updates.lastSyncAttempt);
      }
      
      if (updates.syncAttemptCount !== undefined) {
        setValues.push('sync_attempt_count = ?');
        params.push(updates.syncAttemptCount);
      }
      
      if (updates.last_page_cursor !== undefined) {
        setValues.push('last_page_cursor = ?');
        params.push(updates.last_page_cursor);
      }
      
      if (setValues.length === 0) {
        return; // Nothing to update
      }
      
      params.push(1); // Add ID parameter
      
      const query = `UPDATE sync_status SET ${setValues.join(', ')} WHERE id = ?`;
      try {
        await this.db.runAsync(query, params);
        logger.debug('CatalogSync', 'Updated sync status', updates);
      } catch (dbError) {
        // If there's an error updating, it might be a schema issue
        logger.warn('CatalogSync', 'Error updating sync status, might be schema issue', { error: dbError });
        
        // Check if this is a "no such column" error
        const errorStr = String(dbError);
        if (errorStr.includes('no such column:')) {
          // Schema mismatch, reset database
          logger.warn('CatalogSync', 'Missing column detected, resetting database schema');
          await modernDb.resetDatabase();
          this.db = await modernDb.getDatabase();
          
          // Retry the update with the fresh database
          const newQuery = `UPDATE sync_status SET ${setValues.join(', ')} WHERE id = ?`;
          await this.db.runAsync(newQuery, params);
        } else {
          // Re-throw for other types of errors
          throw dbError;
        }
      }
    } catch (error) {
      logger.error('CatalogSync', 'Failed to update sync status', { error, updates });
      throw new Error(`Failed to update sync status: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  
  /**
   * Check that we have proper authentication before starting sync
   */
  private async checkAuthentication(): Promise<void> {
    logger.debug('CatalogSync', 'Checking authentication status...');
    const token = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
    if (!token) {
      throw new Error('Authentication required: No Square access token found.');
    }
    // Optionally add a check for token expiry if needed, though API interceptor might handle it
    logger.debug('CatalogSync', 'Authentication check passed.');
  }
  
  /**
   * Manually trigger a full catalog sync
   * @param skipCategorySync Whether to skip syncing categories (speeds up full sync)
   */
  public async forceFullSync(): Promise<boolean> {
    logger.info('CatalogSync', 'Forcing full sync...');
    try {
      await this.runFullSync();
      return true; // Indicate sync process was started
    } catch (error) {
      logger.error('CatalogSync', 'Forced full sync failed to start or run', { error });
      return false; // Indicate failure
    }
  }
  
  /**
   * Starts the sync process in the background.
   * Currently triggers a full sync.
   */
  public async startBackgroundSync(): Promise<boolean> {
    logger.info('CatalogSync', 'Starting background sync...');
    try {
      // For now, background sync triggers a full sync
      await this.runFullSync();
      return true; // Indicate sync process was started
    } catch (error) {
      logger.error('CatalogSync', 'Background sync failed to start or run', { error });
      return false; // Indicate failure
    }
  }
  
  /**
   * Reset sync status in case of stuck sync
   */
  public async resetSyncStatus(): Promise<void> {
    logger.info('CatalogSync', 'Resetting sync status in database...');
    if (!this.db) {
      this.db = await modernDb.getDatabase();
    }
    await this.db.runAsync(
      `UPDATE sync_status SET 
         last_sync_time = NULL, 
         is_syncing = 0, 
         sync_error = NULL, 
         sync_progress = 0, 
         sync_total = 0, 
         sync_type = NULL, 
         last_page_cursor = NULL, 
         last_sync_attempt = NULL, 
         sync_attempt_count = 0 
       WHERE id = 1`
    );
    logger.info('CatalogSync', 'Sync status reset.');
  }

  /**
   * Debug method to check if items exist in the database
   */
  public async checkItemsInDatabase(): Promise<{ categoryCount: number; itemCount: number }> {
    logger.debug('CatalogSync', 'Checking item counts in database...');
    const { counts } = await modernDb.checkDatabaseContent(); 
    
    // Define the expected row type (matching modernDb.ts)
    type CountRow = { table_name: string; count: number };

    // Helper to find count, using the now typed `counts` array
    const getCount = (tableName: string): number => {
      // Find the row, but treat it as potentially unknown first
      const row = counts.find((r: unknown): r is CountRow => 
        typeof r === 'object' && r !== null && (r as CountRow).table_name === tableName
      );
      // Now `row` is correctly typed as CountRow | undefined
      return row ? row.count : 0;
    };

    return { 
      categoryCount: getCount('categories'),
      itemCount: getCount('catalog_items')
      // Add other counts if needed
    };
  }

  /**
   * Manually trigger a full catalog sync
   * @param skipCategorySync Whether to skip syncing categories (speeds up full sync)
   */
  public async runFullSync(): Promise<void> {
    logger.info('CatalogSync', 'Starting full catalog sync run...');
    
    // Check auth before proceeding
    try {
      await this.checkAuthentication();
    } catch (authError) {
       logger.error('CatalogSync', 'Authentication failed before starting sync', { error: authError });
      await this.updateSyncStatus({ syncError: authError instanceof Error ? authError.message : String(authError), isSyncing: false });
      return; // Stop sync if not authenticated
    }
    
    let currentStatus = await this.getSyncStatus();

    // Prevent concurrent syncs
    if (currentStatus.isSyncing) {
      logger.warn('CatalogSync', 'Sync already in progress. Skipping new run.');
      return;
    }

    // --- Begin Sync --- 
    await this.updateSyncStatus({
      isSyncing: true,
      syncError: null,
      syncProgress: 0,
      syncTotal: 0, // Reset total, as it's hard to know beforehand
      syncType: 'full',
      lastSyncAttempt: new Date().toISOString(),
      syncAttemptCount: (currentStatus.syncAttemptCount || 0) + 1,
      // Keep last_page_cursor from status in case we are resuming
    });

    let cursor: string | null | undefined = currentStatus.last_page_cursor; // Start from stored cursor if available
    let page = 1;
    let totalObjectsProcessed = 0;
    const limit = 1000; // Page size (adjustable)
    const typesToFetch = 'ITEM,CATEGORY,MODIFIER_LIST,MODIFIER,TAX,DISCOUNT,IMAGE'; // All relevant types
    let successfulCompletion = false;

    try {
      // Clear previous catalog data before starting a full sync
      // Only clear if we are starting from the beginning (no cursor)
      if (!cursor) {
        logger.info('CatalogSync', 'Starting from beginning, clearing existing catalog data...');
        await modernDb.clearCatalogData();
        logger.info('CatalogSync', 'Existing catalog data cleared.');
      }
      
      do {
        logger.info('CatalogSync', `Fetching page ${page}. Cursor: ${cursor ? 'Yes' : 'No'}`);
        
        // Update progress (optional: track page number)
        await this.updateSyncStatus({ syncProgress: totalObjectsProcessed }); // Update progress with objects processed so far

        // Fetch page from API
        // Note: The API function gets the token internally via apiClient
        const response = await api.fetchCatalogPage(limit, cursor, typesToFetch);
        
        const objects = response.objects || [];
        const nextCursor = response.cursor;

        logger.info('CatalogSync', `Page ${page}: Received ${objects.length} objects. Next cursor: ${nextCursor ? 'Yes' : 'No'}`);

        if (objects.length > 0) {
           // Store fetched objects in the database
           logger.debug('CatalogSync', `Storing ${objects.length} objects from page ${page}...`);
           await modernDb.upsertCatalogObjects(objects);
           totalObjectsProcessed += objects.length;
           logger.debug('CatalogSync', `Stored objects from page ${page}. Total processed: ${totalObjectsProcessed}`);
        }

        cursor = nextCursor; // Update cursor for the next iteration

        // Store the latest cursor in case sync is interrupted
        await this.updateSyncStatus({ last_page_cursor: cursor }); 

        page++;

        // Optional delay to avoid overwhelming the backend or DB
        // await new Promise(resolve => setTimeout(resolve, 100)); 

      } while (cursor);

      // --- Sync Complete --- 
      logger.info('CatalogSync', `Full catalog sync completed successfully! Processed ${totalObjectsProcessed} objects.`);
      await this.updateSyncStatus({
        isSyncing: false,
        syncError: null,
        lastSyncTime: new Date().toISOString(),
        syncProgress: totalObjectsProcessed,
        syncTotal: totalObjectsProcessed, // Set total to processed count on success
        syncAttemptCount: 0, // Reset attempt count on success
        last_page_cursor: null // Clear cursor on successful completion
      });
      successfulCompletion = true;

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('CatalogSync', 'Full catalog sync failed', { error: errorMessage, page, lastCursor: cursor });
      await this.updateSyncStatus({
        isSyncing: false,
        syncError: `Sync failed on page ${page}: ${errorMessage}`,
        // Keep progress and attempt count
      });
    } finally {
       // Schedule next sync only if this one completed successfully
       if (successfulCompletion) {
         this.scheduleNextSync();
       }
    }
  }
}

// Export the singleton instance
const catalogSyncService = CatalogSyncService.getInstance();
export default catalogSyncService;