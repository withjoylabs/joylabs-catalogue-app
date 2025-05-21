import React, { useState, useRef, useEffect, useCallback } from 'react';
import { 
  View, 
  Text, 
  SafeAreaView, 
  FlatList, 
  TextInput, 
  TouchableOpacity, 
  KeyboardAvoidingView, 
  Platform, 
  StatusBar,
  ActivityIndicator
} from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../../src/themes';
import ConnectionStatusBar from '../../src/components/ConnectionStatusBar';
import { useApi } from '../../src/providers/ApiProvider';
import { ConvertedItem } from '../../src/types/api';
import { styles } from './searchStyles';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { SearchFilters } from '../../src/database/modernDb';

// Debounce utility
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

// Placeholder for search result type
interface SearchResultItem extends ConvertedItem {
  // ConvertedItem already has fields we need like id, name, price, etc.
  // We can extend with any additional properties if needed
  matchType?: 'name' | 'sku' | 'barcode' | 'category'; // Indicates what field matched the search
  matchContext?: string; // Optional context about the match
}

export default function SearchScreen() {
  const router = useRouter();
  const { isConnected } = useApi();
  const { performSearch, isSearching, searchError } = useCatalogItems();
  
  // State
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState<string>('');
  const [searchResults, setSearchResults] = useState<SearchResultItem[]>([]);
  const [searchFilters, setSearchFilters] = useState<SearchFilters>({
    name: true,
    sku: true,
    barcode: true,
    category: true
  });
  
  // Reference to the search input
  const searchInputRef = useRef<TextInput>(null);

  // Debounce search query
  const debouncedSetQuery = useCallback(debounce(setDebouncedSearchQuery, 300), []);

  useEffect(() => {
    debouncedSetQuery(searchQuery);
  }, [searchQuery, debouncedSetQuery]);

  // Perform search when debounced query or filters change
  useEffect(() => {
    const executeSearch = async () => {
      if (debouncedSearchQuery.trim() === '') {
        setSearchResults([]); // Clear results if search query is empty
        return;
      }
      const results = await performSearch(debouncedSearchQuery, searchFilters);
      setSearchResults(results as SearchResultItem[]);
    };

    executeSearch();
  }, [debouncedSearchQuery, searchFilters, performSearch]);

  // Clear search and results
  const handleClearSearch = () => {
    setSearchQuery('');
    setDebouncedSearchQuery('');
    setSearchResults([]);
    // Focus the search input again after clearing
    searchInputRef.current?.focus();
  };

  // Handle item press to view details
  const handleItemPress = (item: SearchResultItem) => {
    // Navigate to item details page
    router.push(`/item/${item.id}`);
  };
  
  // Toggle search filters
  const toggleFilter = (filter: keyof SearchFilters) => {
    setSearchFilters(prev => ({
      ...prev,
      [filter]: !prev[filter]
    }));
  };
  
  // Render a search result item
  const renderSearchResultItem = ({ item }: { item: SearchResultItem; index: number }) => {
    // Format price safely
    const formattedPrice = typeof item.price === 'number' 
      ? `$${item.price.toFixed(2)}` 
      : 'Variable Price';
    
    // Determine which icon to show based on matchType
    let matchIcon = 'document-text-outline';
    if (item.matchType === 'sku') matchIcon = 'pricetag-outline';
    if (item.matchType === 'barcode') matchIcon = 'barcode-outline';
    if (item.matchType === 'category') matchIcon = 'folder-outline';

    return (
      <TouchableOpacity 
        style={styles.resultItem}
        onPress={() => handleItemPress(item)}
      >
        <View style={styles.resultIconContainer}>
          <Ionicons name={matchIcon as any} size={24} color="#888" />
        </View>
        
        <View style={styles.resultDetails}>
          <Text 
            style={styles.resultName}
            numberOfLines={1}
          >
            {item.name}
          </Text>
          
          <View style={styles.resultMeta}>
            {item.sku && (
              <Text style={styles.resultSku}>SKU: {item.sku}</Text>
            )}
            {item.category && (
              <Text style={styles.resultCategory}>{item.category}</Text>
            )}
            {item.barcode && (
              <Text style={styles.resultBarcode}>UPC: {item.barcode}</Text>
            )}
          </View>
        </View>
        
        <View style={styles.resultPrice}>
          <Text style={styles.priceText}>{formattedPrice}</Text>
          <Ionicons name="chevron-forward" size={18} color="#ccc" />
        </View>
      </TouchableOpacity>
    );
  };
  
  // Render an empty state when no results or query
  const renderEmptyState = () => {
    if (searchError) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="alert-circle-outline" size={48} color="#FF3B30" />
          <Text style={styles.emptyTitle}>Search Error</Text>
          <Text style={styles.emptyText}>{searchError}</Text>
        </View>
      );
    }
    if (isSearching) {
      return (
        <View style={styles.emptyContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.searchingText}>Searching...</Text>
        </View>
      );
    }
    if (searchQuery.length === 0 && debouncedSearchQuery.length === 0) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="search" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>Search Your Catalogue</Text>
          <Text style={styles.emptyText}>
            Enter a product name, SKU, barcode or category to find items
          </Text>
        </View>
      );
    }
    if (searchResults.length === 0 && (searchQuery.length > 0 || debouncedSearchQuery.length > 0)) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="file-tray-outline" size={48} color="#ccc" />
          <Text style={styles.emptyTitle}>No Results</Text>
          <Text style={styles.emptyText}>
            No items found matching "{debouncedSearchQuery || searchQuery}"
          </Text>
        </View>
      );
    }
    return null;
  };

  // Show active filters
  const renderFilterBadges = () => {
    // Only render if we have any filters selected
    const activeFilters = Object.entries(searchFilters)
      .filter(([_, isEnabled]) => isEnabled)
      .map(([key]) => key as keyof SearchFilters);
      
    if (activeFilters.length === 4 || activeFilters.length === 0) {
      return null; // All filters enabled or none enabled, don't show badges
    }
    
    return (
      <View style={styles.filterBadgesContainer}>
        {activeFilters.map((filter) => (
          <View key={filter} style={styles.filterBadge}>
            <Text style={styles.filterBadgeText}>
              {filter.charAt(0).toUpperCase() + filter.slice(1)}
            </Text>
          </View>
        ))}
      </View>
    );
  };
  
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" />
      <ConnectionStatusBar 
        connected={isConnected}
        message={isConnected ? "Connected to Square" : "Not connected to Square"} 
      />
      
      <View style={styles.mainContent}>
        {/* Search Results Area */}
        <FlatList
          data={searchResults}
          renderItem={renderSearchResultItem}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.resultsContainer}
          ListEmptyComponent={renderEmptyState}
          ListHeaderComponent={renderFilterBadges}
          keyboardShouldPersistTaps="handled"
        />
        
        {/* Filter Buttons - rendered only when keyboard is visible */}
        {searchQuery.length > 0 && (
          <View style={styles.filterContainer}>
            <TouchableOpacity 
              style={[styles.filterButton, searchFilters.name && styles.filterButtonActive]}
              onPress={() => toggleFilter('name')}
            >
              <Text style={[styles.filterButtonText, searchFilters.name && styles.filterButtonTextActive]}>
                Name
              </Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={[styles.filterButton, searchFilters.sku && styles.filterButtonActive]}
              onPress={() => toggleFilter('sku')}
            >
              <Text style={[styles.filterButtonText, searchFilters.sku && styles.filterButtonTextActive]}>
                SKU
              </Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={[styles.filterButton, searchFilters.barcode && styles.filterButtonActive]}
              onPress={() => toggleFilter('barcode')}
            >
              <Text style={[styles.filterButtonText, searchFilters.barcode && styles.filterButtonTextActive]}>
                UPC
              </Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={[styles.filterButton, searchFilters.category && styles.filterButtonActive]}
              onPress={() => toggleFilter('category')}
            >
              <Text style={[styles.filterButtonText, searchFilters.category && styles.filterButtonTextActive]}>
                Category
              </Text>
            </TouchableOpacity>
          </View>
        )}
      </View>
      
      {/* Bottom Search Bar */}
      <KeyboardAvoidingView 
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 55 : 0}
        style={styles.searchBarContainer}
      >
        <View style={styles.searchInputWrapper}>
          <Ionicons name="search" size={22} color="#888" style={styles.searchIcon} />
          
          <TextInput
            ref={searchInputRef}
            style={styles.searchInput}
            placeholder="Search items..."
            placeholderTextColor="#999"
            value={searchQuery}
            onChangeText={setSearchQuery}
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="search"
          />
          
          {searchQuery.length > 0 && (
            <TouchableOpacity 
              style={styles.clearButton}
              onPress={handleClearSearch}
            >
              <Ionicons name="close-circle" size={20} color="#aaa" />
            </TouchableOpacity>
          )}
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
} 