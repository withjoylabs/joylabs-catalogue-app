import { generateClient } from 'aws-amplify/api';
import * as mutations from '../graphql/mutations';
import * as queries from '../graphql/queries';
import type { ItemChangeLog } from '../models';
import logger from '../utils/logger';

const client = generateClient();

export type ChangeType = 
  | 'CREATED' 
  | 'IMPORTED' 
  | 'PRICE_CHANGED' 
  | 'TAX_CHANGED' 
  | 'CRV_CHANGED' 
  | 'REORDERED' 
  | 'DISCONTINUED'
  | 'CATEGORY_CHANGED'
  | 'VARIATION_ADDED'
  | 'VARIATION_REMOVED'
  | 'DESCRIPTION_CHANGED'
  | 'SKU_CHANGED'
  | 'BARCODE_CHANGED'
  | 'VENDOR_CHANGED'
  | 'NOTES_CHANGED';

export interface ItemHistoryEntry {
  itemId: string;
  changeType: ChangeType;
  changeDescription: string;
  oldValue?: string;
  newValue?: string;
  userName: string;
  timestamp?: string;
  additionalData?: Record<string, any>;
}

export interface ItemHistoryFilter {
  changeTypes?: ChangeType[];
  dateFrom?: string;
  dateTo?: string;
  userName?: string;
  limit?: number;
  nextToken?: string;
}

class ItemHistoryService {
  /**
   * Check if user is authenticated for history operations
   */
  private isUserAuthenticated(): boolean {
    try {
      // Try to access the client to see if we're authenticated
      // This is a simple check - in a real app you might want to check Auth.currentAuthenticatedUser()
      return true; // We'll rely on GraphQL auth to handle this
    } catch (error) {
      return false;
    }
  }

  /**
   * Log a change to an item's history
   */
  async logItemChange(entry: ItemHistoryEntry): Promise<boolean> {
    // Gracefully handle unauthenticated users
    if (!entry.userName || entry.userName === 'Unknown User' || entry.userName.trim() === '') {
      logger.info('ItemHistoryService:logItemChange', 'Skipping history logging - user not authenticated', {
        itemId: entry.itemId,
        changeType: entry.changeType
      });
      return true; // Return true to not break the flow
    }

    try {
      const changeLogInput = {
        itemID: entry.itemId,
        changeType: entry.changeType,
        changeDetails: entry.changeDescription,
        authorName: entry.userName,
        timestamp: entry.timestamp || new Date().toISOString()
      };

      logger.info('ItemHistoryService:logItemChange', 'Logging item change', {
        itemId: entry.itemId,
        changeType: entry.changeType,
        userName: entry.userName
      });

      const result = await client.graphql({
        query: mutations.createItemChangeLog,
        variables: { input: changeLogInput }
      }) as any;

      if (result.data?.createItemChangeLog) {
        logger.info('ItemHistoryService:logItemChange', 'Successfully logged item change', {
          itemId: entry.itemId,
          changeId: result.data.createItemChangeLog.id
        });
        return true;
      }

      logger.error('ItemHistoryService:logItemChange', 'Failed to create change log entry');
      return false;
    } catch (error) {
      // Check if it's an authentication error
      const errorMessage = (error as any)?.message || String(error);
      if (errorMessage.includes('not authorized') || errorMessage.includes('Unauthenticated') || errorMessage.includes('UNAUTHENTICATED')) {
        logger.info('ItemHistoryService:logItemChange', 'Skipping history logging - authentication required', {
          itemId: entry.itemId,
          changeType: entry.changeType
        });
        return true; // Gracefully skip instead of failing
      }
      
      logger.error('ItemHistoryService:logItemChange', 'Error logging item change', { error, entry });
      return false;
    }
  }

  /**
   * Get history for a specific item
   */
  async getItemHistory(itemId: string, filter?: ItemHistoryFilter): Promise<ItemChangeLog[]> {
    try {
      logger.info('ItemHistoryService:getItemHistory', 'Fetching item history', { itemId, filter });

      const variables: any = {
        itemId,
        limit: filter?.limit || 50,
        nextToken: filter?.nextToken
      };

      // Add filters if provided
      if (filter?.changeTypes && filter.changeTypes.length > 0) {
        variables.filter = {
          changeType: { in: filter.changeTypes }
        };
      }

      const result = await client.graphql({
        query: queries.listChangesForItem,
        variables: {
          itemID: itemId,
          sortDirection: 'DESC',
          ...variables
        }
      }) as any;

      const history = result.data?.listChangesForItem?.items || [];
      
      // Sort by timestamp descending (most recent first)
      const sortedHistory = history.sort((a: any, b: any) => 
        new Date(b.timestamp || '').getTime() - new Date(a.timestamp || '').getTime()
      );

      logger.info('ItemHistoryService:getItemHistory', 'Successfully fetched item history', {
        itemId,
        historyCount: sortedHistory.length
      });

      return sortedHistory;
    } catch (error) {
      // Check if it's an authentication error
      const errorMessage = (error as any)?.message || String(error);
      if (errorMessage.includes('not authorized') || errorMessage.includes('Unauthenticated') || errorMessage.includes('UNAUTHENTICATED')) {
        logger.info('ItemHistoryService:getItemHistory', 'Skipping history fetch - authentication required', { itemId });
        return []; // Return empty array gracefully
      }
      
      logger.error('ItemHistoryService:getItemHistory', 'Error fetching item history', { error, itemId });
      return [];
    }
  }

