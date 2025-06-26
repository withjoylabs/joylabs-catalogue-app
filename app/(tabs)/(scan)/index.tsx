import React, { useState, useEffect, useRef, useCallback, memo } from 'react';
import {
  View, 
  FlatList, 
  // StyleSheet, // Will be replaced by indexStyles
  SafeAreaView, 
  StatusBar, 
  Text, 
  Pressable, 
  ActivityIndicator, 
  TextInput, 
  // Button, // No longer explicitly needed
  Platform, // For KeyboardAvoidingView if we re-add it, but SearchBar handles its input.
  KeyboardAvoidingView, // Keep for filter pills for now, may remove if SearchBar covers all
  ScrollView,
  Modal,
  Animated, // For swipe action
  Alert, // Added for print feedback
  Vibration, // Added for haptic feedback
} from 'react-native';
import { useRouter, useFocusEffect, Link, useNavigation } from 'expo-router';
import { useIsFocused, useNavigationState } from '@react-navigation/native';
import { Swipeable } from 'react-native-gesture-handler'; // Added for swipe actions
import ConnectionStatusBar from '../../../src/components/ConnectionStatusBar';
import NotificationBell from '../../../src/components/NotificationBell'; // Added for notifications access
import { ConvertedItem, SearchResultItem } from '../../../src/types/api';
import { Ionicons } from '@expo/vector-icons';
import { useApi } from '../../../src/providers/ApiProvider';
import { useAppStore } from '../../../src/store';
import { apiClientInstance } from '../../../src/api';
import logger from '../../../src/utils/logger';
import { DatabaseProvider } from '../../../src/components/DatabaseProvider';
import { transformCatalogItemToItem } from '../../../src/utils/catalogTransformers';
import { v4 as uuidv4 } from 'uuid';
import { lightTheme } from '../../../src/themes';
import * as modernDb from '../../../src/database/modernDb';
import { useCatalogItems } from '../../../src/hooks/useCatalogItems';
import { styles } from '../../../src/styles/_indexStyles'; // Updated import
import { SearchFilters } from '../../../src/database/modernDb'; // For search filters type
import { printItemLabel, LabelData } from '../../../src/utils/printLabel'; // Added for printing
import SystemModal from '../../../src/components/SystemModal'; // Added for notifications
import { reorderService, TeamData } from '../../../src/services/reorderService'; // Added for reorder functionality
import { generateClient } from 'aws-amplify/api';
import * as queries from '../../../src/graphql/queries';
import { useAuthenticator } from '@aws-amplify/ui-react-native';

const client = generateClient();

// Debounce utility
const debounce = <F extends (...args: any[]) => any>(func: F, waitFor: number) => {
  let timeout: NodeJS.Timeout | null = null;
  
  const debounced = (...args: Parameters<F>) => {
    if (timeout !== null) {
      clearTimeout(timeout);
    }
    timeout = setTimeout(() => func(...args), waitFor);
  };

  debounced.cancel = () => {
    if (timeout !== null) {
      clearTimeout(timeout);
    }
  };
  
  return debounced as ((...args: Parameters<F>) => void) & { cancel: () => void };
};

// --- START: SearchResultsArea Component Definition ---
interface SearchResultsAreaProps {
  searchTopic: string;
  onPrintSuccessForChaining: () => void;
  onCreateNewItem: (params: { name?: string; sku?: string; barcode?: string }) => void;
  isAwaitingPostSaveSearch: boolean;
  onSearchComplete: () => void;
}

