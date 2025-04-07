import * as Network from 'expo-network';
import { SQLiteDatabase } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system';
import logger from '../utils/logger';
import * as modernDb from './modernDb';
import * as SecureStore from 'expo-secure-store';
import * as tokenService from './tokenService';
import config from '../config';
import { PAGINATION_LIMIT } from '../constants';
import { SQLTransaction } from 'expo-sqlite';
import { getTokenInfo } from '../api/auth';
import { API_BASE_URL } from '../config/constants';
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
        this.syncTimer = setTimeout(() => this.startBackgroundSync(true), 60 * 60 * 1000); // 1 hour
        return;
      }
      
      const lastSync = new Date(status.lastSyncTime).getTime();
      const now = Date.now();
      const elapsed = now - lastSync;
      
      if (elapsed >= SYNC_INTERVAL) {
        // If interval passed, schedule for a reasonable future time
        logger.info('CatalogSync', 'Sync interval passed - scheduling sync in 10 minutes');
        this.syncTimer = setTimeout(() => this.startBackgroundSync(true), 10 * 60 * 1000); // 10 minutes
      } else {
        // Schedule for next interval
        const timeUntilNextSync = SYNC_INTERVAL - elapsed;
        logger.info('CatalogSync', `Scheduling next sync in ${Math.round(timeUntilNextSync / (60 * 1000))} minutes`);
        this.syncTimer = setTimeout(() => this.startBackgroundSync(true), timeUntilNextSync);
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
          syncAttemptCount: result.sync_attempt_count
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
          syncAttemptCount: 0
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
        syncAttemptCount: 0
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
   * Start a background sync operation
   * 
   * @param fullSync Whether to sync all items or just metadata
   * @param skipCategorySync Whether to skip category sync (only relevant when fullSync is true)
   * @returns Promise resolving to true if successful
   */
  public async startBackgroundSync(fullSync: boolean = false, skipCategorySync: boolean = false): Promise<boolean> {
    try {
      logger.info('CatalogSync', `Starting background sync, fullSync=${fullSync}, skipCategorySync=${skipCategorySync}`);
      
      // Check authentication before starting
      await this.checkAuthentication();
      
      // Check network connectivity
      const networkState = await Network.getNetworkStateAsync();
      if (!networkState.isConnected) {
        throw new Error('No network connection available');
      }
      
      // Get current sync status to check if already syncing
      const currentStatus = await this.getSyncStatus();
      if (currentStatus.isSyncing) {
        logger.warn('CatalogSync', 'Sync already in progress, cannot start another');
        return false;
      }
      
      // Update status to indicate sync has started
      await this.updateSyncStatus({
        isSyncing: true,
        syncError: null,
        syncProgress: 0,
        syncType: fullSync ? 'full' : 'categories',
        syncTotal: 0,
        lastSyncAttempt: new Date().toISOString(),
        syncAttemptCount: (currentStatus.syncAttemptCount || 0) + 1
      });
      
      try {
        // Always fetch merchant info first as it contains critical information
        await this.syncMerchantInfo();
        
        // Then fetch store locations 
        await this.syncLocations();
        
        // Sync categories unless explicitly skipped
        if (!skipCategorySync) {
          await this.syncCategories();
        } else {
          logger.info('CatalogSync', 'Skipping category sync as requested');
        }
        
        // If full sync, also sync catalog items
        if (fullSync) {
          logger.info('CatalogSync', 'Starting full catalog item sync with pagination');
          
          let cursor: string | null = null;
          let totalItems = 0;
          let batchNumber = 0;
          
          do {
            logger.debug('CatalogSync', 'Fetching items batch ' + (cursor ? `with cursor ${cursor.substring(0, 10)}...` : ''));
            const result = await this.syncCatalogItems(cursor, batchNumber === 0);
            
            if (!result.success) {
              throw new Error('Failed to sync catalog items batch');
            }
            
            cursor = result.cursor;
            totalItems += result.itemCount;
            batchNumber++;
            
          } while (cursor);
          
          logger.info('CatalogSync', `Completed item sync, processed ${totalItems} total items`);
        }
        
        // Update status to indicate successful completion
        await this.updateSyncStatus({
          isSyncing: false,
          lastSyncTime: new Date().toISOString()
        });
        
        logger.info('CatalogSync', 'Background sync completed successfully');
        return true;
      } catch (syncError) {
        // Update status to indicate failure
        await this.updateSyncStatus({
          isSyncing: false,
          syncError: syncError instanceof Error ? syncError.message : String(syncError)
        });
        
        logger.error('CatalogSync', 'Background sync failed', { error: syncError });
        throw syncError;
      }
    } catch (error) {
      logger.error('CatalogSync', 'Failed to start background sync', { error });
      throw error;
    }
  }
  
  /**
   * Check that we have proper authentication before starting sync
   */
  private async checkAuthentication(): Promise<void> {
    try {
      // Use SecureStore directly to check for token
      const token = await SecureStore.getItemAsync('square_access_token');
      if (!token) {
        throw new Error('No authentication token available');
      }
      
      logger.info('CatalogSync', 'Authentication verified successfully');
    } catch (error) {
      logger.error('CatalogSync', 'Authentication check failed', { error });
      throw new Error(`Authentication failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  
  /**
   * Check if we have a valid Square token
   */
  private async checkTokenValidity(): Promise<boolean> {
    try {
      logger.debug('CatalogSync', 'Checking if token is valid');
      
      // Check if we have an access token
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      if (!accessToken) {
        logger.debug('CatalogSync', 'No access token found');
        return false;
      }
      
      // Check if token has expired based on stored expiry
      const expiryTime = await SecureStore.getItemAsync(TOKEN_EXPIRY_KEY);
      if (expiryTime) {
        const expiry = new Date(expiryTime);
        const now = new Date();
        
        // If token is expired, return false
        if (expiry < now) {
          logger.debug('CatalogSync', 'Token is expired');
          return false;
        }
      }
      
      // Token exists and is not expired
      logger.debug('CatalogSync', 'Token exists and is not expired');
      return true;
    } catch (error) {
      logger.error('CatalogSync', 'Error checking token validity', error);
      return false;
    }
  }
  
  /**
   * Manually trigger a full catalog sync
   * @param skipCategorySync Whether to skip syncing categories (speeds up full sync)
   */
  public async forceFullSync(skipCategorySync: boolean = false): Promise<boolean> {
    try {
      logger.info('CatalogSync', `Forcing full catalog sync${skipCategorySync ? ' (skipping categories)' : ''}`);
      
      // Reset sync state
      await this.updateSyncStatus({
        isSyncing: false,
        syncError: null,
        syncProgress: 0,
        syncTotal: 0,
        syncAttemptCount: 0
      });
      
      // Check network connectivity
      const networkState = await Network.getNetworkStateAsync();
      if (!networkState.isConnected) {
        logger.warn('CatalogSync', 'No network connection - cannot sync');
        await this.updateSyncStatus({
          syncError: 'No network connection',
          lastSyncAttempt: new Date().toISOString()
        });
        return false;
      }
      
      // Test API connection - simplified approach
      try {
        logger.info('CatalogSync', 'Testing API connection');
        
        // Check if we have a valid token before proceeding
        const isTokenValid = await this.checkTokenValidity();
        if (!isTokenValid) {
          logger.warn('CatalogSync', 'No valid token found - cannot sync');
          await this.updateSyncStatus({
            syncError: 'No valid authentication token - please reconnect to Square',
            lastSyncAttempt: new Date().toISOString()
          });
          return false;
        }
        
        // Skip the API connectivity check since it's not available
        // Just proceed with the sync since we already checked network connectivity
        logger.info('CatalogSync', 'Network is connected, proceeding with sync');
      } catch (error) {
        logger.warn('CatalogSync', 'API connection test failed - cannot sync', { error });
        await this.updateSyncStatus({
          syncError: `API connection test failed: ${error instanceof Error ? error.message : String(error)}`,
          lastSyncAttempt: new Date().toISOString()
        });
        return false;
      }
      
      // Start sync process with skipCategorySync parameter
      await this.startBackgroundSync(true, skipCategorySync);
      return true;
    } catch (error) {
      logger.error('CatalogSync', 'Force sync failed', { error });
      
      // Update sync status with error
      await this.updateSyncStatus({
        isSyncing: false,
        syncError: `Force sync failed: ${error instanceof Error ? error.message : String(error)}`,
        syncProgress: 0,
        syncTotal: 0
      });
      
      return false;
    }
  }
  
  /**
   * Synchronize categories from Square API
   */
  public async syncCategories(): Promise<void> {
    try {
      logger.info('CatalogSync', 'Starting categories sync');
      
      // Check if the database is initialized
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      // Update sync status
      await this.updateSyncStatus({
        syncType: 'categories',
        syncProgress: 0,
        syncTotal: 1 // We don't know total yet
      });
      
      // First check if we have a valid token
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      if (!accessToken) {
        throw new Error('No access token available for categories sync');
      }
      
      // Make a direct fetch call to get categories
      const response = await fetch('https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/v2/catalog/list-categories', {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
          'Cache-Control': 'no-cache'
        }
      });
      
      if (!response.ok) {
        // Log HTTP errors in detail
        const errorText = await response.text();
        logger.error('CatalogSync', 'Failed to fetch categories - API error', { 
          status: response.status, 
          statusText: response.statusText,
          errorText: errorText.substring(0, 500)
        });
        throw new Error(`Failed to fetch categories: ${response.status} ${response.statusText}`);
      }
      
      // Parse and log the complete response for debugging
      const responseText = await response.text();
      logger.debug('CatalogSync', 'Raw categories API response', { 
        responseText: responseText.substring(0, 1000) + (responseText.length > 1000 ? '...' : '')
      });
      
      // Parse the response
      let responseData;
      try {
        responseData = JSON.parse(responseText);
      } catch (parseError) {
        logger.error('CatalogSync', 'Failed to parse categories response JSON', { 
          error: parseError,
          responsePreview: responseText.substring(0, 200)
        });
        throw new Error('Invalid JSON response from categories API');
      }
      
      // Log full response structure for debugging
      logger.debug('CatalogSync', 'Categories API response structure', { 
        responseKeys: responseData ? Object.keys(responseData) : [],
        responseType: typeof responseData,
        hasData: !!responseData?.data,
        dataKeys: responseData?.data ? Object.keys(responseData.data) : [],
        hasCategories: Array.isArray(responseData?.data?.categories),
        hasObjects: Array.isArray(responseData?.data?.objects),
        directObjects: Array.isArray(responseData?.objects)
      });
      
      // Extract categories from various possible response formats
      let categories = [];
      
      // Try multiple paths to find categories in the response
      if (responseData?.data?.categories && Array.isArray(responseData.data.categories)) {
        categories = responseData.data.categories;
        logger.debug('CatalogSync', `Found ${categories.length} categories in response.data.categories`);
      } 
      else if (responseData?.data?.objects && Array.isArray(responseData.data.objects)) {
        // Filter objects to only include categories
        categories = responseData.data.objects.filter((obj: any) => obj.type === 'CATEGORY');
        logger.debug('CatalogSync', `Found ${categories.length} categories filtered from ${responseData.data.objects.length} objects in response.data.objects`);
      } 
      else if (responseData?.objects && Array.isArray(responseData.objects)) {
        // Direct objects array
        categories = responseData.objects.filter((obj: any) => obj.type === 'CATEGORY');
        logger.debug('CatalogSync', `Found ${categories.length} categories filtered from ${responseData.objects.length} objects in response.objects`);
      }
      else if (responseData?.categories && Array.isArray(responseData.categories)) {
        // Direct categories array
        categories = responseData.categories;
        logger.debug('CatalogSync', `Found ${categories.length} categories in response.categories`);
      }
      else if (responseData?.data && typeof responseData.data === 'object') {
        // Try to interpret the data object itself as a categories collection
        if (Array.isArray(responseData.data)) {
          categories = responseData.data.filter((obj: any) => obj.type === 'CATEGORY' || !!obj.category_data);
          logger.debug('CatalogSync', `Found ${categories.length} categories in data array`);
        } else {
          logger.error('CatalogSync', 'Data object exists but is not in expected format', responseData.data);
        }
      }
      else if (Array.isArray(responseData)) {
        // Response itself is an array
        categories = responseData.filter((obj: any) => obj.type === 'CATEGORY' || !!obj.category_data);
        logger.debug('CatalogSync', `Found ${categories.length} categories in direct array response`);
      }
      
      // If we couldn't find categories in any standard location, try one more approach with custom logging
      if (categories.length === 0) {
        logger.warn('CatalogSync', 'No categories found in standard response locations, attempting deep search');
        
        // Log the first level of response keys with their types to help debug
        const firstLevelSummary = Object.keys(responseData || {}).map(key => {
          const value = responseData[key];
          return {
            key,
            type: typeof value,
            isArray: Array.isArray(value),
            length: Array.isArray(value) ? value.length : null,
            preview: typeof value === 'object' ? 
              (Array.isArray(value) && value.length > 0 ? 
                JSON.stringify(value[0]).substring(0, 100) : 
                JSON.stringify(value).substring(0, 100)) 
              : String(value)
          };
        });
        
        logger.debug('CatalogSync', 'First level response keys', { firstLevelSummary });
        
        // If there's any array in the response with objects that look like categories, use those
        for (const key of Object.keys(responseData || {})) {
          const value = responseData[key];
          if (Array.isArray(value) && value.length > 0) {
            // Check if items in this array look like categories
            const hasTypeField = value.some((item: any) => item.type === 'CATEGORY');
            const hasCategoryData = value.some((item: any) => item.category_data);
            const hasNameField = value.some((item: any) => item.name);
            
            if (hasTypeField || hasCategoryData || hasNameField) {
              const possibleCategories = value.filter((item: any) => 
                item.type === 'CATEGORY' || item.category_data || 
                (item.name && typeof item.name === 'string')
              );
              
              if (possibleCategories.length > 0) {
                categories = possibleCategories;
                logger.debug('CatalogSync', `Found ${categories.length} possible categories in ${key}`);
                break;
              }
            }
          }
        }
      }
      
      // If we still have no categories, this is an error
      if (categories.length === 0) {
        logger.error('CatalogSync', 'Could not find categories in any response format', {
          responsePreview: JSON.stringify(responseData).substring(0, 500)
        });
        throw new Error('No categories found in API response');
      }
      
      logger.info('CatalogSync', `Found ${categories.length} categories to sync`);
      
      // Update sync status with total
      await this.updateSyncStatus({
        syncTotal: categories.length
      });
      
      // Start a transaction for better performance
      await this.db.withTransactionAsync(async () => {
        const tx = this.db;
        if (!tx) return;
        
        // Clear existing categories
        await tx.runAsync('DELETE FROM categories');
        logger.debug('CatalogSync', 'Cleared existing categories from database');
        
        // Insert categories
        let processedCount = 0;
        for (const category of categories) {
          try {
            // Use safer property access with default values
            const categoryId = category.id || `generated-${Date.now()}-${processedCount}`;
            const categoryName = category.name || 'Unnamed Category';
            
            // Handle category_data wrapped format
            const categoryData = category.category_data || category;
            
            const imageUrl = categoryData.image_url || category.image_url || null;
            const description = categoryData.description || category.description || null;
            const available = categoryData.available !== false && category.available !== false;
            const sortOrder = categoryData.sort_order || category.sort_order || processedCount;
            
            logger.debug('CatalogSync', `Processing category: ${categoryName} (${categoryId})`);
            
            await tx.runAsync(
              `INSERT INTO categories (id, name, image_url, description, available, sort_order, updated_at) 
               VALUES (?, ?, ?, ?, ?, ?, ?)`,
              [
                categoryId,
                categoryName,
                imageUrl,
                description,
                available ? 1 : 0,
                sortOrder,
                new Date().toISOString()
              ]
            );
            
            processedCount++;
            
            // Update progress
            if (processedCount % 10 === 0 || processedCount === categories.length) {
              await this.updateSyncStatus({
                syncProgress: processedCount
              });
            }
          } catch (insertError) {
            // Log the specific category that failed to insert
            logger.error('CatalogSync', 'Failed to insert category', { 
              error: insertError, 
              categoryId: category.id || 'unknown',
              categoryName: category.name || 'Unnamed',
              categoryData: JSON.stringify(category).substring(0, 200) + '...' // Truncate to avoid huge logs
            });
            // Continue with other categories rather than failing the entire batch
          }
        }
        
        logger.info('CatalogSync', `Categories sync completed. Processed ${processedCount} categories`);
      });
    } catch (error) {
      // Improved error logging with more details
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : 'No stack trace';
      logger.error('CatalogSync', 'Failed to sync categories', { 
        error: errorMessage,
        stack: errorStack
      });
      throw new Error(`Failed to sync categories: ${errorMessage}`);
    }
  }
  
  /**
   * Synchronize catalog items starting from a cursor 
   */
  public async syncCatalogItems(cursor?: string | null, initialSync = false): Promise<{ cursor: string | null; success: boolean; itemCount: number }> {
    try {
      // Check network connectivity
      const networkState = await Network.getNetworkStateAsync();
      if (!networkState.isConnected) {
        throw new Error('No network connection available');
      }
      
      logger.info('CatalogSync', `Syncing catalog items${cursor ? ' from cursor' : ' from beginning'}`);
      
      // Get the current sync status
      const syncStatus = await this.getSyncStatus();
      
      // Increment sync progress
      await this.updateSyncStatus({
        syncProgress: initialSync ? 0 : syncStatus.syncProgress,
        syncType: 'items'
      });
      
      // Prepare search parameters with proper structure matching Square SDK format
      // Use the exact format from Square SDK example (camelCase for property names)
      const searchParams: any = {
        objectTypes: ["TAX", "MODIFIER", "CATEGORY", "ITEM"],
        limit: 1000,
        includeDeletedObjects: false,
        includeRelatedObjects: true,
      };
      
      // Add cursor if continuing pagination
      if (cursor) {
        searchParams.cursor = cursor;
      }
      
      // Enhanced logging of search parameters
      logger.debug('CatalogSync', 'Catalog search parameters', JSON.stringify(searchParams));
      
      try {
        // Get access token
        const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
        if (!accessToken) {
          throw new Error('No access token available for item search');
        }
        
        // For debug purposes, log the authentication token format (but not the full token)
        const tokenStart = accessToken.substring(0, 10);
        const tokenEnd = accessToken.substring(accessToken.length - 10);
        logger.debug('CatalogSync', `Using token: ${tokenStart}...${tokenEnd} (${accessToken.length} chars)`);
        
        // Direct fetch call to search catalog items
        const response = await fetch('https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/v2/catalog/search', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`,
            'Cache-Control': 'no-cache'
          },
          body: JSON.stringify(searchParams)
        });
        
        if (!response.ok) {
          const errorText = await response.text();
          logger.error('CatalogSync', 'Failed to search catalog items - API error', { 
            status: response.status, 
            statusText: response.statusText,
            errorText: errorText.substring(0, 500)
          });
          throw new Error(`API error when searching catalog items: ${response.status} ${response.statusText}`);
        }
        
        // Log raw response for debugging
        const responseText = await response.text();
        logger.debug('CatalogSync', 'Raw catalog items search response', { 
          responseStatus: response.status,
          responseStatusText: response.statusText,
          responseTextLength: responseText.length,
          responseTextPreview: responseText.substring(0, 500) + (responseText.length > 500 ? '...' : '')
        });
        
        // Parse the response
        let responseData;
        try {
          responseData = JSON.parse(responseText);
        } catch (error) {
          logger.error('CatalogSync', 'Failed to parse catalog search response', { 
            error,
            responsePreview: responseText.substring(0, 200)
          });
          throw new Error('Invalid JSON in catalog search response');
        }
        
        // Enhanced response logging
        logger.debug('CatalogSync', 'Catalog items search response received', { 
          responseType: typeof responseData,
          isNull: responseData === null,
          isObject: typeof responseData === 'object',
          responseKeys: responseData ? Object.keys(responseData) : [],
          success: responseData?.success || false,
          dataKeys: responseData?.data ? Object.keys(responseData.data) : [],
          objectCount: responseData?.objects?.length || 0, // Direct objects array in response
        });
        
        if (!responseData) {
          throw new Error('Empty response from catalog search API');
        }
        
        if (responseData.error) {
          throw new Error(`API error: ${responseData.error?.message || JSON.stringify(responseData.error) || 'Unknown error'}`);
        }
        
        // Account for different response structures
        let items = [];
        let nextCursor = null;
        
        // Handle different response structures - prioritize direct objects array
        if (Array.isArray(responseData.objects)) {
          // Direct Square API response format
          items = responseData.objects;
          nextCursor = responseData.cursor || null;
          logger.debug('CatalogSync', `Found ${items.length} objects in direct objects array`);
        } else if (responseData.data && Array.isArray(responseData.data.objects)) {
          items = responseData.data.objects;
          nextCursor = responseData.data.cursor || null;
          logger.debug('CatalogSync', `Found ${items.length} objects in data.objects array`);
        } else if (responseData.data && responseData.data.items) {
          items = responseData.data.items;
          nextCursor = responseData.data.cursor || null;
          logger.debug('CatalogSync', `Found ${items.length} objects in data.items array`);
        } else if (responseData.data) {
          // Best guess extraction
          items = responseData.data.objects || responseData.data.items || [];
          nextCursor = responseData.data.cursor || null;
          logger.debug('CatalogSync', `Found ${items.length} objects in data (best guess)`);
        } else {
          // Last resort: try to use the response itself if it's an array
          items = Array.isArray(responseData) ? responseData : [];
          logger.debug('CatalogSync', `Found ${items.length} objects from fallback extraction`);
        }
        
        // Log overall objects found
        logger.debug('CatalogSync', `Found ${items.length} catalog objects to process, cursor: ${nextCursor || 'none'}`);
        
        // Ensure database is initialized
        if (!this.db) {
          this.db = await modernDb.getDatabase();
        }
        
        // Group items by type with proper typing
        const itemsByType: {
          ITEM: any[];
          CATEGORY: any[];
          TAX: any[];
          MODIFIER: any[];
          [key: string]: any[];
        } = {
          ITEM: [],
          CATEGORY: [],
          TAX: [],
          MODIFIER: []
        };
        
        // Sort items by type
        items.forEach((item: any) => {
          if (item.type && itemsByType[item.type]) {
            itemsByType[item.type].push(item);
          }
        });
        
        logger.info('CatalogSync', 'Catalog items by type:', {
          items: itemsByType.ITEM.length,
          categories: itemsByType.CATEGORY.length,
          taxes: itemsByType.TAX.length,
          modifiers: itemsByType.MODIFIER.length
        });
        
        // Process the items in a transaction
        let processedCount = 0;
        
        if (items.length > 0) {
          // Handle initial sync cleanup if needed
          if (initialSync) {
            // Only clear tables if we're starting from the beginning
            await this.db.runAsync('DELETE FROM catalog_items');
            await this.db.runAsync('DELETE FROM catalog_taxes');
            await this.db.runAsync('DELETE FROM catalog_modifiers');
            // We don't clear categories here as they're handled separately
            logger.debug('CatalogSync', 'Cleared existing catalog objects from database during initial sync');
          }
          
          // Process ITEM objects
          if (itemsByType.ITEM.length > 0) {
            await this.processItemObjects(itemsByType.ITEM);
            processedCount += itemsByType.ITEM.length;
          }
          
          // Process CATEGORY objects (these may be additional to what we got in syncCategories)
          if (itemsByType.CATEGORY.length > 0) {
            await this.processCategoryObjects(itemsByType.CATEGORY);
            processedCount += itemsByType.CATEGORY.length;
          }
          
          // Process TAX objects
          if (itemsByType.TAX.length > 0) {
            await this.processTaxObjects(itemsByType.TAX);
            processedCount += itemsByType.TAX.length;
          }
          
          // Process MODIFIER objects
          if (itemsByType.MODIFIER.length > 0) {
            await this.processModifierObjects(itemsByType.MODIFIER);
            processedCount += itemsByType.MODIFIER.length;
          }
        }
        
        // Log the results
        logger.info('CatalogSync', `Processed ${processedCount} catalog objects${nextCursor ? ', more items available' : ''}`);
        
        // Update sync status with progress
        await this.updateSyncStatus({
          syncProgress: (syncStatus.syncProgress || 0) + processedCount
        });
        
        return { 
          cursor: nextCursor, 
          success: true,
          itemCount: processedCount 
        };
      } catch (apiError) {
        // Enhanced API error logging
        const errorMessage = apiError instanceof Error ? apiError.message : String(apiError);
        const errorStack = apiError instanceof Error ? apiError.stack : 'No stack trace';
        
        logger.error('CatalogSync', 'API error in catalog items sync', { 
          error: errorMessage, 
          stack: errorStack,
          // Try to extract more details if possible
          details: typeof apiError === 'object' ? JSON.stringify(apiError) : 'No details'
        });
        
        throw apiError; // Re-throw to be caught by outer catch
      }
    } catch (error) {
      // Improved overall error logging
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : 'No stack trace';
      
      logger.error('CatalogSync', 'Failed to sync catalog items', { 
        error: errorMessage, 
        stack: errorStack 
      });
      
      return { 
        cursor: null, 
        success: false,
        itemCount: 0
      };
    }
  }
  
  /**
   * Process ITEM type objects and save to database
   */
  private async processItemObjects(items: any[]): Promise<void> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      logger.info('CatalogSync', `Processing ${items.length} ITEM objects`);
      
      let successCount = 0;
      
      for (const item of items) {
        try {
          // Extract item data
          const itemId = item.id;
          
          // Get data from item_data if available, or from the item itself
          const itemData = item.item_data || item;
          
          const itemName = itemData.name || 'Unnamed Item';
          const imageUrl = itemData.image_url || null;
          const description = itemData.description || null;
          const available = itemData.available !== false ? 1 : 0;
          const sortOrder = itemData.sort_order || 0;
          const version = item.version || null;
          const updatedAt = item.updated_at || new Date().toISOString();
          const isDeleted = item.is_deleted ? 1 : 0;
          
          // Get tax related fields
          const isTaxable = itemData.is_taxable ? 1 : 0;
          const taxIds = itemData.tax_ids ? JSON.stringify(itemData.tax_ids) : null;
          
          // Get ecommerce fields
          const ecomAvailable = itemData.ecom_available ? 1 : 0;
          const productType = itemData.product_type || null;
          const skipModifierScreen = itemData.skip_modifier_screen ? 1 : 0;
          
          // Get category ID if available
          let categoryId = null;
          if (itemData.category_id) {
            categoryId = itemData.category_id;
          } else if (itemData.categories && itemData.categories.length > 0) {
            // Take the first category
            categoryId = itemData.categories[0].id;
          }
          
          // Store additional data as JSON
          const data = JSON.stringify(item);
          
          await this.db.runAsync(
            `INSERT OR REPLACE INTO catalog_items 
             (id, name, image_url, description, available, sort_order, updated_at, category_id, data,
              version, is_deleted, is_taxable, tax_ids, ecom_available, product_type, skip_modifier_screen, type) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              itemId,
              itemName,
              imageUrl,
              description,
              available,
              sortOrder,
              updatedAt,
              categoryId,
              data,
              version,
              isDeleted,
              isTaxable,
              taxIds,
              ecomAvailable,
              productType,
              skipModifierScreen,
              'ITEM'
            ]
          );
          
          successCount++;
        } catch (insertError) {
          // Log the specific item that failed to insert but continue with the others
          logger.error('CatalogSync', 'Failed to insert item', { 
            error: insertError, 
            itemId: item.id,
            itemName: item.name || (item.item_data ? item.item_data.name : 'Unknown')
          });
        }
      }
      
      logger.info('CatalogSync', `Successfully inserted/updated ${successCount} of ${items.length} ITEM objects`);
    } catch (error) {
      logger.error('CatalogSync', 'Error processing ITEM objects', { error });
      throw error;
    }
  }
  
  /**
   * Process CATEGORY type objects and save to database
   */
  private async processCategoryObjects(categories: any[]): Promise<void> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      logger.info('CatalogSync', `Processing ${categories.length} CATEGORY objects`);
      
      let successCount = 0;
      
      for (const category of categories) {
        try {
          // Extract category data
          const categoryId = category.id;
          
          // Get data from category_data if available, or from the category itself
          const categoryData = category.category_data || category;
          
          const categoryName = categoryData.name || 'Unnamed Category';
          const imageUrl = categoryData.image_url || null;
          const description = categoryData.description || null;
          const available = categoryData.available !== false ? 1 : 0;
          const sortOrder = categoryData.ordinal || 0;
          const version = category.version || null;
          const updatedAt = category.updated_at || new Date().toISOString();
          const isDeleted = category.is_deleted ? 1 : 0;
          
          // Additional category fields
          const parentCategoryId = categoryData.parent_category?.id || null;
          const ordinal = categoryData.ordinal || null;
          const categoryType = categoryData.category_type || null;
          const isTopLevel = categoryData.is_top_level ? 1 : 0;
          
          await this.db.runAsync(
            `INSERT OR REPLACE INTO categories 
             (id, name, image_url, description, available, sort_order, updated_at, version, is_deleted,
              parent_category_id, ordinal, category_type, is_top_level) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              categoryId,
              categoryName,
              imageUrl,
              description,
              available,
              sortOrder,
              updatedAt,
              version,
              isDeleted,
              parentCategoryId,
              ordinal,
              categoryType,
              isTopLevel
            ]
          );
          
          successCount++;
        } catch (insertError) {
          // Log the specific category that failed to insert but continue with the others
          logger.error('CatalogSync', 'Failed to insert category', { 
            error: insertError, 
            categoryId: category.id,
            categoryName: category.name || (category.category_data ? category.category_data.name : 'Unknown')
          });
        }
      }
      
      logger.info('CatalogSync', `Successfully inserted/updated ${successCount} of ${categories.length} CATEGORY objects`);
    } catch (error) {
      logger.error('CatalogSync', 'Error processing CATEGORY objects', { error });
      throw error;
    }
  }
  
  /**
   * Process TAX type objects and save to database
   */
  private async processTaxObjects(taxes: any[]): Promise<void> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      logger.info('CatalogSync', `Processing ${taxes.length} TAX objects`);
      
      let successCount = 0;
      
      for (const tax of taxes) {
        try {
          // Extract tax data
          const taxId = tax.id;
          
          // Get data from tax_data if available, or from the tax itself
          const taxData = tax.tax_data || tax;
          
          const taxName = taxData.name || 'Unnamed Tax';
          const calculationPhase = taxData.calculation_phase || null;
          const inclusionType = taxData.inclusion_type || null;
          const percentage = taxData.percentage || null;
          const appliesToCustomAmounts = taxData.applies_to_custom_amounts ? 1 : 0;
          const enabled = taxData.enabled !== false ? 1 : 0;
          const taxTypeId = taxData.tax_type_id || null;
          const taxTypeName = taxData.tax_type_name || null;
          const version = tax.version || null;
          const updatedAt = tax.updated_at || new Date().toISOString();
          const createdAt = tax.created_at || null;
          const isDeleted = tax.is_deleted ? 1 : 0;
          
          // Store additional data as JSON
          const data = JSON.stringify(tax);
          
          await this.db.runAsync(
            `INSERT OR REPLACE INTO catalog_taxes 
             (id, name, calculation_phase, inclusion_type, percentage, applies_to_custom_amounts, 
              enabled, tax_type_id, tax_type_name, version, updated_at, created_at, is_deleted, type, data) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              taxId,
              taxName,
              calculationPhase,
              inclusionType,
              percentage,
              appliesToCustomAmounts,
              enabled,
              taxTypeId,
              taxTypeName,
              version,
              updatedAt,
              createdAt,
              isDeleted,
              'TAX',
              data
            ]
          );
          
          successCount++;
        } catch (insertError) {
          // Log the specific tax that failed to insert but continue with the others
          logger.error('CatalogSync', 'Failed to insert tax', { 
            error: insertError, 
            taxId: tax.id,
            taxName: tax.name || (tax.tax_data ? tax.tax_data.name : 'Unknown')
          });
        }
      }
      
      logger.info('CatalogSync', `Successfully inserted/updated ${successCount} of ${taxes.length} TAX objects`);
    } catch (error) {
      logger.error('CatalogSync', 'Error processing TAX objects', { error });
      throw error;
    }
  }
  
  /**
   * Process MODIFIER type objects and save to database
   */
  private async processModifierObjects(modifiers: any[]): Promise<void> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      logger.info('CatalogSync', `Processing ${modifiers.length} MODIFIER objects`);
      
      let successCount = 0;
      
      for (const modifier of modifiers) {
        try {
          // Extract modifier data
          const modifierId = modifier.id;
          
          // Get data from modifier_data if available, or from the modifier itself
          const modifierData = modifier.modifier_data || modifier;
          
          const modifierName = modifierData.name || 'Unnamed Modifier';
          const priceAmount = modifierData.price_money?.amount || null;
          const priceCurrency = modifierData.price_money?.currency || null;
          const onByDefault = modifierData.on_by_default ? 1 : 0;
          const ordinal = modifierData.ordinal || null;
          const modifierListId = modifierData.modifier_list_id || null;
          const version = modifier.version || null;
          const updatedAt = modifier.updated_at || new Date().toISOString();
          const createdAt = modifier.created_at || null;
          const isDeleted = modifier.is_deleted ? 1 : 0;
          
          // Store additional data as JSON
          const data = JSON.stringify(modifier);
          
          await this.db.runAsync(
            `INSERT OR REPLACE INTO catalog_modifiers 
             (id, name, price_amount, price_currency, on_by_default, ordinal, modifier_list_id,
              version, updated_at, created_at, is_deleted, type, data) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              modifierId,
              modifierName,
              priceAmount,
              priceCurrency,
              onByDefault,
              ordinal,
              modifierListId,
              version,
              updatedAt,
              createdAt,
              isDeleted,
              'MODIFIER',
              data
            ]
          );
          
          successCount++;
        } catch (insertError) {
          // Log the specific modifier that failed to insert but continue with the others
          logger.error('CatalogSync', 'Failed to insert modifier', { 
            error: insertError, 
            modifierId: modifier.id,
            modifierName: modifier.name || (modifier.modifier_data ? modifier.modifier_data.name : 'Unknown')
          });
        }
      }
      
      logger.info('CatalogSync', `Successfully inserted/updated ${successCount} of ${modifiers.length} MODIFIER objects`);
    } catch (error) {
      logger.error('CatalogSync', 'Error processing MODIFIER objects', { error });
      throw error;
    }
  }
  
  /**
   * Reset sync status in case of stuck sync
   */
  public async resetSyncStatus(): Promise<void> {
    try {
      logger.warn('CatalogSync', 'Resetting sync status');
      
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      await this.updateSyncStatus({
        isSyncing: false,
        syncError: 'Sync reset by user',
        syncProgress: 0,
        syncTotal: 0,
        syncAttemptCount: 0
      });
      
      logger.info('CatalogSync', 'Sync status reset successfully');
    } catch (error) {
      logger.error('CatalogSync', 'Failed to reset sync status', { error });
      throw new Error(`Failed to reset sync status: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Debug method to check if items exist in the database
   */
  public async checkItemsInDatabase(): Promise<{ categoryCount: number; itemCount: number }> {
    try {
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      // Check categories count
      const categoryResult = await this.db.getFirstAsync<{ count: number }>('SELECT COUNT(*) as count FROM categories');
      const categoryCount = categoryResult?.count || 0;
      
      // Check items count
      const itemResult = await this.db.getFirstAsync<{ count: number }>('SELECT COUNT(*) as count FROM catalog_items');
      const itemCount = itemResult?.count || 0;
      
      logger.info('CatalogSync', 'Database content check', { categoryCount, itemCount });
      
      // Get some sample items if they exist
      if (itemCount > 0) {
        const sampleItems = await this.db.getAllAsync(
          'SELECT id, name FROM catalog_items LIMIT 5'
        );
        logger.info('CatalogSync', 'Sample items in database', { sampleItems });
      }
      
      return { categoryCount, itemCount };
    } catch (error) {
      logger.error('CatalogSync', 'Failed to check database content', { error });
      return { categoryCount: -1, itemCount: -1 };
    }
  }

  /**
   * Synchronize merchant information from Square API
   */
  public async syncMerchantInfo(): Promise<boolean> {
    try {
      logger.info('CatalogSync', 'Syncing merchant information');
      
      // Check network connectivity
      const networkState = await Network.getNetworkStateAsync();
      if (!networkState.isConnected) {
        throw new Error('No network connection available');
      }
      
      // Get merchant info from the API
      const response = await api.catalog.getMerchantInfo();
      
      if (!response || !response.merchant || !response.merchant.length) {
        logger.warn('CatalogSync', 'No merchant data returned from API');
        return false;
      }
      
      // Ensure database is initialized
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      try {
        // Check if merchant_info table exists, create it if not
        await this.db.runAsync(`CREATE TABLE IF NOT EXISTS merchant_info (
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
        
        logger.debug('CatalogSync', 'Merchant info table verified');
      } catch (tableError) {
        logger.error('CatalogSync', 'Error ensuring merchant_info table exists', { error: tableError });
      }
      
      // Process merchant data
      for (const merchant of response.merchant) {
        try {
          const merchantId = merchant.id;
          const businessName = merchant.business_name || 'Unknown';
          const country = merchant.country || null;
          const languageCode = merchant.language_code || null;
          const currency = merchant.currency || null;
          const status = merchant.status || null;
          const mainLocationId = merchant.main_location_id || null;
          const createdAt = merchant.created_at || new Date().toISOString();
          const logoUrl = merchant.logo_url || null;
          
          // Store additional data as JSON
          const data = JSON.stringify(merchant);
          
          // Insert or update merchant info
          await this.db.runAsync(
            `INSERT OR REPLACE INTO merchant_info 
             (id, business_name, country, language_code, currency, status, main_location_id, created_at, logo_url, data, last_updated) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              merchantId,
              businessName,
              country,
              languageCode,
              currency,
              status,
              mainLocationId,
              createdAt,
              logoUrl,
              data,
              new Date().toISOString()
            ]
          );
          
          logger.info('CatalogSync', `Stored merchant info: ${businessName} (${merchantId})`);
        } catch (error) {
          logger.error('CatalogSync', 'Failed to process merchant data', { error, merchantId: merchant.id });
        }
      }
      
      return true;
    } catch (error) {
      logger.error('CatalogSync', 'Failed to sync merchant info', { error });
      return false;
    }
  }
  
  /**
   * Synchronize location information from Square API
   */
  public async syncLocations(): Promise<boolean> {
    try {
      logger.info('CatalogSync', 'Syncing location information');
      
      // Check network connectivity
      const networkState = await Network.getNetworkStateAsync();
      if (!networkState.isConnected) {
        throw new Error('No network connection available');
      }
      
      // Get locations from the API
      const response = await api.catalog.getLocations();
      
      if (!response || !response.locations || !response.locations.length) {
        logger.warn('CatalogSync', 'No location data returned from API');
        return false;
      }
      
      // Ensure database is initialized
      if (!this.db) {
        this.db = await modernDb.getDatabase();
      }
      
      try {
        // Check if locations table exists, create it if not
        await this.db.runAsync(`CREATE TABLE IF NOT EXISTS locations (
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
        
        logger.debug('CatalogSync', 'Locations table verified');
      } catch (tableError) {
        logger.error('CatalogSync', 'Error ensuring locations table exists', { error: tableError });
      }
      
      // Process location data
      for (const location of response.locations) {
        try {
          const locationId = location.id;
          const name = location.name || 'Unknown Location';
          const merchantId = location.merchant_id || null;
          const address = location.address ? JSON.stringify(location.address) : null;
          const timezone = location.timezone || null;
          const phoneNumber = location.phone_number || null;
          const businessName = location.business_name || null;
          const businessEmail = location.business_email || null;
          const websiteUrl = location.website_url || null;
          const description = location.description || null;
          const status = location.status || null;
          const type = location.type || null;
          const logoUrl = location.logo_url || null;
          const createdAt = location.created_at || new Date().toISOString();
          
          // Store additional data as JSON
          const data = JSON.stringify(location);
          
          // Insert or update location
          await this.db.runAsync(
            `INSERT OR REPLACE INTO locations 
             (id, name, merchant_id, address, timezone, phone_number, business_name, business_email, 
              website_url, description, status, type, logo_url, created_at, data, last_updated) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              locationId,
              name,
              merchantId,
              address,
              timezone,
              phoneNumber,
              businessName,
              businessEmail,
              websiteUrl,
              description,
              status,
              type,
              logoUrl,
              createdAt,
              data,
              new Date().toISOString()
            ]
          );
          
          logger.info('CatalogSync', `Stored location: ${name} (${locationId})`);
        } catch (error) {
          logger.error('CatalogSync', 'Failed to process location data', { error, locationId: location.id });
        }
      }
      
      return true;
    } catch (error) {
      logger.error('CatalogSync', 'Failed to sync locations', { error });
      return false;
    }
  }
}

// Export the singleton instance
const catalogSyncService = CatalogSyncService.getInstance();
export default catalogSyncService;