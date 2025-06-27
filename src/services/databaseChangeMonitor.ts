import { getDatabase } from '../database/modernDb';
import crossReferenceService from './crossReferenceService';
import logger from '../utils/logger';

/**
 * Database Change Monitor Service
 * 
 * Monitors the local SQLite database for changes to Square catalog items
 * and team data, then automatically invalidates cross-reference caches
 * to ensure reorder lists show updated item details in real-time.
 * 
 * LOCAL-FIRST ARCHITECTURE:
 * - Monitors local SQLite database changes (not webhooks)
 * - Webhooks trigger catchup sync → updates local DB → this service detects changes
 * - No direct webhook listeners - relies on existing catchup sync architecture
 */

export interface DatabaseChange {
  table: 'catalog_items' | 'team_data';
  operation: 'INSERT' | 'UPDATE' | 'DELETE';
  itemId: string;
  timestamp: number;
}

type ChangeListener = (changes: DatabaseChange[]) => void;

class DatabaseChangeMonitor {
  private listeners: ChangeListener[] = [];
  private isMonitoring = false;
  private monitoringInterval: NodeJS.Timeout | null = null;
  private lastCheckTimestamp: number = 0;
  private readonly CHECK_INTERVAL = 2000; // Check every 2 seconds

  // Track last known state for change detection
  private lastCatalogChecksum: string = '';
  private lastTeamDataChecksum: string = '';

  /**
   * Start monitoring database changes
   */
  async startMonitoring(): Promise<void> {
    if (this.isMonitoring) {
      logger.debug('[DatabaseChangeMonitor]', 'Already monitoring database changes');
      return;
    }

    try {
      // Initialize baseline checksums
      await this.updateBaseline();
      
      this.isMonitoring = true;
      this.lastCheckTimestamp = Date.now();

      // Start periodic checking
      this.monitoringInterval = setInterval(async () => {
        await this.checkForChanges();
      }, this.CHECK_INTERVAL);

      logger.info('[DatabaseChangeMonitor]', 'Started monitoring database changes');
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Failed to start monitoring', { error });
    }
  }