const SearchResultsArea = memo(({ 
  searchTopic, 
  onPrintSuccessForChaining, 
  onCreateNewItem,
  isAwaitingPostSaveSearch,
  onSearchComplete
}: SearchResultsAreaProps) => {
  const router = useRouter(); 
  const swipeableRefs = useRef<Record<string, Swipeable | null>>({});
  
  // Get authenticated user information
  const { user } = useAuthenticator((context) => [context.user]);

  // Audio/Haptic feedback for reorder actions
  const playSuccessSound = useCallback(() => {
    console.log('🔊 SUCCESS - Item added to reorder!');
    logger.info('SearchResultsArea', 'Playing success feedback for reorder');
    // Single short vibration for success
    Vibration.vibrate(100);
  }, []);

  const { lastUpdatedItem, setLastUpdatedItem } = useAppStore();

  const [showPrintNotification, setShowPrintNotification] = useState(false);
  const [printNotificationMessage, setPrintNotificationMessage] = useState('');
  const [printNotificationType, setPrintNotificationType] = useState<'success' | 'error'>('success');

  // Reorder notification state
  const [showReorderNotification, setShowReorderNotification] = useState(false);
  const [reorderNotificationMessage, setReorderNotificationMessage] = useState('');
  const [reorderNotificationType, setReorderNotificationType] = useState<'success' | 'error'>('success');
  const [reorderNotificationItemId, setReorderNotificationItemId] = useState<string | null>(null);

  const [searchResults, setSearchResults] = useState<SearchResultItem[]>([]);
  const [isSearchPending, setIsSearchPending] = useState(false);
  const [searchFilters, setSearchFilters] = useState<SearchFilters>({
    name: true, 
    sku: true,
    barcode: true,
    category: false 
  });
  const [sortOrder, setSortOrder] = useState<'default' | 'az' | 'za' | 'price_asc' | 'price_desc'>('default');
  const [selectedResultCategoryId, setSelectedResultCategoryId] = useState<string | null>(null);
  const [availableResultCategories, setAvailableResultCategories] = useState<Array<{ id: string; name: string }>>([]);

  const { performSearch, isSearching: catalogIsSearching, searchError: catalogSearchError } = useCatalogItems();
  
  // Get categories from store for manual category lookup if needed
  const categories = useAppStore((state) => state.categories);
  
  // Helper function to fetch team data for an item (now uses reorder service for caching)
  const fetchTeamData = useCallback(async (itemId: string): Promise<TeamData | undefined> => {
    return await reorderService.fetchTeamData(itemId);
  }, []);

  // Helper function to ensure proper category conversion
  const ensureCategoryName = useCallback(async (item: SearchResultItem): Promise<string | undefined> => {
    // First try the already converted category from search results
    if (item.category) {
      return item.category;
    }
    
    // If no category name, try to look it up using categoryId or reporting_category_id from database
    const categoryId = item.categoryId || item.reporting_category_id;
    if (categoryId) {
      try {
        const categoriesFromDb = await modernDb.getAllCategories();
        const foundCategory = categoriesFromDb.find(cat => cat.id === categoryId);
        return foundCategory?.name;
      } catch (error) {
        logger.error('SearchResultsArea:ensureCategoryName', 'Error fetching categories from DB', { error, categoryId });
      }
    }
    
    return undefined;
  }, []);
  
  const itemModalJustClosed = useAppStore((state) => state.itemModalJustClosed);
  
  // Extracted search logic into a useCallback
  const executeSearch = useCallback(async () => {
    if (searchTopic.trim() === '') {
      setSearchResults([]);
      setIsSearchPending(false); // Clear pending state for empty search
      return;
    }
    
    // Set pending state immediately and clear old results to prevent flash
    setIsSearchPending(true);
    setSearchResults([]); // Clear old results immediately
    
    logger.info('SearchResultsArea', 'Executing search for topic:', { topic: searchTopic });
    const rawResults = await performSearch(searchTopic, searchFilters);
    
    let processedResults = [...rawResults];

    if (selectedResultCategoryId) {
      processedResults = processedResults.filter(item => item.categoryId === selectedResultCategoryId);
    }

    switch (sortOrder) {
      case 'az':
        processedResults.sort((a, b) => (a.name ?? '').localeCompare(b.name ?? ''));
        break;
      case 'za':
        processedResults.sort((a, b) => (b.name ?? '').localeCompare(a.name ?? ''));
        break;
      case 'price_asc':
        processedResults.sort((a, b) => (a.price ?? Infinity) - (b.price ?? Infinity));
        break;
      case 'price_desc':
        processedResults.sort((a, b) => (b.price ?? -Infinity) - (a.price ?? -Infinity));
        break;
    }
    setSearchResults(processedResults);
    setIsSearchPending(false); // Clear pending state when search completes
    onSearchComplete(); // Notify parent that search is done
    // logger.info('SearchResultsArea', 'Search executed, results set.', { count: processedResults.length });
  }, [searchTopic, searchFilters, performSearch, sortOrder, selectedResultCategoryId, setSearchResults, onSearchComplete]);

  // useEffect to run search when query/filters/sort change
  useEffect(() => {
    executeSearch();
  }, [executeSearch]); // Depends on the memoized executeSearch

  // Effect to update/refresh search results if a relevant item was globally updated or created
  useEffect(() => {
    if (lastUpdatedItem) {
      logger.info('SearchResultsArea', 'lastUpdatedItem detected, queueing re-search.', { itemId: lastUpdatedItem.id });
      // Add a small delay to give the database time to process the update
      // before we re-query. This helps prevent race conditions on save.
      const refreshTimer = setTimeout(() => {
        logger.info('SearchResultsArea', 'Executing delayed search refresh.');
        executeSearch(); 
        setLastUpdatedItem(null); 
      }, 300); // 300ms delay

      return () => clearTimeout(refreshTimer);
    }
  }, [lastUpdatedItem, setLastUpdatedItem, executeSearch]);

  useEffect(() => {
    const fetchCategoriesForFilter = async () => {
      try {
        const categoriesFromDb = await modernDb.getAllCategories();
        const formattedCategories = categoriesFromDb
          .map(cat => ({ id: cat.id, name: cat.name }))
          .sort((a, b) => a.name.localeCompare(b.name));
        setAvailableResultCategories(formattedCategories);
      } catch (err) {
        logger.error('SearchResultsArea: Failed to fetch categories for filter', String(err));
        setAvailableResultCategories([]); // Set to empty on error
      }
    };
    fetchCategoriesForFilter();
  }, []);

  const toggleFilter = useCallback((toggledFilter: keyof Omit<SearchFilters, 'category'>) => {
    setSearchFilters(currentFilters => {
      const relevantFilters = { name: currentFilters.name, sku: currentFilters.sku, barcode: currentFilters.barcode };
      let countActive = 0;
      let isToggledFilterActive = false;
      for (const key in relevantFilters) {
        if (relevantFilters[key as keyof typeof relevantFilters]) {
          countActive++;
          if (key === toggledFilter) {
            isToggledFilterActive = true;
          }
        }
      }
      const isCurrentlyTheOnlyActiveFilter = isToggledFilterActive && countActive === 1;
      if (isCurrentlyTheOnlyActiveFilter) {
        return { ...currentFilters, name: true, sku: true, barcode: true };
      } else {
        const newFiltersState: SearchFilters = { ...currentFilters, name: false, sku: false, barcode: false };
        newFiltersState[toggledFilter] = true;
        return newFiltersState;
      }
    });
  }, [setSearchFilters]);

  const handleSelectResultCategory = useCallback((categoryId: string | null) => {
      setSelectedResultCategoryId(categoryId);
  }, [setSelectedResultCategoryId]);

  const handleResultItemPress = useCallback((item: SearchResultItem) => {
    // logger.info('SearchResultsArea', 'Search result selected', { itemId: item.id, name: item.name });
    router.push(`/item/${item.id}`);
  }, [router]);

  const handleSwipePrint = useCallback(async (item: SearchResultItem) => {
    logger.info('SearchResultsArea:handleSwipePrint', 'Print triggered for item', { itemId: item.id, name: item.name });
    const labelData: LabelData = {
      itemId: item.id,
      itemName: item.name || 'Item Name',
      price: item.price,
      sku: item.sku,
      barcode: item.barcode,
    };

    let printWasSuccessful = false;
    try {
      const success = await printItemLabel(labelData);
      if (success) {
        setPrintNotificationMessage(`Label for "${item.name || 'Item'}" sent to printer.`);
        setPrintNotificationType('success');
        printWasSuccessful = true;
      } else {
        setPrintNotificationMessage('Could not send label to printer. Check connection.');
        setPrintNotificationType('error');
      }
    } catch (error) {
      logger.error('SearchResultsArea:handleSwipePrint', 'Error printing label', { error });
      setPrintNotificationMessage('An unexpected error occurred during printing.');
      setPrintNotificationType('error');
    } finally {
      setShowPrintNotification(true); 
      setTimeout(() => setShowPrintNotification(false), 3000);
      swipeableRefs.current[item.id]?.close(); // Close swipeable row
      if (printWasSuccessful) {
        onPrintSuccessForChaining(); // Call the callback on successful print
      }
    }
  }, [printItemLabel, swipeableRefs, setPrintNotificationMessage, setPrintNotificationType, setShowPrintNotification, onPrintSuccessForChaining]);

  const handleSwipeReorder = useCallback(async (item: SearchResultItem) => {
    // IMMEDIATE FEEDBACK - No delays, no awaits, just instant response
    setReorderNotificationMessage(`"${item.name || 'Item'}" added to reorder list.`);
    setReorderNotificationType('success');
    setReorderNotificationItemId(item.id);
    setShowReorderNotification(true);
    playSuccessSound();
    swipeableRefs.current[item.id]?.close();
    
    logger.info('SearchResultsArea:handleSwipeReorder', 'Reorder triggered for item', { itemId: item.id, name: item.name });
    
    // Now do all the async work in the background
    // Ensure we have the proper category name
    const categoryName = await ensureCategoryName(item);
    
    // Debug logging for category data
    logger.info('SearchResultsArea:handleSwipeReorder', 'Category data debug', {
      itemId: item.id,
      originalCategory: item.category,
      categoryId: item.categoryId,
      reportingCategoryId: item.reporting_category_id,
      ensuredCategoryName: categoryName,
      categoriesCount: categories?.length || 0
    });
    
    // Convert SearchResultItem to ConvertedItem for reorder service
    const convertedItem: ConvertedItem = {
      id: item.id,
      name: item.name || '',
      sku: item.sku,
      barcode: item.barcode,
      price: item.price,
      category: categoryName, // Use the ensured category name
      categoryId: item.categoryId, // Keep the category ID
      reporting_category_id: item.categoryId || item.reporting_category_id, // Include reporting_category_id
      description: item.description,
      isActive: true,
      images: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    try {
      // Fetch team data for the item
      const teamData = await fetchTeamData(item.id);
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      const success = await reorderService.addItem(convertedItem, 1, teamData, userName);
      if (!success) {
        // Only update notification if there was an error
        setReorderNotificationMessage('Failed to add item to reorder list.');
        setReorderNotificationType('error');
      }
    } catch (error) {
      logger.error('SearchResultsArea:handleSwipeReorder', 'Error adding item to reorder list', { error });
      setReorderNotificationMessage('An unexpected error occurred while adding to reorder list.');
      setReorderNotificationType('error');
    }
    
    // Hide notification after delay
      setTimeout(() => {
        setShowReorderNotification(false);
        setReorderNotificationItemId(null);
      }, 3000);
  }, [reorderService, swipeableRefs, setReorderNotificationMessage, setReorderNotificationType, setShowReorderNotification, setReorderNotificationItemId, ensureCategoryName, fetchTeamData, user, playSuccessSound]);

  const handleFullSwipeReorder = useCallback(async (item: SearchResultItem) => {
    // IMMEDIATE FEEDBACK - No delays, no awaits, just instant response
    setReorderNotificationMessage(`"${item.name || 'Item'}" added to reorder list.`);
    setReorderNotificationType('success');
    setReorderNotificationItemId(item.id);
    setShowReorderNotification(true);
    playSuccessSound();
    
    logger.info('SearchResultsArea:handleFullSwipeReorder', 'Full swipe reorder triggered for item', { itemId: item.id, name: item.name });
    
    // Now do all the async work in the background
    // Ensure we have the proper category name
    const categoryName = await ensureCategoryName(item);
    
    // Convert SearchResultItem to ConvertedItem for reorder service
    const convertedItem: ConvertedItem = {
      id: item.id,
      name: item.name || '',
      sku: item.sku,
      barcode: item.barcode,
      price: item.price,
      category: categoryName, // Use the ensured category name
      categoryId: item.categoryId, // Keep the category ID
      reporting_category_id: item.categoryId || item.reporting_category_id, // Include reporting_category_id
      description: item.description,
      isActive: true,
      images: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    try {
      // Fetch team data for the item
      const teamData = await fetchTeamData(item.id);
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      const success = await reorderService.addItem(convertedItem, 1, teamData, userName);
      if (!success) {
        // Only update notification if there was an error
        setReorderNotificationMessage('Failed to add item to reorder list.');
        setReorderNotificationType('error');
      }
    } catch (error) {
      logger.error('SearchResultsArea:handleFullSwipeReorder', 'Error adding item to reorder list', { error });
      setReorderNotificationMessage('An unexpected error occurred while adding to reorder list.');
      setReorderNotificationType('error');
    }
    
    // Hide notification after delay
      setTimeout(() => {
        setShowReorderNotification(false);
        setReorderNotificationItemId(null);
      }, 2000); // Shorter timeout for full swipe
  }, [reorderService, setReorderNotificationMessage, setReorderNotificationType, setShowReorderNotification, setReorderNotificationItemId, ensureCategoryName, fetchTeamData, user, playSuccessSound]);

  const renderLeftActions = useCallback((progress: Animated.AnimatedInterpolation<number>, dragX: Animated.AnimatedInterpolation<number>, item: SearchResultItem) => {
    const SWIPE_BUTTON_WIDTH = 100; 
    // const LIST_HORIZONTAL_PADDING = 16; // No longer needed here

    const trans = progress.interpolate({
      inputRange: [0, 1],
      outputRange: [-SWIPE_BUTTON_WIDTH, 0], 
      extrapolate: 'clamp',
    });

    return (
      <Pressable 
        onPress={() => { 
          handleSwipePrint(item);
        }}
        // Apply width directly, margin hacks removed.
        style={[styles.swipePrintActionLeft, { width: SWIPE_BUTTON_WIDTH }]} 
      >
        <Animated.View style={[
          styles.swipePrintButtonContainer, 
          { width: SWIPE_BUTTON_WIDTH, transform: [{ translateX: trans }] }
        ]}>
            <Ionicons name="print-outline" size={24} color="#fff" style={{ marginRight: 8 }} />
            <Text style={styles.swipePrintActionText}>Print</Text>
        </Animated.View>
      </Pressable>
    );
  }, [handleSwipePrint, styles]);

  const renderRightActions = useCallback((progress: Animated.AnimatedInterpolation<number>, dragX: Animated.AnimatedInterpolation<number>, item: SearchResultItem) => {
    const SWIPE_BUTTON_WIDTH = 100; // Reduced width since no icon

    const trans = progress.interpolate({
      inputRange: [0, 1],
      outputRange: [SWIPE_BUTTON_WIDTH, 0],
      extrapolate: 'clamp',
    });

    return (
      <Pressable 
        onPress={() => { 
          handleSwipeReorder(item);
        }}
        style={[styles.swipeReorderActionRight, { width: SWIPE_BUTTON_WIDTH }]} 
      >
        <Animated.View style={[
          styles.swipeReorderButtonContainer, 
          { width: SWIPE_BUTTON_WIDTH, transform: [{ translateX: trans }] }
        ]}>
            <Text style={styles.swipeReorderActionText}>Reorder</Text>
        </Animated.View>
      </Pressable>
    );
  }, [handleSwipeReorder, styles]);

  const renderSearchResultItem = useCallback(({ item, index }: { item: SearchResultItem; index: number }) => {
    const formattedPrice = typeof item.price === 'number' 
      ? `$${item.price.toFixed(2)}` 
      : (item.price ? String(item.price) : 'N/A');
    return (
      <Swipeable
        ref={(ref) => { swipeableRefs.current[item.id] = ref; }}
        renderLeftActions={(progress, dragX) => renderLeftActions(progress, dragX, item)} 
        renderRightActions={(progress, dragX) => renderRightActions(progress, dragX, item)}
        onSwipeableWillOpen={() => {
          Object.values(swipeableRefs.current).forEach(ref => {
            if (ref && ref !== swipeableRefs.current[item.id]) {
              ref.close();
            }
          });
        }}
        onSwipeableRightOpen={() => {
          // Full swipe to the left (revealing right actions) - auto add to reorder
          handleFullSwipeReorder(item);
          // Close the swipeable immediately for instant feedback
            swipeableRefs.current[item.id]?.close();
        }}
        friction={1}
        leftThreshold={40} 
        rightThreshold={40}
        overshootFriction={8} 
        enableTrackpadTwoFingerGesture
      >
        <Pressable style={styles.resultItem} onPress={() => handleResultItemPress(item)}>
          <View style={styles.resultNumberContainer}>
            <Text style={styles.resultNumberText}>{index + 1}</Text>
          </View>
          <View style={styles.resultDetails}>
            <Text style={styles.resultName} numberOfLines={1}>{item.name ?? 'N/A'}</Text>
            <View style={styles.resultMeta}>
              {item.sku && <Text style={styles.resultSku}>SKU: {item.sku}</Text>}
              {item.category && <Text style={styles.resultCategory}>{item.category}</Text>}
              {item.barcode && <Text style={styles.resultBarcode}>UPC: {item.barcode}</Text>}
            </View>
          </View>
          <View style={styles.resultPrice}>
            <Text style={styles.priceText}>{formattedPrice}</Text>
            <Ionicons name="chevron-forward" size={18} color="#ccc" />
          </View>
          {/* Inline reorder success notification */}
          {showReorderNotification && reorderNotificationItemId === item.id && reorderNotificationType === 'success' && (
            <View style={styles.inlineNotification}>
              <Ionicons name="checkmark-circle" size={16} color="#fff" />
              <Text style={styles.inlineNotificationText}>Added to reorder!</Text>
            </View>
          )}
        </Pressable>
      </Swipeable>
    );
  }, [handleResultItemPress, renderLeftActions, renderRightActions, styles, swipeableRefs, showReorderNotification, reorderNotificationItemId, reorderNotificationType, handleFullSwipeReorder]);

  const renderEmptyState = useCallback(() => {
    if (catalogSearchError) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="alert-circle-outline" size={48} color="#FF3B30" />
          <Text style={styles.emptyTitle}>Search Error</Text>
          <Text style={styles.emptyText}>{catalogSearchError}</Text>
        </View>
      );
    }
    // While searching OR awaiting post-save search OR search is pending, show a spinner.
    if (catalogIsSearching || isAwaitingPostSaveSearch || isSearchPending) {
      return (
        <View style={styles.emptyContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.searchingText}>Searching...</Text>
        </View>
      );
    }
    if (searchTopic.trim() === '') {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="search-outline" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>Scan or Search Your Catalog</Text>
          <Text style={styles.emptyText}>Use the input below to search by name, SKU, barcode, or category.</Text>
        </View>
      );
    }
    if (searchResults.length === 0 && searchTopic.trim() !== '') {
      const query = searchTopic.trim();
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="file-tray-outline" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>No Results Found</Text>
          <Text style={styles.emptyText}>No items found matching "{query}".</Text>
          <View style={styles.createItemButtonsContainer}>
            <Pressable 
              style={styles.createItemButton} 
              onPress={() => onCreateNewItem({ name: query })}
            >
              <Text style={styles.createItemButtonText}>Create new item with name "{query}"</Text>
            </Pressable>
            <Pressable 
              style={styles.createItemButton} 
              onPress={() => onCreateNewItem({ sku: query })}
            >
              <Text style={styles.createItemButtonText}>Create new item with SKU "{query}"</Text>
            </Pressable>
            <Pressable 
              style={styles.createItemButton} 
              onPress={() => onCreateNewItem({ barcode: query })}
            >
              <Text style={styles.createItemButtonText}>Create new item with UPC "{query}"</Text>
            </Pressable>
          </View>
        </View>
      );
    }
    return null;
  }, [catalogSearchError, catalogIsSearching, searchTopic, searchResults, styles, lightTheme, onCreateNewItem, isAwaitingPostSaveSearch, isSearchPending]);

  const renderFilterBadges = useCallback(() => {
    const activeFilters = Object.entries(searchFilters).filter(([key, isEnabled]) => key !== 'category' && isEnabled).map(([key]) => key as keyof SearchFilters);
    if (activeFilters.length === 3 || activeFilters.length === 0) return null;
    if (searchTopic.trim().length === 0) return null; 
    return (
      <View style={styles.filterBadgesContainer}>
        {activeFilters.map((filterKey) => (
          <View key={filterKey} style={styles.filterBadge}><Text style={styles.filterBadgeText}>{filterKey.charAt(0).toUpperCase() + filterKey.slice(1)}</Text></View>
        ))}
        {selectedResultCategoryId && availableResultCategories.find(c => c.id === selectedResultCategoryId) && (
            <View style={styles.filterBadge}><Text style={styles.filterBadgeText}>Category: {availableResultCategories.find(c => c.id === selectedResultCategoryId)?.name}</Text></View>
        )}
      </View>
    );
  }, [searchFilters, searchTopic, styles, selectedResultCategoryId, availableResultCategories]);

  return (
    <View style={styles.mainContent}> 
      <FlatList
        data={searchResults}
        renderItem={renderSearchResultItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.resultsContainer}
        ListEmptyComponent={renderEmptyState}
        ListHeaderComponent={renderFilterBadges}
        keyboardShouldPersistTaps="handled"
        style={{ flex: 1 }}
      />
      {searchTopic.trim().length > 0 && (
        <FilterAndSortControls 
          searchFilters={searchFilters} 
          onToggleFilter={toggleFilter} 
          sortOrder={sortOrder} 
          onSetSortOrder={setSortOrder} 
          availableResultCategories={availableResultCategories}
          selectedResultCategoryId={selectedResultCategoryId}
          onSelectResultCategory={handleSelectResultCategory}
        />
      )}
      <SystemModal
        visible={showPrintNotification}
        onClose={() => setShowPrintNotification(false)}
        message={printNotificationMessage}
        type={printNotificationType}
        position="top"
        autoClose={true}
        autoCloseTime={2500} // Slightly shorter time for quick feedback
      />

    </View>
  );
});
// --- END: SearchResultsArea Component Definition ---