  /**
   * Log item creation
   */
  async logItemCreation(itemId: string, itemName: string, userName: string): Promise<boolean> {
    return this.logItemChange({
      itemId,
      changeType: 'CREATED',
      changeDescription: `Item "${itemName}" created`,
      userName,
      additionalData: { itemName }
    });
  }

  /**
   * Log item import/sync
   */
  async logItemImport(itemId: string, itemName: string, source: 'sync' | 'webhook', userName: string = 'System'): Promise<boolean> {
    return this.logItemChange({
      itemId,
      changeType: 'IMPORTED',
      changeDescription: `Item "${itemName}" imported via ${source}`,
      userName,
      additionalData: { itemName, source }
    });
  }

  /**
   * Log price changes
   */
  async logPriceChange(
    itemId: string, 
    itemName: string, 
    variationName: string | null,
    oldPrice: number | undefined, 
    newPrice: number | undefined, 
    userName: string
  ): Promise<boolean> {
    const variationLabel = variationName ? ` (${variationName})` : '';
    const oldPriceStr = oldPrice !== undefined ? `$${oldPrice.toFixed(2)}` : 'Variable';
    const newPriceStr = newPrice !== undefined ? `$${newPrice.toFixed(2)}` : 'Variable';
    
    return this.logItemChange({
      itemId,
      changeType: 'PRICE_CHANGED',
      changeDescription: `Price changed for "${itemName}"${variationLabel}: ${oldPriceStr} → ${newPriceStr}`,
      oldValue: oldPriceStr,
      newValue: newPriceStr,
      userName,
      additionalData: { itemName, variationName, oldPrice, newPrice }
    });
  }

  /**
   * Log CRV changes
   */
  async logCRVChange(
    itemId: string,
    itemName: string,
    oldCRV: number | undefined,
    newCRV: number | undefined,
    userName: string
  ): Promise<boolean> {
    const oldCRVStr = oldCRV !== undefined ? `$${oldCRV.toFixed(2)}` : 'None';
    const newCRVStr = newCRV !== undefined ? `$${newCRV.toFixed(2)}` : 'None';
    
    return this.logItemChange({
      itemId,
      changeType: 'CRV_CHANGED',
      changeDescription: `CRV changed for "${itemName}": ${oldCRVStr} → ${newCRVStr}`,
      oldValue: oldCRVStr,
      newValue: newCRVStr,
      userName,
      additionalData: { itemName, oldCRV, newCRV }
    });
  }

  /**
   * Log tax changes
   */
  async logTaxChange(
    itemId: string,
    itemName: string,
    addedTaxes: string[],
    removedTaxes: string[],
    taxNameMap: Record<string, string>,
    userName: string
  ): Promise<boolean> {
    const changes: string[] = [];
    
    if (addedTaxes.length > 0) {
      const taxNames = addedTaxes.map(id => taxNameMap[id] || id).join(', ');
      changes.push(`Added: ${taxNames}`);
    }
    
    if (removedTaxes.length > 0) {
      const taxNames = removedTaxes.map(id => taxNameMap[id] || id).join(', ');
      changes.push(`Removed: ${taxNames}`);
    }
    
    if (changes.length === 0) return true; // No changes to log
    
    return this.logItemChange({
      itemId,
      changeType: 'TAX_CHANGED',
      changeDescription: `Tax settings changed for "${itemName}": ${changes.join('; ')}`,
      userName,
      additionalData: { itemName, addedTaxes, removedTaxes }
    });
  }

  /**
   * Log reorder completion (when item completes the full reorder cycle: added → completed → received)
   */
  async logReorder(
    itemId: string,
    itemName: string,
    quantity: number,
    userName: string
  ): Promise<boolean> {
    return this.logItemChange({
      itemId,
      changeType: 'REORDERED',
      changeDescription: `Item "${itemName}" reorder completed (quantity: ${quantity})`,
      newValue: quantity.toString(),
      userName,
      additionalData: { itemName, quantity }
    });
  }

  /**
   * Log discontinued status change
   */
  async logDiscontinuedChange(
    itemId: string,
    itemName: string,
    wasDiscontinued: boolean,
    isDiscontinued: boolean,
    userName: string
  ): Promise<boolean> {
    const description = isDiscontinued 
      ? `Item "${itemName}" marked as discontinued`
      : `Item "${itemName}" reactivated (no longer discontinued)`;
    
    return this.logItemChange({
      itemId,
      changeType: 'DISCONTINUED',
      changeDescription: description,
      oldValue: wasDiscontinued.toString(),
      newValue: isDiscontinued.toString(),
      userName,
      additionalData: { itemName, wasDiscontinued, isDiscontinued }
    });
  }

