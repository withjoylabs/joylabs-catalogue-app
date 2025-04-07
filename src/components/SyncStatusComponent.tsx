import React, { useState, useEffect, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, ScrollView } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import catalogSyncService, { SyncStatus } from '../database/catalogSync';
import logger from '../utils/logger';
import { formatDistanceToNow } from 'date-fns';
import * as Network from 'expo-network';
import { FontAwesome5 } from '@expo/vector-icons';
import api from '../api';
import ProgressBar from 'react-native-progress/Bar';
import * as modernDb from '../database/modernDb';
import * as SecureStore from 'expo-secure-store';

// Define interface for merchant info and location data
interface MerchantInfo {
  id: string;
  businessName: string;
  country?: string;
  languageCode?: string;
  currency?: string;
  status?: string;
  mainLocationId?: string;
}

interface Location {
  id: string;
  name: string;
  merchantId?: string;
  address?: string;
  status?: string;
  type?: string;
}

const SyncStatusComponent: React.FC = () => {
  const [syncStatus, setSyncStatus] = useState<SyncStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [apiTestResult, setApiTestResult] = useState<string | null>(null);
  const [showDebugOptions, setShowDebugOptions] = useState(false);
  const [autoSyncEnabled, setAutoSyncEnabled] = useState(false);
  const [dbDebugResult, setDbDebugResult] = useState<string | null>(null);
  const [skipCategorySync, setSkipCategorySync] = useState(false);
  const [merchantInfo, setMerchantInfo] = useState<MerchantInfo | null>(null);
  const [locations, setLocations] = useState<Location[]>([]);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Initialize sync service and fetch merchant data
  useEffect(() => {
    const init = async () => {
      try {
        setLoading(true);
        await catalogSyncService.initialize();
        await refreshSyncStatus();
        await fetchMerchantData();
      } catch (err) {
        setError(`Error initializing sync service: ${err instanceof Error ? err.message : String(err)}`);
        logger.error('SyncStatusComponent', 'Failed to initialize sync service', { error: err });
      } finally {
        setLoading(false);
      }
    };

    init();

    // Set up polling for sync status - but only poll frequently when actually syncing
    // Otherwise, use a much longer interval to avoid excessive API calls
    intervalRef.current = setInterval(async () => {
      // During active sync, check status more frequently (every 1 second)
      if (syncing) {
        await refreshSyncStatus();
      } else {
        // When not syncing, only refresh status every minute at most
        // We can still use the syncing flag to limit DB calls
        const now = Date.now();
        const oneMinute = 60 * 1000;
        if (now % oneMinute < 1000) { // Only check once per minute
          await refreshSyncStatus();
        }
      }
    }, syncing ? 1000 : 5000); // Check more frequently when syncing, else every 5 seconds (and filtered)

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [syncing]);

  // Fetch merchant and location data from the database
  const fetchMerchantData = async () => {
    try {
      const db = await modernDb.getDatabase();
      
      // First check if the tables exist
      try {
        // Ensure merchant_info table exists
        await db.runAsync(`CREATE TABLE IF NOT EXISTS merchant_info (
          id TEXT PRIMARY KEY NOT NULL,
          business_name TEXT,
          country TEXT,
          language_code TEXT,
          currency TEXT,
          status TEXT,
          main_location_id TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          logo_url TEXT,
          data TEXT
        )`);
        
        // Ensure locations table exists
        await db.runAsync(`CREATE TABLE IF NOT EXISTS locations (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT,
          merchant_id TEXT,
          address TEXT,
          timezone TEXT,
          phone_number TEXT,
          business_name TEXT,
          business_email TEXT,
          website_url TEXT,
          description TEXT,
          status TEXT,
          type TEXT,
          logo_url TEXT,
          created_at TEXT,
          last_updated TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          data TEXT
        )`);
      } catch (tableError) {
        logger.error('SyncStatusComponent', 'Error ensuring tables exist', { error: tableError });
      }
      
      // Fetch merchant info
      const merchantRows = await db.getAllAsync(
        'SELECT id, business_name as businessName, country, language_code as languageCode, ' +
        'currency, status, main_location_id as mainLocationId FROM merchant_info LIMIT 1'
      );
      
      if (merchantRows && merchantRows.length > 0) {
        setMerchantInfo(merchantRows[0] as MerchantInfo);
      }
      
      // Fetch locations
      const locationRows = await db.getAllAsync(
        'SELECT id, name, merchant_id as merchantId, status, type FROM locations ORDER BY name'
      );
      
      if (locationRows && locationRows.length > 0) {
        setLocations(locationRows as Location[]);
      }
    } catch (err) {
      logger.error('SyncStatusComponent', 'Failed to fetch merchant data', { error: err });
    }
  };

  const refreshSyncStatus = async () => {
    try {
      // Only get status from database, no API calls
      const status = await catalogSyncService.getSyncStatus();
      setSyncStatus(status);
      setSyncing(status.isSyncing);
    } catch (err) {
      setError(`Error getting sync status: ${err instanceof Error ? err.message : String(err)}`);
      logger.error('SyncStatusComponent', 'Failed to get sync status', { error: err });
    }
  };

  // Toggle auto sync feature
  const toggleAutoSync = async () => {
    const newValue = !autoSyncEnabled;
    setAutoSyncEnabled(newValue);
    catalogSyncService.setAutoSync(newValue);
  };

  const handleSync = async (fullSync = true) => {
    try {
      setLoading(true);
      setError(null);
      
      // Check token before attempting sync
      const token = await SecureStore.getItemAsync('square_access_token');
      if (!token) {
        setError('Authentication failed: No Square token found. Please log in first.');
        setLoading(false);
        return;
      }
      
      if (fullSync) {
        await catalogSyncService.forceFullSync(skipCategorySync);
      } else {
        await catalogSyncService.syncCategories();
      }
      
      // Refresh the sync status and merchant data
      await refreshSyncStatus();
      await fetchMerchantData();
    } catch (err) {
      // Extract meaningful error from the error object
      let errorMessage = `Sync failed: ${err instanceof Error ? err.message : String(err)}`;
      
      // Check if it's an authentication error
      if (errorMessage.includes('authentication') || errorMessage.includes('token')) {
        errorMessage = 'Authentication error: Your Square connection may have expired. Please log in again.';
      }
      
      setError(errorMessage);
      logger.error('SyncStatusComponent', 'Sync error', { error: err });
    } finally {
      setLoading(false);
    }
  };

  const resetSync = async () => {
    try {
      setError(null);
      await catalogSyncService.resetSyncStatus();
      await refreshSyncStatus();
    } catch (err) {
      setError(`Error resetting sync: ${err instanceof Error ? err.message : String(err)}`);
      logger.error('SyncStatusComponent', 'Reset error', { error: err });
    }
  };

  const testApiConnection = async () => {
    try {
      setApiTestResult('Testing API connections...');
      setError(null);
      
      // Use direct Network call to check connectivity
      const networkState = await Network.getNetworkStateAsync();
      
      if (!networkState.isConnected) {
        setApiTestResult(`Network connection failed: Connected: ${networkState.isConnected}`);
        return;
      }
      
      // Get access token
      const accessToken = await SecureStore.getItemAsync('square_access_token');
      if (!accessToken) {
        setApiTestResult('No access token found - please log in to Square');
        return;
      }
      
      // Test the categories endpoint
      const categoriesResponse = await fetch('https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/v2/catalog/list-categories', {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
          'Cache-Control': 'no-cache'
        }
      });
      
      // Test the search endpoint
      const searchResponse = await fetch('https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/v2/catalog/search', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
          'Cache-Control': 'no-cache'
        },
        body: JSON.stringify({
          objectTypes: ["TAX", "MODIFIER", "CATEGORY", "ITEM"],
          limit: 10 // Just test with a small limit
        })
      });
      
      const categoriesOk = categoriesResponse.ok;
      const searchOk = searchResponse.ok;
      
      // Get text of search response to see what's coming back
      const searchText = await searchResponse.text();
      const searchData = searchText ? JSON.parse(searchText) : null;
      const hasObjects = searchData && Array.isArray(searchData.objects) && searchData.objects.length > 0;
      
      let result = 'API Test Results:\n';
      result += `• Network: Connected\n`;
      result += `• Categories API: ${categoriesOk ? '✓' : '✗'} (${categoriesResponse.status})\n`;
      result += `• Search API: ${searchOk ? '✓' : '✗'} (${searchResponse.status})\n`;
      result += `• Search returned objects: ${hasObjects ? `✓ (${searchData.objects.length})` : '✗'}\n`;
      result += `• Token: ${accessToken ? '✓ Present' : '✗ Missing'} (${accessToken ? accessToken.substring(0, 10) + '...' : 'N/A'})`;
      
      setApiTestResult(result);
    } catch (err) {
      setApiTestResult(`Error testing API: ${err instanceof Error ? err.message : String(err)}`);
      logger.error('SyncStatusComponent', 'API test error', { error: err });
    }
  };

  // Replace debugDatabase function
  const debugDatabase = async () => {
    try {
      setDbDebugResult('Checking database...');
      const result = await modernDb.checkDatabaseContent();

      // Create a detailed summary
      let summary = `Database contains:\n`;
      summary += `• ${result.categories.count} categories\n`;
      summary += `• ${result.items.count} items\n`;
      summary += `• ${result.taxes.count} taxes\n`;
      summary += `• ${result.modifiers.count} modifiers\n\n`;

      if (result.categories.sample.length > 0) {
        summary += 'Sample Categories:\n';
        result.categories.sample.forEach((cat, i) => {
          summary += `${i+1}. ${cat.name} (${cat.id})\n`;
        });
        summary += '\n';
      }

      if (result.items.sample.length > 0) {
        summary += 'Sample Items:\n';
        result.items.sample.forEach((item, i) => {
          summary += `${i+1}. ${item.name} (${item.id})\n`;
        });
        summary += '\n';
      }

      if (result.taxes.sample.length > 0) {
        summary += 'Sample Taxes:\n';
        result.taxes.sample.forEach((tax, i) => {
          summary += `${i+1}. ${tax.name} (${tax.percentage}%)\n`;
        });
        summary += '\n';
      }

      if (result.modifiers.sample.length > 0) {
        summary += 'Sample Modifiers:\n';
        result.modifiers.sample.forEach((mod, i) => {
          summary += `${i+1}. ${mod.name} (${mod.price_amount || 0} ${mod.price_currency || 'USD'})\n`;
        });
      }

      setDbDebugResult(summary);
    } catch (err) {
      setDbDebugResult(`Error checking database: ${err instanceof Error ? err.message : String(err)}`);
      logger.error('SyncStatusComponent', 'Database debug error', { error: err });
    }
  };

  // Render sync progress
  const renderProgress = () => {
    if (!syncStatus) return null;
    
    const { syncProgress, syncTotal, syncType } = syncStatus;
    
    // Don't show progress if not syncing
    if (!syncing) return null;
    
    // Don't show progress if we don't have a total
    if (syncTotal <= 0) return null;
    
    const progressPercentage = Math.min(100, Math.round((syncProgress / syncTotal) * 100));
    
    return (
      <View style={styles.progressContainer}>
        <Text style={styles.progressText}>
          {syncType === 'categories' ? 'Syncing categories' : 'Syncing items'}: {syncProgress} / {syncTotal} ({progressPercentage}%)
        </Text>
        <ProgressBar
          progress={progressPercentage / 100}
          width={null}
          height={10}
          color="#3498db"
          borderRadius={5}
          style={styles.progressBar}
        />
      </View>
    );
  };

  const renderSyncProgress = () => {
    if (!syncStatus || !syncStatus.syncProgress) return null;
    
    // For large catalogs, show estimated percentage
    let progressText = '';
    if (syncStatus.syncType === 'full' && syncStatus.syncProgress > 0) {
      // We now have 4 object types, so our estimate might be larger
      const estimatedTotal = 20000; // Approximate catalog size including all object types
      const percentComplete = Math.min(100, Math.round((syncStatus.syncProgress / estimatedTotal) * 100));
      progressText = `${syncStatus.syncProgress} objects (~${percentComplete}% of catalog)`;
    } else if (syncStatus.syncType === 'categories') {
      progressText = `${syncStatus.syncProgress} categories`;
    } else {
      progressText = `${syncStatus.syncProgress} objects`;
    }
    
    return (
      <Text style={styles.statusText}>
        Progress: {progressText}
      </Text>
    );
  };

  const renderSyncOptions = () => {
    if (syncStatus?.isSyncing) return null;
    
    return (
      <View style={styles.optionsContainer}>
        <View style={styles.checkboxContainer}>
          <TouchableOpacity
            style={styles.checkbox}
            onPress={() => setSkipCategorySync(!skipCategorySync)}
          >
            <Text style={skipCategorySync ? styles.checkboxChecked : styles.checkboxUnchecked}>
              {skipCategorySync ? '✓' : ''}
            </Text>
          </TouchableOpacity>
          <Text style={styles.checkboxLabel}>Skip category sync (faster)</Text>
        </View>
      </View>
    );
  };

  // Render merchant information
  const renderMerchantInfo = () => {
    if (!merchantInfo) return null;
    
    return (
      <View style={styles.merchantContainer}>
        <Text style={styles.merchantTitle}>Merchant Information</Text>
        <View style={styles.merchantDetail}>
          <Text style={styles.merchantLabel}>Business Name:</Text>
          <Text style={styles.merchantValue}>{merchantInfo.businessName}</Text>
        </View>
        {merchantInfo.country && (
          <View style={styles.merchantDetail}>
            <Text style={styles.merchantLabel}>Country:</Text>
            <Text style={styles.merchantValue}>{merchantInfo.country}</Text>
          </View>
        )}
        {merchantInfo.currency && (
          <View style={styles.merchantDetail}>
            <Text style={styles.merchantLabel}>Currency:</Text>
            <Text style={styles.merchantValue}>{merchantInfo.currency}</Text>
          </View>
        )}
        <View style={styles.merchantDetail}>
          <Text style={styles.merchantLabel}>Merchant ID:</Text>
          <Text style={styles.merchantValue}>{merchantInfo.id}</Text>
        </View>
        <View style={styles.merchantDetail}>
          <Text style={styles.merchantLabel}>Status:</Text>
          <Text style={[styles.merchantValue, 
            merchantInfo.status === 'ACTIVE' ? styles.activeStatus : 
            merchantInfo.status === 'INACTIVE' ? styles.inactiveStatus : styles.merchantValue
          ]}>
            {merchantInfo.status || 'Unknown'}
          </Text>
        </View>
      </View>
    );
  };

  // Render locations information
  const renderLocations = () => {
    if (!locations || locations.length === 0) return null;
    
    return (
      <View style={styles.locationsContainer}>
        <Text style={styles.locationsTitle}>Locations ({locations.length})</Text>
        <ScrollView style={styles.locationsList} nestedScrollEnabled={true}>
          {locations.map((location, index) => (
            <View key={location.id} style={styles.locationItem}>
              <View style={styles.locationHeader}>
                <Text style={styles.locationName}>{location.name}</Text>
                <Text style={[styles.locationStatus, 
                  location.status === 'ACTIVE' ? styles.activeStatus : 
                  location.status === 'INACTIVE' ? styles.inactiveStatus : styles.locationStatus
                ]}>
                  {location.status || 'Unknown'}
                </Text>
              </View>
              <Text style={styles.locationId}>ID: {location.id}</Text>
              {location.type && <Text style={styles.locationType}>Type: {location.type}</Text>}
            </View>
          ))}
        </ScrollView>
      </View>
    );
  };

  if (loading && !syncStatus) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0000ff" />
        <Text style={styles.loadingText}>Loading sync status...</Text>
      </View>
    );
  }
  
  return (
    <View style={styles.container}>
      {/* Status information */}
      <View style={styles.statusContainer}>
        <Text style={styles.title}>Catalog Sync Status</Text>
        <Text style={styles.subtitle}>
          Sync your Square catalog (categories, items, taxes, and modifiers) to use offline
        </Text>
        <Text style={styles.lastSyncText}>{syncStatus?.lastSyncTime ? new Date(syncStatus.lastSyncTime).toLocaleString() : 'Never synced'}</Text>
        
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Status:</Text>
          <Text style={styles.statusValue}>
            {syncing ? (
              <Text style={styles.syncingText}>Syncing...</Text>
            ) : error ? (
              <Text style={styles.errorText}>Error</Text>
            ) : (
              <Text style={styles.readyText}>Ready</Text>
            )}
          </Text>
        </View>
        
        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorTitle}>Error:</Text>
            <Text style={styles.errorMessage}>{error}</Text>
          </View>
        )}
        
        {renderProgress()}
        {syncStatus && syncStatus.isSyncing && renderSyncProgress()}
        
        {/* Merchant and location information */}
        {!syncing && renderMerchantInfo()}
        {!syncing && renderLocations()}
      </View>
      
      {renderSyncOptions()}
      
      {/* Action buttons */}
      <View style={styles.buttonContainer}>
        <TouchableOpacity 
          style={[styles.syncButton, syncing && styles.disabledButton]} 
          onPress={() => handleSync(true)}
          disabled={syncing}
        >
          <Text style={styles.buttonText}>Full Sync</Text>
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={[styles.syncButton, styles.categoriesButton, syncing && styles.disabledButton]} 
          onPress={() => handleSync(false)}
          disabled={syncing}
        >
          <Text style={styles.buttonText}>Categories Only</Text>
        </TouchableOpacity>
        
        {/* Debug toggle button */}
        <TouchableOpacity
          style={styles.debugButton}
          onPress={() => setShowDebugOptions(!showDebugOptions)}
        >
          <FontAwesome5 name="bug" size={16} color="#fff" />
        </TouchableOpacity>
      </View>
      
      {/* Debug options */}
      {showDebugOptions && (
        <View style={styles.debugContainer}>
          <Text style={styles.debugTitle}>Debug Options</Text>
          
          <View style={styles.debugButtonsContainer}>
            <TouchableOpacity 
              style={[styles.debugActionButton, styles.resetButton]} 
              onPress={resetSync}
              disabled={syncing}
            >
              <Text style={styles.buttonText}>Reset Sync</Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.debugActionButton} 
              onPress={testApiConnection}
              disabled={syncing}
            >
              <Text style={styles.buttonText}>Test API</Text>
            </TouchableOpacity>
          </View>
          
          {/* Debug Database Button */}
          <TouchableOpacity 
            style={[styles.debugActionButton, styles.databaseButton]} 
            onPress={debugDatabase}
            disabled={syncing}
          >
            <Text style={styles.buttonText}>Debug Database</Text>
          </TouchableOpacity>
          
          {/* Database Debug Results */}
          {dbDebugResult && (
            <View style={styles.debugResultContainer}>
              <Text style={styles.debugResultText}>{dbDebugResult}</Text>
            </View>
          )}
          
          {/* Auto Sync Toggle */}
          <View style={styles.toggleContainer}>
            <Text style={styles.toggleLabel}>Automatic Background Sync:</Text>
            <TouchableOpacity
              style={[
                styles.toggleButton,
                autoSyncEnabled ? styles.toggleEnabled : styles.toggleDisabled
              ]}
              onPress={toggleAutoSync}
              disabled={syncing}
            >
              <Text style={styles.toggleText}>
                {autoSyncEnabled ? 'Enabled' : 'Disabled'}
              </Text>
            </TouchableOpacity>
          </View>
          
          {apiTestResult && (
            <View style={styles.apiResultContainer}>
              <Text style={styles.apiResultText}>{apiTestResult}</Text>
            </View>
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
    marginBottom: 16,
  },
  statusContainer: {
    marginBottom: 16,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  statusLabel: {
    fontWeight: 'bold',
    fontSize: 16,
  },
  statusValue: {
    fontSize: 16,
  },
  syncingText: {
    color: '#f59e0b',
    fontWeight: 'bold',
  },
  readyText: {
    color: '#10b981',
    fontWeight: 'bold',
  },
  errorText: {
    color: '#ef4444',
    fontWeight: 'bold',
  },
  errorContainer: {
    backgroundColor: '#fee2e2',
    padding: 12,
    borderRadius: 6,
    marginTop: 8,
    marginBottom: 8,
  },
  errorTitle: {
    color: '#b91c1c',
    fontSize: 14,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  errorMessage: {
    color: '#b91c1c',
    fontSize: 14,
  },
  progressContainer: {
    marginTop: 8,
  },
  progressText: {
    fontSize: 14,
    marginBottom: 4,
  },
  progressBar: {
    height: 10,
    borderRadius: 5,
  },
  buttonContainer: {
    flexDirection: 'row',
    gap: 12,
  },
  syncButton: {
    flex: 1,
    backgroundColor: '#3b82f6',
    padding: 12,
    borderRadius: 6,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
  },
  categoriesButton: {
    backgroundColor: '#8b5cf6',
  },
  buttonText: {
    color: 'white',
    fontWeight: 'bold',
    fontSize: 16,
  },
  disabledButton: {
    opacity: 0.5,
  },
  debugButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 10,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1,
  },
  debugContainer: {
    marginTop: 20,
    backgroundColor: '#f5f5f5',
    borderRadius: 10,
    padding: 15,
    borderWidth: 1,
    borderColor: '#ddd',
  },
  debugTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 10,
    color: '#555',
  },
  debugButtonsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  debugActionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#5C6BC0',
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 15,
    flex: 1,
    marginRight: 10,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1,
  },
  resetButton: {
    backgroundColor: '#FF7043',
    marginRight: 0,
    marginLeft: 10,
  },
  loadingText: {
    marginTop: 8,
    fontSize: 14,
    color: '#6b7280',
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#6b7280',
  },
  lastSyncText: {
    fontSize: 14,
    marginBottom: 8,
  },
  apiResultContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: '#f5f5f5',
    borderRadius: 6,
  },
  apiResultText: {
    color: '#6b7280',
    fontSize: 14,
  },
  toggleContainer: {
    marginTop: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  toggleLabel: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#555',
  },
  toggleButton: {
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 4,
    minWidth: 80,
    alignItems: 'center',
  },
  toggleEnabled: {
    backgroundColor: '#4CAF50',
  },
  toggleDisabled: {
    backgroundColor: '#F44336',
  },
  toggleText: {
    color: 'white',
    fontWeight: 'bold',
  },
  databaseButton: {
    backgroundColor: '#2196F3',
    marginTop: 10,
  },
  debugResultContainer: {
    marginTop: 10,
    padding: 12,
    backgroundColor: '#f0f0f0',
    borderRadius: 6,
    borderLeftWidth: 4,
    borderLeftColor: '#2196F3',
  },
  debugResultText: {
    color: '#333',
    fontSize: 14,
  },
  statusText: {
    marginTop: 8,
    fontSize: 14,
    color: '#6b7280',
  },
  optionsContainer: {
    marginBottom: 12,
  },
  checkboxContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  checkbox: {
    width: 20,
    height: 20,
    borderWidth: 1,
    borderColor: '#6b7280',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 8,
    borderRadius: 4,
  },
  checkboxChecked: {
    color: '#007AFF',
    fontWeight: 'bold',
  },
  checkboxUnchecked: {
    color: 'transparent',
  },
  checkboxLabel: {
    fontSize: 14,
    color: '#6b7280',
  },
  // Merchant info styles
  merchantContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: '#f0f7ff',
    borderRadius: 8,
    borderLeftWidth: 3,
    borderLeftColor: '#3b82f6',
  },
  merchantTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#3b82f6',
  },
  merchantDetail: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  merchantLabel: {
    fontSize: 14,
    color: '#4b5563',
    fontWeight: '500',
  },
  merchantValue: {
    fontSize: 14,
    color: '#1f2937',
  },
  
  // Locations styles
  locationsContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: '#f0f9ff',
    borderRadius: 8,
    borderLeftWidth: 3,
    borderLeftColor: '#0ea5e9',
  },
  locationsTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#0ea5e9',
  },
  locationsList: {
    maxHeight: 150,
  },
  locationItem: {
    marginBottom: 10,
    padding: 8,
    backgroundColor: 'white',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#e5e7eb',
  },
  locationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  locationName: {
    fontSize: 15,
    fontWeight: 'bold',
    color: '#111827',
  },
  locationStatus: {
    fontSize: 12,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    overflow: 'hidden',
  },
  locationId: {
    fontSize: 12,
    color: '#6b7280',
    marginBottom: 2,
  },
  locationType: {
    fontSize: 12,
    color: '#6b7280',
  },
  
  // Status styles
  activeStatus: {
    color: '#059669',
    backgroundColor: '#d1fae5',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    overflow: 'hidden',
  },
  inactiveStatus: {
    color: '#dc2626',
    backgroundColor: '#fee2e2',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    overflow: 'hidden',
  },
});

export default SyncStatusComponent; 