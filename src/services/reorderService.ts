import { ConvertedItem } from '../types/api';
import logger from '../utils/logger';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { generateClient } from 'aws-amplify/api';
import * as queries from '../graphql/queries';
import * as subscriptions from '../graphql/subscriptions';
import * as mutations from '../graphql/mutations';
import { itemHistoryService } from './itemHistoryService';

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

  // Initialize the service
  async initialize(userId?: string) {
    if (this.isInitialized && this.currentUserId === userId) return;
    
    this.currentUserId = userId || null;
    
    try {
      // Check authentication status first
      const isAuthenticated = await this.checkAuthStatus();
      
      if (isAuthenticated) {
        // Load reorder items from server
        await this.loadReorderItems();
        
        // Set up real-time subscriptions
        this.setupSubscriptions();
      } else {
        // Load from offline storage
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

  // Load reorder items from AppSync
  private async loadReorderItems() {
    try {
      logger.info('[ReorderService]', 'Loading reorder items from server');
      
      const response = await this.client.graphql({
        query: queries.listReorderItems,
        variables: {
          limit: 1000 // Adjust as needed
        }
      }) as any;
      
      if (response.data?.listReorderItems?.items) {
        this.reorderItems = response.data.listReorderItems.items.map((item: any, index: number) => ({
          ...item,
          timestamp: new Date(item.createdAt),
          index: index + 1
        }));
        
        logger.info('[ReorderService]', `Loaded ${this.reorderItems.length} reorder items from server`);
        
        // Load team data for all items
        await this.loadTeamDataForItems();
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to load reorder items', { error });
    }
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

  // Set up real-time subscriptions
  private setupSubscriptions() {
    try {
      // Subscribe to ReorderItem creation
      const createSubscription = this.client.graphql({
        query: subscriptions.onCreateReorderItem
      });

      if ('subscribe' in createSubscription) {
        const sub = (createSubscription as any).subscribe({
          next: ({ data }: any) => {
            if (data?.onCreateReorderItem) {
              this.handleReorderItemCreated(data.onCreateReorderItem);
            }
          },
          error: (error: any) => {
            logger.error('[ReorderService]', 'Create subscription error', { error });
          }
        });
        this.subscriptions.push(sub);
      }

      // Subscribe to ReorderItem updates
      const updateSubscription = this.client.graphql({
        query: subscriptions.onUpdateReorderItem
      });

      if ('subscribe' in updateSubscription) {
        const sub = (updateSubscription as any).subscribe({
          next: ({ data }: any) => {
            if (data?.onUpdateReorderItem) {
              this.handleReorderItemUpdated(data.onUpdateReorderItem);
            }
          },
          error: (error: any) => {
            logger.error('[ReorderService]', 'Update subscription error', { error });
          }
        });
        this.subscriptions.push(sub);
      }

      // Subscribe to ReorderItem deletion
      const deleteSubscription = this.client.graphql({
        query: subscriptions.onDeleteReorderItem
      });

      if ('subscribe' in deleteSubscription) {
        const sub = (deleteSubscription as any).subscribe({
          next: ({ data }: any) => {
            if (data?.onDeleteReorderItem) {
              this.handleReorderItemDeleted(data.onDeleteReorderItem);
            }
          },
          error: (error: any) => {
            logger.error('[ReorderService]', 'Delete subscription error', { error });
          }
        });
        this.subscriptions.push(sub);
      }

      // Subscribe to ItemData updates for team data
      const teamDataSubscription = this.client.graphql({
        query: subscriptions.onUpdateItemData
      });

      if ('subscribe' in teamDataSubscription) {
        const sub = (teamDataSubscription as any).subscribe({
          next: ({ data }: any) => {
            if (data?.onUpdateItemData) {
              this.handleTeamDataUpdate(data.onUpdateItemData);
            }
          },
          error: (error: any) => {
            logger.error('[ReorderService]', 'Team data subscription error', { error });
          }
        });
        this.subscriptions.push(sub);
      }

      logger.info('[ReorderService]', 'Real-time subscriptions set up');
    } catch (error: any) {
      logger.error('[ReorderService]', 'Failed to set up subscriptions', { error });
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

  // Enhanced team data fetching with caching
  async fetchTeamData(itemId: string): Promise<TeamData | undefined> {
    // Check cache first
    const cached = this.teamDataCache.get(itemId);
    if (cached && (Date.now() - cached.timestamp) < this.CACHE_DURATION) {
      return cached.data;
    }

    try {
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
        
        // Update cache
        this.teamDataCache.set(itemId, { data: teamData, timestamp: Date.now() });
        return teamData;
      }
    } catch (error: any) {
      // Gracefully handle authentication errors
      if (error?.name === 'NoSignedUser' || error?.underlyingError?.name === 'NotAuthorizedException') {
        logger.info('[ReorderService]', 'User not signed in, skipping team data fetch', { itemId });
        return undefined;
      }
      logger.error('[ReorderService]', 'Error fetching team data', { error, itemId });
    }
    return undefined;
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

  // Clean up subscriptions
  cleanup() {
    this.subscriptions.forEach(sub => {
      if (sub && typeof sub.unsubscribe === 'function') {
        sub.unsubscribe();
      }
    });
    this.subscriptions = [];
    logger.info('[ReorderService]', 'Subscriptions cleaned up');
  }

  // Add item to reorder list using GraphQL
  async addItem(item: ConvertedItem, quantity: number = 1, teamData?: TeamData, addedBy: string = 'Unknown User', overwriteMode: boolean = false): Promise<boolean> {
    try {
      // Check if item already exists in reorder list
      const existingItemIndex = this.reorderItems.findIndex(
        reorderItem => reorderItem.itemId === item.id
      );

      if (this.isOfflineMode) {
        // Handle offline mode - add/update locally
        if (existingItemIndex >= 0) {
          // Update quantity for existing item
          const existingItem = this.reorderItems[existingItemIndex];
          if (overwriteMode) {
            existingItem.quantity = quantity; // Overwrite instead of add
          } else {
            existingItem.quantity += quantity; // Add to existing quantity
          }
          existingItem.updatedAt = new Date().toISOString();
          
          // Add to pending sync
          const existingPendingIndex = this.pendingSyncItems.findIndex(pending => pending.id === existingItem.id);
          if (existingPendingIndex >= 0) {
            this.pendingSyncItems[existingPendingIndex] = { ...existingItem };
          } else {
            this.pendingSyncItems.push({ ...existingItem });
          }
        } else {
          // Add new item locally
          const newReorderItem: ReorderItem = {
            id: `offline-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            itemId: item.id,
            itemName: item.name || 'Unknown Item',
            itemBarcode: item.barcode || undefined,
            itemCategory: item.category || undefined,
            itemPrice: item.price,
            quantity,
            completed: false,
            addedBy: addedBy,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            teamData,
            timestamp: new Date(),
            index: this.reorderItems.length + 1
          };
          
          this.reorderItems.push(newReorderItem);
          this.pendingSyncItems.push({ ...newReorderItem });
        }
        
        await this.saveOfflineItems();
        this.notifyListeners();
        
        logger.info('[ReorderService]', `Added item locally: ${item.name}`, {
          itemId: item.id,
          quantity,
          isOffline: true
        });
        return true;
      }

      // Try to add/update on server
      if (existingItemIndex >= 0) {
        // Update quantity if item already exists
        const existingItem = this.reorderItems[existingItemIndex];
        const newQuantity = overwriteMode ? quantity : existingItem.quantity + quantity;
        
        const response = await this.client.graphql({
          query: mutations.updateReorderItem,
          variables: {
            input: {
              id: existingItem.id,
              quantity: newQuantity
            }
          }
        }) as any;

        if (response.data?.updateReorderItem) {
          logger.info('[ReorderService]', `Updated quantity for existing item: ${item.name}`, {
            itemId: item.id,
            newQuantity
          });
          return true;
        }
      } else {
        // Add new item to reorder list
        const response = await this.client.graphql({
          query: mutations.createReorderItem,
          variables: {
            input: {
              itemId: item.id,
              itemName: item.name,
              itemBarcode: item.barcode || undefined,
              itemCategory: item.category || undefined,
              itemPrice: item.price,
              quantity,
              completed: false,
              addedBy: addedBy
            }
          }
        }) as any;

        if (response.data?.createReorderItem) {
          logger.info('[ReorderService]', `Added new item to reorder list: ${item.name}`, {
            itemId: item.id,
            quantity
          });
          return true;
        }
      }

      return false;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to add item to reorder list, falling back to offline mode', { error, itemId: item.id });
      
      // Fallback to offline mode
      this.isOfflineMode = true;
      
      // Check if item already exists in reorder list
      const existingItemIndex = this.reorderItems.findIndex(
        reorderItem => reorderItem.itemId === item.id
      );

      if (existingItemIndex >= 0) {
        // Update quantity for existing item
        const existingItem = this.reorderItems[existingItemIndex];
        if (overwriteMode) {
          existingItem.quantity = quantity; // Overwrite instead of add
        } else {
          existingItem.quantity += quantity; // Add to existing quantity
        }
        existingItem.updatedAt = new Date().toISOString();
        
        // Add to pending sync
        const existingPendingIndex = this.pendingSyncItems.findIndex(pending => pending.id === existingItem.id);
        if (existingPendingIndex >= 0) {
          this.pendingSyncItems[existingPendingIndex] = { ...existingItem };
        } else {
          this.pendingSyncItems.push({ ...existingItem });
        }
      } else {
        // Add new item locally
        const newReorderItem: ReorderItem = {
          id: `offline-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
          itemId: item.id,
          itemName: item.name || 'Unknown Item',
          itemBarcode: item.barcode || undefined,
          itemCategory: item.category || undefined,
          itemPrice: item.price,
          quantity,
          completed: false,
          addedBy: addedBy || 'Unknown User',
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          teamData,
          timestamp: new Date(),
          index: this.reorderItems.length + 1
        };
        
        this.reorderItems.push(newReorderItem);
        this.pendingSyncItems.push({ ...newReorderItem });
      }
      
      await this.saveOfflineItems();
      this.notifyListeners();
      
      logger.info('[ReorderService]', `Added item locally after error: ${item.name}`, {
        itemId: item.id,
        quantity,
        isOfflineFallback: true
      });
      return true;
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

  // Clear all reorder items
  async clear() {
    try {
      // Delete all items from server
      for (const item of this.reorderItems) {
        await this.client.graphql({
          query: mutations.deleteReorderItem,
          variables: {
            input: { id: item.id }
          }
        });
      }
      logger.info('[ReorderService]', 'Cleared all reorder items');
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to clear reorder items', { error });
    }
  }

  // Remove specific item
  async removeItem(itemId: string) {
    try {
      if (this.isOfflineMode) {
        // Remove from local storage
        const itemIndex = this.reorderItems.findIndex(item => item.id === itemId);
        if (itemIndex >= 0) {
          const removedItem = this.reorderItems[itemIndex];
          this.reorderItems.splice(itemIndex, 1);
          
          // Remove from pending sync if it exists there
          this.pendingSyncItems = this.pendingSyncItems.filter(item => item.id !== itemId);
          
          // Re-index remaining items
          this.reorderItems.forEach((item, index) => {
            item.index = index + 1;
          });
          
          await this.saveOfflineItems();
          this.notifyListeners();
          
          logger.info('[ReorderService]', `Removed item locally: ${itemId}`);
        }
        return;
      }

      // Try to remove from server
      const response = await this.client.graphql({
        query: mutations.deleteReorderItem,
        variables: {
          input: { id: itemId }
        }
      }) as any;

      if (response.data?.deleteReorderItem) {
        logger.info('[ReorderService]', `Removed reorder item: ${itemId}`);
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to remove reorder item, falling back to offline mode', { error, itemId });
      
      // Fallback to offline mode
      this.isOfflineMode = true;
      const itemIndex = this.reorderItems.findIndex(item => item.id === itemId);
      if (itemIndex >= 0) {
        this.reorderItems.splice(itemIndex, 1);
        
        // Remove from pending sync if it exists there
        this.pendingSyncItems = this.pendingSyncItems.filter(item => item.id !== itemId);
        
        // Re-index remaining items
        this.reorderItems.forEach((item, index) => {
          item.index = index + 1;
        });
        
        await this.saveOfflineItems();
        this.notifyListeners();
        
        logger.info('[ReorderService]', `Removed item locally after error: ${itemId}`);
      }
    }
  }

  // Toggle item completion
  async toggleCompletion(itemId: string, userName: string = 'Unknown User') {
    try {
      const item = this.reorderItems.find(item => item.id === itemId);
      if (!item) return;

      const newCompletedState = !item.completed;

      // Track reorder history if the item is being marked as completed (reordered)
      if (newCompletedState && item.itemId && item.itemId !== item.id) { // Only track for real items, not custom ones
        try {
          await itemHistoryService.logReorder(
            item.itemId,
            item.itemName || 'Unknown Item',
            item.quantity,
            userName
          );
        } catch (historyError) {
          logger.error('[ReorderService]', 'Failed to track reorder history', { historyError, itemId });
          // Don't fail the reorder operation if history tracking fails
        }
      }

      if (this.isOfflineMode) {
        // Update locally
        item.completed = newCompletedState;
        item.updatedAt = new Date().toISOString();
        
        // Add to pending sync if not already there
        const existingPendingIndex = this.pendingSyncItems.findIndex(pending => pending.id === itemId);
        if (existingPendingIndex >= 0) {
          this.pendingSyncItems[existingPendingIndex] = { ...item };
        } else {
          this.pendingSyncItems.push({ ...item });
        }
        
        await this.saveOfflineItems();
        this.notifyListeners();
        
        logger.info('[ReorderService]', `Toggled completion locally for item: ${itemId}`, { 
          completed: newCompletedState 
        });
        return;
      }

      // Try to update on server
      const response = await this.client.graphql({
        query: mutations.updateReorderItem,
        variables: {
          input: {
            id: itemId,
            completed: newCompletedState
          }
        }
      }) as any;

      if (response.data?.updateReorderItem) {
        logger.info('[ReorderService]', `Toggled completion for item: ${itemId}`, { 
          completed: newCompletedState 
        });
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to toggle completion, falling back to offline mode', { error, itemId });
      
      // Fallback to offline mode
      this.isOfflineMode = true;
      const item = this.reorderItems.find(item => item.id === itemId);
      if (item) {
        const newCompletedState = !item.completed;
        
        // Track reorder history if being marked as completed
        if (newCompletedState && item.itemId && item.itemId !== item.id) {
          try {
            await itemHistoryService.logReorder(
              item.itemId,
              item.itemName || 'Unknown Item',
              item.quantity,
              userName
            );
          } catch (historyError) {
            logger.error('[ReorderService]', 'Failed to track reorder history (offline)', { historyError, itemId });
          }
        }
        
        item.completed = newCompletedState;
        item.updatedAt = new Date().toISOString();
        
        // Add to pending sync
        const existingPendingIndex = this.pendingSyncItems.findIndex(pending => pending.id === itemId);
        if (existingPendingIndex >= 0) {
          this.pendingSyncItems[existingPendingIndex] = { ...item };
        } else {
          this.pendingSyncItems.push({ ...item });
        }
        
        await this.saveOfflineItems();
        this.notifyListeners();
      }
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
        addedBy: customItem.addedBy,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        timestamp: new Date(),
        index: this.reorderItems.length + 1,
        teamData: customItem.vendor ? { vendor: customItem.vendor } : undefined
      };

      if (this.isOfflineMode) {
        // Add to local storage and pending sync
        this.reorderItems.unshift(newItem);
        this.pendingSyncItems.push(newItem);
        await this.saveOfflineItems();
        this.notifyListeners();
        
        logger.info('[ReorderService]', `Added custom item to offline storage: ${customItem.itemName}`, {
          itemId: customId,
          quantity: customItem.quantity
        });
        return true;
      } else {
        // Try to add to server
        const response = await this.client.graphql({
          query: mutations.createReorderItem,
          variables: {
            input: {
              itemId: customId,
              itemName: customItem.itemName,
              itemBarcode: undefined,
              itemCategory: customItem.itemCategory || 'Custom',
              itemPrice: undefined,
              quantity: customItem.quantity,
              completed: false,
              addedBy: customItem.addedBy
            }
          }
        }) as any;

        if (response.data?.createReorderItem) {
          logger.info('[ReorderService]', `Added custom item to server: ${customItem.itemName}`, {
            itemId: customId,
            quantity: customItem.quantity
          });
          return true;
        }
      }

      return false;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to add custom item, falling back to offline mode', { 
        error, 
        itemName: customItem.itemName 
      });
      
      // Fallback to offline mode
      this.isOfflineMode = true;
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
        addedBy: customItem.addedBy,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        timestamp: new Date(),
        index: this.reorderItems.length + 1,
        teamData: customItem.vendor ? { vendor: customItem.vendor } : undefined
      };

      this.reorderItems.unshift(newItem);
      this.pendingSyncItems.push(newItem);
      await this.saveOfflineItems();
      this.notifyListeners();
      
      return true; // Return true since we saved locally
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
}

// Export singleton instance
export const reorderService = new ReorderService(); 