  /**
   * Stop monitoring database changes
   */
  stopMonitoring(): void {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = null;
    }
    this.isMonitoring = false;
    logger.info('[DatabaseChangeMonitor]', 'Stopped monitoring database changes');
  }

  /**
   * Add listener for database changes
   */
  addListener(listener: ChangeListener): () => void {
    this.listeners.push(listener);
    
    // Start monitoring when first listener is added
    if (this.listeners.length === 1) {
      this.startMonitoring();
    }

    return () => {
      this.listeners = this.listeners.filter(l => l !== listener);
      
      // Stop monitoring when no listeners remain
      if (this.listeners.length === 0) {
        this.stopMonitoring();
      }
    };
  }

  /**
   * Check for database changes since last check
   */
  private async checkForChanges(): Promise<void> {
    try {
      const changes: DatabaseChange[] = [];
      const currentTime = Date.now();

      // Check catalog_items changes
      const catalogChanges = await this.checkCatalogChanges();
      changes.push(...catalogChanges);

      // Check team_data changes
      const teamDataChanges = await this.checkTeamDataChanges();
      changes.push(...teamDataChanges);

      // Notify listeners if changes detected
      if (changes.length > 0) {
        logger.info('[DatabaseChangeMonitor]', `Detected ${changes.length} database changes`, {
          catalogChanges: catalogChanges.length,
          teamDataChanges: teamDataChanges.length
        });

        // Invalidate cross-reference caches for changed items
        await this.invalidateCaches(changes);

        // Notify all listeners
        this.listeners.forEach(listener => {
          try {
            listener(changes);
          } catch (error) {
            logger.error('[DatabaseChangeMonitor]', 'Error in change listener', { error });
          }
        });
      }

      this.lastCheckTimestamp = currentTime;
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Error checking for database changes', { error });
    }
  }

  /**
   * Check for catalog_items table changes
   */
  private async checkCatalogChanges(): Promise<DatabaseChange[]> {
    try {
      const db = await getDatabase();
      
      // Get current checksum of catalog_items table
      const result = await db.getFirstAsync<{ checksum: string }>(
        `SELECT COUNT(*) || '-' || COALESCE(MAX(updated_at), '') as checksum 
         FROM catalog_items WHERE is_deleted = 0`
      );

      const currentChecksum = result?.checksum || '';
      
      if (currentChecksum !== this.lastCatalogChecksum && this.lastCatalogChecksum !== '') {
        logger.debug('[DatabaseChangeMonitor]', 'Catalog changes detected', {
          oldChecksum: this.lastCatalogChecksum,
          newChecksum: currentChecksum
        });

        // Get recently updated items (since last check)
        const recentlyUpdated = await db.getAllAsync<{ id: string; updated_at: string }>(
          `SELECT id, updated_at FROM catalog_items 
           WHERE is_deleted = 0 AND updated_at > datetime('now', '-${this.CHECK_INTERVAL * 2 / 1000} seconds')
           ORDER BY updated_at DESC`
        );

        this.lastCatalogChecksum = currentChecksum;

        return recentlyUpdated.map(item => ({
          table: 'catalog_items' as const,
          operation: 'UPDATE' as const,
          itemId: item.id,
          timestamp: Date.now()
        }));
      }

      this.lastCatalogChecksum = currentChecksum;
      return [];
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Error checking catalog changes', { error });
      return [];
    }
  }

  /**
   * Check for team_data table changes
   */
  private async checkTeamDataChanges(): Promise<DatabaseChange[]> {
    try {
      const db = await getDatabase();
      
      // Get current checksum of team_data table
      const result = await db.getFirstAsync<{ checksum: string }>(
        `SELECT COUNT(*) || '-' || COALESCE(MAX(last_updated), '') as checksum 
         FROM team_data`
      );

      const currentChecksum = result?.checksum || '';
      
      if (currentChecksum !== this.lastTeamDataChecksum && this.lastTeamDataChecksum !== '') {
        logger.debug('[DatabaseChangeMonitor]', 'Team data changes detected', {
          oldChecksum: this.lastTeamDataChecksum,
          newChecksum: currentChecksum
        });

        // Get recently updated items (since last check)
        const recentlyUpdated = await db.getAllAsync<{ item_id: string; last_updated: string }>(
          `SELECT item_id, last_updated FROM team_data 
           WHERE last_updated > datetime('now', '-${this.CHECK_INTERVAL * 2 / 1000} seconds')
           ORDER BY last_updated DESC`
        );

        this.lastTeamDataChecksum = currentChecksum;

        return recentlyUpdated.map(item => ({
          table: 'team_data' as const,
          operation: 'UPDATE' as const,
          itemId: item.item_id,
          timestamp: Date.now()
        }));
      }

      this.lastTeamDataChecksum = currentChecksum;
      return [];
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Error checking team data changes', { error });
      return [];
    }
  }

  /**
   * Invalidate cross-reference caches for changed items
   */
  private async invalidateCaches(changes: DatabaseChange[]): Promise<void> {
    try {
      const itemIds = [...new Set(changes.map(change => change.itemId))];
      
      logger.debug('[DatabaseChangeMonitor]', `Invalidating caches for ${itemIds.length} items`, { itemIds });

      // Clear cross-reference caches for affected items
      crossReferenceService.clearCaches();

      logger.info('[DatabaseChangeMonitor]', 'Cross-reference caches invalidated for changed items');
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Error invalidating caches', { error });
    }
  }

  /**
   * Update baseline checksums
   */
  private async updateBaseline(): Promise<void> {
    try {
      const db = await getDatabase();
      
      // Get initial catalog checksum
      const catalogResult = await db.getFirstAsync<{ checksum: string }>(
        `SELECT COUNT(*) || '-' || COALESCE(MAX(updated_at), '') as checksum 
         FROM catalog_items WHERE is_deleted = 0`
      );
      this.lastCatalogChecksum = catalogResult?.checksum || '';

      // Get initial team data checksum
      const teamDataResult = await db.getFirstAsync<{ checksum: string }>(
        `SELECT COUNT(*) || '-' || COALESCE(MAX(last_updated), '') as checksum 
         FROM team_data`
      );
      this.lastTeamDataChecksum = teamDataResult?.checksum || '';

      logger.debug('[DatabaseChangeMonitor]', 'Updated baseline checksums', {
        catalogChecksum: this.lastCatalogChecksum,
        teamDataChecksum: this.lastTeamDataChecksum
      });
    } catch (error) {
      logger.error('[DatabaseChangeMonitor]', 'Error updating baseline checksums', { error });
    }
  }

  /**
   * Get monitoring status
   */
  getStatus() {
    return {
      isMonitoring: this.isMonitoring,
      listenerCount: this.listeners.length,
      lastCheckTimestamp: this.lastCheckTimestamp,
      checkInterval: this.CHECK_INTERVAL
    };
  }
}

// Export singleton instance
export const databaseChangeMonitor = new DatabaseChangeMonitor();
export default databaseChangeMonitor;
