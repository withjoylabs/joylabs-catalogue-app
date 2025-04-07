import React, { useState, useEffect, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, Platform } from 'react-native';
import { MaterialIcons, FontAwesome5 } from '@expo/vector-icons';
import catalogSyncService, { SyncStatus } from '../database/catalogSync';
import logger from '../utils/logger';
import { formatDistanceToNow } from 'date-fns';
import * as Network from 'expo-network';
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

// Update SyncStatus type if needed locally, or rely on imported one if modified
type CurrentSyncStatus = SyncStatus & { 
  last_page_cursor?: string | null; 
};

const SyncStatusComponent: React.FC = () => {
  const [status, setStatus] = useState<CurrentSyncStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showDebugOptions, setShowDebugOptions] = useState(false);
  const [apiTestResult, setApiTestResult] = useState<string | null>(null);
  const [dbDebugResult, setDbDebugResult] = useState<string | null>(null);
  const [autoSyncEnabled, setAutoSyncEnabled] = useState(false);
  const [skipCategorySync, setSkipCategorySync] = useState(false);
  const [merchantInfo, setMerchantInfo] = useState<MerchantInfo | null>(null);
  const [locations, setLocations] = useState<Location[]>([]);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Fetch initial status and set up polling
  const refreshStatus = useCallback(async () => {
    try {
      const currentStatus = await catalogSyncService.getSyncStatus();
      setStatus(currentStatus as CurrentSyncStatus); // Cast might be needed if type not updated in service
      setError(null); // Clear general error on successful status fetch
    } catch (err) {
      const msg = `Error fetching sync status: ${err instanceof Error ? err.message : String(err)}`;
      logger.error('SyncStatusComponent', msg, { error: err });
      setError(msg);
      setStatus(null); // Clear status on error
    } finally {
      setLoading(false); // Stop initial loading indicator
    }
  }, []);

  useEffect(() => {
    refreshStatus(); // Initial fetch
    
    // Poll for status updates, especially when syncing
    const intervalId = setInterval(() => {
      // Only refresh if the component thinks a sync might be running or finished recently
      if (status?.isSyncing || loading) {
         refreshStatus();
      }
      // Add less frequent polling even when idle if desired
      // else if (Date.now() % 60000 < 1000) { // e.g., check once a minute
      //   refreshStatus();
      // }
    }, 2000); // Poll every 2 seconds when potentially syncing

    return () => clearInterval(intervalId);
  }, [refreshStatus, status?.isSyncing, loading]); // Re-run if sync state changes

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

  // Toggle auto sync feature
  const toggleAutoSync = async () => {
    const newValue = !autoSyncEnabled;
    setAutoSyncEnabled(newValue);
    catalogSyncService.setAutoSync(newValue);
  };

  // --- Action Handlers ---
  const handleStartSync = async () => {
    logger.info('SyncStatusComponent', 'User initiated full sync');
    setLoading(true); // Show loading while sync starts
    setError(null);
    try {
      // No need to await this, let it run in the background
      catalogSyncService.runFullSync(); 
      // Refresh status almost immediately to show it's syncing
      setTimeout(refreshStatus, 500); 
    } catch (err) {
       const msg = `Failed to start sync: ${err instanceof Error ? err.message : String(err)}`;
       logger.error('SyncStatusComponent', msg, { error: err });
       setError(msg);
       setLoading(false);
    }
    // Loading will be set to false by the polling useEffect finding isSyncing=false
  };

  const handleResetSync = async () => {
    logger.info('SyncStatusComponent', 'User initiated sync reset');
    Alert.alert(
      'Reset Sync Status',
      'Are you sure? This will clear any sync errors and allow a new sync to start from the beginning.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Reset',
          style: 'destructive',
          onPress: async () => {
            try {
              await catalogSyncService.resetSyncStatus();
              await refreshStatus(); // Refresh UI
            } catch (err) {
              const msg = `Failed to reset sync: ${err instanceof Error ? err.message : String(err)}`;
              logger.error('SyncStatusComponent', msg, { error: err });
              setError(msg);
            }
          },
        },
      ]
    );
  };

  // --- Debug Handlers ---
  const handleTestApi = async () => {
    setApiTestResult('Testing...');
    try {
      // Simple test: Fetch first page with limit 1
      const response = await api.fetchCatalogPage(1, null, 'ITEM');
      setApiTestResult(`API Test OK: Success=${response.success}, Objects=${response.objects?.length}, Cursor=${response.cursor ? 'Yes' : 'No'}`);
    } catch (err) {
      const msg = `API Test Failed: ${err instanceof Error ? err.message : String(err)}`;
      logger.error('SyncStatusComponent', msg, { error: err });
      setApiTestResult(msg);
    }
  };

  const handleDebugDb = async () => {
    setDbDebugResult('Checking...');
    try {
      const result = await modernDb.checkDatabaseContent();
      let summary = 'DB Counts:\n';
      result.counts.forEach(row => {
        summary += `• ${row.table_name}: ${row.count}\n`;
      });
      setDbDebugResult(summary);
    } catch (err) {
      const msg = `DB Check Failed: ${err instanceof Error ? err.message : String(err)}`;
      logger.error('SyncStatusComponent', msg, { error: err });
      setDbDebugResult(msg);
    }
  };

  // --- Render Logic ---
  const renderStatusDetails = () => {
    if (!status) return <Text style={styles.statusText}>Loading status...</Text>;

    let statusText = 'Idle';
    let statusStyle = styles.idleText;
    if (status.isSyncing) {
      statusText = 'Syncing...';
      statusStyle = styles.syncingText;
    } else if (status.syncError) {
      statusText = 'Error';
      statusStyle = styles.errorText;
    } else if (status.lastSyncTime) {
      statusText = 'Synced';
      statusStyle = styles.syncedText;
    }

    return (
      <View>
        <View style={styles.statusRow}>
          <Text style={styles.statusLabel}>Status:</Text>
          <Text style={[styles.statusValue, statusStyle]}>{statusText}</Text>
        </View>
        
        {status.isSyncing && status.syncProgress > 0 && (
          <Text style={styles.progressInfo}>Processed {status.syncProgress} objects...</Text>
          // Add ProgressBar if desired, but total is unknown during sync
        )}

        {status.lastSyncTime && !status.isSyncing && (
           <Text style={styles.lastSyncText}>
             Last Sync: {formatDistanceToNow(new Date(status.lastSyncTime), { addSuffix: true })}
           </Text>
        )}
        
        {status.syncError && (
          <View style={styles.errorDisplay}>
            <Text style={styles.errorTitle}>Sync Error:</Text>
            <Text style={styles.errorMessage}>{status.syncError}</Text>
          </View>
        )}
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
        <View style={styles.locationsList}>
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
        </View>
      </View>
    );
  };

  // --- Main Return ---
  if (loading && !status) {
    return (
      <View style={[styles.container, styles.loadingContainer]}>
        <ActivityIndicator size="large" color="#3b82f6" />
        <Text style={styles.loadingText}>Loading Sync Info...</Text>
      </View>
    );
  }
  
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Catalog Synchronization</Text>
      <Text style={styles.subtitle}>
        Download the full Square catalog for offline use.
      </Text>

      {renderStatusDetails()}
      
      {/* General component errors (e.g., failed to fetch status) */} 
      {error && !status?.syncError && (
         <View style={styles.errorDisplay}>
            <Text style={styles.errorTitle}>Component Error:</Text>
            <Text style={styles.errorMessage}>{error}</Text>
          </View>
      )}

      {/* Action Buttons */} 
      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[styles.actionButton, styles.syncButton, (status?.isSyncing || loading) && styles.disabledButton]}
          onPress={handleStartSync}
          disabled={status?.isSyncing || loading}
        >
          {status?.isSyncing ? (
             <ActivityIndicator size="small" color="#fff" />
          ) : (
             <FontAwesome5 name="sync-alt" size={16} color="#fff" />
          )}
          <Text style={styles.buttonText}>{status?.isSyncing ? 'Sync in Progress' : 'Start Full Sync'}</Text>
        </TouchableOpacity>
        
        {/* Debug Toggle Button */} 
         <TouchableOpacity
          style={styles.debugToggleButton}
          onPress={() => setShowDebugOptions(!showDebugOptions)}
        >
          <FontAwesome5 name="bug" size={18} color={showDebugOptions ? "#3b82f6" : "#6b7280"} />
        </TouchableOpacity>
      </View>

      {/* Debug Options Area */} 
      {showDebugOptions && (
        <View style={styles.debugContainer}>
          <Text style={styles.debugTitle}>Debug Options</Text>
          <View style={styles.debugButtonRow}>
            <TouchableOpacity 
              style={[styles.debugAction, styles.resetButton]} 
              onPress={handleResetSync}
              disabled={status?.isSyncing}
            >
              <Text style={styles.debugButtonText}>Reset Sync Status</Text>
            </TouchableOpacity>
             <TouchableOpacity 
              style={styles.debugAction} 
              onPress={handleTestApi}
              disabled={status?.isSyncing}
            >
              <Text style={styles.debugButtonText}>Test API</Text>
            </TouchableOpacity>
            <TouchableOpacity 
              style={styles.debugAction} 
              onPress={handleDebugDb}
              disabled={status?.isSyncing}
            >
              <Text style={styles.debugButtonText}>Check DB</Text>
            </TouchableOpacity>
          </View>
          {apiTestResult && (
            <View style={styles.debugResultBox}><Text style={styles.debugResultText}>{apiTestResult}</Text></View>
          )}
          {dbDebugResult && (
            <View style={styles.debugResultBox}><Text style={styles.debugResultText}>{dbDebugResult}</Text></View>
          )}
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 8,
    marginVertical: 10,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 3,
  },
  loadingContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 150,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#6b7280',
  },
  title: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 4,
    color: '#1f2937',
  },
  subtitle: {
    fontSize: 14,
    color: '#6b7280',
    marginBottom: 16,
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
    paddingVertical: 8,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: '#e5e7eb',
  },
  statusLabel: {
    fontSize: 15,
    color: '#4b5563',
    fontWeight: '500',
  },
  statusValue: {
    fontSize: 15,
    fontWeight: 'bold',
  },
  idleText: {
    color: '#6b7280',
  },
   syncingText: {
    color: '#f59e0b',
  },
  syncedText: {
     color: '#10b981',
  },
  errorText: {
     color: '#ef4444',
  },
  lastSyncText: {
    fontSize: 13,
    color: '#6b7280',
    marginBottom: 12,
    fontStyle: 'italic',
  },
  progressInfo: {
    fontSize: 13,
    color: '#4b5563',
    marginBottom: 8,
  },
  errorDisplay: {
    backgroundColor: '#fee2e2',
    padding: 10,
    borderRadius: 6,
    marginTop: 8,
    borderLeftWidth: 4,
    borderLeftColor: '#ef4444',
  },
  errorTitle: {
    fontWeight: 'bold',
    color: '#b91c1c',
    marginBottom: 4,
  },
  errorMessage: {
    color: '#b91c1c',
  },
  buttonRow: {
    flexDirection: 'row',
    marginTop: 20,
    alignItems: 'center',
  },
  actionButton: {
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 6,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
  },
  syncButton: {
    backgroundColor: '#3b82f6',
    flex: 1, // Take available space
  },
  buttonText: {
    color: '#fff',
    fontWeight: 'bold',
    fontSize: 16,
  },
  disabledButton: {
    opacity: 0.6,
  },
  debugToggleButton: {
    padding: 10,
    marginLeft: 12,
  },
  debugContainer: {
    marginTop: 16,
    padding: 12,
    backgroundColor: '#f3f4f6',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#e5e7eb',
  },
  debugTitle: {
    fontSize: 15,
    fontWeight: 'bold',
    marginBottom: 10,
    color: '#4b5563',
  },
  debugButtonRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 10,
  },
  debugAction: {
     backgroundColor: '#6b7280',
     paddingVertical: 8,
     paddingHorizontal: 12,
     borderRadius: 5,
     marginHorizontal: 4,
  },
  resetButton: {
     backgroundColor: '#ef4444',
  },
  debugButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  debugResultBox: {
    backgroundColor: '#e5e7eb',
    padding: 8,
    borderRadius: 4,
    marginTop: 8,
  },
  debugResultText: {
    fontSize: 12,
    color: '#1f2937',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
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
  },
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
  componentContainer: {
    flex: 1,
  },
  statusText: {
    marginTop: 8,
    fontSize: 14,
    color: '#6b7280',
  },
});

export default SyncStatusComponent; 