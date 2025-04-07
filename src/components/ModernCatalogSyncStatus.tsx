import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, ScrollView } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { formatDistanceToNow } from 'date-fns';
import NetInfo from '@react-native-community/netinfo';
import { useSQLiteContext } from 'expo-sqlite';
import SyncProgressBar from './SyncProgressBar';
import logger from '../utils/logger';
import { CatalogSyncService, SyncStatus } from '../database/catalogSync';

const ModernCatalogSyncStatus: React.FC = () => {
  const db = useSQLiteContext();
  const [syncStatus, setSyncStatus] = useState<SyncStatus | null>(null);
  const [isConnected, setIsConnected] = useState<boolean>(true);
  const [showDebugInfo, setShowDebugInfo] = useState<boolean>(false);
  const [networkType, setNetworkType] = useState<string>('unknown');
  const [testBatchRunning, setTestBatchRunning] = useState<boolean>(false);
  const [testBatchResult, setTestBatchResult] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  
  // Initialize the sync service
  const syncService = CatalogSyncService.getInstance();

  // Fetch sync status
  const fetchSyncStatus = useCallback(async () => {
    try {
      const status = await syncService.getSyncStatus();
      setSyncStatus(status);
      setIsLoading(false);
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to fetch sync status', { error });
      setIsLoading(false);
    }
  }, [syncService]);

  // Handle sync status update
  const handleSyncStatusUpdate = useCallback((status: SyncStatus) => {
    setSyncStatus(status);
  }, []);

  // Handle sync button click
  const handleSync = async () => {
    if (syncStatus?.isSyncing) return;
    
    try {
      await syncService.forceFullSync();
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to start sync', { error });
      Alert.alert('Sync Error', `Failed to start sync: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };

  // Handle categories-only sync
  const handleCategoriesOnlySync = async () => {
    if (syncStatus?.isSyncing) return;
    
    try {
      await syncService.syncCategories();
      Alert.alert('Sync Complete', 'Categories synced successfully.');
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to sync categories', { error });
      Alert.alert('Sync Error', `Failed to sync categories: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };

  // Reset sync state
  const resetSyncState = async () => {
    try {
      logger.info('CatalogSyncStatus', 'Forcefully clearing sync status');
      await syncService.forceClearSyncStatus();
      Alert.alert('Reset Complete', 'Sync state has been successfully reset.');
      await fetchSyncStatus(); // Refresh immediately
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to reset sync state', { error });
      Alert.alert('Reset Failed', `Could not reset sync state: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  };

  // Test API connection
  const testApiConnection = async () => {
    try {
      setTestBatchRunning(true);
      setTestBatchResult(null);
      
      const result = await syncService.testApiConnection();
      setTestBatchResult(`API test successful: ${JSON.stringify(result)}`);
      
      Alert.alert('API Test', 'API connection successful!');
    } catch (error) {
      logger.error('CatalogSyncStatus', 'API test failed', { error });
      setTestBatchResult(`Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
      
      Alert.alert('API Test Failed', `${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setTestBatchRunning(false);
    }
  };

  // Test small batch sync
  const testSmallBatchSync = async () => {
    try {
      setTestBatchRunning(true);
      setTestBatchResult(null);
      
      await syncService.testSmallBatchSync();
      setTestBatchResult('Small batch sync completed successfully');
      
      Alert.alert('Test Sync', 'Small batch sync completed successfully!');
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Small batch sync failed', { error });
      setTestBatchResult(`Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
      
      Alert.alert('Test Sync Failed', `${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setTestBatchRunning(false);
    }
  };

  // Toggle debug info
  const toggleDebugInfo = () => {
    setShowDebugInfo(!showDebugInfo);
  };

  // Format last sync time
  const formatLastSyncTime = (lastSyncTime: string | null): string => {
    if (!lastSyncTime) return 'Never';
    
    try {
      const date = new Date(lastSyncTime);
      return formatDistanceToNow(date, { addSuffix: true });
    } catch (error) {
      return 'Invalid date';
    }
  };

  // Set up effects
  useEffect(() => {
    // Set up network connectivity listener
    const unsubscribe = NetInfo.addEventListener(state => {
      setIsConnected(state.isConnected ?? false);
      setNetworkType(state.type || 'unknown');
    });

    // Check network on mount
    NetInfo.fetch().then(state => {
      setIsConnected(state.isConnected ?? false);
      setNetworkType(state.type || 'unknown');
    });

    // Initialize sync service and fetch status
    const initializeSync = async () => {
      try {
        await syncService.initialize();
        fetchSyncStatus();
      } catch (error) {
        logger.error('CatalogSyncStatus', 'Failed to initialize sync service', { error });
      }
    };

    initializeSync();

    // Set up sync status listener
    syncService.registerListener('modernStatusComponent', handleSyncStatusUpdate);
    
    // Refresh sync status periodically
    const intervalId = setInterval(fetchSyncStatus, 3000);

    // Cleanup
    return () => {
      syncService.unregisterListener('modernStatusComponent');
      unsubscribe();
      clearInterval(intervalId);
    };
  }, [fetchSyncStatus, handleSyncStatusUpdate, syncService]);

  // Render sync status
  const renderSyncStatus = () => {
    if (isLoading) {
      return (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="small" color="#4caf50" />
          <Text style={styles.statusText}>Loading sync status...</Text>
        </View>
      );
    }

    if (!syncStatus) {
      return (
        <Text style={styles.statusText}>No sync status available</Text>
      );
    }

    return (
      <View style={styles.statusContainer}>
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Last sync:</Text>
          <Text style={styles.statusValue}>
            {formatLastSyncTime(syncStatus.lastSyncTime)}
            {syncStatus.syncComplete === false && " (partial)"}
          </Text>
        </View>
        
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Status:</Text>
          <Text style={[
            styles.statusValue,
            syncStatus.isSyncing ? styles.syncing : null,
            syncStatus.syncError ? styles.error : null
          ]}>
            {syncStatus.isSyncing
              ? 'Syncing...'
              : syncStatus.syncError
                ? 'Error'
                : 'Ready'
            }
          </Text>
        </View>
        
        {/* Progress bar */}
        {syncStatus.isSyncing && syncStatus.totalItems > 0 && (
          <SyncProgressBar showWhenComplete={false} />
        )}
        
        {syncStatus.syncError && (
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Error:</Text>
            <Text style={[styles.statusValue, styles.error]} numberOfLines={2}>
              {syncStatus.syncError}
            </Text>
          </View>
        )}

        {/* Debug info when enabled */}
        {showDebugInfo && (
          <>
            <View style={styles.divider} />
            <Text style={styles.debugTitle}>Debug Information</Text>
            
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>Network:</Text>
              <Text style={styles.statusValue}>
                {isConnected ? `Connected (${networkType})` : 'DISCONNECTED ❌'}
              </Text>
            </View>
            
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>DB Status:</Text>
              <Text style={styles.statusValue}>
                is_syncing = {syncStatus.isSyncing ? 'TRUE' : 'false'}, 
                items = {syncStatus.syncedItems}/{syncStatus.totalItems}
              </Text>
            </View>
            
            {testBatchResult && (
              <View style={styles.statusRow}>
                <Text style={styles.statusLabel}>Test Result:</Text>
                <Text style={styles.statusValue}>
                  {testBatchResult}
                </Text>
              </View>
            )}
            
            <View style={styles.debugButtonRow}>
              <TouchableOpacity 
                style={[styles.debugButton, { backgroundColor: '#ff9800' }]}
                onPress={testApiConnection}
                disabled={testBatchRunning}
              >
                <Text style={styles.debugButtonText}>Test API</Text>
              </TouchableOpacity>
              
              <TouchableOpacity 
                style={[styles.debugButton, { backgroundColor: '#e91e63' }]}
                onPress={resetSyncState}
                disabled={testBatchRunning}
              >
                <Text style={styles.debugButtonText}>Reset Sync</Text>
              </TouchableOpacity>
              
              <TouchableOpacity 
                style={[styles.debugButton, { backgroundColor: '#3f51b5' }]}
                onPress={testSmallBatchSync}
                disabled={testBatchRunning}
              >
                <Text style={styles.debugButtonText}>Test Batch</Text>
              </TouchableOpacity>
            </View>
          </>
        )}
      </View>
    );
  };

  // Main render
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Catalog Sync</Text>
        <TouchableOpacity
          style={styles.debugToggle}
          onPress={toggleDebugInfo}
        >
          <MaterialIcons name="bug-report" size={20} color="#666" />
        </TouchableOpacity>
      </View>

      {!isConnected && (
        <View style={styles.offlineMessage}>
          <MaterialIcons name="wifi-off" size={16} color="#f44336" />
          <Text style={styles.offlineText}>Offline - Connect to sync</Text>
        </View>
      )}

      {renderSyncStatus()}
      
      <View style={styles.buttonContainer}>
        <TouchableOpacity 
          style={[
            styles.syncButton, 
            { flex: 1 },
            (syncStatus?.isSyncing || !isConnected || isLoading) && styles.disabledButton
          ]}
          disabled={syncStatus?.isSyncing || !isConnected || isLoading}
          onPress={handleSync}
        >
          {syncStatus?.isSyncing ? (
            <ActivityIndicator size="small" color="#ffffff" />
          ) : (
            <>
              <MaterialIcons name="sync" size={16} color="#ffffff" />
              <Text style={styles.buttonText}>Full Sync</Text>
            </>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={[
            styles.syncButton,
            { flex: 1, backgroundColor: '#2196f3', marginLeft: 8 },
            (syncStatus?.isSyncing || !isConnected || isLoading) && styles.disabledButton
          ]}
          disabled={syncStatus?.isSyncing || !isConnected || isLoading}
          onPress={handleCategoriesOnlySync}
        >
          <MaterialIcons name="category" size={16} color="#ffffff" />
          <Text style={styles.buttonText}>Categories Only</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#ffffff',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
  },
  debugToggle: {
    padding: 8,
  },
  buttonContainer: {
    flexDirection: 'row',
    marginTop: 16,
  },
  syncButton: {
    backgroundColor: '#4caf50',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  disabledButton: {
    backgroundColor: '#a5d6a7',
  },
  buttonText: {
    color: '#ffffff',
    fontWeight: '600',
    marginLeft: 4,
  },
  statusContainer: {
    marginTop: 8,
  },
  loadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
  },
  statusRow: {
    flexDirection: 'row',
    marginBottom: 8,
  },
  statusLabel: {
    width: 80,
    fontWeight: '500',
    color: '#666666',
  },
  statusValue: {
    flex: 1,
    color: '#333333',
  },
  syncing: {
    color: '#2196f3',
  },
  error: {
    color: '#f44336',
  },
  offlineMessage: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#ffebee',
    padding: 8,
    borderRadius: 4,
    marginBottom: 12,
  },
  offlineText: {
    color: '#f44336',
    marginLeft: 8,
    fontSize: 12,
  },
  statusText: {
    color: '#666666',
    fontStyle: 'italic',
  },
  divider: {
    height: 1,
    backgroundColor: '#e0e0e0',
    marginVertical: 8,
  },
  debugTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    marginBottom: 8,
  },
  debugButtonRow: {
    flexDirection: 'row',
    marginTop: 8,
  },
  debugButton: {
    flex: 1,
    padding: 8,
    borderRadius: 4,
    alignItems: 'center',
    marginHorizontal: 4,
  },
  debugButtonText: {
    color: '#ffffff',
    fontWeight: '600',
    fontSize: 12,
  },
});

export default ModernCatalogSyncStatus; 