  /**
   * Log category changes
   */
  async logCategoryChange(
    itemId: string,
    itemName: string,
    oldCategoryName: string | undefined,
    newCategoryName: string | undefined,
    userName: string
  ): Promise<boolean> {
    const oldCategory = oldCategoryName || 'None';
    const newCategory = newCategoryName || 'None';
    
    return this.logItemChange({
      itemId,
      changeType: 'CATEGORY_CHANGED',
      changeDescription: `Category changed for "${itemName}": ${oldCategory} → ${newCategory}`,
      oldValue: oldCategory,
      newValue: newCategory,
      userName,
      additionalData: { itemName, oldCategoryName, newCategoryName }
    });
  }

  /**
   * Log variation changes
   */
  async logVariationChange(
    itemId: string,
    itemName: string,
    action: 'added' | 'removed',
    variationName: string | null,
    userName: string
  ): Promise<boolean> {
    const variationLabel = variationName || 'Unnamed variation';
    const changeType = action === 'added' ? 'VARIATION_ADDED' : 'VARIATION_REMOVED';
    const description = `Variation "${variationLabel}" ${action} ${action === 'added' ? 'to' : 'from'} "${itemName}"`;
    
    return this.logItemChange({
      itemId,
      changeType,
      changeDescription: description,
      newValue: variationLabel,
      userName,
      additionalData: { itemName, variationName, action }
    });
  }

  /**
   * Log vendor changes (team data)
   */
  async logVendorChange(
    itemId: string,
    itemName: string,
    oldVendor: string | undefined,
    newVendor: string | undefined,
    userName: string
  ): Promise<boolean> {
    const oldVendorStr = oldVendor || 'None';
    const newVendorStr = newVendor || 'None';
    
    return this.logItemChange({
      itemId,
      changeType: 'VENDOR_CHANGED',
      changeDescription: `Vendor changed for "${itemName}": ${oldVendorStr} → ${newVendorStr}`,
      oldValue: oldVendorStr,
      newValue: newVendorStr,
      userName,
      additionalData: { itemName, oldVendor, newVendor }
    });
  }

  /**
   * Log notes changes (team data)
   */
  async logNotesChange(
    itemId: string,
    itemName: string,
    oldNotes: string | undefined,
    newNotes: string | undefined,
    userName: string
  ): Promise<boolean> {
    const hasOldNotes = oldNotes && oldNotes.trim().length > 0;
    const hasNewNotes = newNotes && newNotes.trim().length > 0;
    
    let description: string;
    if (!hasOldNotes && hasNewNotes) {
      description = `Notes added to "${itemName}"`;
    } else if (hasOldNotes && !hasNewNotes) {
      description = `Notes removed from "${itemName}"`;
    } else {
      description = `Notes updated for "${itemName}"`;
    }
    
    return this.logItemChange({
      itemId,
      changeType: 'NOTES_CHANGED',
      changeDescription: description,
      oldValue: oldNotes || undefined,
      newValue: newNotes || undefined,
      userName,
      additionalData: { itemName, oldNotes, newNotes }
    });
  }

  /**
   * Log vendor unit cost changes (calculated field)
   */
  async logVendorUnitCostChange(
    itemId: string,
    itemName: string,
    oldVendorUnitCost: number | undefined,
    newVendorUnitCost: number | undefined,
    userName: string
  ): Promise<boolean> {
    const oldValueStr = oldVendorUnitCost !== undefined ? `$${oldVendorUnitCost.toFixed(2)}` : 'Not calculated';
    const newValueStr = newVendorUnitCost !== undefined ? `$${newVendorUnitCost.toFixed(2)}` : 'Not calculated';
    
    return this.logItemChange({
      itemId,
      changeType: 'CRV_CHANGED', // Reusing CRV_CHANGED type for vendor cost changes
      changeDescription: `Vendor unit cost changed from ${oldValueStr} to ${newValueStr}`,
      oldValue: oldValueStr,
      newValue: newValueStr,
      userName,
      additionalData: { 
        itemName,
        oldVendorUnitCost,
        newVendorUnitCost,
        changeSubtype: 'vendor_unit_cost'
      }
    });
  }

  /**
   * Bulk log multiple changes (useful for imports)
   */
  async logBulkChanges(entries: ItemHistoryEntry[]): Promise<boolean[]> {
    const results = await Promise.allSettled(
      entries.map(entry => this.logItemChange(entry))
    );
    
    return results.map(result => 
      result.status === 'fulfilled' ? result.value : false
    );
  }
}

// Export singleton instance
export const itemHistoryService = new ItemHistoryService();
export default itemHistoryService; 