// --- START: FilterAndSortControls Component Definition ---
interface FilterAndSortControlsProps {
  searchFilters: SearchFilters;
  onToggleFilter: (filter: keyof Omit<SearchFilters, 'category'>) => void;
  sortOrder: 'default' | 'az' | 'za' | 'price_asc' | 'price_desc';
  onSetSortOrder: (order: 'default' | 'az' | 'za' | 'price_asc' | 'price_desc') => void;
  availableResultCategories: Array<{ id: string; name: string }>;
  selectedResultCategoryId: string | null;
  onSelectResultCategory: (categoryId: string | null) => void;
}
const FilterAndSortControls = memo(({
  searchFilters, 
  onToggleFilter, 
  sortOrder, 
  onSetSortOrder,
  availableResultCategories,
  selectedResultCategoryId,
  onSelectResultCategory
}: FilterAndSortControlsProps) => {
  const sortLabels: Record<typeof sortOrder, string> = {
    default: 'Default',
    az: 'A-Z',
    za: 'Z-A',
    price_asc: 'Price Low-High',
    price_desc: 'Price High-Low',
  };

  const handleSortCycle = () => {
    const orders: Array<typeof sortOrder> = ['default', 'az', 'za', 'price_asc', 'price_desc'];
    const currentIndex = orders.indexOf(sortOrder);
    const nextIndex = (currentIndex + 1) % orders.length;
    onSetSortOrder(orders[nextIndex]);
  };

  const [isCategoryModalVisible, setCategoryModalVisible] = useState(false);
  const [modalCategorySearchTerm, setModalCategorySearchTerm] = useState('');

  const filteredModalCategories = availableResultCategories.filter(cat => 
    cat.name.toLowerCase().includes(modalCategorySearchTerm.toLowerCase())
  );

  const selectedCategoryName = selectedResultCategoryId 
    ? availableResultCategories.find(c => c.id === selectedResultCategoryId)?.name 
    : 'Category';

  return (
    <View style={styles.controlsContainer}> 
      <View style={styles.filterAndSortInnerContainer}> 
        <View style={styles.filterContainer}>
          <Pressable style={[styles.filterButton, searchFilters.name && styles.filterButtonActive]} onPress={() => onToggleFilter('name')}><Text style={[styles.filterButtonText, searchFilters.name && styles.filterButtonTextActive]}>Name</Text></Pressable>
          <Pressable style={[styles.filterButton, searchFilters.sku && styles.filterButtonActive]} onPress={() => onToggleFilter('sku')}><Text style={[styles.filterButtonText, searchFilters.sku && styles.filterButtonTextActive]}>SKU</Text></Pressable>
          <Pressable style={[styles.filterButton, searchFilters.barcode && styles.filterButtonActive]} onPress={() => onToggleFilter('barcode')}><Text style={[styles.filterButtonText, searchFilters.barcode && styles.filterButtonTextActive]}>UPC</Text></Pressable>
          <Pressable 
            style={[styles.filterButton, selectedResultCategoryId && styles.filterButtonActive, { flexDirection: 'row', alignItems: 'center' }]} 
            onPress={() => setCategoryModalVisible(true)}
          >
            <Ionicons name="filter-outline" size={14} color={selectedResultCategoryId ? '#FFFFFF' : lightTheme.colors.text} style={{ marginRight: 3 }} />
            <Text style={[styles.filterButtonText, selectedResultCategoryId && styles.filterButtonTextActive]}>
              {selectedCategoryName}
            </Text>
          </Pressable>
        </View>
        
        <Pressable style={styles.sortCycleButton} onPress={handleSortCycle}>
          <Ionicons name="swap-vertical-outline" size={16} color={lightTheme.colors.text} style={{ marginRight: 5 }} />
          <Text style={styles.sortCycleButtonText}>Sort: {sortLabels[sortOrder]}</Text>
        </Pressable>
      </View>
      <Modal
        animationType="slide"
        transparent={true}
        visible={isCategoryModalVisible}
        onRequestClose={() => {
          setCategoryModalVisible(false);
          setModalCategorySearchTerm('');
        }}
      >
        <View style={styles.categoryModalContainer}>
          <KeyboardAvoidingView 
            behavior={Platform.OS === "ios" ? "padding" : "height"} 
            style={{ flexShrink: 1 }} 
            keyboardVerticalOffset={Platform.OS === "ios" ? 20 : 0} 
          >
            <View style={styles.categoryModalContent}>
              <Text style={styles.categoryModalTitle}>Filter by Category</Text>
              <FlatList
                data={[{ id: null, name: `All Categories` }, ...filteredModalCategories]}
                keyExtractor={(item) => item.id ?? 'all'}
                renderItem={({ item }) => (
                  <Pressable 
                      style={styles.categoryModalItem}
                      onPress={() => {
                          onSelectResultCategory(item.id); 
                          setCategoryModalVisible(false);
                          setModalCategorySearchTerm('');
                      }}
                  >
                    <Text 
                      style={[
                          styles.categoryModalItemText,
                          (item.id === selectedResultCategoryId) && styles.categoryModalItemTextSelected 
                      ]}
                    >
                      {item.name}
                    </Text>
                  </Pressable>
                )}
                ListEmptyComponent={() => (
                  <View style={styles.categoryModalEmpty}>
                    <Text style={styles.categoryModalEmptyText}>No categories match "{modalCategorySearchTerm}"</Text>
                  </View>
                )}
              />
              <TextInput
                style={styles.categoryModalSearchInput}
                placeholder="Search categories..."
                placeholderTextColor="#999"
                value={modalCategorySearchTerm}
                onChangeText={setModalCategorySearchTerm}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <View style={styles.categoryModalFooter}>
                  <Pressable 
                      style={[styles.categoryModalButton, styles.categoryModalClearButton]} 
                      onPress={() => {
                          onSelectResultCategory(null); 
                          setCategoryModalVisible(false);
                          setModalCategorySearchTerm('');
                      }}
                  >
                      <Text style={[styles.categoryModalButtonText, styles.categoryModalClearButtonText]}>Clear Selection</Text>
                  </Pressable>
                  <Pressable 
                      style={[styles.categoryModalButton, styles.categoryModalCloseButton]} 
                      onPress={() => {
                          setCategoryModalVisible(false);
                          setModalCategorySearchTerm('');
                      }}
                  >
                      <Text style={styles.categoryModalButtonText}>Close</Text>
                  </Pressable>
              </View>
            </View>
          </KeyboardAvoidingView>
        </View>
      </Modal>
    </View>
  );
});
// --- END: FilterAndSortControls Component Definition ---

