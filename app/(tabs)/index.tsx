import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { View, FlatList, StyleSheet, SafeAreaView, StatusBar, Text, TouchableOpacity, ActivityIndicator, TextInput } from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import ConnectionStatusBar from '../../src/components/ConnectionStatusBar';
import SearchBar from '../../src/components/SearchBar';
import SortHeader from '../../src/components/SortHeader';
import CatalogueItemCard from '../../src/components/CatalogueItemCard';
import SwipeableRow from '../../src/components/SwipeableRow';
import { ScanHistoryItem } from '../../src/types';
import { ConvertedItem, CatalogObject, CatalogItemData } from '../../src/types/api';
import { Ionicons } from '@expo/vector-icons';
import { useApi } from '../../src/providers/ApiProvider';
import { useAppStore } from '../../src/store';
import { apiClientInstance } from '../../src/api';
import logger from '../../src/utils/logger';
import { DatabaseProvider } from '../../src/components/DatabaseProvider';
import { transformCatalogItemToItem } from '../../src/utils/catalogTransformers';
import { Alert } from 'react-native';
import { v4 as uuidv4 } from 'uuid';
import { lightTheme } from '../../src/themes';
import * as modernDb from '../../src/database/modernDb';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';

export default function App() {
  return (
    <DatabaseProvider>
      <RootLayoutNav />
    </DatabaseProvider>
  );
}

