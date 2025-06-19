import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, FlatList, TouchableOpacity, ActivityIndicator, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import { itemHistoryService, type ChangeType } from '../services/itemHistoryService';
import type { ItemChangeLog } from '../models';
import logger from '../utils/logger';

interface ItemHistorySectionProps {
  itemId: string;
  itemName?: string;
}

interface HistoryItemProps {
  item: ItemChangeLog;
  index: number;
}

const CHANGE_TYPE_ICONS: Record<ChangeType, string> = {
  CREATED: 'add-circle-outline',
  IMPORTED: 'download-outline',
  PRICE_CHANGED: 'pricetag-outline',
  TAX_CHANGED: 'receipt-outline',
  CRV_CHANGED: 'leaf-outline',
  REORDERED: 'refresh-outline',
  DISCONTINUED: 'ban-outline',
  CATEGORY_CHANGED: 'filing-outline',
  VARIATION_ADDED: 'add-outline',
  VARIATION_REMOVED: 'remove-outline',
  DESCRIPTION_CHANGED: 'document-text-outline',
  SKU_CHANGED: 'barcode-outline',
  BARCODE_CHANGED: 'scan-outline',
  VENDOR_CHANGED: 'business-outline',
  NOTES_CHANGED: 'clipboard-outline'
};

const CHANGE_TYPE_COLORS: Record<ChangeType, string> = {
  CREATED: '#28a745',
  IMPORTED: '#007bff',
  PRICE_CHANGED: '#ffc107',
  TAX_CHANGED: '#6f42c1',
  CRV_CHANGED: '#20c997',
  REORDERED: '#17a2b8',
  DISCONTINUED: '#dc3545',
  CATEGORY_CHANGED: '#fd7e14',
  VARIATION_ADDED: '#28a745',
  VARIATION_REMOVED: '#dc3545',
  DESCRIPTION_CHANGED: '#6c757d',
  SKU_CHANGED: '#343a40',
  BARCODE_CHANGED: '#495057',
  VENDOR_CHANGED: '#e83e8c',
  NOTES_CHANGED: '#6f42c1'
};

const formatTimestamp = (timestamp: string): string => {
  try {
    const date = new Date(timestamp);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);
    
    if (diffInSeconds < 60) {
      return 'Just now';
    } else if (diffInSeconds < 3600) {
      const minutes = Math.floor(diffInSeconds / 60);
      return `${minutes} minute${minutes !== 1 ? 's' : ''} ago`;
    } else if (diffInSeconds < 86400) {
      const hours = Math.floor(diffInSeconds / 3600);
      return `${hours} hour${hours !== 1 ? 's' : ''} ago`;
    } else if (diffInSeconds < 604800) {
      const days = Math.floor(diffInSeconds / 86400);
      return `${days} day${days !== 1 ? 's' : ''} ago`;
    } else {
      return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined
      });
    }
  } catch (error) {
    return 'Unknown time';
  }
};