export default function App() {
  return (
    <DatabaseProvider>
      <RootLayoutNav />
    </DatabaseProvider>
  );
}

function RootLayoutNav() {
  const router = useRouter();
  const { isConnected } = useApi();
  const searchInputRef = useRef<TextInput>(null);

  // State for the *finalized* search term that triggers the actual search.
  const [searchTopic, setSearchTopic] = useState('');
  const [isAwaitingPostSaveSearch, setIsAwaitingPostSaveSearch] = useState(false);
  
  // Track reorder count for badge
  const [reorderCount, setReorderCount] = useState(0);
  
  // Listen to reorder service changes
  useEffect(() => {
    setReorderCount(reorderService.getCount());
    const unsubscribe = reorderService.addListener((items) => {
      setReorderCount(items.length);
    });
    return unsubscribe;
  }, []);

  const handleClearSearch = useCallback(() => {
    setSearchTopic('');
    // Focus the input after clearing
    setTimeout(() => {
      searchInputRef.current?.focus();
    }, 100);
  }, []);

  useFocusEffect(
    useCallback(() => {
      // Failsafe to ensure the loading state doesn't get stuck.
      if (isAwaitingPostSaveSearch) {
        const timer = setTimeout(() => {
          if (isAwaitingPostSaveSearch) {
              setIsAwaitingPostSaveSearch(false);
          }
        }, 2000);
        return () => clearTimeout(timer);
      }
    }, [isAwaitingPostSaveSearch])
  );


  const handleSearchSubmit = useCallback((query: string) => {
    // logger.info('RootLayoutNav', 'Search submitted', { query });
    setSearchTopic(query);
    // NOTE: No longer triggering select all here to avoid aggressive highlighting.
  }, []);

  const handleCreateNewItem = useCallback((params: { name?: string; sku?: string; barcode?: string }) => {
    logger.info('RootLayoutNav', 'Navigating to create new item', params);
    setIsAwaitingPostSaveSearch(true);
    router.push({ pathname: '/item/new', params });
  }, [router]);

  const handlePrintAndClear = useCallback(() => {
    setSearchTopic('');
    // After printing, just focus the input. Selection is handled by the focus effect.
    setTimeout(() => {
      searchInputRef.current?.focus();
    }, 100); 
  }, []);
  
  const scanHistory = useAppStore((state) => state.scanHistory);
  const addScanHistoryItem = useAppStore((state) => state.addScanHistoryItem);
  
  const navigateToHistory = useCallback(() => {
    router.push('/(tabs)/scanHistory');
  }, [router]);
  
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
      
      {/* Header with JOYLABS Logo and Status/Notification */}
      <View style={styles.headerContainer}>
        <Text style={styles.logoText}>JOYLABS</Text>
        <View style={styles.headerRightContainer}>
          <ConnectionStatusBar 
            connected={isConnected} 
            compact={true}
          />
          <NotificationBell />
        </View>
      </View>

      <ScanHistoryButtonComponent count={scanHistory.length} onNavigate={navigateToHistory} />

      <SearchResultsArea 
        searchTopic={searchTopic} 
        onPrintSuccessForChaining={handlePrintAndClear}
        onCreateNewItem={handleCreateNewItem}
        isAwaitingPostSaveSearch={isAwaitingPostSaveSearch}
        onSearchComplete={() => setIsAwaitingPostSaveSearch(false)}
      />

      <BottomSearchBarComponent 
        ref={searchInputRef} 
        searchTopic={searchTopic}
        onSearchSubmit={handleSearchSubmit} 
        onClearSearch={handleClearSearch}
      />
    </SafeAreaView>
  );
}

