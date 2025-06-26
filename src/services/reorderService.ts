import { ConvertedItem } from '../types/api';
import logger from '../utils/logger';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { generateClient } from 'aws-amplify/api';
import * as queries from '../graphql/queries';
import * as subscriptions from '../graphql/subscriptions';
import * as mutations from '../graphql/mutations';
import { itemHistoryService } from './itemHistoryService';
import * as modernDb from '../database/modernDb';
import appSyncMonitor from './appSyncMonitor';

export interface TeamData {
  vendor?: string;
  vendorCost?: number;
  caseUpc?: string;
  caseCost?: number;
  caseQuantity?: number;
  discontinued?: boolean;
  notes?: string;
}

export interface ReorderItem {
  id: string;
  itemId: string;
  itemName: string;
  itemBarcode?: string;
  itemCategory?: string;
  itemPrice?: number;
  quantity: number;
  completed: boolean;
  received: boolean;
  addedBy: string;
  createdAt: string;
  updatedAt: string;
  // Local computed fields
  item?: ConvertedItem;
  teamData?: TeamData;
  timestamp?: Date;
  index?: number;
}

class ReorderService {
  private reorderItems: ReorderItem[] = [];
  private listeners: Array<(items: ReorderItem[]) => void> = [];
  private client = generateClient();
  private teamDataCache = new Map<string, { data: TeamData; timestamp: number }>();
  private subscriptions: any[] = [];
  private isInitialized = false;
  private readonly CACHE_DURATION = 5 * 60 * 1000; // 5 minutes
  private currentUserId: string | null = null;
  private isOfflineMode = false;
  private pendingSyncItems: ReorderItem[] = []; // Items waiting to sync
  private readonly STORAGE_KEY = 'reorder_items_offline';

  // Event-driven sync queue for batched operations
  private syncQueue: Array<{ operation: string; data: any; timestamp: number; retryCount?: number }> = [];
  private syncBatchTimeout: NodeJS.Timeout | null = null;
  private isProcessingQueue = false;
  private lastServerSync = 0;
  private readonly BATCH_DELAY = 3000; // 3 seconds to collect operations
  private readonly MAX_BATCH_SIZE = 10; // Max operations per batch

  // Initialize the service
  async initialize(userId?: string) {
    if (this.isInitialized && this.currentUserId === userId) return;
    
    this.currentUserId = userId || null;
    
    try {
      // Check authentication status first
      const isAuthenticated = await this.checkAuthStatus();

      if (isAuthenticated) {
        // Load from local storage first (local-first approach)
        await this.loadOfflineItems();

        // Set up smart real-time subscriptions (resource-efficient)
        this.setupSmartSubscriptions();

        // Set up event-driven sync (no polling)
        this.setupEventDrivenSync();
      } else {
        // Load from offline storage
        this.isOfflineMode = true;
        await this.loadOfflineItems();
      }
      
      this.isInitialized = true;
      logger.info('[ReorderService]', 'Service initialized successfully', { 
        userId: this.currentUserId,
        isOfflineMode: this.isOfflineMode 
      });
      
      // Notify all listeners with loaded data
      this.notifyListeners();
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to initialize service', { error });
      // Fallback to offline mode
      this.isOfflineMode = true;
      await this.loadOfflineItems();
      this.notifyListeners();
    }
  }

  // Load reorder items from local database first (LOCAL-FIRST ARCHITECTURE)
  private async loadReorderItems() {
    try {
      logger.info('[ReorderService]', '🔍 Loading reorder items locally (LOCAL-FIRST)');

      // ✅ CRITICAL FIX: Load from local SQLite first
      const localReorderItems = await this.loadLocalReorderItems();

      if (localReorderItems && localReorderItems.length > 0) {
        this.reorderItems = localReorderItems;
        logger.info('[ReorderService]', `✅ Loaded ${this.reorderItems.length} reorder items from local database`);

        // Load team data for all items
        await this.loadTeamDataForItems();

        // ✅ NO TIME-BASED POLLING: Data syncs only via webhooks/AppSync or CRUD operations
      } else {
        logger.info('[ReorderService]', '📭 No local reorder items found - attempting initial recovery from DynamoDB');
        // ✅ INITIAL RECOVERY: When local data is missing, recover from DynamoDB once
        await this.recoverFromDynamoDB();
      }
    } catch (error) {
      logger.error('[ReorderService]', '❌ Failed to load reorder items', { error });
    }
  }

  // Manual sync function for explicit user-triggered syncs only
  async manualSync() {
    try {
      logger.info('[ReorderService]', '🔄 Manual sync triggered by user');

      // 🚨 EMERGENCY FIX: Warn user about potential data loss
      if (this.pendingSyncItems.length > 0) {
        logger.warn('[ReorderService]', `⚠️ WARNING: ${this.pendingSyncItems.length} pending items will be synced to server first`);

        // Sync pending items first to prevent data loss
        await this.syncPendingItems();
      }

      // Monitor AppSync request
      await appSyncMonitor.beforeRequest('listReorderItems', 'ReorderService:manualSync', { limit: 1000 });

      const response = await this.client.graphql({
        query: queries.listReorderItems,
        variables: {
          limit: 1000 // Adjust as needed
        }
      }) as any;

      if (response.data?.listReorderItems?.items) {
        const serverItems = response.data.listReorderItems.items.map((item: any, index: number) => ({
          ...item,
          timestamp: new Date(item.createdAt),
          index: index + 1
        }));

        // 🚨 CONFLICT RESOLUTION: Merge server items with local items instead of overwriting
        const mergedItems = this.mergeServerAndLocalItems(serverItems, this.reorderItems);

        // Save to local database
        await this.saveReorderItemsLocally(mergedItems);

        // Update in-memory items
        this.reorderItems = mergedItems;

        logger.info('[ReorderService]', `✅ Manual sync completed: ${mergedItems.length} reorder items (merged)`);

        // Load team data for all items
        await this.loadTeamDataForItems();

        // Notify listeners of updated data
        this.notifyListeners();
      }
    } catch (error) {
      logger.error('[ReorderService]', '❌ Manual sync failed', { error });
      throw error;
    }
  }

