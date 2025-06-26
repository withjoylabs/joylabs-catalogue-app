import React, { useState, useEffect } from 'react';
import { View, FlatList, StyleSheet, Text, TouchableOpacity, ActivityIndicator, RefreshControl } from 'react-native';
import { useRouter, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import ConnectionStatusBar from '../src/components/ConnectionStatusBar';
import SearchBar from '../src/components/SearchBar';
import { useCatalogItems } from '../src/hooks/useCatalogItems';
import { ConvertedItem } from '../src/types/api';
import { lightTheme } from '../src/themes';

export default function CatalogueScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [filteredItems, setFilteredItems] = useState<ConvertedItem[]>([]);
  const [sortOrder, setSortOrder] = useState<'newest' | 'oldest' | 'name' | 'price'>('newest');
  
  const { 
    products, 
    isProductsLoading, 
    isRefreshing,
    productError, 
    hasMore, 
    connected,
    refreshProducts,
    loadMoreProducts
  } = useCatalogItems();
  
  // Filter products when search changes
  useEffect(() => {
    if (!search.trim()) {
      setFilteredItems(products);
    } else {
      const searchLower = search.toLowerCase();
      const filtered = products.filter(
        item => (item.name || '').toLowerCase().includes(searchLower) || 
               (item.description || '').toLowerCase().includes(searchLower) ||
               (item.sku || '').toLowerCase().includes(searchLower)
      );
      setFilteredItems(filtered);
    }
  }, [products, search]);
  
  const handleSearch = () => {
    console.log('Searching for:', search);
    // Already handled by the useEffect above
  };
  
  const handleClearSearch = () => {
    setSearch('');
  };
  
  const handleItemPress = (item: ConvertedItem) => {
    console.log('Item pressed:', item);
    router.push(`/item/${item.id}`);
  };
  
  const handleRefresh = () => {
    refreshProducts();
  };
  
  const handleLoadMore = () => {
    if (hasMore && !isProductsLoading && !isRefreshing) {
      loadMoreProducts();
    }
  };
  
  const handleAddItem = () => {
    // Navigate to item creation screen
    router.push('/item/new');
  };
  
  // Sort items based on the current sort order
  const sortedItems = [...filteredItems].sort((a, b) => {
    switch (sortOrder) {
      case 'newest':
        return new Date(b.updatedAt || 0).getTime() - new Date(a.updatedAt || 0).getTime();
      case 'oldest':
        return new Date(a.updatedAt || 0).getTime() - new Date(b.updatedAt || 0).getTime();
      case 'name':
        return (a.name || '').localeCompare(b.name || '');
      case 'price':
        if (a.price === undefined && b.price === undefined) return 0;
        if (a.price === undefined) return 1;
        if (b.price === undefined) return -1;
        return b.price - a.price;
      default:
        return 0;
    }
  });
  
  const renderItem = ({ item }: { item: ConvertedItem }) => (
    <TouchableOpacity 
      style={styles.itemCard}
      onPress={() => handleItemPress(item)}
    >
      <View style={styles.itemContent}>
        <Text style={styles.itemName} numberOfLines={1}>{item.name}</Text>
        {item.description && (
          <Text style={styles.itemDescription} numberOfLines={2}>{item.description}</Text>
        )}
        <View style={styles.itemDetails}>
          {item.sku && <Text style={styles.itemSku}>SKU: {item.sku}</Text>}
          {item.category && <Text style={styles.itemCategory}>{item.category}</Text>}
        </View>
      </View>
      
      <View style={styles.itemPriceContainer}>
        {item.price !== undefined ? (
          <Text style={styles.itemPrice}>${item.price.toFixed(2)}</Text>
        ) : (
          <Text style={styles.noPrice}>No Price</Text>
        )}
        <Ionicons name="chevron-forward" size={20} color="#ccc" />
      </View>
    </TouchableOpacity>
  );
  
  const renderFooter = () => {
    if (!hasMore) return null;
    
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color={lightTheme.colors.primary} />
        <Text style={styles.footerText}>Loading more items...</Text>
      </View>
    );
  };
  
  const renderEmpty = () => {
    if (isProductsLoading) {
      return (
        <View style={styles.emptyContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.emptyText}>Loading catalogue items...</Text>
        </View>
      );
    }
    
    if (productError) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="alert-circle-outline" size={48} color="red" />
          <Text style={styles.errorText}>{productError}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={refreshProducts}>
            <Text style={styles.retryButtonText}>Retry</Text>
          </TouchableOpacity>
        </View>
      );
    }
    
    if (search && filteredItems.length === 0) {
      return (
        <View style={styles.emptyContainer}>
          <Ionicons name="search-outline" size={48} color="#ccc" />
          <Text style={styles.emptyText}>No items match your search</Text>
          <TouchableOpacity style={styles.clearButton} onPress={handleClearSearch}>
            <Text style={styles.clearButtonText}>Clear Search</Text>
          </TouchableOpacity>
        </View>
      );
    }
    
    return (
      <View style={styles.emptyContainer}>
        <Ionicons name="cube-outline" size={48} color="#ccc" />
        <Text style={styles.emptyText}>No items in your catalogue</Text>
        <Text style={styles.emptySubtext}>
          {connected ? 
            "Add items to start building your catalogue" : 
            "Connect to Square to sync your items"
          }
        </Text>
        {connected && (
          <TouchableOpacity style={styles.addButton} onPress={handleAddItem}>
            <Ionicons name="add" size={24} color="#fff" />
            <Text style={styles.addButtonText}>Add Item</Text>
          </TouchableOpacity>
        )}
      </View>
    );
  };
  
  return (
    <View style={styles.container}>
      <StatusBar style="dark" />
      
      <Stack.Screen
        options={{
          title: 'Catalogue',
          headerShown: true,
          headerStyle: {
            backgroundColor: '#fff',
          },
          headerTitleStyle: {
            color: '#333',
            fontWeight: 'bold',
          },
          headerLeft: () => (
            <TouchableOpacity
              style={styles.backButton}
              onPress={() => router.back()}
            >
              <Ionicons name="arrow-back" size={24} color="#333" />
            </TouchableOpacity>
          ),
          headerRight: () => (
            <TouchableOpacity
              style={styles.addItemButton}
              onPress={handleAddItem}
            >
              <Ionicons name="add" size={24} color={lightTheme.colors.primary} />
            </TouchableOpacity>
          ),
        }}
      />
      
      <ConnectionStatusBar 
        connected={connected} 
        message={connected ? "Connected to Square" : "Not connected to Square"}
      />
      
      <SearchBar 
        value={search}
        onChangeText={setSearch}
        onSubmit={handleSearch}
        onClear={handleClearSearch}
        autoSearchOnEnter={true}
        autoSearchOnTab={false}
      />
      
      <View style={styles.sortHeader}>
        <Text style={styles.sortTitle}>
          {filteredItems.length} {filteredItems.length === 1 ? 'Item' : 'Items'}
        </Text>
        
        <View style={styles.sortOptions}>
          <Text style={styles.sortLabel}>Sort by:</Text>
          <TouchableOpacity 
            style={[styles.sortButton, sortOrder === 'newest' && styles.activeSortButton]} 
            onPress={() => setSortOrder('newest')}
          >
            <Text style={[styles.sortButtonText, sortOrder === 'newest' && styles.activeSortButtonText]}>Newest</Text>
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={[styles.sortButton, sortOrder === 'name' && styles.activeSortButton]} 
            onPress={() => setSortOrder('name')}
          >
            <Text style={[styles.sortButtonText, sortOrder === 'name' && styles.activeSortButtonText]}>Name</Text>
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={[styles.sortButton, sortOrder === 'price' && styles.activeSortButton]} 
            onPress={() => setSortOrder('price')}
          >
            <Text style={[styles.sortButtonText, sortOrder === 'price' && styles.activeSortButtonText]}>Price</Text>
          </TouchableOpacity>
        </View>
      </View>
      
      <FlatList
        data={sortedItems}
        keyExtractor={(item) => item.id}
        renderItem={renderItem}
        ListEmptyComponent={renderEmpty}
        ListFooterComponent={renderFooter}
        contentContainerStyle={styles.listContent}
        onEndReached={handleLoadMore}
        onEndReachedThreshold={0.3}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            colors={[lightTheme.colors.primary]}
          />
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  backButton: {
    padding: 8,
  },
  addItemButton: {
    padding: 8,
  },
  sortHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  sortTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  sortOptions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sortLabel: {
    fontSize: 14,
    color: '#666',
    marginRight: 8,
  },
  sortButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginHorizontal: 4,
    borderRadius: 16,
    backgroundColor: '#f0f0f0',
  },
  activeSortButton: {
    backgroundColor: lightTheme.colors.primary,
  },
  sortButtonText: {
    fontSize: 12,
    color: '#666',
  },
  activeSortButtonText: {
    color: '#fff',
    fontWeight: '500',
  },
  listContent: {
    flexGrow: 1,
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyText: {
    fontSize: 18,
    color: '#333',
    fontWeight: '500',
    marginTop: 16,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginTop: 8,
    marginHorizontal: 32,
  },
  errorText: {
    color: 'red',
    fontSize: 16,
    marginTop: 16,
    textAlign: 'center',
  },
  retryButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 16,
  },
  retryButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  clearButton: {
    backgroundColor: '#f0f0f0',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 16,
  },
  clearButtonText: {
    color: '#333',
    fontWeight: '600',
  },
  addButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 16,
  },
  addButtonText: {
    color: '#fff',
    fontWeight: '600',
    marginLeft: 8,
  },
  itemCard: {
    flexDirection: 'row',
    backgroundColor: '#fff',
    borderRadius: 8,
    marginTop: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  itemContent: {
    flex: 1,
  },
  itemName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  itemDescription: {
    fontSize: 14,
    color: '#666',
    marginBottom: 8,
  },
  itemDetails: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  itemSku: {
    fontSize: 12,
    color: '#888',
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 8,
  },
  itemCategory: {
    fontSize: 12,
    color: '#888',
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  itemPriceContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    marginLeft: 8,
  },
  itemPrice: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    marginRight: 8,
  },
  noPrice: {
    fontSize: 12,
    color: '#999',
    marginRight: 8,
  },
  footerLoader: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 16,
  },
  footerText: {
    fontSize: 14,
    color: '#666',
    marginLeft: 8,
  },
}); 