// Define Memoized Components
interface FilterButtonsProps {
  searchFilters: SearchFilters;
  onToggleFilter: (filter: keyof SearchFilters) => void;
}
const FilterButtonsComponent = memo(({ searchFilters, onToggleFilter }: FilterButtonsProps) => {
  return (
    <View style={styles.filterContainer}>
      <Pressable style={[styles.filterButton, searchFilters.name && styles.filterButtonActive]} onPress={() => onToggleFilter('name')}><Text style={[styles.filterButtonText, searchFilters.name && styles.filterButtonTextActive]}>Name</Text></Pressable>
      <Pressable style={[styles.filterButton, searchFilters.sku && styles.filterButtonActive]} onPress={() => onToggleFilter('sku')}><Text style={[styles.filterButtonText, searchFilters.sku && styles.filterButtonTextActive]}>SKU</Text></Pressable>
      <Pressable style={[styles.filterButton, searchFilters.barcode && styles.filterButtonActive]} onPress={() => onToggleFilter('barcode')}><Text style={[styles.filterButtonText, searchFilters.barcode && styles.filterButtonTextActive]}>UPC</Text></Pressable>
      <Pressable style={[styles.filterButton, searchFilters.category && styles.filterButtonActive]} onPress={() => onToggleFilter('category')}><Text style={[styles.filterButtonText, searchFilters.category && styles.filterButtonTextActive]}>Category</Text></Pressable>
    </View>
  );
});