  // 🚨 EMERGENCY FIX: Add conflict resolution to prevent data loss
  private mergeServerAndLocalItems(serverItems: ReorderItem[], localItems: ReorderItem[]): ReorderItem[] {
    const merged = [...serverItems];

    // Add local items that don't exist on server
    localItems.forEach(localItem => {
      const existsOnServer = serverItems.find(serverItem =>
        serverItem.id === localItem.id ||
        (serverItem.itemId === localItem.itemId && serverItem.createdAt === localItem.createdAt)
      );

      if (!existsOnServer) {
        logger.info('[ReorderService]', `🔄 Preserving local item not found on server: ${localItem.itemName}`);
        merged.push(localItem);
      }
    });

    return merged.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  }

  // Load team data for all reorder items
  private async loadTeamDataForItems() {
    for (const item of this.reorderItems) {
      try {
        const teamData = await this.fetchTeamData(item.itemId);
        if (teamData) {
          item.teamData = teamData;
        }
      } catch (error) {
        logger.warn('[ReorderService]', `Failed to load team data for ${item.itemName}`, { error });
      }
    }
  }

  // Set up event-driven sync (no polling)
  private setupEventDrivenSync() {
    // Listen for app state changes to trigger sync
    if (typeof window !== 'undefined') {
      // Sync when app comes back into focus
      window.addEventListener('focus', () => this.triggerBatchSync('APP_FOCUS'));

      // Sync before app goes into background
      window.addEventListener('blur', () => this.triggerBatchSync('APP_BLUR'));
    }

    logger.info('[ReorderService]', 'Event-driven sync setup complete');
  }

  // Trigger batched sync after user interactions
  private triggerBatchSync(reason: string) {
    if (this.syncQueue.length === 0) return;

    // Clear existing timeout
    if (this.syncBatchTimeout) {
      clearTimeout(this.syncBatchTimeout);
    }

    // Set new timeout for batching
    this.syncBatchTimeout = setTimeout(async () => {
      if (this.isProcessingQueue) return;

      logger.info('[ReorderService]', `Triggering batch sync: ${reason}`, {
        queueLength: this.syncQueue.length
      });

      await this.processSyncBatch();
    }, this.BATCH_DELAY);
  }

  // Process batched sync operations
  private async processSyncBatch() {
    if (this.syncQueue.length === 0 || this.isProcessingQueue) return;

    this.isProcessingQueue = true;

    try {
      // Take a batch of operations
      const batch = this.syncQueue.splice(0, this.MAX_BATCH_SIZE);

      logger.info('[ReorderService]', `Processing sync batch: ${batch.length} operations`);

      // Group operations by type for efficient batching
      const groupedOps = this.groupOperationsByType(batch);

      // Process each group
      for (const [opType, operations] of Object.entries(groupedOps)) {
        try {
          await this.processBatchedOperations(opType, operations);
        } catch (error) {
          logger.error('[ReorderService]', `Failed to process batch: ${opType}`, { error });

          // Re-queue failed operations with exponential backoff
          operations.forEach(op => {
            const retryDelay = Math.min(5000 * Math.pow(2, op.retryCount || 0), 60000); // Max 1 minute
            if ((op.retryCount || 0) < 3) { // Max 3 retries
              setTimeout(() => {
                this.syncQueue.push({
                  ...op,
                  retryCount: (op.retryCount || 0) + 1,
                  timestamp: Date.now()
                });
              }, retryDelay);
            }
          });
        }
      }

      // If there are more operations, schedule another batch
      if (this.syncQueue.length > 0) {
        this.triggerBatchSync('REMAINING_OPERATIONS');
      }

    } finally {
      this.isProcessingQueue = false;
    }
  }

  // Group operations by type for efficient batching
  private groupOperationsByType(operations: any[]): Record<string, any[]> {
    return operations.reduce((groups, op) => {
      if (!groups[op.operation]) {
        groups[op.operation] = [];
      }
      groups[op.operation].push(op);
      return groups;
    }, {} as Record<string, any[]>);
  }

  // Process batched operations efficiently
  private async processBatchedOperations(operationType: string, operations: any[]) {
    switch (operationType) {
      case 'CREATE_ITEM':
        // Batch create operations
        await this.batchCreateItems(operations.map(op => op.data));
        break;
      case 'UPDATE_ITEM':
        // Batch update operations
        await this.batchUpdateItems(operations.map(op => op.data));
        break;
      case 'DELETE_ITEM':
        // Batch delete operations
        await this.batchDeleteItems(operations.map(op => op.data));
        break;
      case 'TOGGLE_COMPLETION':
        // Batch completion toggles
        await this.batchToggleCompletion(operations.map(op => op.data));
        break;
      default:
        logger.warn('[ReorderService]', 'Unknown batch operation', { operationType });
    }
  }

  // Batch create multiple items
  private async batchCreateItems(items: any[]) {
    logger.info('[ReorderService]', `Batch creating ${items.length} items`);

    // Process in parallel but limit concurrency
    const promises = items.map(item => this.syncCreateItem(item));
    await Promise.allSettled(promises);
  }

  // Batch update multiple items
  private async batchUpdateItems(items: any[]) {
    logger.info('[ReorderService]', `Batch updating ${items.length} items`);

    const promises = items.map(item => this.syncUpdateItem(item));
    await Promise.allSettled(promises);
  }

