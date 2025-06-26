import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, ActivityIndicator, RefreshControl, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import { useCatalogCategories } from '../hooks/useCatalogCategories';
import { useNavigation } from '@react-navigation/native';
import { Image } from 'react-native';
import { useSquareAuth } from '../hooks/useSquareAuth';
import SyncProgressBar from '../components/SyncProgressBar';
import catalogSyncService from '../database/catalogSync';
import * as modernDb from '../database/modernDb';
import NetInfo from '@react-native-community/netinfo';
import tokenService from '../services/tokenService';
import { useWebhooks } from '../hooks/useWebhooks';
import logger from '../utils/logger';

// Define category interface to match the hook
interface Category {
  id: string;
  name: string;
  imageUrl?: string;
  itemCount?: number;
}

// Define navigation type
type NavigationProp = any; // Simplified for now

// Default placeholder image
const PLACEHOLDER_IMAGE = 'https://placehold.co/600x400/e0e0e0/CCCCCC?text=No+Image';

const CategoriesScreen: React.FC = () => {
  const navigation = useNavigation<NavigationProp>();
  const { categories, isLoading, error, refetchCategories } = useCatalogCategories();
  const { isConnected } = useSquareAuth();
  const [syncing, setSyncing] = useState(false);
  const [syncStatus, setSyncStatus] = useState<any>(null);
  const [refreshing, setRefreshing] = useState(false);
  
  // Integrate webhook system for real-time updates
  const { isWebhookActive, merchantId } = useWebhooks();
  
  // Check sync status when screen loads
  useEffect(() => {
    const checkSyncStatus = async () => {
      const status = await catalogSyncService.getSyncStatus();
      setSyncStatus(status);
      console.log('📊 Current sync status:', status);
    };
    
    // Check sync status once on mount, no polling
    checkSyncStatus();
  }, []);
  
  const handleSyncCatalog = async () => {
    try {
      setSyncing(true);
      Alert.alert(
        "Syncing Catalog",
        "Starting full catalog sync. This may take a while for large catalogs.",
        [{ text: "OK" }]
      );
      await catalogSyncService.forceFullSync();
    } catch (error) {
      console.error("Sync error:", error);
      Alert.alert(
        "Sync Error",
        "There was an error syncing your catalog. Please try again later.",
        [{ text: "OK" }]
      );
    } finally {
      setSyncing(false);
    }
  };
  
  // Debug function to check and reset sync status
  const handleDebugSyncStatus = async () => {
    try {
      // Get current status from the database
      const db = await modernDb.getDatabase();
      const result = await db.getFirstAsync<any>('SELECT * FROM sync_status LIMIT 1');
      const dbStatus = result;
      
      // Check network connectivity
      const netInfo = await NetInfo.fetch();
      
      // Prepare diagnostic message
      const diagnosticInfo = `
Network Status: ${netInfo.isConnected ? 'Connected ✓' : 'DISCONNECTED ⚠️'}
Network Type: ${netInfo.type}

Database sync_status:
- is_syncing: ${dbStatus?.is_syncing ? 'TRUE ⚠️' : 'false ✓'}
- last_sync_time: ${dbStatus?.last_sync_time || 'never'}
- synced_items: ${dbStatus?.synced_items || 0}
- total_items: ${dbStatus?.total_items || 0}
- last_cursor: ${dbStatus?.last_cursor ? dbStatus.last_cursor.substring(0, 15) + '...' : 'null'}
- sync_error: ${dbStatus?.sync_error || 'none'}

If is_syncing shows TRUE but no Lambda calls are happening, the sync state is stuck.
Choose "Reset Sync State" to fix this.
      `;
      
      // Show alert with status and reset options
      Alert.alert(
        "Sync Status Debug", 
        diagnosticInfo,
        [
          { 
            text: "Reset Sync State",
            style: "destructive",
            onPress: async () => {
              try {
                // Use the correct method from catalogSyncService
                await catalogSyncService.resetSyncStatus();
                Alert.alert("Sync State Reset", "Sync state has been completely reset");
              } catch (error) {
                console.error("Reset error:", error);
                // Fallback to direct SQL if the method fails
                const db = await modernDb.getDatabase();
                await db.runAsync('UPDATE sync_status SET is_syncing = 0, sync_error = NULL WHERE id = 1');
                Alert.alert("Sync State Reset", "Sync state has been reset (fallback method)");
              }
            }
          },
          { 
            text: "Test API Call",
            onPress: async () => {
              try {
                console.log("🧪 Testing direct API call to catalog endpoint...");
                Alert.alert("Testing API", "Making direct API call to catalog endpoint. Check console logs.");
                
                // Get the token from an appropriate source (update based on your actual token management)
                const { accessToken } = await tokenService.getTokenInfo();
                const response = await fetch("https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/v2/catalog/list-categories", {
                  method: "GET",
                  headers: {
                    "Authorization": `Bearer ${accessToken || ''}`,
                    "Cache-Control": "no-cache",
                    "X-Test-Request": "true" // Add custom header to identify test requests
                  }
                });
                
                const data = await response.json();
                console.log("🧪 Direct API test result:", {
                  status: response.status,
                  statusText: response.statusText,
                  headers: Object.fromEntries(response.headers.entries()),
                  dataLength: JSON.stringify(data).length,
                  data: data
                });
                
                Alert.alert("API Test Result", 
                  `Status: ${response.status}\n` +
                  `Success: ${data.success ? "Yes ✓" : "No ❌"}\n` +
                  `Objects: ${data.objects?.length || 0}\n` +
                  `Check console for full response`
                );
              } catch (error) {
                console.error("🧪 API test error:", error);
                Alert.alert("API Test Failed", `Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
              }
            }
          },
          {
            text: "Force Categories Sync Only",
            onPress: async () => {
              try {
                Alert.alert("Syncing Categories", "Starting categories-only sync (no items)");
                // TODO: This method doesn't exist in CatalogSyncService
                // await catalogSyncService.syncCategories();
                Alert.alert("Categories Sync", "Categories feature not implemented yet");
              } catch (error) {
                console.error("Categories sync error:", error);
                Alert.alert("Categories Sync Failed", `Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
              }
            }
          },
          { text: "Close", style: "cancel" }
        ]
      );
    } catch (error) {
      console.error("Debug error:", error);
      Alert.alert("Debug Error", "Could not retrieve sync status information");
    }
  };
  
  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await refetchCategories();
      logger.info('CategoriesScreen', 'Categories refreshed successfully');
    } catch (error) {
      logger.error('CategoriesScreen', 'Failed to refresh categories', { error });
      Alert.alert('Refresh Failed', 'Could not refresh categories. Please try again.');
    } finally {
      setRefreshing(false);
    }
  }, [refetchCategories]);

  // Auto-refresh when webhook system detects changes
  useEffect(() => {
    if (isWebhookActive) {
      logger.info('CategoriesScreen', 'Webhook system active, categories will update automatically');
    }
  }, [isWebhookActive]);

  const renderItem = ({ item }: { item: Category }) => (
    <TouchableOpacity
      style={styles.categoryCard}
      onPress={() => {
        // Navigate to products filtered by this category
        navigation.navigate('Products', { categoryId: item.id, categoryName: item.name });
      }}
    >
      <Image
        source={{ uri: item.imageUrl || PLACEHOLDER_IMAGE }}
        style={styles.categoryImage}
      />
      <View style={styles.categoryInfo}>
        <Text style={styles.categoryName}>{item.name}</Text>
        {item.itemCount !== undefined && (
          <Text style={styles.itemCount}>{item.itemCount} items</Text>
        )}
        <Ionicons name="chevron-forward" size={20} color="#888" />
      </View>
    </TouchableOpacity>
  );

  // Show connection screen if not connected to Square
  if (!isConnected) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.errorContainer}>
          <Ionicons name="cloud-offline" size={64} color={lightTheme.colors.text} />
          <Text style={styles.errorText}>Not Connected to Square</Text>
          <Text style={styles.errorDetail}>
            Please connect your Square account in the Profile tab to view your categories.
          </Text>
          <TouchableOpacity
            style={styles.retryButton}
            onPress={() => navigation.navigate('/(profile)')}
          >
            <Text style={styles.retryButtonText}>Go to Profile</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // Show loading state
  if (isLoading && !refreshing) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Categories</Text>
          <View style={styles.statusContainer}>
            {isWebhookActive ? (
              <View style={styles.statusBadge}>
                <Ionicons name="cloud-done" size={16} color={lightTheme.colors.secondary} />
                <Text style={[styles.statusText, { color: lightTheme.colors.secondary }]}>
                  Live
                </Text>
              </View>
            ) : (
              <TouchableOpacity style={styles.refreshButton} onPress={handleRefresh}>
                <Ionicons name="refresh" size={20} color={lightTheme.colors.primary} />
              </TouchableOpacity>
            )}
          </View>
        </View>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.loadingText}>Loading categories...</Text>
        </View>
      </SafeAreaView>
    );
  }

  // Show error state
  if (error) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Categories</Text>
          <View style={styles.statusContainer}>
            {isWebhookActive ? (
              <View style={styles.statusBadge}>
                <Ionicons name="cloud-done" size={16} color={lightTheme.colors.secondary} />
                <Text style={[styles.statusText, { color: lightTheme.colors.secondary }]}>
                  Live
                </Text>
              </View>
            ) : (
              <TouchableOpacity style={styles.refreshButton} onPress={handleRefresh}>
                <Ionicons name="refresh" size={20} color={lightTheme.colors.primary} />
              </TouchableOpacity>
            )}
          </View>
        </View>
        <View style={styles.errorContainer}>
          <Ionicons name="alert-circle" size={48} color={lightTheme.colors.notification} />
          <Text style={styles.errorText}>Failed to load categories</Text>
          <Text style={styles.errorDetail}>{error}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={handleRefresh}>
            <Text style={styles.retryButtonText}>Try Again</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // Show empty state
  if (categories.length === 0) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>Categories</Text>
          <View style={styles.statusContainer}>
            {isWebhookActive ? (
              <View style={styles.statusBadge}>
                <Ionicons name="cloud-done" size={16} color={lightTheme.colors.secondary} />
                <Text style={[styles.statusText, { color: lightTheme.colors.secondary }]}>
                  Live
                </Text>
              </View>
            ) : (
              <TouchableOpacity style={styles.refreshButton} onPress={handleRefresh}>
                <Ionicons name="refresh" size={20} color={lightTheme.colors.primary} />
              </TouchableOpacity>
            )}
          </View>
        </View>
        <View style={styles.emptyContainer}>
          <Ionicons name="folder-open-outline" size={64} color={lightTheme.colors.text} />
          <Text style={styles.emptyText}>No categories found</Text>
          <Text style={styles.emptySubtext}>
            {isWebhookActive 
              ? 'Categories will appear here automatically when added'
              : 'Pull down to refresh or check your connection'
            }
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  // Show categories list
  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Categories</Text>
        <View style={styles.statusContainer}>
          {isWebhookActive ? (
            <View style={styles.statusBadge}>
              <Ionicons name="cloud-done" size={16} color={lightTheme.colors.secondary} />
              <Text style={[styles.statusText, { color: lightTheme.colors.secondary }]}>
                Live
              </Text>
            </View>
          ) : (
            <TouchableOpacity style={styles.refreshButton} onPress={handleRefresh}>
              <Ionicons name="refresh" size={20} color={lightTheme.colors.primary} />
            </TouchableOpacity>
          )}
        </View>
      </View>
      <FlatList
        data={categories}
        renderItem={renderItem}
        keyExtractor={(item: Category) => item.id}
        contentContainerStyle={styles.listContainer}
        refreshing={refreshing}
        onRefresh={handleRefresh}
        showsVerticalScrollIndicator={false}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Ionicons name="folder-open-outline" size={64} color={lightTheme.colors.text} />
            <Text style={styles.emptyText}>No categories found</Text>
            <Text style={styles.emptySubtext}>
              {isWebhookActive 
                ? 'Categories will appear here automatically when added'
                : 'Pull down to refresh or check your connection'
              }
            </Text>
          </View>
        }
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  listContainer: {
    flexGrow: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: lightTheme.colors.background,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: lightTheme.colors.text,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: lightTheme.colors.background,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: lightTheme.colors.secondary,
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
    marginLeft: 4,
  },
  refreshButton: {
    padding: 8,
  },
  categoryCard: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 12,
    marginBottom: 15,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  categoryImage: {
    width: '100%',
    height: 120,
    backgroundColor: '#f0f0f0',
  },
  categoryInfo: {
    padding: 15,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  categoryName: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 2,
  },
  itemCount: {
    fontSize: 14,
    color: lightTheme.colors.text,
    opacity: 0.7,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: lightTheme.colors.text,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  errorText: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 16,
    textAlign: 'center',
  },
  errorDetail: {
    fontSize: 14,
    color: lightTheme.colors.text,
    opacity: 0.7,
    marginTop: 8,
    textAlign: 'center',
  },
  retryButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 24,
  },
  retryButtonText: {
    color: lightTheme.colors.background,
    fontSize: 16,
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
    paddingTop: 64,
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 16,
    textAlign: 'center',
  },
  emptySubtext: {
    fontSize: 14,
    color: lightTheme.colors.text,
    opacity: 0.7,
    marginTop: 8,
    textAlign: 'center',
  },
});

export default CategoriesScreen; 