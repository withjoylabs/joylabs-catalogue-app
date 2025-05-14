import React, { useState, useCallback, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, TextInput } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import * as modernDb from '../database/modernDb';
import catalogSyncService from '../database/catalogSync';
import { useSquareAuth } from '../hooks/useSquareAuth';
import api from '../api';
import logger from '../utils/logger';

interface SyncStatus {
  lastSyncTime: string | null;
  isSyncing: boolean;
  syncError: string | null;
  syncProgress: number;
  syncTotal: number;
  syncType: string | null;
  syncAttempt: number;
}

// Component that displays catalog sync status and controls
export default function CatalogSyncStatus() {
  const [status, setStatus] = useState<SyncStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [showDebug, setShowDebug] = useState(false);
  const [isInspectingDb, setIsInspectingDb] = useState(false);
  const [dbItemCount, setDbItemCount] = useState({ categoryCount: 0, itemCount: 0 });
  const [isResettingDb, setIsResettingDb] = useState(false);
  const { hasValidToken } = useSquareAuth();

  // Initialize the sync service when component mounts
  useEffect(() => {
    const initializeSyncService = async () => {
      try {
        logger.info('CatalogSyncStatus', 'Initializing catalog sync service');
        await catalogSyncService.initialize();
        // After initialization, fetch the status immediately
        fetchSyncStatus();
      } catch (error) {
        logger.error('CatalogSyncStatus', 'Failed to initialize sync service', { error });
      }
    };
    
    initializeSyncService();
  }, []);

  // Fetch sync status from the database
  const fetchSyncStatus = async () => {
    try {
      setLoading(true);
      const db = await modernDb.getDatabase();
      
      // First, check if the sync_status table exists and has a record
      try {
        // Check if table exists
        const tableCheck = await db.getFirstAsync<{count: number}>(
          "SELECT count(*) as count FROM sqlite_master WHERE type='table' AND name='sync_status'"
        );
        
        if (!tableCheck || tableCheck.count === 0) {
          logger.warn('CatalogSyncStatus', 'sync_status table does not exist, initializing schema');
          await modernDb.initializeSchema();
        } else {
          // Check if sync_status has a record
          const recordCheck = await db.getFirstAsync<{count: number}>(
            "SELECT count(*) as count FROM sync_status WHERE id = 1"
          );
          
          if (!recordCheck || recordCheck.count === 0) {
            logger.warn('CatalogSyncStatus', 'No sync_status record found, creating default');
            await db.runAsync("INSERT INTO sync_status (id) VALUES (1)");
          }
        }
      } catch (schemaError) {
        logger.error('CatalogSyncStatus', 'Error checking sync_status schema', { schemaError });
        // Try to recreate schema if there was an error
        await modernDb.initializeSchema();
      }
      
      // Now fetch the status
      const result = await db.getFirstAsync<{
        last_sync_time: string | null;
        is_syncing: number;
        sync_error: string | null;
        sync_progress: number;
        sync_total: number;
        sync_type: string | null;
        sync_attempt: number;
      }>('SELECT * FROM sync_status WHERE id = 1');
      
      if (result) {
        setStatus({
          lastSyncTime: result.last_sync_time,
          isSyncing: !!result.is_syncing,
          syncError: result.sync_error,
          syncProgress: result.sync_progress || 0,
          syncTotal: result.sync_total || 0,
          syncType: result.sync_type,
          syncAttempt: result.sync_attempt || 0
        });
      }

      // Get item counts each time we fetch status
      await checkItemsCount();
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to fetch sync status', { error });
      Alert.alert('Error', 'Failed to load sync status');
    } finally {
      setLoading(false);
    }
  };

  // Fetch status when component becomes visible
  useFocusEffect(
    useCallback(() => {
      logger.debug('CatalogSyncStatus', 'Component focused, fetching status once');
      // Just fetch the status once when the component gains focus
      fetchSyncStatus();
      
      // No polling interval - we'll only update when actions are taken
      return () => {
        // No intervals to clear
      };
    }, [])
  );

  // Start a full catalog sync
  const startFullSync = async () => {
    try {
      if (!hasValidToken) {
        Alert.alert('Auth Required', 'Please connect to Square first');
        return;
      }
      
      await catalogSyncService.initialize();
      await catalogSyncService.runFullSync();
      
      // Immediately fetch status after starting sync to update UI
      setTimeout(() => {
        logger.debug('CatalogSyncStatus', 'Fetching status after starting sync');
        fetchSyncStatus();
      }, 500); // Short delay to let sync process start
      
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to start full sync', { error });
      Alert.alert('Error', 'Failed to start sync');
    }
  };

  // Sync only categories - Comment out as method doesn't exist
  /*
  const syncCategoriesOnly = async () => {
    try {
      if (!hasValidToken) {
        Alert.alert('Auth Required', 'Please connect to Square first');
        return;
      }
      
      await catalogSyncService.initialize();
      // This method needs to be implemented in catalogSyncService if needed
      // await catalogSyncService.syncCategories(); 
      fetchSyncStatus();
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to sync categories', { error });
      Alert.alert('Error', 'Failed to sync categories');
    }
  };
  */

  // Test API connectivity
  const testApi = async () => {
    try {
      const result = await api.webhooks.healthCheck();
      Alert.alert(
        'API Test',
        result.success
          ? 'Connection successful'
          : `Connection failed: ${result.error?.message || 'Unknown error'}`
      );
    } catch (error) {
      logger.error('CatalogSyncStatus', 'API test failed', { error });
      Alert.alert('API Test', `Connection failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };

  // Reset sync status if stuck
  const resetSync = async () => {
    try {
      const db = await modernDb.getDatabase();
      await db.runAsync(
        'UPDATE sync_status SET is_syncing = 0, sync_error = NULL, sync_progress = 0, sync_total = 0 WHERE id = 1'
      );
      
      Alert.alert('Success', 'Sync status has been reset');
      fetchSyncStatus();
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to reset sync status', { error });
      Alert.alert('Error', 'Failed to reset sync status');
    }
  };

  // Inspect Database Handler
  const handleInspectDatabase = async () => {
    setIsInspectingDb(true);
    try {
      const items = await modernDb.getFirstTenItemsRaw();
      logger.info('CatalogSyncStatus', 'Raw DB Inspection Results:', { items });
      // Log to console for easier viewing in development environment
      console.log('--- Inspect DB (First 10 Items) ---');
      console.log(JSON.stringify(items, null, 2));
      console.log('--- End Inspect DB --- ');
      Alert.alert('Inspect DB', `Fetched ${items.length} raw items. Check console/logs for details.`);
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to inspect database', { error });
      Alert.alert('Error', 'Failed to inspect database. Check logs.');
    } finally {
      setIsInspectingDb(false);
    }
  };

  // Add checkItemsCount function to get database stats
  const checkItemsCount = async () => {
    try {
      const counts = await catalogSyncService.checkItemsInDatabase();
      setDbItemCount(counts);
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to get item counts', { error });
    }
  };

  // Complete database reset function
  const resetDatabase = async () => {
    Alert.alert(
      'Reset Entire Database',
      'This will delete ALL data in the local database. Are you sure you want to continue?',
      [
        {
          text: 'Cancel',
          style: 'cancel'
        },
        {
          text: 'Reset Everything',
          style: 'destructive',
          onPress: async () => {
            try {
              setIsResettingDb(true);
              logger.warn('CatalogSyncStatus', 'User initiated complete database reset');
              
              // First reset the sync status
              await catalogSyncService.resetSyncStatus();
              
              // Then reset the entire database
              await modernDb.resetDatabase();
              
              // Re-initialize sync service
              await catalogSyncService.initialize();
              
              // Fetch status
              await fetchSyncStatus();
              
              Alert.alert('Success', 'Database has been completely reset');
            } catch (error) {
              logger.error('CatalogSyncStatus', 'Failed to reset database', { error });
              Alert.alert('Error', 'Failed to reset database');
            } finally {
              setIsResettingDb(false);
            }
          }
        }
      ]
    );
  };

  if (loading && !status) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0000ff" />
      </View>
    );
  }

  // Format last sync time
  const lastSyncText = status?.lastSyncTime
    ? new Date(status.lastSyncTime).toLocaleString()
    : 'Never';

  // Calculate sync progress percentage
  const syncProgress = status?.syncTotal && status.syncTotal > 0
    ? Math.round((status.syncProgress / status.syncTotal) * 100)
    : 0;

  return (
    <View style={styles.container}>
      <View style={styles.headerSection}>
        <Text style={styles.headerText}>Catalog Sync Status</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity 
            onPress={fetchSyncStatus}
            style={styles.refreshButton}
            disabled={loading}
          >
            {loading ? (
              <ActivityIndicator size="small" color="#2196f3" />
            ) : (
              <Ionicons name="refresh-outline" size={20} color="#333" />
            )}
          </TouchableOpacity>
          {status?.isSyncing && (
            <View style={styles.syncingIndicator}>
              <ActivityIndicator size="small" color="#2196f3" />
              <Text style={styles.syncingText}>Syncing...</Text>
            </View>
          )}
        </View>
      </View>

      <View style={styles.statusSection}>
        <Text style={styles.label}>Last Sync:</Text>
        <Text style={styles.value}>{lastSyncText}</Text>
      </View>

      {/* Add item count indicators */}
      <View style={styles.statusSection}>
        <Text style={styles.label}>Items in Database:</Text>
        <Text style={styles.value}>{dbItemCount.itemCount}</Text>
      </View>

      <View style={styles.statusSection}>
        <Text style={styles.label}>Categories in Database:</Text>
        <Text style={styles.value}>{dbItemCount.categoryCount}</Text>
      </View>

      {status?.isSyncing && (
        <>
          <View style={styles.statusSection}>
            <Text style={styles.label}>Progress:</Text>
            <Text style={styles.value}>
              {status.syncProgress} / {status.syncTotal} ({syncProgress}%)
            </Text>
          </View>
          
          <View style={styles.progressBarContainer}>
            <View 
              style={[
                styles.progressBar, 
                { width: `${syncProgress}%` }
              ]} 
            />
          </View>
        </>
      )}

      {status?.syncError && (
        <View style={styles.errorSection}>
          <Text style={styles.errorText}>{status.syncError}</Text>
        </View>
      )}
      
      {!status?.isSyncing && !status?.syncError && status?.lastSyncTime && (
        <View style={styles.statusMessageContainer}>
          <Ionicons name="checkmark-circle" size={20} color="#4caf50" />
          <Text style={styles.statusMessageText}>Sync completed successfully</Text>
        </View>
      )}
      
      {!status?.lastSyncTime && !status?.isSyncing && (
        <View style={styles.statusMessageContainer}>
          <Ionicons name="information-circle" size={20} color="#ff9800" />
          <Text style={styles.statusMessageText}>Never synced</Text>
        </View>
      )}

      <View style={styles.buttonContainer}>
        <TouchableOpacity
          style={[styles.button, status?.isSyncing && styles.buttonDisabled]}
          onPress={startFullSync}
          disabled={status?.isSyncing}
        >
          <Text style={styles.buttonText}>Full Sync</Text>
        </TouchableOpacity>

        {/* Comment out Categories Only button */}
        {/*
        <TouchableOpacity
          style={[styles.button, status?.isSyncing && styles.buttonDisabled]}
          onPress={syncCategoriesOnly}
          disabled={status?.isSyncing}
        >
          <Text style={styles.buttonText}>Categories Only</Text>
        </TouchableOpacity>
        */}

        <TouchableOpacity
          style={[styles.debugButton]}
          onPress={() => setShowDebug(!showDebug)}
        >
          <Ionicons name="bug" size={24} color="#333" />
        </TouchableOpacity>
      </View>

      {showDebug && (
        <View style={styles.debugSection}>
          <TouchableOpacity
            style={styles.debugActionButton}
            onPress={testApi}
          >
            <Text style={styles.buttonText}>Test API</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.debugActionButton}
            onPress={resetSync}
          >
            <Text style={styles.buttonText}>Reset Sync Status</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.debugActionButton, isInspectingDb && styles.buttonDisabled]}
            onPress={handleInspectDatabase}
            disabled={isInspectingDb}
          >
            {isInspectingDb ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Inspect DB (First 10)</Text>
            )}
          </TouchableOpacity>
          
          {/* Add the complete database reset button */}
          <TouchableOpacity
            style={[styles.debugActionButton, styles.dangerButton, isResettingDb && styles.buttonDisabled]}
            onPress={resetDatabase}
            disabled={isResettingDb}
          >
            {isResettingDb ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Reset ENTIRE Database</Text>
            )}
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 8,
    marginBottom: 20,
  },
  headerSection: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 15,
  },
  headerText: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#333',
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  refreshButton: {
    padding: 5,
    marginRight: 10,
  },
  syncingIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  syncingText: {
    marginLeft: 5,
    color: '#2196f3',
    fontWeight: '500',
  },
  statusSection: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  label: {
    fontWeight: '400',
    color: '#333',
  },
  value: {
    fontWeight: '600',
    color: '#333',
  },
  errorSection: {
    backgroundColor: '#ffebee',
    padding: 8,
    borderRadius: 4,
    marginBottom: 16,
  },
  errorText: {
    color: '#d32f2f',
  },
  buttonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  button: {
    backgroundColor: '#2196f3',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 4,
    flex: 1,
    marginHorizontal: 4,
    alignItems: 'center',
  },
  buttonDisabled: {
    backgroundColor: '#bdbdbd',
  },
  buttonText: {
    fontWeight: '600',
    color: '#fff',
  },
  debugButton: {
    padding: 8,
    marginLeft: 10,
    justifyContent: 'center',
    alignItems: 'center',
  },
  debugSection: {
    marginTop: 15,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#eee',
    alignItems: 'stretch',
  },
  debugActionButton: {
    backgroundColor: '#546e7a',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 5,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 10,
    minHeight: 44,
  },
  debugInput: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 4,
    paddingHorizontal: 10,
    paddingVertical: 8,
    marginTop: 15,
    marginBottom: 10,
    backgroundColor: '#fff',
    fontSize: 14,
    color: '#333',
  },
  progressBarContainer: {
    height: 10,
    backgroundColor: '#e0e0e0',
    borderRadius: 5,
    marginVertical: 10,
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#2196f3',
  },
  statusMessageContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 5,
    marginBottom: 15,
  },
  statusMessageText: {
    marginLeft: 5,
    color: '#555',
  },
  dangerButton: {
    backgroundColor: '#d32f2f',
  },
}); 