function RootLayoutNav() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [sortOrder, setSortOrder] = useState<'newest' | 'oldest' | 'name' | 'price'>('newest');
  const [isSearching, setIsSearching] = useState(false);
  
  // Ref for the search input
  const searchInputRef = useRef<TextInput>(null);
  
  const { isConnected } = useApi();
  
  const scanHistory = useAppStore((state) => state.scanHistory);
  const addScanHistoryItem = useAppStore((state) => state.addScanHistoryItem);
  const removeScanHistoryItem = useAppStore((state) => state.removeScanHistoryItem);
  const autoSearchOnEnter = useAppStore((state) => state.autoSearchOnEnter);
  const autoSearchOnTab = useAppStore((state) => state.autoSearchOnTab);
  
  useEffect(() => {
    // Log the settings when the component mounts and when they change
    logger.info('Home::SettingsCheck', 'Current auto-search settings:', { 
      autoSearchOnEnter,
      autoSearchOnTab,
    });
  }, [autoSearchOnEnter, autoSearchOnTab]);
  
  useEffect(() => {
    logger.info('Home', 'Home screen mounted');
    // Focus the search input when the component mounts
    setTimeout(() => {
      if (searchInputRef.current) {
        searchInputRef.current.focus();
      }
    }, 300); // Short delay to ensure the component is fully mounted
  }, []);
  
  // Also focus the search field when returning to this screen
  useFocusEffect(
    useCallback(() => {
      logger.info('Home::useFocusEffect', 'Screen focused, attempting to focus search input.');
      // Attempt to focus directly without setTimeout
      if (searchInputRef.current) {
        logger.info('Home::useFocusEffect', 'searchInputRef.current is available, calling focus().');
        searchInputRef.current.focus();
      } else {
        logger.warn('Home::useFocusEffect', 'searchInputRef.current is NULL when direct focus attempt was made.');
      }
      
      return () => {
        logger.info('Home::useFocusEffect', 'Screen lost focus.');
        // Optional: blur input when screen loses focus
        // if (searchInputRef.current) {
        //   searchInputRef.current.blur();
        // }
      };
    }, [])
  );
  
  // Function to determine search type
  const getQueryType = (query: string): 'UPC' | 'SKU' | 'NAME' => {
    // UPC: 8, 12, 13, or 14 digits
    if (/^\d{8}$|^\d{12,14}$/.test(query)) {
      return 'UPC';
    }
    // Simple SKU check (alphanumeric, potentially starting/ending specific way - adjust if needed)
    if (/^[a-zA-Z0-9\-]+$/.test(query) && !/^\d+$/.test(query)) { // Alphanumeric but not *only* digits
        // Add more specific SKU patterns here if applicable
        return 'SKU';
    }
    // Default to name search
    return 'NAME';
  };
  
  const handleSearch = async (submittedValue?: string) => {
    // Prioritize submittedValue if provided, otherwise use component's search state.
    const valueToSearch = typeof submittedValue === 'string' ? submittedValue : search;
    
    logger.info('Home::handleSearch', `Search initiated. Source: ${typeof submittedValue === 'string' ? 'direct_submission' : 'state'}, Value: "${valueToSearch}"`);

    if (!valueToSearch.trim()) {
      logger.warn('Home::handleSearch', 'Search value is empty, aborting.');
      return;
    }
    
    // Blur input when search starts - check if searchInputRef.current exists
    if (searchInputRef.current) {
      searchInputRef.current.blur();
    }
    
    const query = valueToSearch.trim();
    const queryType = getQueryType(query);
    
    logger.info('Home', `Processing search - Value: "${query}", Type: ${queryType}`);
    setIsSearching(true);
    
    try {
      // --- 1. Search Local Database First --- 
      logger.debug('Home', 'Attempting local DB search first...', { query });
      const localItems = await modernDb.searchLocalItems(query);
      
      if (localItems.length > 0) {
        // Item found locally
        logger.info('Home', 'Item found in local DB', { count: localItems.length, query });
        
        if (localItems.length > 1) {
          logger.warn('Home', 'Multiple items found locally. Using the first result.', {
            count: localItems.length,
            query,
            firstItemId: localItems[0]?.id
          });
          // TODO: Implement UI to allow user to select the correct item when multiple are found locally.
        }
        
        const localItemToUse = localItems[0]; // Use the first item for now
        
        // ** Add check for valid item and ID before routing **
        if (localItemToUse && typeof localItemToUse.id === 'string' && localItemToUse.id.trim() !== '') {
          let historyItem: ScanHistoryItem | null = null;
          try {
            // 1. Try creating history item
            logger.debug('Home', 'Attempting to generate scanId...');
            // ** TEMP TEST: Use Date.now() instead of uuidv4 **
            const scanId = `temp-${Date.now()}-${Math.random().toString(36).substring(2, 8)}`; 
            // const scanId = uuidv4(); // Generate UUID first
            logger.debug('Home', 'Generated scanId', { scanId });
            
            logger.debug('Home', 'Attempting to create historyItem object (with full data)...');
            // Explicitly include all relevant fields from the enriched localItemToUse
            historyItem = {
              id: localItemToUse.id,
              name: localItemToUse.name,
              description: localItemToUse.description,
              price: localItemToUse.price,
              sku: localItemToUse.sku, // Ensure SKU is included
              barcode: localItemToUse.barcode, // Ensure Barcode/UPC is included
              isActive: localItemToUse.isActive,
              category: localItemToUse.category,
              categoryId: localItemToUse.categoryId,
              images: localItemToUse.images,
              createdAt: localItemToUse.createdAt,
              updatedAt: localItemToUse.updatedAt,
              taxIds: localItemToUse.taxIds, // Ensure Tax IDs are included
              // History specific fields
              scanId: scanId,
              scanTime: new Date().toISOString(),
            };
            logger.debug('Home', 'History item object created', { scanId: historyItem.scanId });
          } catch (historyCreationError) {
            // Catch errors from either uuid or object creation
            logger.error('Home', 'Error creating history item object from local item', { error: historyCreationError, item: localItemToUse });
            throw historyCreationError; // Re-throw to be caught by outer catch
          }
          
          if (historyItem) {
             // Log the complete history item before adding to store
             logger.debug('Home', 'Attempting to add history item to store:', historyItem);
             try {
               // 2. Try adding to Zustand store
               addScanHistoryItem(historyItem);
               logger.debug('Home', 'Added item to scan history store', { scanId: historyItem.scanId });
             } catch (storeError) {
               logger.error('Home', 'Error adding item to Zustand store', { error: storeError, historyItem });
               throw storeError; // Re-throw to be caught by outer catch
             }
             
             try {
               // 3. Try navigating
               logger.info('Home', 'Navigating to item details', { itemId: localItemToUse.id });
               router.push(`/item/${localItemToUse.id}`);
               setSearch(''); // Clear search input in UI
             } catch (navigationError) {
               logger.error('Home', 'Error navigating to item details', { error: navigationError, itemId: localItemToUse.id });
               throw navigationError; // Re-throw to be caught by outer catch
             }
          }
          
        } else {
           // Log error if ID is missing or invalid
           logger.error('Home', 'Local search found item but ID is missing or invalid', { itemData: JSON.stringify(localItemToUse) });
           Alert.alert('Search Error', 'Found item locally, but could not navigate to its details (Invalid ID).');
        }
      } else {
        // --- 2. Search Backend API (if not found locally) --- 
        logger.info('Home', 'Item not found locally, searching backend API...', { query, queryType });

        // Use a proper query structure with text_query as recommended by Square API
        logger.debug('Home', 'Sending search request with proper query structure', { fullQuery: query, queryType });
        const searchPayload = {
          object_types: ['ITEM', 'ITEM_VARIATION'],
          query: {
            text_query: {
              keywords: [query]
            }
          },
          limit: 100
        };
        
        logger.debug('Home', 'Search payload:', searchPayload);
        const response = await apiClientInstance.post('/v2/catalog/search', searchPayload);
      
        if (response.data.success && response.data.objects && response.data.objects.length > 0) {
          
          // --- Handle Potential Duplicates --- 
          if ((queryType === 'UPC' || queryType === 'SKU') && response.data.objects.length > 1) {
            logger.warn('Home', `Multiple items found for ${queryType}: ${query}. Using the first result.`, {
              count: response.data.objects.length,
              query,
              queryType,
              firstItemId: response.data.objects[0]?.id
            });
            // TODO: Implement UI to allow user to select the correct item when multiple are found for UPC/SKU.
          }
          // --- End Handle Potential Duplicates ---
          
          const foundRawItem = response.data.objects[0]; // This is a raw CatalogObject
          
          // We need to enrich this raw item before saving to history
          logger.debug('Home', 'API search found raw item, attempting enrichment...', { itemId: foundRawItem.id });
          
          let enrichedItem: ConvertedItem | null = null;
          try {
            const db = await modernDb.getDatabase();
            // Fetch the full raw data from DB using the ID found via API
            // Use getItemOrVariationRawById to ensure we handle both cases
            const rawDbResult = await modernDb.getItemOrVariationRawById(foundRawItem.id);
            
            if (rawDbResult?.data_json) {
               let itemJson: string | null = null;
               let variationJson: string | null = null;
               let itemId = foundRawItem.id;
               let itemUpdatedAt = new Date().toISOString();

               if (rawDbResult.found_in === 'item') {
                 itemJson = rawDbResult.data_json;
                 const firstVariation = await db.getFirstAsync<any>(
                   `SELECT data_json FROM item_variations WHERE item_id = ? AND is_deleted = 0 LIMIT 1`,
                   [itemId]
                 );
                 variationJson = firstVariation?.data_json || null;
                 itemUpdatedAt = rawDbResult.updated_at || itemUpdatedAt;
               } else if (rawDbResult.found_in === 'variation') {
                 variationJson = rawDbResult.data_json;
                 itemId = rawDbResult.item_id;
                 const parentItem = await db.getFirstAsync<any>(
                   `SELECT data_json, updated_at FROM catalog_items WHERE id = ? AND is_deleted = 0`,
                   [itemId]
                 );
                 itemJson = parentItem?.data_json || null;
                 itemUpdatedAt = parentItem?.updated_at || itemUpdatedAt;
               }

               if (itemJson) {
                 const itemData = JSON.parse(itemJson);
                 const variationData = variationJson ? JSON.parse(variationJson) : {};

                 // Extract Modifier IDs
                 const modifierListInfo = itemData?.item_data?.modifier_list_info;
                 let actualModifierListIds: string[] = [];

                 if (modifierListInfo && Array.isArray(modifierListInfo) && modifierListInfo.length > 0) {
                   actualModifierListIds = modifierListInfo
                     .map((info: any) => info?.modifier_list_id)
                     .filter((id: any): id is string => typeof id === 'string');
                 }
                 
                 // Reconstruct for transformer
                  const reconstructedCatalogObject: Partial<CatalogObject> & { id: string } = {
                    id: itemId,
                    type: 'ITEM',
                    updated_at: itemUpdatedAt,
                    version: itemData.version || '0', 
                    is_deleted: false,
                    item_data: {
                      ...(itemData.item_data || {}),
                      variations: variationData.id ? [{
                        id: variationData.id, type: 'ITEM_VARIATION', updated_at: variationData.updated_at, 
                        version: variationData.version, item_variation_data: variationData.item_variation_data
                      }] : []
                    }
                  };

                  // Transform the enriched, reconstructed data
                  enrichedItem = transformCatalogItemToItem(reconstructedCatalogObject as any);
               } else {
                  logger.warn('Home', 'Could not find necessary parent item JSON during API result enrichment', { apiFoundId: foundRawItem.id });
               }
            } else {
               logger.warn('Home', 'API found item ID, but no corresponding raw data found in DB for enrichment', { itemId: foundRawItem.id });
               // Fallback: Use the initially transformed (incomplete) item?
               enrichedItem = transformCatalogItemToItem(foundRawItem); // This will lack tax/crv
            }
          } catch (enrichError) {
             logger.error('Home', 'Error enriching item found via API', { itemId: foundRawItem.id, error: enrichError });
             enrichedItem = transformCatalogItemToItem(foundRawItem); // Fallback to basic transform on error
          }

          // Use the enriched item (or fallback) if available
          if (enrichedItem) {
            logger.info('Home', 'Item enriched (or fell back) after API search', { itemId: enrichedItem.id, name: enrichedItem.name, hasTax: !!enrichedItem.taxIds?.length });
            
            const historyItem: ScanHistoryItem = {
              ...enrichedItem, // Use the enriched item data
              scanId: uuidv4(),
              scanTime: new Date().toISOString(),
            };
            addScanHistoryItem(historyItem);
            router.push(`/item/${enrichedItem.id}`);
            setSearch(''); // Clear search input in UI
          } else {
            logger.warn('Home', 'API Search returned item but enrichment/transformation failed', { rawItem: foundRawItem });
            Alert.alert('Search Error', 'Found an item, but could not display its details.');
          }
        } else if (response.data.success) {
          logger.info('Home', 'Search completed (API), no items found', { query, queryType });
          Alert.alert('Not Found', `No item found matching "${query}".`);
        } else {
          logger.error('Home', 'Search API call failed', { query, queryType, error: response.data.error?.message });
          Alert.alert('Search Error', response.data.error?.message || 'Could not perform search. Please check connection.');
        }
      }
      // --- End Search Logic --- 
      
    } catch (error) {
      logger.error('Home', 'Error during search execution', { query, queryType, error });
      Alert.alert('Search Error', 'An unexpected error occurred during search.');
    } finally {
      setIsSearching(false);
    }
  };
  
  const handleItemPress = (item: ScanHistoryItem | ConvertedItem) => {
    const itemId = item.id;
    logger.info('Home', 'Item selected from history', { itemId });
    router.push(`/item/${itemId}`);
  };
  
  const handleDeleteHistoryItem = (scanId: string) => {
    logger.info('Home', 'Removing item from scan history', { scanId });
    removeScanHistoryItem(scanId);
  };
  
  const sortedItems = [...scanHistory].sort((a, b) => {
    switch (sortOrder) {
      case 'newest':
        return new Date(b.scanTime).getTime() - new Date(a.scanTime).getTime();
      case 'oldest':
        return new Date(a.scanTime).getTime() - new Date(b.scanTime).getTime();
      case 'name':
        return (a.name ?? '').localeCompare(b.name ?? '');
      case 'price':
        const aPrice = typeof a.price === 'number' ? a.price : 0;
        const bPrice = typeof b.price === 'number' ? b.price : 0;
        return bPrice - aPrice;
      default:
        return 0;
    }
  });
  
  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
      
      <View style={styles.mainContainer}>
        <ConnectionStatusBar 
          connected={isConnected} 
          message="Square Connection Status" 
        />
        
        <SearchBar 
          ref={searchInputRef}
          value={search}
          onChangeText={setSearch}
          onSubmit={handleSearch}
          onClear={() => setSearch('')}
          autoSearchOnEnter={autoSearchOnEnter}
          autoSearchOnTab={autoSearchOnTab}
        />
        
        <SortHeader 
          title="Scan History" 
          sortOrder={sortOrder}
          onSortChange={setSortOrder}
        />
        
        <FlatList
          data={sortedItems}
          keyExtractor={(item) => item.scanId}
          renderItem={({ item, index }) => (
            <SwipeableRow
              onDelete={() => handleDeleteHistoryItem(item.scanId)}
              itemName={item.name ?? undefined}
            >
              <CatalogueItemCard 
                item={item}
                index={sortedItems.length - index}
                onPress={() => handleItemPress(item)}
              />
            </SwipeableRow>
          )}
          contentContainerStyle={styles.listContent}
          style={styles.listContainer}
          ListEmptyComponent={() => (
            <View style={styles.emptyListContainer}>
              <Ionicons name="scan-circle-outline" size={60} color="#ccc" />
              <Text style={styles.emptyListText}>Scan history is empty.</Text>
              <Text style={styles.emptyListSubText}>Search for items to add them here.</Text>
            </View>
          )}
        />
      </View>
      {isSearching && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.loadingText}>Searching...</Text>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#fff',
  },
  mainContainer: {
    flex: 1,
  },
  listContainer: {
    flex: 1,
  },
  listContent: {
    paddingBottom: 20,
    flexGrow: 1,
  },
  emptyListContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 40,
    marginTop: 50,
  },
  emptyListText: {
    marginTop: 15,
    fontSize: 18,
    fontWeight: '500',
    color: '#888',
  },
  emptyListSubText: {
    marginTop: 5,
    fontSize: 14,
    color: '#aaa',
    textAlign: 'center',
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#555',
  },
}); 