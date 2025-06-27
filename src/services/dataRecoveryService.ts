import logger from '../utils/logger';
import * as modernDb from '../database/modernDb';
import { generateClient } from 'aws-amplify/api';
import * as queries from '../graphql/queries';
import appSyncMonitor from './appSyncMonitor';
import AsyncStorage from '@react-native-async-storage/async-storage';

interface RecoveryStatus {
  lastRecoveryAttempt?: string;
  recoveryVersion?: number;
  teamDataRecovered?: boolean;
  reorderItemsRecovered?: boolean;
}

class DataRecoveryService {
  private static instance: DataRecoveryService;
  private client = generateClient();
  private readonly RECOVERY_VERSION = 1; // Increment when recovery logic changes
  private readonly STORAGE_KEY = 'data_recovery_status';

  static getInstance(): DataRecoveryService {
    if (!DataRecoveryService.instance) {
      DataRecoveryService.instance = new DataRecoveryService();
    }
    return DataRecoveryService.instance;
  }

  /**
   * Check if data recovery is needed and perform it
   * This runs once when the app starts and detects missing local data
   * LOCAL-FIRST: Only attempts recovery if user is signed in, otherwise gracefully continues
   */
  async checkAndRecoverData(): Promise<void> {
    try {
      logger.info('DataRecovery', '🔍 Checking if data recovery is needed...');

      // Check if we've already attempted recovery for this version
      const recoveryStatus = await this.getRecoveryStatus();

      if (recoveryStatus.recoveryVersion === this.RECOVERY_VERSION) {
        logger.info('DataRecovery', '✅ Data recovery already completed for this version');
        return;
      }

      // Check if local data is missing
      const needsRecovery = await this.checkIfRecoveryNeeded();

      if (!needsRecovery) {
        logger.info('DataRecovery', '✅ Local data exists, no recovery needed');
        await this.markRecoveryComplete();
        return;
      }

      logger.info('DataRecovery', '🔄 Local data missing, checking if recovery is possible...');

      // LOCAL-FIRST: Check if user is signed in before attempting AppSync recovery
      try {
        // Attempt a simple test query to see if we can connect
        await this.testAppSyncConnection();

        // If we get here, user is signed in and we can attempt recovery
        logger.info('DataRecovery', '🔄 User signed in, starting recovery from DynamoDB...');
        await this.performDataRecovery();
        await this.markRecoveryComplete();
        logger.info('DataRecovery', '✅ Data recovery completed successfully');

      } catch (connectionError) {
        // User not signed in or offline - this is OK for local-first
        logger.info('DataRecovery', '🔒 User not signed in or offline - continuing with local-only mode', { connectionError });

        // Mark recovery as attempted so we don't keep trying
        await this.markRecoveryComplete();
        logger.info('DataRecovery', '✅ Local-first mode enabled - app will work with local data only');
      }

    } catch (error) {
      logger.error('DataRecovery', '❌ Data recovery failed', { error });
      // Don't throw - this is a background operation
      // Mark as complete so we don't keep failing
      try {
        await this.markRecoveryComplete();
      } catch (markError) {
        logger.error('DataRecovery', 'Failed to mark recovery complete', { markError });
      }
    }
  }

  /**
   * Check if recovery is needed by examining local database
   */
  private async checkIfRecoveryNeeded(): Promise<boolean> {
    try {
      const db = await modernDb.getDatabase();
      
      // Check if team_data table has any data
      const teamDataCount = await db.getFirstAsync<{ count: number }>(`
        SELECT COUNT(*) as count FROM team_data
      `);
      
      // Check if reorder_items table has any data
      const reorderItemsCount = await db.getFirstAsync<{ count: number }>(`
        SELECT COUNT(*) as count FROM reorder_items
      `);
      
      const hasTeamData = (teamDataCount?.count || 0) > 0;
      const hasReorderItems = (reorderItemsCount?.count || 0) > 0;
      
      logger.info('DataRecovery', 'Local data check', {
        teamDataCount: teamDataCount?.count || 0,
        reorderItemsCount: reorderItemsCount?.count || 0,
        hasTeamData,
        hasReorderItems
      });
      
      // Recovery needed if both tables are empty
      return !hasTeamData && !hasReorderItems;
      
    } catch (error) {
      logger.error('DataRecovery', 'Error checking if recovery needed', { error });
      return true; // Assume recovery needed if we can't check
    }
  }

  /**
   * Test if we can connect to AppSync (user signed in)
   */
  private async testAppSyncConnection(): Promise<void> {
    try {
      // Simple test query with minimal data
      const response = await this.client.graphql({
        query: queries.listItemDatas,
        variables: {
          limit: 1
        }
      }) as any;

      // If we get here without error, connection works
      logger.debug('DataRecovery', 'AppSync connection test successful');
    } catch (error) {
      logger.debug('DataRecovery', 'AppSync connection test failed', { error });
      throw error;
    }
  }

  /**
   * Perform the actual data recovery from DynamoDB
   */
  private async performDataRecovery(): Promise<void> {
    try {
      // Recover team data
      await this.recoverTeamData();
      
      // Recover reorder items
      await this.recoverReorderItems();
      
    } catch (error) {
      logger.error('DataRecovery', 'Error during data recovery', { error });
      throw error;
    }
  }

