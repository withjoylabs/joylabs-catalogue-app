import React, { useState, useEffect, useRef, useCallback, memo } from 'react';
import {
  View, 
  FlatList, 
  // StyleSheet, // Will be replaced by indexStyles
  SafeAreaView, 
  StatusBar, 
  Text, 
  TouchableOpacity, 
  ActivityIndicator, 
  TextInput, 
  // Button, // No longer explicitly needed
  Platform, // For KeyboardAvoidingView if we re-add it, but SearchBar handles its input.
  KeyboardAvoidingView, // Keep for filter pills for now, may remove if SearchBar covers all
  ScrollView,
  Modal,
  Animated, // For swipe action
  Alert, // Added for print feedback
} from 'react-native';
import { useRouter, useFocusEffect, Link, useNavigation } from 'expo-router';
import { useIsFocused } from '@react-navigation/native';
import { Swipeable } from 'react-native-gesture-handler'; // Added for swipe actions
import ConnectionStatusBar from '../../src/components/ConnectionStatusBar';
import { ConvertedItem, SearchResultItem } from '../../src/types/api';
import { Ionicons } from '@expo/vector-icons';
import { useApi } from '../../src/providers/ApiProvider';
import { useAppStore } from '../../src/store';
import { apiClientInstance } from '../../src/api';
import logger from '../../src/utils/logger';
import { DatabaseProvider } from '../../src/components/DatabaseProvider';
import { transformCatalogItemToItem } from '../../src/utils/catalogTransformers';
import { v4 as uuidv4 } from 'uuid';
import { lightTheme } from '../../src/themes';
import * as modernDb from '../../src/database/modernDb';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { styles } from './_indexStyles'; // Updated import
import { SearchFilters } from '../../src/database/modernDb'; // For search filters type
import { printItemLabel, LabelData } from '../../src/utils/printLabel'; // Added for printing
import SystemModal from '../../src/components/SystemModal'; // Added for notifications

// Debounce utility (copied from search.tsx)
const debounce = <F extends (...args: any[]) => any>(func: F, waitFor: number) => {
  let timeout: NodeJS.Timeout | null = null;
  const debounced = (...args: Parameters<F>) => {
    if (timeout !== null) {
      clearTimeout(timeout);
      timeout = null;
    }
    timeout = setTimeout(() => func(...args), waitFor);
  };
  return debounced as (...args: Parameters<F>) => ReturnType<F>;
};

// --- START: SearchResultsArea Component Definition ---
interface SearchResultsAreaProps {
  initialSearchQuery: string;
  onPrintSuccessForChaining: () => void;
}

