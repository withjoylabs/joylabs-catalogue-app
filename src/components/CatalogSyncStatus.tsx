import React, { useState, useCallback, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, TextInput, ScrollView } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import * as modernDb from '../database/modernDb';
import catalogSyncService from '../database/catalogSync';
import { useSquareAuth } from '../hooks/useSquareAuth';
import api, { directSquareApi } from '../api';
import logger from '../utils/logger';
import * as FileSystem from 'expo-file-system';

interface SyncStatus {
  lastSyncTime: string | null;
  isSyncing: boolean;
  syncError: string | null;
  syncProgress: number;
  syncTotal: number;
  syncType: string | null;
  syncAttempt: number;
}

interface LocationData {
  id: string;
  name: string;
  data?: string; // JSON string with full location data
}

// Component that displays catalog sync status and controls
export default function CatalogSyncStatus() {
  const [status, setStatus] = useState<SyncStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [showDebug, setShowDebug] = useState(false);
  const [isInspectingDb, setIsInspectingDb] = useState(false);
  const [dbItemCount, setDbItemCount] = useState({ categoryCount: 0, itemCount: 0 });
  const [isResettingDb, setIsResettingDb] = useState(false);
  const [locations, setLocations] = useState<LocationData[]>([]);
  const [isSyncingLocations, setIsSyncingLocations] = useState(false);
  const [expandedLocationIds, setExpandedLocationIds] = useState<string[]>([]);
  const { hasValidToken } = useSquareAuth();

  // Initialize the sync service when component mounts
  useEffect(() => {
    const initializeSyncService = async () => {
      try {
        logger.info('CatalogSyncStatus', 'Initializing catalog sync service');
        await catalogSyncService.initialize();
        // After initialization, fetch the status immediately
        fetchSyncStatus();
        fetchLocations();
      } catch (error) {
        logger.error('CatalogSyncStatus', 'Failed to initialize sync service', { error });
      }
    };
    
    initializeSyncService();
  }, []);

  // Fetch locations from database
  const fetchLocations = async () => {
    try {
      const locationsData = await modernDb.getAllLocations();
      
      // Get full location data for each location
      const enrichedLocations = await Promise.all(locationsData.map(async (location) => {
        try {
          // Get the full location data from the database
          const db = await modernDb.getDatabase();
          const fullLocationData = await db.getFirstAsync<{ data: string }>(
            'SELECT data FROM locations WHERE id = ?', 
            [location.id]
          );
          
          return {
            ...location,
            data: fullLocationData?.data
          };
        } catch (error) {
          logger.error('CatalogSyncStatus', `Failed to get full data for location ${location.id}`, { error });
          return location;
        }
      }));
      
      setLocations(enrichedLocations);
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to fetch locations', { error });
    }
  };

  // Toggle location expansion
  const toggleLocationExpansion = (locationId: string) => {
    setExpandedLocationIds(prevIds => {
      if (prevIds.includes(locationId)) {
        return prevIds.filter(id => id !== locationId);
      } else {
        return [...prevIds, locationId];
      }
    });
  };

  // Extract location details from the JSON string
  const getLocationDetails = (locationData?: string) => {
    if (!locationData) return null;
    
    try {
      return JSON.parse(locationData);
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to parse location data', { error });
      return null;
    }
  };

  // Format business hours for display
  const formatBusinessHours = (businessHours: any) => {
    if (!businessHours || !businessHours.periods || !Array.isArray(businessHours.periods)) {
      return 'No business hours available';
    }
    
    const daysOfWeek = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const sortedPeriods = [...businessHours.periods].sort((a, b) => 
      daysOfWeek.indexOf(a.day_of_week) - daysOfWeek.indexOf(b.day_of_week)
    );
    
    return sortedPeriods.map(period => (
      `${period.day_of_week}: ${period.start_local_time} - ${period.end_local_time}`
    )).join('\n');
  };

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
      fetchLocations();
      
      // No polling interval - we'll only update when actions are taken
      return () => {
        // No intervals to clear
      };
    }, [])
  );

  // Effect to auto-refresh status while syncing is in progress
  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;
    if (status?.isSyncing) {
      // Set up an interval to fetch status every second
      interval = setInterval(() => {
        logger.debug('CatalogSyncStatus', 'Auto-refreshing sync status...');
        fetchSyncStatus();
      }, 1000); // 1 second
    }

    // Cleanup function to clear the interval when sync is done or component unmounts
    return () => {
      if (interval) {
        clearInterval(interval);
      }
    };
  }, [status?.isSyncing]); // This effect depends only on the isSyncing status

  // Start a full catalog sync
  const startFullSync = async () => {
    try {
      if (!hasValidToken) {
        Alert.alert('Auth Required', 'Please connect to Square first');
        return;
      }
      
      logger.info('CatalogSyncStatus', 'Starting full sync process...');
      
      // Step 1: Sync locations silently and get the count.
      const locationsSynced = await syncLocationsOnly({ silent: true });
      
      // Step 2: Initialize the catalog sync service.
      await catalogSyncService.initialize();
      
      // Step 3: Run the full sync for items and categories and get the counts.
      const { itemCount, categoryCount } = await catalogSyncService.runFullSync();
      
      // Step 4: Show a consolidated success message.
      Alert.alert(
        'Full Sync Complete',
        `Successfully synced:\n- ${locationsSynced} Locations\n- ${categoryCount} Categories\n- ${itemCount} Items`,
        [{ text: 'OK' }]
      );

      // Step 5: Refresh the UI with the new data.
      await fetchSyncStatus();
      await fetchLocations();
      
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Failed to start full sync', { error });
      Alert.alert('Error', `Failed to start sync: ${error instanceof Error ? error.message : 'Unknown error'}`);
      // Also refresh status on error to clear is_syncing flag if needed
      await fetchSyncStatus();
      await fetchLocations();
    }
  };

  // Sync only locations
  const syncLocationsOnly = async (options?: { silent?: boolean }): Promise<number> => {
    try {
      if (!hasValidToken) {
        if (!options?.silent) {
        Alert.alert('Auth Required', 'Please connect to Square first');
        }
        return 0;
      }
      
      setIsSyncingLocations(true);
      let locationCount = 0;
      
      try {
        logger.info('CatalogSyncStatus', 'Starting locations sync');
        const response = await directSquareApi.fetchLocations();
        
        if (!response.success || !response.data?.locations) {
          const errorMessage = typeof response.error === 'string' ? response.error : 'Failed to fetch locations from Square API';
          throw new Error(errorMessage);
        }
        
        const locations = response.data.locations;
        locationCount = locations.length;

          const db = await modernDb.getDatabase();
          await db.withTransactionAsync(async () => {
          await db.runAsync('DELETE FROM locations'); // Clear old locations
              for (const location of locations) {
                  const addressStr = location.address ? JSON.stringify(location.address) : null;
                      await db.runAsync(`
                        INSERT INTO locations (
                id, name, merchant_id, address, timezone, phone_number, 
                business_name, business_email, website_url, logo_url, 
                description, status, type, created_at, last_updated, data
              ) 
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      `, [
              location.id,
              location.name,
              location.merchant_id,
                        addressStr,
              location.timezone,
              location.phone_number,
              location.business_name,
              location.business_email,
              location.website_url,
              location.logo_url,
              location.description,
              location.status,
              location.type,
              location.created_at,
                        new Date().toISOString(),
                        JSON.stringify(location)
                      ]);
                    }
        });
        
        if (!options?.silent) {
          Alert.alert('Success', `Successfully synced ${locationCount} locations.`);
        }
        await fetchLocations(); // Refresh locations list
        
      } catch (error) {
        logger.error('CatalogSyncStatus', 'Failed to sync locations', { error });
        if (!options?.silent) {
          Alert.alert('Error', `Failed to sync locations: ${error instanceof Error ? error.message : 'Unknown Error'}`);
        }
        // Re-throw if silent, so the calling function (full sync) knows it failed
        if (options?.silent) {
          throw error;
        }
      } finally {
        setIsSyncingLocations(false);
      }
      return locationCount;
    } catch (error) {
      logger.error('CatalogSyncStatus', 'Outer error in syncLocationsOnly', { error });
      setIsSyncingLocations(false);
       if (options?.silent) {
          throw error; // Propagate error for full sync to handle
       }
      return 0;
    }
  };

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
            try {
              setIsResettingDb(true);
              logger.warn('CatalogSyncStatus', 'User initiated complete database reset');
              
              await modernDb.resetDatabase();
              
      // Re-initialize sync service and refresh status
              await catalogSyncService.initialize();
              await fetchSyncStatus();
      await fetchLocations(); // Also refresh locations
              
              Alert.alert('Success', 'Database has been completely reset');

            } catch (error) {
              logger.error('CatalogSyncStatus', 'Failed to reset database', { error });
              Alert.alert('Error', 'Failed to reset database');
            } finally {
              setIsResettingDb(false);
            }
  };

  // Display locations section with expandable details
  const renderLocationItem = (location: LocationData) => {
    const isExpanded = expandedLocationIds.includes(location.id);
    const locationDetails = getLocationDetails(location.data);
    
    return (
      <View key={location.id} style={styles.locationItemContainer}>
        <TouchableOpacity 
          style={styles.locationItemHeader}
          onPress={() => toggleLocationExpansion(location.id)}
        >
          <Text style={styles.locationItemName}>{location.name}</Text>
          <Ionicons 
            name={isExpanded ? "chevron-up" : "chevron-down"} 
            size={20} 
            color="#555"
          />
        </TouchableOpacity>
        
        {isExpanded && locationDetails && (
          <View style={styles.locationDetailsContainer}>
            {locationDetails.business_name && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Business Name:</Text>
                <Text style={styles.detailValue}>{locationDetails.business_name}</Text>
              </View>
            )}
            
            {locationDetails.country && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Country:</Text>
                <Text style={styles.detailValue}>{locationDetails.country}</Text>
              </View>
            )}
            
            {locationDetails.currency && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Currency:</Text>
                <Text style={styles.detailValue}>{locationDetails.currency}</Text>
              </View>
            )}
            
            {locationDetails.website_url && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Website:</Text>
                <Text style={styles.detailValue}>{locationDetails.website_url}</Text>
              </View>
            )}
            
            {locationDetails.business_email && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Email:</Text>
                <Text style={styles.detailValue}>{locationDetails.business_email}</Text>
              </View>
            )}
            
            {locationDetails.business_hours && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Hours:</Text>
                <Text style={styles.detailValue}>
                  {formatBusinessHours(locationDetails.business_hours)}
                </Text>
              </View>
            )}
            
            {locationDetails.phone_number && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Phone:</Text>
                <Text style={styles.detailValue}>{locationDetails.phone_number}</Text>
              </View>
            )}
            
            {locationDetails.address && (
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Address:</Text>
                <Text style={styles.detailValue}>
                  {locationDetails.address.address_line_1}
                  {locationDetails.address.address_line_2 ? `, ${locationDetails.address.address_line_2}` : ''}
                  {`\n${locationDetails.address.locality}, ${locationDetails.address.administrative_district_level_1} ${locationDetails.address.postal_code}`}
                </Text>
              </View>
            )}
          </View>
        )}
      </View>
    );
  };

  // Render the main component
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
      <ScrollView style={styles.scrollContainer}>
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
        <Text style={styles.statusLabel}>Last Sync:</Text>
        <Text style={styles.statusValue}>{status?.lastSyncTime ? new Date(status.lastSyncTime).toLocaleString() : 'Never'}</Text>
      </View>

        {/* Item count indicators */}
        <View style={styles.statusSection}>
          <Text style={styles.label}>Items in Database:</Text>
          <Text style={styles.value}>{dbItemCount.itemCount}</Text>
        </View>

        <View style={styles.statusSection}>
          <Text style={styles.label}>Categories in Database:</Text>
          <Text style={styles.value}>{dbItemCount.categoryCount}</Text>
        </View>

        {/* Progress Display */}
        {status?.isSyncing && (
          <View>
            <View style={styles.statusRow}>
              <Text style={styles.statusLabel}>Progress:</Text>
              <Text style={styles.statusValue}>
                {`${status.syncProgress || 0} objects synced`}
              </Text>
            </View>
          </View>
        )}

        {status?.syncError && !status?.isSyncing && (
          <View style={styles.errorBox}>
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
            style={[styles.button, status?.isSyncing ? styles.buttonDisabled : null]}
          onPress={startFullSync}
            disabled={status?.isSyncing || !hasValidToken}
        >
          <Text style={styles.buttonText}>Full Sync</Text>
        </TouchableOpacity>

        <TouchableOpacity
            style={[styles.button, isSyncingLocations ? styles.buttonDisabled : null]}
            onPress={() => syncLocationsOnly({ silent: false })}
            disabled={isSyncingLocations || !hasValidToken}
        >
            {isSyncingLocations ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Sync Locations</Text>
            )}
        </TouchableOpacity>

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

        {/* Locations Section - Enhanced with expandable details */}
        <View style={styles.locationsSection}>
          <Text style={styles.sectionHeader}>Locations ({locations.length})</Text>
          {locations.length === 0 ? (
            <Text style={styles.noDataText}>No locations found</Text>
          ) : (
            <View style={styles.locationsList}>
              {locations.map(location => renderLocationItem(location))}
            </View>
          )}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#fff',
    borderRadius: 8,
    flex: 1,
  },
  scrollContainer: {
    flex: 1,
    padding: 16,
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
  statusLabel: {
    fontWeight: '400',
    color: '#333',
  },
  statusValue: {
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
    justifyContent: 'center', // Added to center activity indicator
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
  // Locations section styles
  locationsSection: {
    marginTop: 20,
    paddingTop: 15,
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
  },
  sectionHeader: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
    color: '#333',
  },
  noDataText: {
    fontSize: 14,
    color: '#666',
    fontStyle: 'italic',
    marginBottom: 10,
  },
  locationsList: {
    marginTop: 5,
  },
  locationItemContainer: {
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 6,
    overflow: 'hidden',
  },
  locationItemHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    backgroundColor: '#f5f5f5',
  },
  locationItemName: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
  },
  locationDetailsContainer: {
    padding: 12,
    backgroundColor: '#fff',
  },
  detailRow: {
    marginBottom: 8,
  },
  detailLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: '#444',
    marginBottom: 2,
  },
  detailValue: {
    fontSize: 14,
    color: '#666',
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  errorBox: {
    backgroundColor: '#ffebee',
    padding: 8,
    borderRadius: 4,
    marginBottom: 16,
  },
}); 