  /**
   * Recover all team data from DynamoDB
   */
  private async recoverTeamData(): Promise<void> {
    try {
      logger.info('DataRecovery', '🔄 Recovering team data from DynamoDB...');
      
      // Monitor AppSync request
      await appSyncMonitor.beforeRequest('listItemDatas', 'DataRecovery:teamData', { limit: 1000 });
      
      const response = await this.client.graphql({
        query: queries.listItemDatas,
        variables: {
          limit: 1000
        }
      }) as any;
      
      if (response.data?.listItemDatas?.items) {
        const teamDataItems = response.data.listItemDatas.items;
        
        logger.info('DataRecovery', `Found ${teamDataItems.length} team data items to recover`);
        
        for (const item of teamDataItems) {
          try {
            await modernDb.upsertTeamData({
              itemId: item.id,
              caseUpc: item.caseUpc,
              caseCost: item.caseCost,
              caseQuantity: item.caseQuantity,
              vendor: item.vendor,
              discontinued: item.discontinued,
              notes: item.notes?.[0]?.content,
              lastSyncAt: new Date().toISOString(),
              owner: item.owner
            });
          } catch (error) {
            logger.warn('DataRecovery', 'Failed to recover team data item', { itemId: item.id, error });
          }
        }
        
        logger.info('DataRecovery', `✅ Team data recovery completed: ${teamDataItems.length} items`);
      } else {
        logger.info('DataRecovery', '📭 No team data found in DynamoDB');
      }
      
    } catch (error) {
      logger.error('DataRecovery', 'Team data recovery failed', { error });
      throw error;
    }
  }

  /**
   * Recover all reorder items from DynamoDB
   */
  private async recoverReorderItems(): Promise<void> {
    try {
      logger.info('DataRecovery', '🔄 Recovering reorder items from DynamoDB...');
      
      // Monitor AppSync request
      await appSyncMonitor.beforeRequest('listReorderItems', 'DataRecovery:reorderItems', { limit: 1000 });
      
      const response = await this.client.graphql({
        query: queries.listReorderItems,
        variables: {
          limit: 1000
        }
      }) as any;
      
      if (response.data?.listReorderItems?.items) {
        const reorderItems = response.data.listReorderItems.items;
        
        logger.info('DataRecovery', `Found ${reorderItems.length} reorder items to recover`);
        
        const db = await modernDb.getDatabase();
        const now = new Date().toISOString();
        
        await db.withTransactionAsync(async () => {
          for (const item of reorderItems) {
            try {
              await db.runAsync(`
                INSERT OR REPLACE INTO reorder_items
                (id, item_id, quantity, status, added_by, created_at, updated_at, last_sync_at, owner, pending_sync)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              `, [
                item.id,
                item.itemId,                    // Reference to Square catalog
                item.quantity,                  // Reorder quantity
                item.status || 'incomplete',    // 'incomplete' | 'complete'
                item.addedBy,                   // Who added it
                item.createdAt,                 // Timestamps
                item.updatedAt,
                now,                           // Last sync timestamp
                item.owner,
                0 // not pending sync
              ]);
            } catch (error) {
              logger.warn('DataRecovery', 'Failed to recover reorder item', { itemId: item.id, error });
            }
          }
        });
        
        logger.info('DataRecovery', `✅ Reorder items recovery completed: ${reorderItems.length} items`);
      } else {
        logger.info('DataRecovery', '📭 No reorder items found in DynamoDB');
      }
      
    } catch (error) {
      logger.error('DataRecovery', 'Reorder items recovery failed', { error });
      throw error;
    }
  }

  /**
   * Get recovery status from storage
   */
  private async getRecoveryStatus(): Promise<RecoveryStatus> {
    try {
      const stored = await AsyncStorage.getItem(this.STORAGE_KEY);
      return stored ? JSON.parse(stored) : {};
    } catch (error) {
      logger.error('DataRecovery', 'Failed to get recovery status', { error });
      return {};
    }
  }

  /**
   * Mark recovery as complete
   */
  private async markRecoveryComplete(): Promise<void> {
    try {
      const status: RecoveryStatus = {
        lastRecoveryAttempt: new Date().toISOString(),
        recoveryVersion: this.RECOVERY_VERSION,
        teamDataRecovered: true,
        reorderItemsRecovered: true
      };
      
      await AsyncStorage.setItem(this.STORAGE_KEY, JSON.stringify(status));
      logger.info('DataRecovery', 'Recovery marked as complete');
    } catch (error) {
      logger.error('DataRecovery', 'Failed to mark recovery complete', { error });
    }
  }

  /**
   * Force a new recovery (for testing or manual recovery)
   */
  async forceRecovery(): Promise<void> {
    try {
      // Clear recovery status to force new recovery
      await AsyncStorage.removeItem(this.STORAGE_KEY);
      
      // Perform recovery
      await this.checkAndRecoverData();
    } catch (error) {
      logger.error('DataRecovery', 'Force recovery failed', { error });
      throw error;
    }
  }
}

export default DataRecoveryService.getInstance();
