import { ConvertedItem } from '../types/api';
import logger from '../utils/logger';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { generateClient } from 'aws-amplify/api';
import * as queries from '../graphql/queries';
import * as subscriptions from '../graphql/subscriptions';

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
  item: ConvertedItem;
  quantity: number;
  timestamp: Date;
  completed: boolean;
  index: number;
  addedBy?: string; // User who added the item
  teamData?: TeamData; // Team data from AppSync
}

class ReorderService {
  private reorderItems: ReorderItem[] = [];
  private listeners: Array<(items: ReorderItem[]) => void> = [];
  private client = generateClient();
  private teamDataCache = new Map<string, { data: TeamData; timestamp: number }>();
  private subscriptions: any[] = [];
  private isInitialized = false;
  private readonly STORAGE_KEY = '@reorder_items';
  private readonly CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

  // Initialize the service
  async initialize() {
    if (this.isInitialized) return;
    
    try {
      // Load persisted reorder items
      await this.loadPersistedItems();
      
      // Set up real-time subscriptions for team data updates
      this.setupSubscriptions();
      
      this.isInitialized = true;
      logger.info('[ReorderService]', 'Service initialized successfully');
      
      // Notify all listeners with loaded data
      this.notifyListeners();
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to initialize service', { error });
    }
  }

  // Load persisted reorder items from storage
  private async loadPersistedItems() {
    try {
      logger.info('[ReorderService]', 'Attempting to load persisted items from AsyncStorage');
      const storedItems = await AsyncStorage.getItem(this.STORAGE_KEY);
      logger.info('[ReorderService]', 'AsyncStorage result', { 
        storageKey: this.STORAGE_KEY,
        hasStoredItems: !!storedItems,
        storedItemsLength: storedItems?.length || 0
      });
      
      if (storedItems) {
        const parsedItems = JSON.parse(storedItems);
        // Convert timestamp strings back to Date objects
        this.reorderItems = parsedItems.map((item: any) => ({
          ...item,
          timestamp: new Date(item.timestamp)
        }));
        logger.info('[ReorderService]', `Successfully loaded ${this.reorderItems.length} persisted items`, {
          items: this.reorderItems.map(item => ({ id: item.id, name: item.item.name, completed: item.completed }))
        });
      } else {
        logger.info('[ReorderService]', 'No persisted items found in AsyncStorage');
      }
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to load persisted items', { error });
    }
  }

  // Persist reorder items to storage
  private async persistItems() {
    try {
      logger.info('[ReorderService]', 'Attempting to persist items to AsyncStorage', {
        itemCount: this.reorderItems.length,
        storageKey: this.STORAGE_KEY
      });
      await AsyncStorage.setItem(this.STORAGE_KEY, JSON.stringify(this.reorderItems));
      logger.info('[ReorderService]', 'Successfully persisted items to AsyncStorage');
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to persist items', { error });
    }
  }

  // Set up real-time subscriptions for team data updates
  private setupSubscriptions() {
    try {
      // Subscribe to ItemData updates for real-time team data syncing
      const updateSubscription = this.client.graphql({
        query: subscriptions.onUpdateItemData
      });

      // Handle subscription as an observable
      if ('subscribe' in updateSubscription) {
        const sub = (updateSubscription as any).subscribe({
          next: ({ data }: any) => {
            if (data?.onUpdateItemData) {
              this.handleTeamDataUpdate(data.onUpdateItemData);
            }
          },
          error: (error: any) => {
            // Gracefully handle authentication errors
            if (error?.name === 'NoSignedUser' || error?.underlyingError?.name === 'NotAuthorizedException') {
              logger.info('[ReorderService]', 'User not signed in, skipping real-time subscriptions');
              return;
            }
            logger.error('[ReorderService]', 'Subscription error', { error });
          }
        });
        this.subscriptions.push(sub);
      }

      logger.info('[ReorderService]', 'Real-time subscriptions set up');
    } catch (error: any) {
      // Gracefully handle authentication errors
      if (error?.name === 'NoSignedUser' || error?.underlyingError?.name === 'NotAuthorizedException') {
        logger.info('[ReorderService]', 'User not signed in, skipping subscription setup');
        return;
      }
      logger.error('[ReorderService]', 'Failed to set up subscriptions', { error });
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
      if (reorderItem.item.id === itemId) {
        reorderItem.teamData = teamData;
        itemsUpdated = true;
      }
    });
    
    if (itemsUpdated) {
      this.persistItems();
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
      this.initialize().then(() => {
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

  // Add item to reorder list
  addItem(item: ConvertedItem, quantity: number = 1, teamData?: TeamData, addedBy?: string): boolean {
    try {
      // Check if item already exists in reorder list
      const existingItemIndex = this.reorderItems.findIndex(
        reorderItem => reorderItem.item.id === item.id
      );

      if (existingItemIndex >= 0) {
        // Update quantity if item already exists
        this.reorderItems[existingItemIndex].quantity += quantity;
        this.reorderItems[existingItemIndex].timestamp = new Date();
        logger.info('[ReorderService]', `Updated quantity for existing item: ${item.name}`, {
          itemId: item.id,
          newQuantity: this.reorderItems[existingItemIndex].quantity
        });
      } else {
        // Add new item to reorder list
        const newItem: ReorderItem = {
          id: `${item.id}-${Date.now()}`,
          item,
          quantity,
          timestamp: new Date(),
          completed: false,
          index: this.reorderItems.length + 1,
          addedBy: addedBy || 'Unknown User',
          teamData,
        };

        this.reorderItems.push(newItem);
        logger.info('[ReorderService]', `Added new item to reorder list: ${item.name}`, {
          itemId: item.id,
          quantity
        });
      }

      this.persistItems();
      this.notifyListeners();
      return true;
    } catch (error) {
      logger.error('[ReorderService]', 'Failed to add item to reorder list', { error, itemId: item.id });
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

  // Clear all reorder items
  clear() {
    this.reorderItems = [];
    this.persistItems();
    this.notifyListeners();
  }

  // Remove specific item
  removeItem(itemId: string) {
    this.reorderItems = this.reorderItems.filter(item => item.id !== itemId);
    // Re-index remaining items
    this.reorderItems.forEach((item, index) => {
      item.index = index + 1;
    });
    this.persistItems();
    this.notifyListeners();
  }

  // Toggle item completion
  toggleCompletion(itemId: string) {
    const item = this.reorderItems.find(item => item.id === itemId);
    if (item) {
      item.completed = !item.completed;
      this.persistItems();
      this.notifyListeners();
    }
  }
}

// Export singleton instance
export const reorderService = new ReorderService(); 