interface BottomSearchBarProps {
  searchTopic: string;
  onSearchSubmit: (query: string) => void;
  onClearSearch: () => void;
}
const BottomSearchBarComponent = memo(React.forwardRef<TextInput, BottomSearchBarProps>(({ 
  searchTopic,
  onSearchSubmit,
  onClearSearch,
}, ref) => {
  // This state is for UI responsiveness (e.g., showing/hiding clear buttons).
  const [inputValue, setInputValue] = useState(searchTopic);
  const inputRef = useRef<TextInput>(null);

  // Debounced function to trigger search after user stops typing.
  const debouncedSearch = useCallback(debounce((query: string) => {
    onSearchSubmit(query);
  }, 500), [onSearchSubmit]);

  // Sync from parent if searchTopic changes externally (e.g., from history).
  // Only update if the values are actually different to prevent unnecessary re-renders
  useEffect(() => {
    if (searchTopic !== inputValue) {
      setInputValue(searchTopic);
      // Update the actual TextInput value for uncontrolled component
      if (inputRef.current) {
        inputRef.current.setNativeProps({ text: searchTopic });
    }
    }
  }, [searchTopic]); // Remove inputValue from dependencies to prevent loops

  const handleChangeText = (text: string) => {
    setInputValue(text); // Update local state for UI purposes.
    debouncedSearch(text); // Trigger the actual debounced search.
  };

  const handleClear = () => {
    debouncedSearch.cancel();
    setInputValue('');
    // Clear the uncontrolled TextInput
    if (inputRef.current) {
      inputRef.current.setNativeProps({ text: '' });
    }
    onClearSearch(); // Notify parent to clear search results
  };

  // Combine refs - use both the forwarded ref and our internal ref
  const combinedRef = useCallback((instance: TextInput | null) => {
    inputRef.current = instance;
    if (typeof ref === 'function') {
      ref(instance);
    } else if (ref) {
      ref.current = instance;
    }
  }, [ref]);

  const KAV_OFFSET_IOS_internal = 62; // Should be 62 for iPhone. Increased for tab bar + safe area
  const KAV_OFFSET_ANDROID_internal = 20;

  return (
    <KeyboardAvoidingView 
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={Platform.OS === 'ios' ? KAV_OFFSET_IOS_internal : KAV_OFFSET_ANDROID_internal}
      style={styles.searchBarContainer} 
    >
      <Pressable 
        style={[styles.externalClearTextButton, inputValue.length === 0 && styles.externalClearTextButtonDisabled]}
        onPress={handleClear}
        disabled={inputValue.length === 0}
      >
        <Text style={[styles.externalClearButtonText, inputValue.length === 0 && styles.externalClearButtonTextDisabled]}>Clear</Text>
      </Pressable>
      <View style={styles.searchInputWrapper}>
        <Ionicons name="search" size={22} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={combinedRef}
          style={styles.searchInput}
          placeholder="Scan barcode or search items..."
          placeholderTextColor="#999"
          defaultValue={searchTopic} // Back to uncontrolled for HID scanner
          onChangeText={handleChangeText}
          autoFocus={true}
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          blurOnSubmit={false}
        />
        {inputValue.length > 0 && (
          <Pressable style={styles.clearButton} onPress={handleClear}>
            <Ionicons name="close-circle" size={20} color="#aaa" />
          </Pressable>
        )}
      </View>
    </KeyboardAvoidingView>
  );
}));