const SearchResultsArea = memo(({ initialSearchQuery, onPrintSuccessForChaining }: SearchResultsAreaProps) => {
  const router = useRouter(); 
  const swipeableRefs = useRef<Record<string, Swipeable | null>>({});

  const { lastUpdatedItem, setLastUpdatedItem } = useAppStore();

  const [showPrintNotification, setShowPrintNotification] = useState(false);
  const [printNotificationMessage, setPrintNotificationMessage] = useState('');
  const [printNotificationType, setPrintNotificationType] = useState<'success' | 'error'>('success');

  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState<string>('');
  const [searchResults, setSearchResults] = useState<SearchResultItem[]>([]);
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
  const debouncedSetQuery = useCallback(debounce(setDebouncedSearchQuery, 500), []);

  useEffect(() => {
    debouncedSetQuery(initialSearchQuery);
  }, [initialSearchQuery, debouncedSetQuery]);

  // Extracted search logic into a useCallback
  const executeSearch = useCallback(async () => {
    if (debouncedSearchQuery.trim() === '') {
      setSearchResults([]);
      return;
    }
    
    logger.info('SearchResultsArea', 'Executing search for query:', { query: debouncedSearchQuery });
    const rawResults = await performSearch(debouncedSearchQuery, searchFilters);
    
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
    logger.info('SearchResultsArea', 'Search executed, results set.', { count: processedResults.length });
  }, [debouncedSearchQuery, searchFilters, performSearch, sortOrder, selectedResultCategoryId, setSearchResults]);

  // useEffect to run search when query/filters/sort change
  useEffect(() => {
    executeSearch();
  }, [executeSearch]); // Depends on the memoized executeSearch

  // Effect to update/refresh search results if a relevant item was globally updated or created
  useEffect(() => {
    if (lastUpdatedItem) {
      logger.info('SearchResultsArea', 'lastUpdatedItem detected, re-executing search.', { itemId: lastUpdatedItem.id });
      executeSearch(); 
      setLastUpdatedItem(null); 
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
    logger.info('SearchResultsArea', 'Search result selected', { itemId: item.id, name: item.name });
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

  const renderLeftActions = useCallback((progress: Animated.AnimatedInterpolation<number>, dragX: Animated.AnimatedInterpolation<number>, item: SearchResultItem) => {
    const SWIPE_BUTTON_WIDTH = 100; 
    // const LIST_HORIZONTAL_PADDING = 16; // No longer needed here

    const trans = progress.interpolate({
      inputRange: [0, 1],
      outputRange: [-SWIPE_BUTTON_WIDTH, 0], 
      extrapolate: 'clamp',
    });

    return (
      <TouchableOpacity 
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
      </TouchableOpacity>
    );
  }, [handleSwipePrint, styles]);

  const renderSearchResultItem = useCallback(({ item, index }: { item: SearchResultItem; index: number }) => {
    const formattedPrice = typeof item.price === 'number' 
      ? `$${item.price.toFixed(2)}` 
      : (item.price ? String(item.price) : 'N/A');
    return (
      <Swipeable
        ref={(ref) => { swipeableRefs.current[item.id] = ref; }}
        renderLeftActions={(progress, dragX) => renderLeftActions(progress, dragX, item)} 
        onSwipeableWillOpen={() => {
          Object.values(swipeableRefs.current).forEach(ref => {
            if (ref && ref !== swipeableRefs.current[item.id]) {
              ref.close();
            }
          });
        }}
        friction={2}
        leftThreshold={50} 
        overshootFriction={8} 
        enableTrackpadTwoFingerGesture
      >
        <TouchableOpacity style={styles.resultItem} onPress={() => handleResultItemPress(item)} activeOpacity={1}>
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
        </TouchableOpacity>
      </Swipeable>
    );
  }, [handleResultItemPress, renderLeftActions, styles, swipeableRefs]);

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
    if (catalogIsSearching && debouncedSearchQuery.trim() !== '') {
      return (
        <View style={styles.emptyContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.searchingText}>Searching...</Text>
        </View>
      );
    }
    if (debouncedSearchQuery.trim() === '' && initialSearchQuery.trim() === '') {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="search-outline" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>Scan or Search Your Catalog</Text>
          <Text style={styles.emptyText}>Use the input below to search by name, SKU, barcode, or category.</Text>
        </View>
      );
    }
    if (searchResults.length === 0 && debouncedSearchQuery.trim() !== '') {
      const query = debouncedSearchQuery.trim();
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="file-tray-outline" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>No Results Found</Text>
          <Text style={styles.emptyText}>No items found matching "{query}".</Text>
          <View style={styles.createItemButtonsContainer}>
            <TouchableOpacity 
              style={styles.createItemButton} 
              onPress={() => router.push({ pathname: '/item/new', params: { name: query }})}
            >
              <Text style={styles.createItemButtonText}>Create new item with name "{query}"</Text>
            </TouchableOpacity>
            <TouchableOpacity 
              style={styles.createItemButton} 
              onPress={() => router.push({ pathname: '/item/new', params: { sku: query }})}
            >
              <Text style={styles.createItemButtonText}>Create new item with SKU "{query}"</Text>
            </TouchableOpacity>
            <TouchableOpacity 
              style={styles.createItemButton} 
              onPress={() => router.push({ pathname: '/item/new', params: { barcode: query }})}
            >
              <Text style={styles.createItemButtonText}>Create new item with UPC "{query}"</Text>
            </TouchableOpacity>
          </View>
        </View>
      );
    }
    return null;
  }, [catalogSearchError, catalogIsSearching, debouncedSearchQuery, initialSearchQuery, searchResults, styles, lightTheme, router]);

  const renderFilterBadges = useCallback(() => {
    const activeFilters = Object.entries(searchFilters).filter(([key, isEnabled]) => key !== 'category' && isEnabled).map(([key]) => key as keyof SearchFilters);
    if (activeFilters.length === 3 || activeFilters.length === 0) return null;
    if (initialSearchQuery.trim().length === 0) return null; 
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
  }, [searchFilters, initialSearchQuery, styles, selectedResultCategoryId, availableResultCategories]);

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
      {initialSearchQuery.trim().length > 0 && (
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
          <TouchableOpacity style={[styles.filterButton, searchFilters.name && styles.filterButtonActive]} onPress={() => onToggleFilter('name')}><Text style={[styles.filterButtonText, searchFilters.name && styles.filterButtonTextActive]}>Name</Text></TouchableOpacity>
          <TouchableOpacity style={[styles.filterButton, searchFilters.sku && styles.filterButtonActive]} onPress={() => onToggleFilter('sku')}><Text style={[styles.filterButtonText, searchFilters.sku && styles.filterButtonTextActive]}>SKU</Text></TouchableOpacity>
          <TouchableOpacity style={[styles.filterButton, searchFilters.barcode && styles.filterButtonActive]} onPress={() => onToggleFilter('barcode')}><Text style={[styles.filterButtonText, searchFilters.barcode && styles.filterButtonTextActive]}>UPC</Text></TouchableOpacity>
          <TouchableOpacity 
            style={[styles.filterButton, selectedResultCategoryId && styles.filterButtonActive, { flexDirection: 'row', alignItems: 'center' }]} 
            onPress={() => setCategoryModalVisible(true)}
          >
            <Ionicons name="filter-outline" size={14} color={selectedResultCategoryId ? '#FFFFFF' : lightTheme.colors.text} style={{ marginRight: 3 }} />
            <Text style={[styles.filterButtonText, selectedResultCategoryId && styles.filterButtonTextActive]}>
              {selectedCategoryName}
            </Text>
          </TouchableOpacity>
        </View>
        
        <TouchableOpacity style={styles.sortCycleButton} onPress={handleSortCycle}>
          <Ionicons name="swap-vertical-outline" size={16} color={lightTheme.colors.text} style={{ marginRight: 5 }} />
          <Text style={styles.sortCycleButtonText}>Sort: {sortLabels[sortOrder]}</Text>
        </TouchableOpacity>
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
                  <TouchableOpacity 
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
                  </TouchableOpacity>
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
                  <TouchableOpacity 
                      style={[styles.categoryModalButton, styles.categoryModalClearButton]} 
                      onPress={() => {
                          onSelectResultCategory(null); 
                          setCategoryModalVisible(false);
                          setModalCategorySearchTerm('');
                      }}
                  >
                      <Text style={[styles.categoryModalButtonText, styles.categoryModalClearButtonText]}>Clear Selection</Text>
                  </TouchableOpacity>
                  <TouchableOpacity 
                      style={[styles.categoryModalButton, styles.categoryModalCloseButton]} 
                      onPress={() => {
                          setCategoryModalVisible(false);
                          setModalCategorySearchTerm('');
                      }}
                  >
                      <Text style={styles.categoryModalButtonText}>Close</Text>
                  </TouchableOpacity>
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
  const isFocused = useIsFocused();
  const searchInputRef = useRef<TextInput>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [isScanSearch, setIsScanSearch] = useState(false);

  // Auto-focus and select text in search bar on screen focus
  useFocusEffect(
    useCallback(() => {
      const focusTimeout = setTimeout(() => {
        searchInputRef.current?.focus();
        if (isScanSearch && searchQuery.length > 0) {
          searchInputRef.current?.setSelection(0, searchQuery.length);
          setIsScanSearch(false); // Reset the flag after selection
        }
      }, 500);

      return () => {
        clearTimeout(focusTimeout);
      };
    }, [isScanSearch, searchQuery])
  );

  const handleClearSearch = useCallback(() => {
    setSearchQuery('');
    setIsScanSearch(false);
    searchInputRef.current?.focus();
  }, []);

  const handleBarcodeScanned = useCallback((data: { [key: string]: any }) => {
    const barcode = data.data;
    if (typeof barcode === 'string' && barcode.length > 0) {
      logger.info('Barcode scanned', barcode);
      setSearchQuery(barcode);
      setIsScanSearch(true); // Flag this as a scan-initiated search
    }
  }, []);

  const handlePrintAndClear = useCallback(() => {
    setSearchQuery('');
    setIsScanSearch(false);
    setTimeout(() => {
      searchInputRef.current?.focus();
    }, 100);
  }, []);

  const scanHistory = useAppStore((state) => state.scanHistory);
  const addScanHistoryItem = useAppStore((state) => state.addScanHistoryItem);
  const autoSearchOnEnter = useAppStore((state) => state.autoSearchOnEnter);
  const autoSearchOnTab = useAppStore((state) => state.autoSearchOnTab);
  
  const navigateToHistory = useCallback(() => {
    router.push('/(tabs)/scanHistory');
  }, [router]);

  const handlePrintSuccessForChaining = useCallback(() => {
    if (searchInputRef.current) {
      searchInputRef.current.focus();
      if (searchQuery.length > 0) {
        searchInputRef.current.setSelection(0, searchQuery.length);
      }
      logger.info('RootLayoutNav', 'Search input focused and text selected for chain scanning.');
    }
  }, [searchInputRef, searchQuery]);
  
  const KAV_OFFSET_IOS = 0;
  const KAV_OFFSET_ANDROID = 0;
  
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
      
        <ConnectionStatusBar 
          connected={isConnected} 
          message="Square Connection Status" 
        />
        
      <ScanHistoryButtonComponent count={scanHistory.length} onNavigate={navigateToHistory} />

      <SearchResultsArea 
        initialSearchQuery={searchQuery} 
        onPrintSuccessForChaining={handlePrintAndClear}
      />

      <BottomSearchBarComponent 
        searchInputRef={searchInputRef} 
        searchQuery={searchQuery} 
        setSearchQuery={setSearchQuery} 
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
      <TouchableOpacity style={[styles.filterButton, searchFilters.name && styles.filterButtonActive]} onPress={() => onToggleFilter('name')}><Text style={[styles.filterButtonText, searchFilters.name && styles.filterButtonTextActive]}>Name</Text></TouchableOpacity>
      <TouchableOpacity style={[styles.filterButton, searchFilters.sku && styles.filterButtonActive]} onPress={() => onToggleFilter('sku')}><Text style={[styles.filterButtonText, searchFilters.sku && styles.filterButtonTextActive]}>SKU</Text></TouchableOpacity>
      <TouchableOpacity style={[styles.filterButton, searchFilters.barcode && styles.filterButtonActive]} onPress={() => onToggleFilter('barcode')}><Text style={[styles.filterButtonText, searchFilters.barcode && styles.filterButtonTextActive]}>UPC</Text></TouchableOpacity>
      <TouchableOpacity style={[styles.filterButton, searchFilters.category && styles.filterButtonActive]} onPress={() => onToggleFilter('category')}><Text style={[styles.filterButtonText, searchFilters.category && styles.filterButtonTextActive]}>Category</Text></TouchableOpacity>
    </View>
  );
});