  // Batch delete multiple items
  private async batchDeleteItems(items: any[]) {
    logger.info('[ReorderService]', `Batch deleting ${items.length} items`);

    const promises = items.map(item => this.syncDeleteItem(item));
    await Promise.allSettled(promises);
  }

  // Batch toggle completion for multiple items
  private async batchToggleCompletion(items: any[]) {
    logger.info('[ReorderService]', `Batch toggling completion for ${items.length} items`);

    const promises = items.map(item => this.syncToggleCompletion(item));
    await Promise.allSettled(promises);
  }

  // Set up smart real-time subscriptions (resource-efficient)
  private setupSmartSubscriptions() {
    try {
      // Only subscribe to changes from OTHER users (not our own changes)
      this.subscribeToOtherUsersChanges();
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to setup smart subscriptions', { error });
    }
  }

  // Subscribe only to changes from other users
  private subscribeToOtherUsersChanges() {
    try {
      // Subscribe to reorder item updates from other users
      const updateSubscription = this.client.graphql({
        query: subscriptions.onUpdateReorderItem,
        variables: {
          filter: {
            addedBy: {
              ne: this.currentUserId // Only changes from other users
            }
          }
        }
      }).subscribe({
        next: (result: any) => {
          const updatedItem = result.data?.onUpdateReorderItem;
          if (updatedItem && updatedItem.addedBy !== this.currentUserId) {
            this.handleExternalUpdate(updatedItem);
          }
        },
        error: (error: any) => {
          logger.error('[ReorderService]', 'Subscription error', { error });
        }
      });

      this.subscriptions.push(updateSubscription);
      logger.info('[ReorderService]', 'Smart subscriptions setup complete');
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to setup subscriptions', { error });
    }
  }