const HistoryItem: React.FC<HistoryItemProps> = ({ item, index }) => {
  const [isExpanded, setIsExpanded] = useState(false);
  
  const changeType = item.changeType as ChangeType;
  const iconName = CHANGE_TYPE_ICONS[changeType] || 'information-circle-outline';
  const iconColor = CHANGE_TYPE_COLORS[changeType] || lightTheme.colors.primary;
  
  const hasDetails = item.changeDetails && item.changeDetails.trim().length > 0;
  
  return (
    <View style={[styles.historyItem, index === 0 && styles.firstHistoryItem]}>
      <View style={styles.historyHeader}>
        <View style={styles.historyIconContainer}>
          <Ionicons 
            name={iconName as any} 
            size={16} 
            color={iconColor} 
            style={styles.historyIcon}
          />
        </View>
        
        <View style={styles.historyContent}>
          <Text style={styles.historyDescription} numberOfLines={isExpanded ? undefined : 2}>
            {item.changeDetails || `${changeType} change`}
          </Text>
          
          <View style={styles.historyMeta}>
            <Text style={styles.historyUser}>{item.authorName || 'Unknown'}</Text>
            <Text style={styles.historyTimestamp}>
              {formatTimestamp(item.timestamp || item.createdAt || '')}
            </Text>
          </View>
          
          {hasDetails && isExpanded && (
            <View style={styles.historyDetails}>
              <Text style={styles.historyDetailValue}>{item.changeDetails}</Text>
            </View>
          )}
        </View>
        
        {hasDetails && (
          <TouchableOpacity
            style={styles.expandButton}
            onPress={() => setIsExpanded(!isExpanded)}
            hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
          >
            <Ionicons
              name={isExpanded ? 'chevron-up' : 'chevron-down'}
              size={16}
              color={lightTheme.colors.text}
            />
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
};

const ItemHistorySection: React.FC<ItemHistorySectionProps> = ({ itemId, itemName }) => {
  const [history, setHistory] = useState<ItemChangeLog[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<ChangeType | 'ALL'>('ALL');
  
  const loadHistory = useCallback(async () => {
    if (!itemId) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      logger.info('ItemHistorySection:loadHistory', 'Loading history for item', { itemId });
      
      const filter = filterType !== 'ALL' ? { changeTypes: [filterType] } : undefined;
      const historyData = await itemHistoryService.getItemHistory(itemId, filter);
      
      setHistory(historyData);
      logger.info('ItemHistorySection:loadHistory', 'Successfully loaded history', { 
        itemId, 
        historyCount: historyData.length 
      });
    } catch (err) {
      // Check if it's an authentication error
      const errorMessage = (err as any)?.message || String(err);
      if (errorMessage.includes('not authorized') || errorMessage.includes('Unauthenticated') || errorMessage.includes('UNAUTHENTICATED')) {
        logger.info('ItemHistorySection:loadHistory', 'History unavailable - authentication required', { itemId });
        setHistory([]); // Show empty history gracefully
        setError(null); // Don't show error for auth issues
      } else {
        logger.error('ItemHistorySection:loadHistory', 'Error loading history', { error: err, itemId });
        setError('Failed to load item history');
      }
    } finally {
      setIsLoading(false);
    }
  }, [itemId, filterType]);
  
  useEffect(() => {
    loadHistory();
  }, [loadHistory]);
  
  const renderHistoryItem = useCallback(({ item, index }: { item: ItemChangeLog; index: number }) => (
    <HistoryItem item={item} index={index} />
  ), []);
  
  const renderEmptyState = useCallback(() => {
    if (isLoading) {
      return (
        <View style={styles.emptyContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.emptyText}>Loading history...</Text>
        </View>
      );
    }
    
    if (error) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="alert-circle-outline" size={48} color="#dc3545" />
          <Text style={styles.emptyTitle}>Error Loading History</Text>
          <Text style={styles.emptyText}>{error}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={loadHistory}>
            <Text style={styles.retryButtonText}>Retry</Text>
          </TouchableOpacity>
        </View>
      );
    }
    
    return (
      <View style={styles.emptyContainer}>
        <Ionicons name="time-outline" size={48} color={lightTheme.colors.border} />
        <Text style={styles.emptyTitle}>No History</Text>
        <Text style={styles.emptyText}>
          {filterType === 'ALL' 
            ? `No changes have been recorded for ${itemName || 'this item'} yet.`
            : `No ${filterType.toLowerCase().replace('_', ' ')} changes found.`
          }
        </Text>
      </View>
    );
  }, [isLoading, error, itemName, filterType, loadHistory]);
  
  const filterOptions: Array<{ label: string; value: ChangeType | 'ALL' }> = [
    { label: 'All Changes', value: 'ALL' },
    { label: 'Price Changes', value: 'PRICE_CHANGED' },
    { label: 'Reorders', value: 'REORDERED' },
    { label: 'Team Data', value: 'DISCONTINUED' },
    { label: 'Categories', value: 'CATEGORY_CHANGED' },
    { label: 'Taxes & CRV', value: 'TAX_CHANGED' }
  ];
  
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.sectionTitle}>Item History</Text>
        <TouchableOpacity 
          style={styles.refreshButton}
          onPress={loadHistory}
          hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
        >
          <Ionicons name="refresh-outline" size={20} color={lightTheme.colors.primary} />
        </TouchableOpacity>
      </View>
      
      {/* Filter Options */}
      <View style={styles.filterContainer}>
        <FlatList
          horizontal
          showsHorizontalScrollIndicator={false}
          data={filterOptions}
          keyExtractor={(item) => item.value}
          renderItem={({ item }) => (
            <TouchableOpacity
              style={[
                styles.filterButton,
                filterType === item.value && styles.filterButtonActive
              ]}
              onPress={() => setFilterType(item.value)}
            >
              <Text style={[
                styles.filterButtonText,
                filterType === item.value && styles.filterButtonTextActive
              ]}>
                {item.label}
              </Text>
            </TouchableOpacity>
          )}
          contentContainerStyle={styles.filterList}
        />
      </View>
      
      {/* History List */}
      <FlatList
        data={history}
        renderItem={renderHistoryItem}
        keyExtractor={(item) => item.id || `${item.itemID}-${item.timestamp}`}
        ListEmptyComponent={renderEmptyState}
        contentContainerStyle={styles.historyList}
        showsVerticalScrollIndicator={false}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
  },
  refreshButton: {
    padding: 4,
  },
  filterContainer: {
    marginBottom: 16,
  },
  filterList: {
    paddingHorizontal: 0,
  },
  filterButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginRight: 8,
    borderRadius: 16,
    backgroundColor: lightTheme.colors.card,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
  },
  filterButtonActive: {
    backgroundColor: lightTheme.colors.primary,
    borderColor: lightTheme.colors.primary,
  },
  filterButtonText: {
    fontSize: 12,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },
  filterButtonTextActive: {
    color: '#fff',
  },
  historyList: {
    flexGrow: 1,
  },
  historyItem: {
    marginBottom: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: lightTheme.colors.border,
  },
  firstHistoryItem: {
    borderTopWidth: 0,
    paddingTop: 0,
  },
  historyHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  historyIconContainer: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: `${lightTheme.colors.primary}15`,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  historyIcon: {
    // Icon styles handled by Ionicons
  },
  historyContent: {
    flex: 1,
  },
  historyDescription: {
    fontSize: 14,
    color: lightTheme.colors.text,
    fontWeight: '500',
    lineHeight: 20,
    marginBottom: 4,
  },
  historyMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  historyUser: {
    fontSize: 12,
    color: lightTheme.colors.primary,
    fontWeight: '500',
    marginRight: 8,
  },
  historyTimestamp: {
    fontSize: 12,
    color: lightTheme.colors.text + '80',
  },
  historyDetails: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 8,
    padding: 12,
    marginTop: 8,
  },
  historyDetailRow: {
    flexDirection: 'row',
    marginBottom: 4,
  },
  historyDetailLabel: {
    fontSize: 12,
    color: lightTheme.colors.text + '80',
    fontWeight: '600',
    width: 40,
  },
  historyDetailValue: {
    fontSize: 12,
    color: lightTheme.colors.text,
    flex: 1,
  },
  expandButton: {
    padding: 4,
    marginLeft: 8,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 12,
    marginBottom: 8,
  },
  emptyText: {
    fontSize: 14,
    color: lightTheme.colors.text + '80',
    textAlign: 'center',
    lineHeight: 20,
  },
  retryButton: {
    marginTop: 16,
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
  },
  retryButtonText: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '500',
  },
});

export default ItemHistorySection; 