// Define Memoized ScanHistoryButtonComponent
interface ScanHistoryButtonProps {
  count: number;
  onNavigate: () => void;
}
const ScanHistoryButtonComponent = memo(({ count, onNavigate }: ScanHistoryButtonProps) => {
  return (
    <View style={styles.historyButtonContainer}>
      <Link href="/(tabs)/scanHistory" asChild>
        <Pressable style={styles.historyButton} onPress={onNavigate}>
          <Ionicons name="archive-outline" size={20} color={lightTheme.colors.primary} style={{marginRight: 8}} />
          <Text style={styles.historyButtonText}>View Scan History ({count})</Text>
        </Pressable>
      </Link>
    </View>
  );
});

// Note: The StyleSheet.create block is now expected to be in ./indexStyles.tsx
// Ensure styles.loadingOverlay and styles.loadingText are defined in indexStyles.tsx

// The old StyleSheet from index.tsx is removed, but its specific styles (like loadingOverlay)
// need to be present in indexStyles.tsx or merged.
// I will assume indexStyles.tsx (copied from searchStyles.tsx) will be the base,
// and any unique, necessary styles from the original index.tsx's StyleSheet (like loadingOverlay)
// should be added to indexStyles.tsx if not already covered.
// For now, I will add loadingOverlay to indexStyles.tsx as it's referenced. 