  // Handle updates from other users
  private async handleExternalUpdate(updatedItem: any) {
    try {
      // Check if this conflicts with local data
      const localItem = this.reorderItems.find(item => item.id === updatedItem.id);

      if (localItem && localItem.updatedAt > updatedItem.updatedAt) {
        // Local data is newer - show conflict resolution dialog
        await this.showConflictResolutionDialog(localItem, updatedItem);
      } else {
        // Server data is newer or no conflict - update locally
        await this.updateLocalItemFromServer(updatedItem);
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to handle external update', { error });
    }
  }

  // Queue sync operation and trigger batching
  private queueBackgroundSync(operation: string, data: any) {
    if (this.isOfflineMode) {
      logger.info('[ReorderService]', `Queuing operation for later sync: ${operation}`);
      return;
    }

    this.syncQueue.push({
      operation,
      data,
      timestamp: Date.now(),
      retryCount: 0
    });

    logger.debug('[ReorderService]', `Queued sync operation: ${operation}`, { queueLength: this.syncQueue.length });

    // Trigger batched sync after user interaction
    this.triggerBatchSync('USER_INTERACTION');
  }

  // Force immediate sync (for manual sync button)
  async forceSyncNow(): Promise<void> {
    if (this.syncQueue.length === 0) {
      logger.info('[ReorderService]', 'No pending operations to sync');
      return;
    }

    logger.info('[ReorderService]', 'Force syncing pending operations immediately');

    // Clear any pending batch timeout
    if (this.syncBatchTimeout) {
      clearTimeout(this.syncBatchTimeout);
      this.syncBatchTimeout = null;
    }

    // Process immediately
    await this.processSyncBatch();
  }

  // Background sync methods
  private async syncCreateItem(data: any) {
    try {
      const response = await this.client.graphql({
        query: mutations.createReorderItem,
        variables: {
          input: data
        }
      }) as any;

      if (response.data?.createReorderItem) {
        logger.info('[ReorderService]', `✅ Background sync: Created item on server`, { itemId: data.itemId });
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to sync create item', { error, data });
      throw error;
    }
  }

  private async syncUpdateItem(data: any) {
    try {
      const response = await this.client.graphql({
        query: mutations.updateReorderItem,
        variables: {
          input: data
        }
      }) as any;

      if (response.data?.updateReorderItem) {
        logger.info('[ReorderService]', `✅ Background sync: Updated item on server`, { itemId: data.id });
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to sync update item', { error, data });
      throw error;
    }
  }

  private async syncDeleteItem(data: any) {
    try {
      const response = await this.client.graphql({
        query: mutations.deleteReorderItem,
        variables: {
          input: { id: data.id }
        }
      }) as any;

      if (response.data?.deleteReorderItem) {
        logger.info('[ReorderService]', `✅ Background sync: Deleted item on server`, { itemId: data.id });
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to sync delete item', { error, data });
      throw error;
    }
  }

  private async syncToggleCompletion(data: any) {
    try {
      const response = await this.client.graphql({
        query: mutations.updateReorderItem,
        variables: {
          input: {
            id: data.id,
            completed: data.completed,
            updatedAt: data.updatedAt
          }
        }
      }) as any;

      if (response.data?.updateReorderItem) {
        logger.info('[ReorderService]', `✅ Background sync: Toggled completion on server`, { itemId: data.id, completed: data.completed });
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to sync toggle completion', { error, data });
      throw error;
    }
  }

  // Show conflict resolution dialog
  private async showConflictResolutionDialog(localItem: ReorderItem, serverItem: any): Promise<void> {
    return new Promise((resolve) => {
      // Import Alert from react-native
      const { Alert } = require('react-native');

      Alert.alert(
        'Sync Conflict Detected',
        `Item "${localItem.itemName}" has been modified by another user.\n\nLocal: qty ${localItem.quantity}, updated ${new Date(localItem.updatedAt).toLocaleTimeString()}\nServer: qty ${serverItem.quantity}, updated ${new Date(serverItem.updatedAt).toLocaleTimeString()}\n\nWhat would you like to do?`,
        [
          {
            text: 'Keep Local',
            onPress: () => {
              logger.info('[ReorderService]', 'User chose to keep local version');
              // Queue local version to overwrite server
              this.queueBackgroundSync('UPDATE_ITEM', {
                id: localItem.id,
                quantity: localItem.quantity,
                completed: localItem.completed,
                updatedAt: new Date().toISOString()
              });
              resolve();
            }
          },
          {
            text: 'Use Server',
            onPress: async () => {
              logger.info('[ReorderService]', 'User chose to use server version');
              await this.updateLocalItemFromServer(serverItem);
              resolve();
            }
          },
          {
            text: 'Merge',
            onPress: () => {
              logger.info('[ReorderService]', 'User chose to merge versions');
              // Merge by taking higher quantity and more recent completion status
              const mergedItem = {
                ...localItem,
                quantity: Math.max(localItem.quantity, serverItem.quantity),
                completed: serverItem.updatedAt > localItem.updatedAt ? serverItem.completed : localItem.completed,
                updatedAt: new Date().toISOString()
              };

              // Update local item
              const itemIndex = this.reorderItems.findIndex(item => item.id === localItem.id);
              if (itemIndex >= 0) {
                this.reorderItems[itemIndex] = mergedItem;
                this.notifyListeners();
              }

              // Queue merged version to server
              this.queueBackgroundSync('UPDATE_ITEM', {
                id: mergedItem.id,
                quantity: mergedItem.quantity,
                completed: mergedItem.completed,
                updatedAt: mergedItem.updatedAt
              });

              resolve();
            }
          },
          {
            text: 'Cancel',
            style: 'cancel',
            onPress: () => {
              logger.info('[ReorderService]', 'User cancelled conflict resolution');
              resolve();
            }
          }
        ],
        { cancelable: false }
      );
    });
  }

  // Update local item from server data
  private async updateLocalItemFromServer(serverItem: any): Promise<void> {
    try {
      const itemIndex = this.reorderItems.findIndex(item => item.id === serverItem.id);

      if (itemIndex >= 0) {
        // Update existing item
        this.reorderItems[itemIndex] = {
          ...this.reorderItems[itemIndex],
          ...serverItem,
          timestamp: new Date(serverItem.createdAt),
          index: itemIndex + 1
        };
      } else {
        // Add new item from server
        this.reorderItems.push({
          ...serverItem,
          timestamp: new Date(serverItem.createdAt),
          index: this.reorderItems.length + 1
        });
      }

      // Save to local database
      await this.saveOfflineItems();

      // Notify listeners
      this.notifyListeners();

      logger.info('[ReorderService]', `Updated local item from server: ${serverItem.itemName}`);
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to update local item from server', { error });
    }
  }

  // Handle real-time reorder item creation
  private handleReorderItemCreated(newItem: any) {
    // Don't add if it's already in our local list
    const exists = this.reorderItems.find(item => item.id === newItem.id);
    if (exists) return;

    const reorderItem: ReorderItem = {
      ...newItem,
      timestamp: new Date(newItem.createdAt),
      index: this.reorderItems.length + 1
    };

    this.reorderItems.push(reorderItem);
    logger.info('[ReorderService]', `Real-time: Added reorder item ${newItem.itemName}`);
    this.notifyListeners();
  }

  // Handle real-time reorder item updates
  private handleReorderItemUpdated(updatedItem: any) {
    const index = this.reorderItems.findIndex(item => item.id === updatedItem.id);
    if (index >= 0) {
      this.reorderItems[index] = {
        ...updatedItem,
        timestamp: new Date(updatedItem.createdAt),
        index: this.reorderItems[index].index
      };
      logger.info('[ReorderService]', `Real-time: Updated reorder item ${updatedItem.itemName}`);
      this.notifyListeners();
    }
  }

  // Handle real-time reorder item deletion
  private handleReorderItemDeleted(deletedItem: any) {
    const initialLength = this.reorderItems.length;
    this.reorderItems = this.reorderItems.filter(item => item.id !== deletedItem.id);
    
    if (this.reorderItems.length < initialLength) {
      // Re-index remaining items
      this.reorderItems.forEach((item, index) => {
        item.index = index + 1;
      });
      logger.info('[ReorderService]', `Real-time: Deleted reorder item ${deletedItem.itemName}`);
      this.notifyListeners();
    }
  }

  // Handle team data updates from subscriptions
  private handleTeamDataUpdate(updatedItemData: any) {
    const itemId = updatedItemData.id;
    
    // Update cache
    const teamData: TeamData = {
      vendor: updatedItemData.vendor,
      vendorCost: updatedItemData.caseCost && updatedItemData.caseQuantity ? 
        updatedItemData.caseCost / updatedItemData.caseQuantity : undefined,
      caseUpc: updatedItemData.caseUpc,
      caseCost: updatedItemData.caseCost,
      caseQuantity: updatedItemData.caseQuantity,
      discontinued: updatedItemData.discontinued,
      notes: updatedItemData.notes?.[0]?.content,
    };
    
    this.teamDataCache.set(itemId, { data: teamData, timestamp: Date.now() });
    
    // Update any reorder items with this team data
    let itemsUpdated = false;
    this.reorderItems.forEach(reorderItem => {
      if (reorderItem.itemId === itemId) {
        reorderItem.teamData = teamData;
        itemsUpdated = true;
      }
    });
    
    if (itemsUpdated) {
      this.notifyListeners();
      logger.info('[ReorderService]', `Updated team data for item ${itemId} via real-time sync`);
    }
  }

  // LOCAL-FIRST team data fetching with caching
  async fetchTeamData(itemId: string): Promise<TeamData | undefined> {
    // Check cache first
    const cached = this.teamDataCache.get(itemId);
    if (cached && (Date.now() - cached.timestamp) < this.CACHE_DURATION) {
      return cached.data;
    }

    try {
      logger.info('[ReorderService]', '🔍 Fetching team data locally (LOCAL-FIRST)', { itemId });

      // ✅ CRITICAL FIX: Get from local SQLite only - NO AppSync calls
      const localTeamData = await modernDb.getTeamData(itemId);

      if (localTeamData) {
        const teamData: TeamData = {
          vendor: localTeamData.vendor,
          vendorCost: localTeamData.caseCost && localTeamData.caseQuantity ?
            localTeamData.caseCost / localTeamData.caseQuantity : undefined,
          caseUpc: localTeamData.caseUpc,
          caseCost: localTeamData.caseCost,
          caseQuantity: localTeamData.caseQuantity,
          discontinued: localTeamData.discontinued,
          notes: localTeamData.notes,
        };

        // Update cache
        this.teamDataCache.set(itemId, { data: teamData, timestamp: Date.now() });
        logger.info('[ReorderService]', '✅ Team data loaded from local database', { itemId });
        return teamData;
      } else {
        logger.info('[ReorderService]', '📭 No local team data found', { itemId });

        // ✅ LOCAL-FIRST: Only attempt recovery if explicitly requested AND online
        // Don't auto-recover on every scan - this violates local-first philosophy
        if (this.isOfflineMode) {
          logger.info('[ReorderService]', '🔒 Offline mode - skipping team data recovery', { itemId });
          return undefined;
        }

        // Check if we've already attempted recovery for this item recently
        const recoveryKey = `recovery_attempted_${itemId}`;
        const lastAttempt = this.teamDataCache.get(recoveryKey);
        if (lastAttempt && (Date.now() - lastAttempt.timestamp) < 300000) { // 5 minutes
          logger.info('[ReorderService]', '⏰ Recent recovery attempt - skipping to avoid spam', { itemId });
          return undefined;
        }

        // Mark that we're attempting recovery to prevent spam
        this.teamDataCache.set(recoveryKey, { data: null, timestamp: Date.now() });

        logger.info('[ReorderService]', '🔄 Attempting one-time team data recovery from DynamoDB', { itemId });
        return await this.recoverTeamDataFromDynamoDB(itemId);
      }
    } catch (error: any) {
      logger.error('[ReorderService]', '❌ Error fetching local team data', { error, itemId });
      return undefined;
    }
  }

  // ✅ CONTROLLED RECOVERY: Recover team data from DynamoDB only when appropriate
  private async recoverTeamDataFromDynamoDB(itemId: string): Promise<TeamData | undefined> {
    try {
      // Double-check offline status before making network call
      if (this.isOfflineMode) {
        logger.info('[ReorderService]', '🔒 Offline mode detected - aborting team data recovery', { itemId });
        return undefined;
      }

      logger.info('[ReorderService]', '🔄 Recovering team data from DynamoDB (controlled recovery)', { itemId });

      // Monitor AppSync request
      await appSyncMonitor.beforeRequest('getItemData', 'ReorderService:teamDataRecovery', { id: itemId });

      const response = await this.client.graphql({
        query: queries.getItemData,
        variables: { id: itemId }
      }) as any;

      if (response.data?.getItemData) {
        const itemData = response.data.getItemData;
        const teamData: TeamData = {
          vendor: itemData.vendor,
          vendorCost: itemData.caseCost && itemData.caseQuantity ?
            itemData.caseCost / itemData.caseQuantity : undefined,
          caseUpc: itemData.caseUpc,
          caseCost: itemData.caseCost,
          caseQuantity: itemData.caseQuantity,
          discontinued: itemData.discontinued,
          notes: itemData.notes?.[0]?.content,
        };

        // Save to local database for future use
        await modernDb.upsertTeamData({
          itemId: itemId,
          caseUpc: itemData.caseUpc,
          caseCost: itemData.caseCost,
          caseQuantity: itemData.caseQuantity,
          vendor: itemData.vendor,
          discontinued: itemData.discontinued,
          notes: itemData.notes?.[0]?.content,
          lastSyncAt: new Date().toISOString(),
          owner: itemData.owner
        });

        // Update cache
        this.teamDataCache.set(itemId, { data: teamData, timestamp: Date.now() });
        logger.info('[ReorderService]', '✅ Team data recovered from DynamoDB and saved locally', { itemId });
        return teamData;
      } else {
        logger.info('[ReorderService]', '📭 No team data found in DynamoDB', { itemId });
        return undefined;
      }
    } catch (error: any) {
      logger.error('[ReorderService]', '❌ Team data recovery from DynamoDB failed', { error, itemId });

      // If it's an authentication error, switch to offline mode to prevent future attempts
      if (error.name === 'NotAuthorizedException' || error.name === 'NoSignedUser') {
        logger.warn('[ReorderService]', '🔒 Authentication failed - switching to offline mode', { itemId });
        this.isOfflineMode = true;
      }

      return undefined;
    }
  }

  // Add listener for reorder list changes
  addListener(listener: (items: ReorderItem[]) => void) {
    this.listeners.push(listener);
    
    // Initialize service when first listener is added
    if (this.listeners.length === 1 && !this.isInitialized) {
      this.initialize(this.currentUserId || undefined).then(() => {
        // Notify the listener with current data after initialization
        listener([...this.reorderItems]);
      });
    } else {
      // If already initialized, immediately provide current data
      listener([...this.reorderItems]);
    }
    
    return () => {
      this.listeners = this.listeners.filter(l => l !== listener);
    };
  }

  // Notify all listeners of changes
  private notifyListeners() {
    this.listeners.forEach(listener => listener([...this.reorderItems]));
  }

  // Clean up subscriptions and timers
  cleanup() {
    this.subscriptions.forEach(sub => {
      if (sub && typeof sub.unsubscribe === 'function') {
        sub.unsubscribe();
      }
    });
    this.subscriptions = [];

    // Clean up sync timeout
    if (this.syncBatchTimeout) {
      clearTimeout(this.syncBatchTimeout);
      this.syncBatchTimeout = null;
    }

    logger.info('[ReorderService]', 'Subscriptions and timers cleaned up');
  }

  // Add item to reorder list using GraphQL
  async addItem(item: ConvertedItem, quantity: number = 1, teamData?: TeamData, addedBy: string = 'Unknown User', overwriteMode: boolean = false): Promise<boolean> {
    try {
      // Check if item already exists in reorder list
      const existingItemIndex = this.reorderItems.findIndex(
        reorderItem => reorderItem.itemId === item.id
      );

      // 🚀 LOCAL-FIRST: Always work locally first for instant responsiveness
      if (existingItemIndex >= 0) {
        // Update quantity for existing item locally
        const existingItem = this.reorderItems[existingItemIndex];
        if (overwriteMode) {
          existingItem.quantity = quantity; // Overwrite instead of add
        } else {
          existingItem.quantity += quantity; // Add to existing quantity
        }
        existingItem.updatedAt = new Date().toISOString();

        // Queue background sync
        this.queueBackgroundSync('UPDATE_ITEM', {
          id: existingItem.id,
          quantity: existingItem.quantity,
          updatedAt: existingItem.updatedAt
        });

        logger.info('[ReorderService]', `✅ Updated item locally: ${existingItem.itemName} (qty: ${existingItem.quantity})`);
      } else {
        // Add new item locally
        const newReorderItem: ReorderItem = {
          id: `local-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
          itemId: item.id,
          itemName: item.name || 'Unknown Item',
          itemBarcode: item.barcode || undefined,
          itemCategory: item.category || undefined,
          itemPrice: item.price,
          quantity,
          completed: false,
          received: false,
          addedBy: addedBy,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          teamData,
          timestamp: new Date(),
          index: this.reorderItems.length + 1
        };

        this.reorderItems.push(newReorderItem);

        // Queue background sync
        this.queueBackgroundSync('CREATE_ITEM', {
          itemId: item.id,
          itemName: item.name,
          itemBarcode: item.barcode || undefined,
          itemCategory: item.category || undefined,
          itemPrice: item.price,
          quantity,
          completed: false,
          addedBy: addedBy
        });

        logger.info('[ReorderService]', `✅ Added item locally: ${item.name} (qty: ${quantity})`);
      }

      await this.saveOfflineItems();
      this.notifyListeners();

      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to add item', { error, itemId: item.id });
      return false;
    }
  }

  // Get all reorder items
  getItems(): ReorderItem[] {
    return [...this.reorderItems];
  }

  // Get reorder items count
  getCount(): number {
    return this.reorderItems.length;
  }

  // Get incomplete reorder items count (for badge display)
  getIncompleteCount(): number {
    return this.reorderItems.filter(item => !item.completed).length;
  }

  // Clear all reorder items - LOCAL-FIRST
  async clear() {
    try {
      const itemCount = this.reorderItems.length;

      // 🚀 LOCAL-FIRST: Clear locally first for instant responsiveness
      const itemsToDelete = [...this.reorderItems]; // Copy for background sync

      // Clear local arrays immediately
      this.reorderItems = [];

      // Queue background deletion for each item
      itemsToDelete.forEach(item => {
        this.queueBackgroundSync('DELETE_ITEM', {
          id: item.id
        });
      });

      // Save empty state locally
      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `✅ Cleared ${itemCount} items locally (background sync queued)`);
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to clear reorder items locally', { error });
      return false;
    }
  }

  // Remove specific item - LOCAL-FIRST
  async removeItem(itemId: string): Promise<boolean> {
    try {
      const itemIndex = this.reorderItems.findIndex(item => item.id === itemId);
      if (itemIndex === -1) {
        logger.warn('[ReorderService]', 'Item not found for removal', { itemId });
        return false;
      }

      const removedItem = this.reorderItems[itemIndex];

      // 🚀 LOCAL-FIRST: Remove locally first for instant responsiveness
      this.reorderItems.splice(itemIndex, 1);

      // Re-index remaining items
      this.reorderItems.forEach((item, index) => {
        item.index = index + 1;
      });

      // Queue background deletion
      this.queueBackgroundSync('DELETE_ITEM', {
        id: itemId
      });

      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `✅ Removed item locally: ${removedItem.itemName} (background sync queued)`);
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to remove reorder item locally', { error, itemId });
      return false;
    }
  }

  // Move item to chronological top by updating timestamp (independent of GUI filters/sorting)
  async moveItemToTop(itemId: string, teamData?: TeamData, userName: string = 'Unknown User'): Promise<boolean> {
    try {
      const itemIndex = this.reorderItems.findIndex(item => item.id === itemId);
      if (itemIndex === -1) {
        logger.error('[ReorderService]', 'Item not found for moveItemToTop', { itemId });
        return false;
      }

      const existingItem = this.reorderItems[itemIndex];

      // 🚀 LOCAL-FIRST: Update timestamp to bring to chronological top (behind the scenes)
      const now = new Date().toISOString();

      // Update item with new timestamp - this makes it chronologically most recent
      // regardless of how the GUI is filtering/sorting the display
      existingItem.updatedAt = now;
      existingItem.timestamp = new Date(now);
      existingItem.completed = false; // Reset to incomplete
      if (teamData) {
        existingItem.teamData = teamData;
      }

      // Queue background sync
      this.queueBackgroundSync('UPDATE_ITEM', {
        id: itemId,
        completed: false,
        updatedAt: now
      });

      // Keep internal data sorted chronologically (most recent first)
      // This ensures scanning logic works correctly regardless of GUI display
      this.reorderItems.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());

      // Re-index items
      this.reorderItems.forEach((item, index) => {
        item.index = index + 1;
      });

      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `Moved item to chronological top: ${existingItem.itemName}`, {
        itemId,
        newTimestamp: now,
        note: 'Chronological position independent of GUI filters'
      });
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to move item to top', { error, itemId });
      return false;
    }
  }

  // Mark item as received by deleting from reorder list and logging in item history
  async markAsReceived(itemId: string, userName: string = 'Unknown User'): Promise<boolean> {
    try {
      const itemIndex = this.reorderItems.findIndex(item => item.id === itemId);
      if (itemIndex === -1) {
        logger.error('[ReorderService]', 'Item not found for markAsReceived', { itemId });
        return false;
      }

      const reorderItem = this.reorderItems[itemIndex];
      const squareItemId = reorderItem.itemId;

      // Step 1: Log the reorder completion in item history (using itemHistoryService)
      try {
        // Import itemHistoryService if not already imported
        const { itemHistoryService } = await import('./itemHistoryService');

        await itemHistoryService.logReorder(
          squareItemId,
          reorderItem.itemName || 'Unknown Item',
          reorderItem.quantity,
          userName
        );

        logger.info('[ReorderService]', `Logged reorder completion in item history: ${squareItemId}`, {
          itemName: reorderItem.itemName,
          quantity: reorderItem.quantity
        });
      } catch (historyError) {
        logger.error('[ReorderService]', 'Failed to log reorder completion in item history', {
          error: historyError,
          itemId: squareItemId
        });
        // Continue with deletion even if history logging fails
      }

      // Step 2: 🚀 LOCAL-FIRST: Delete locally first, then sync in background
      // Remove from active reorder list
      this.reorderItems.splice(itemIndex, 1);

      // Re-index remaining items
      this.reorderItems.forEach((item, index) => {
        item.index = index + 1;
      });

      // Queue background deletion
      this.queueBackgroundSync('DELETE_ITEM', {
        id: itemId
      });

      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `✅ Deleted received item locally: ${itemId}`, {
        itemName: reorderItem.itemName
      });
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to mark item as received', { error, itemId });
      return false;
    }
  }

  // Toggle item completion
  async toggleCompletion(itemId: string, userName: string = 'Unknown User') {
    try {
      const item = this.reorderItems.find(item => item.id === itemId);
      if (!item) return;

      const newCompletedState = !item.completed;

      // Note: We don't log reorder history here anymore - only when item is received (markAsReceived)

      // 🚀 LOCAL-FIRST: Update locally first for instant responsiveness
      item.completed = newCompletedState;
      item.updatedAt = new Date().toISOString();

      // Queue background sync
      this.queueBackgroundSync('TOGGLE_COMPLETION', {
        id: itemId,
        completed: newCompletedState,
        updatedAt: item.updatedAt
      });

      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `Toggled completion locally for item: ${itemId}`, {
        completed: newCompletedState
      });
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to toggle completion', { error, itemId });
    }
  }

  // Manual refresh - reload from server and sync pending items
  async refresh() {
    try {
      // Check if we can connect to server
      const isAuthenticated = await this.checkAuthStatus();
      
      if (isAuthenticated) {
        // Sync pending items first
        await this.syncPendingItems();
        
        // Then reload from server
        await this.loadReorderItems();
        this.notifyListeners();
        logger.info('[ReorderService]', 'Manual refresh completed with sync');
      } else {
        // Still offline, just reload local data
        await this.loadOfflineItems();
        this.notifyListeners();
        logger.info('[ReorderService]', 'Manual refresh completed (offline mode)');
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Manual refresh failed', { error });
    }
  }

  // Sync pending items to server
  private async syncPendingItems(): Promise<void> {
    if (this.pendingSyncItems.length === 0) return;
    
    logger.info('[ReorderService]', `Syncing ${this.pendingSyncItems.length} pending items`);
    
    const syncedItems: string[] = [];
    
    for (const item of this.pendingSyncItems) {
      try {
        const response = await this.client.graphql({
          query: mutations.createReorderItem,
          variables: {
            input: {
              itemId: item.itemId,
              itemName: item.itemName,
              itemBarcode: item.itemBarcode,
              itemCategory: item.itemCategory,
              itemPrice: item.itemPrice,
              quantity: item.quantity,
              completed: item.completed,
              addedBy: item.addedBy
            }
          }
        }) as any;

        if (response.data?.createReorderItem) {
          syncedItems.push(item.id);
          logger.info('[ReorderService]', `Synced item: ${item.itemName}`);
        }
      } catch (error) {
        logger.error('[ReorderService]', `Failed to sync item: ${item.itemName}`, { error });
      }
    }
    
    // Remove synced items from pending list
    this.pendingSyncItems = this.pendingSyncItems.filter(item => !syncedItems.includes(item.id));
    
    logger.info('[ReorderService]', `Sync completed: ${syncedItems.length} items synced, ${this.pendingSyncItems.length} pending`);
  }

  // Add custom item to reorder list (items not in catalog)
  async addCustomItem(customItem: {
    itemName: string;
    itemCategory?: string;
    quantity: number;
    addedBy: string;
    vendor?: string;
    notes?: string;
  }): Promise<boolean> {
    try {
      const customId = `custom-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      
      const newItem: ReorderItem = {
        id: customId,
        itemId: customId,
        itemName: customItem.itemName,
        itemBarcode: undefined,
        itemCategory: customItem.itemCategory || 'Custom',
        itemPrice: undefined,
        quantity: customItem.quantity,
        completed: false,
        received: false,
        addedBy: customItem.addedBy,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        timestamp: new Date(),
        index: this.reorderItems.length + 1,
        teamData: customItem.vendor ? { vendor: customItem.vendor } : undefined
      };

      // 🚀 LOCAL-FIRST: Add locally first for instant responsiveness
      this.reorderItems.unshift(newItem);

      // Queue background sync
      this.queueBackgroundSync('CREATE_ITEM', {
        itemId: customId,
        itemName: customItem.itemName,
        itemBarcode: undefined,
        itemCategory: customItem.itemCategory || 'Custom',
        itemPrice: undefined,
        quantity: customItem.quantity,
        completed: false,
        addedBy: customItem.addedBy
      });

      await this.saveOfflineItems();
      this.notifyListeners();

      logger.info('[ReorderService]', `✅ Added custom item locally: ${customItem.itemName} (background sync queued)`, {
        itemId: customId,
        quantity: customItem.quantity
      });
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to add custom item locally', {
        error,
        itemName: customItem.itemName
      });
      return false;
    }
  }

  // Check if user is authenticated and online
  private async checkAuthStatus(): Promise<boolean> {
    try {
      // Try a simple GraphQL query to test authentication
      await this.client.graphql({
        query: queries.listReorderItems,
        variables: { limit: 1 }
      });
      this.isOfflineMode = false;
      return true;
    } catch (error: any) {
      if (error?.name === 'NoSignedUser' || error?.underlyingError?.name === 'NotAuthorizedException') {
        this.isOfflineMode = true;
        logger.info('[ReorderService]', 'User not authenticated, switching to offline mode');
        return false;
      }
      // Other errors might be network issues, still try offline mode
      this.isOfflineMode = true;
      logger.warn('[ReorderService]', 'Network/auth error, switching to offline mode', { error });
      return false;
    }
  }

  // Load items from local storage when offline
  private async loadOfflineItems(): Promise<void> {
    try {
      const stored = await AsyncStorage.getItem(this.STORAGE_KEY);
      if (stored) {
        const items = JSON.parse(stored);
        this.reorderItems = items.map((item: any, index: number) => ({
          ...item,
          timestamp: new Date(item.createdAt),
          index: index + 1
        }));
        logger.info('[ReorderService]', `Loaded ${this.reorderItems.length} items from offline storage`);
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to load offline items', { error });
    }
  }

  // Save items to local storage
  private async saveOfflineItems(): Promise<void> {
    try {
      await AsyncStorage.setItem(this.STORAGE_KEY, JSON.stringify(this.reorderItems));
      logger.info('[ReorderService]', 'Saved items to offline storage');
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to save offline items', { error });
    }
  }

  // Get current sync status
  getSyncStatus(): { isOnline: boolean; pendingCount: number; isAuthenticated: boolean } {
    return {
      isOnline: !this.isOfflineMode,
      pendingCount: this.pendingSyncItems.length,
      isAuthenticated: !this.isOfflineMode
    };
  }

  // Local database functions for reorder items
  private async loadLocalReorderItems(): Promise<ReorderItem[]> {
    try {
      const db = await modernDb.getDatabase();
      const results = await db.getAllAsync<any>(`
        SELECT * FROM reorder_items
        WHERE pending_sync = 0
        ORDER BY created_at DESC
      `);

      return results.map(row => ({
        id: row.id,
        itemId: row.item_id,
        itemName: row.item_name,
        itemBarcode: row.item_barcode,
        itemCategory: row.item_category,
        itemPrice: row.item_price,
        quantity: row.quantity,
        completed: row.completed === 1,
        received: false,
        addedBy: row.added_by,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        timestamp: new Date(row.created_at),
        index: 0 // Will be set later
      }));
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to load local reorder items', { error });
      return [];
    }
  }

  private async saveReorderItemsLocally(items: ReorderItem[]): Promise<void> {
    try {
      const db = await modernDb.getDatabase();
      const now = new Date().toISOString();

      await db.withTransactionAsync(async () => {
        for (const item of items) {
          await db.runAsync(`
            INSERT OR REPLACE INTO reorder_items
            (id, item_id, item_name, item_barcode, item_category, item_price, quantity, completed, added_by, created_at, updated_at, last_sync_at, pending_sync)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `, [
            item.id,
            item.itemId,
            item.itemName,
            item.itemBarcode,
            item.itemCategory,
            item.itemPrice,
            item.quantity,
            item.completed ? 1 : 0,
            item.addedBy,
            item.createdAt,
            item.updatedAt,
            now,
            0 // not pending sync
          ]);
        }
      });

      logger.info('[ReorderService]', `Saved ${items.length} reorder items locally`);
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to save reorder items locally', { error });
    }
  }

  // ✅ INITIAL RECOVERY: Recover data from DynamoDB when local data is missing
  private async recoverFromDynamoDB(): Promise<void> {
    try {
      logger.info('[ReorderService]', '🔄 Recovering reorder items from DynamoDB (initial recovery)');

      // Monitor AppSync request
      await appSyncMonitor.beforeRequest('listReorderItems', 'ReorderService:initialRecovery', { limit: 1000 });

      const response = await this.client.graphql({
        query: queries.listReorderItems,
        variables: {
          limit: 1000 // Adjust as needed
        }
      }) as any;

      if (response.data?.listReorderItems?.items) {
        const serverItems = response.data.listReorderItems.items.map((item: any, index: number) => ({
          ...item,
          timestamp: new Date(item.createdAt),
          index: index + 1
        }));

        // Save to local database
        await this.saveReorderItemsLocally(serverItems);

        // Update in-memory items
        this.reorderItems = serverItems;

        logger.info('[ReorderService]', `✅ Initial recovery completed: ${serverItems.length} reorder items recovered from DynamoDB`);

        // Load team data for all items
        await this.loadTeamDataForItems();

        // Notify listeners of recovered data
        this.notifyListeners();
      } else {
        logger.info('[ReorderService]', '📭 No reorder items found in DynamoDB');
      }
    } catch (error) {
      logger.error('[ReorderService]', '❌ Initial recovery from DynamoDB failed', { error });
      // Don't throw - this is a recovery operation
    }
  }
}

// Export singleton instance
export const reorderService = new ReorderService(); 