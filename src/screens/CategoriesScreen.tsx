import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, ActivityIndicator, RefreshControl, Alert } from 'react-native';
import { useCatalogCategories } from '../hooks/useCatalogCategories';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { Image } from 'react-native';
import { useSquareAuth } from '../hooks/useSquareAuth';
import SyncProgressBar from '../components/SyncProgressBar';
import catalogSyncService from '../database/catalogSync';
import * as modernDb from '../database/modernDb';
import NetInfo from '@react-native-community/netinfo';
import tokenService from '../services/tokenService';

// Define category interface to match the hook
interface Category {
  id: string;
  name: string;
  imageUrl?: string;
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
  
  // Check sync status when screen loads
  useEffect(() => {
    const checkSyncStatus = async () => {
      const status = await catalogSyncService.getSyncStatus();
      setSyncStatus(status);
      console.log('📊 Current sync status:', status);
    };
    
    checkSyncStatus();
    const intervalId = setInterval(checkSyncStatus, 2000); // Check every 2 seconds
    
    return () => clearInterval(intervalId);
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
                await catalogSyncService.syncCategories();
                Alert.alert("Categories Sync", "Categories sync completed");
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
        <Ionicons name="chevron-forward" size={20} color="#888" />
      </View>
    </TouchableOpacity>
  );

  // Show connection screen if not connected to Square
  if (!isConnected) {
    return (
      <View style={styles.container}>
        <View style={styles.errorContainer}>
          <Ionicons name="cloud-offline" size={64} color="#ccc" />
          <Text style={styles.errorTitle}>Not Connected to Square</Text>
          <Text style={styles.errorText}>
            Please connect your Square account in the Profile tab to view your categories.
          </Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => navigation.navigate('Profile')}
          >
            <Text style={styles.buttonText}>Go to Profile</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show loading state
  if (isLoading && categories.length === 0) {
    return (
      <View style={styles.container}>
        <SyncProgressBar showWhenComplete={false} />
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color="#0066cc" />
          <Text style={styles.loadingText}>Loading categories...</Text>
          <TouchableOpacity 
            style={styles.debugButton}
            onPress={handleDebugSyncStatus}
          >
            <Ionicons name="bug" size={16} color="#fff" />
            <Text style={styles.debugButtonText}>Debug Sync</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show error state
  if (error && categories.length === 0) {
    return (
      <View style={styles.container}>
        <SyncProgressBar showWhenComplete={false} />
        <View style={styles.errorContainer}>
          <Ionicons name="alert-circle-outline" size={64} color="#cc0000" />
          <Text style={styles.errorTitle}>Error Loading Categories</Text>
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => refetchCategories()}
          >
            <Text style={styles.buttonText}>Retry</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.debugButton, { marginTop: 10 }]}
            onPress={handleDebugSyncStatus}
          >
            <Ionicons name="bug" size={16} color="#fff" />
            <Text style={styles.debugButtonText}>Debug Sync</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show empty state
  if (categories.length === 0) {
    return (
      <View style={styles.container}>
        <SyncProgressBar showWhenComplete={false} />
        <View style={styles.errorContainer}>
          <Ionicons name="folder-open-outline" size={64} color="#ccc" />
          <Text style={styles.errorTitle}>No Categories Found</Text>
          <Text style={styles.errorText}>
            You don't have any categories in your Square catalog yet.
          </Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => refetchCategories()}
          >
            <Text style={styles.buttonText}>Refresh</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.debugButton, { marginTop: 10 }]}
            onPress={handleDebugSyncStatus}
          >
            <Ionicons name="bug" size={16} color="#fff" />
            <Text style={styles.debugButtonText}>Debug Sync</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show categories list
  return (
    <View style={styles.container}>
      <SyncProgressBar showWhenComplete={false} />
      <View style={styles.headerContainer}>
        <Text style={styles.headerText}>Categories</Text>
        <View style={styles.buttonContainer}>
          <TouchableOpacity 
            style={styles.syncButton}
            onPress={handleSyncCatalog}
            disabled={syncing}
          >
            <Ionicons name="sync" size={18} color="#fff" />
            <Text style={styles.syncButtonText}>Sync Catalog</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={styles.debugButton}
            onPress={handleDebugSyncStatus}
          >
            <Ionicons name="bug" size={16} color="#fff" />
            <Text style={styles.debugButtonText}>Debug</Text>
          </TouchableOpacity>
        </View>
      </View>
      <FlatList
        data={categories}
        renderItem={renderItem}
        keyExtractor={(item: Category) => item.id}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl refreshing={isLoading} onRefresh={refetchCategories} />
        }
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f8f8',
    paddingTop: 10,
  },
  list: {
    padding: 15,
  },
  headerContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 15,
  },
  buttonContainer: {
    flexDirection: 'row',
  },
  headerText: {
    fontSize: 22,
    fontWeight: 'bold',
    color: '#333',
  },
  syncButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0066cc',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
    marginRight: 8,
  },
  syncButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
    marginLeft: 5,
  },
  debugButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#666',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
  },
  debugButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
    marginLeft: 5,
  },
  categoryCard: {
    backgroundColor: '#fff',
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
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  loadingText: {
    marginTop: 20,
    fontSize: 16,
    color: '#666',
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 30,
  },
  errorTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    marginTop: 20,
    marginBottom: 10,
    color: '#333',
  },
  errorText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 20,
  },
  buttonPrimary: {
    backgroundColor: '#0066cc',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    marginTop: 10,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  centerContent: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default CategoriesScreen; 