interface BottomSearchBarProps {
  searchInputRef: React.RefObject<TextInput | null>;
  searchQuery: string;
  setSearchQuery: (query: string) => void;
  onClearSearch: () => void;
}
const BottomSearchBarComponent = memo(({ 
  searchInputRef, 
  searchQuery, 
  setSearchQuery, 
  onClearSearch,
}: BottomSearchBarProps) => {
  const KAV_OFFSET_IOS_internal = 0; 
  const KAV_OFFSET_ANDROID_internal = 0;

  return (
    <KeyboardAvoidingView 
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={Platform.OS === 'ios' ? KAV_OFFSET_IOS_internal : KAV_OFFSET_ANDROID_internal}
      style={styles.searchBarContainer} 
    >
      <TouchableOpacity 
        style={[styles.externalClearTextButton, searchQuery.length === 0 && styles.externalClearTextButtonDisabled]}
        onPress={onClearSearch}
        disabled={searchQuery.length === 0}
      >
        <Text style={[styles.externalClearButtonText, searchQuery.length === 0 && styles.externalClearButtonTextDisabled]}>Clear</Text>
      </TouchableOpacity>
      <View style={styles.searchInputWrapper}>
        <Ionicons name="search" size={22} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={searchInputRef}
          style={styles.searchInput}
          placeholder="Scan barcode or search items..."
          placeholderTextColor="#999"
          value={searchQuery}
          onChangeText={setSearchQuery}
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          blurOnSubmit={false}
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity style={styles.clearButton} onPress={onClearSearch}>
            <Ionicons name="close-circle" size={20} color="#aaa" />
          </TouchableOpacity>
        )}
      </View>
    </KeyboardAvoidingView>
  );
});

// Define Memoized ScanHistoryButtonComponent
interface ScanHistoryButtonProps {
  count: number;
  onNavigate: () => void;
}
const ScanHistoryButtonComponent = memo(({ count, onNavigate }: ScanHistoryButtonProps) => {
  return (
    <View style={styles.historyButtonContainer}>
      <Link href="/(tabs)/scanHistory" asChild>
        <TouchableOpacity style={styles.historyButton} onPress={onNavigate}>
          <Ionicons name="archive-outline" size={20} color={lightTheme.colors.primary} style={{marginRight: 8}} />
          <Text style={styles.historyButtonText}>View Scan History ({count})</Text>
        </TouchableOpacity>
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