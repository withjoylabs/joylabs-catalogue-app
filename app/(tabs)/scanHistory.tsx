import React, { useState, useMemo } from 'react';
import { View, FlatList, StyleSheet, SafeAreaView, Text, TouchableOpacity, StatusBar } from 'react-native';
import { useRouter, Link } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAppStore } from '../../src/store';
import { ScanHistoryItem } from '../../src/types';
import CatalogueItemCard from '../../src/components/CatalogueItemCard';
import SwipeableRow from '../../src/components/SwipeableRow';
import SortHeader from '../../src/components/SortHeader';
import { lightTheme } from '../../src/themes';

export default function ScanHistoryScreen() {
  const router = useRouter();
  const scanHistory = useAppStore((state) => state.scanHistory);
  const removeScanHistoryItem = useAppStore((state) => state.removeScanHistoryItem);
  const [sortOrder, setSortOrder] = useState<'newest' | 'oldest' | 'name' | 'price'>('newest');

  const handleItemPress = (item: ScanHistoryItem) => {
    const itemId = item.id;
    // logger.info('ScanHistory', 'Item selected from history', { itemId }); // Optional: Add logger if needed
    router.push(`/item/${itemId}`);
  };

  const handleDeleteHistoryItem = (scanId: string) => {
    // logger.info('ScanHistory', 'Removing item from scan history', { scanId }); // Optional: Add logger
    removeScanHistoryItem(scanId);
  };

  const sortedItems = useMemo(() => {
    return [...scanHistory].sort((a, b) => {
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
  }, [scanHistory, sortOrder]);

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
      
      {/* Header for Scan History Page */}
      <View style={styles.headerContainer}>
        <Link href="../" asChild>
          <TouchableOpacity style={styles.backButton}>
            <Ionicons name="arrow-back" size={24} color={lightTheme.colors.primary} />
          </TouchableOpacity>
        </Link>
        <Text style={styles.headerTitle}>Scan History</Text>
        <View style={{ width: 40 }} />{/* Spacer for centering title */}
      </View>

      <View style={styles.mainContainer}>
        <SortHeader 
          title="Sorted By" // Changed title for context
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
                index={sortedItems.length - index} // Keep original index logic for display
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
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#fff',
  },
  headerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    backgroundColor: '#fff',
  },
  backButton: {
    padding: 5,
    marginRight: 10,
  },
  headerTitle: {
    flex: 1,
    fontSize: 18,
    fontWeight: '600',
    textAlign: 'center',
    color: lightTheme.colors.text,
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
    marginTop: 50, // Keep some margin
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
}); 