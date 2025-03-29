import React, { useState, useEffect } from 'react';
import { 
  View, 
  Text, 
  StyleSheet, 
  FlatList, 
  TouchableOpacity, 
  ActivityIndicator,
  Share,
  Alert,
  SafeAreaView,
  Platform
} from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import logger, { LogLevel, getLogs, clearLogs, exportLogs } from '../src/utils/logger';
import { lightTheme } from '../src/themes';
import * as Network from 'expo-network';
import * as FileSystem from 'expo-file-system';
import * as Device from 'expo-device';
import * as Sharing from 'expo-sharing';
import { useApi } from '../src/providers/ApiProvider';

// Format timestamp to a readable date
const formatTimestamp = (timestamp: number): string => {
  const date = new Date(timestamp);
  return date.toLocaleString();
};

// Get color for log level
const getLogLevelColor = (level: LogLevel): string => {
  switch (level) {
    case LogLevel.DEBUG:
      return '#2196F3';
    case LogLevel.INFO:
      return '#4CAF50';
    case LogLevel.WARN:
      return '#FF9800';
    case LogLevel.ERROR:
      return '#F44336';
    default:
      return '#757575';
  }
};

export default function DebugScreen() {
  const router = useRouter();
  const [logs, setLogs] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState<LogLevel | null>(null);
  const [networkInfo, setNetworkInfo] = useState<any>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [apiTestResult, setApiTestResult] = useState<{
    status: 'idle' | 'loading' | 'success' | 'error';
    message?: string;
    responseTime?: number;
  }>({ status: 'idle' });
  const [deviceInfo, setDeviceInfo] = useState<any>(null);
  
  // Get API connection status
  const { isConnected, verifyConnection } = useApi();
  
  // Fetch logs and device info on mount
  useEffect(() => {
    loadData();
  }, []);
  
  const loadData = async () => {
    setIsLoading(true);
    await Promise.all([
      loadLogs(),
      getNetworkInfo(),
      loadDeviceInfo()
    ]);
    setIsLoading(false);
  };
  
  // Get network information
  const getNetworkInfo = async () => {
    try {
      const networkState = await Network.getNetworkStateAsync();
      const ipAddress = await Network.getIpAddressAsync();
      
      setNetworkInfo({
        isConnected: networkState.isConnected,
        isInternetReachable: networkState.isInternetReachable,
        type: networkState.type,
        ipAddress
      });
      
      logger.info('Debug', 'Network info loaded', { networkState, ipAddress });
    } catch (error) {
      logger.error('Debug', 'Failed to get network info', { error });
    }
  };
  
  // Load device information
  const loadDeviceInfo = async () => {
    try {
      setDeviceInfo({
        brand: Device.brand,
        manufacturer: Device.manufacturer,
        modelName: Device.modelName,
        designName: Device.designName,
        productName: Device.productName,
        deviceYearClass: Device.deviceYearClass,
        totalMemory: Device.totalMemory,
        osName: Device.osName,
        osVersion: Device.osVersion,
        osBuildId: Device.osBuildId,
        platformApiLevel: Device.platformApiLevel
      });
    } catch (error) {
      logger.error('Debug', 'Failed to load device info', { error });
    }
  };
  
  // Load logs from the logger
  const loadLogs = () => {
    setIsLoading(true);
    try {
      const allLogs = getLogs();
      setLogs(allLogs.reverse()); // Show newest first
      logger.info('Debug', `Loaded ${allLogs.length} logs`);
    } catch (error) {
      Alert.alert('Error', 'Failed to load logs');
      logger.error('Debug', 'Failed to load logs', { error });
    } finally {
      setIsLoading(false);
      setRefreshing(false);
    }
  };
  
  // Handle refresh
  const handleRefresh = () => {
    setRefreshing(true);
    loadLogs();
    getNetworkInfo();
    loadDeviceInfo();
  };
  
  // Clear all logs
  const handleClearLogs = () => {
    Alert.alert(
      'Clear Logs',
      'Are you sure you want to clear all logs?',
      [
        { text: 'Cancel', style: 'cancel' },
        { 
          text: 'Clear', 
          style: 'destructive',
          onPress: async () => {
            try {
              await clearLogs();
              setLogs([]);
              Alert.alert('Success', 'Logs cleared successfully');
            } catch (error) {
              Alert.alert('Error', 'Failed to clear logs');
              logger.error('Debug', 'Failed to clear logs', { error });
            }
          }
        }
      ]
    );
  };
  
  // Export logs to a file and share
  const handleExportLogs = async () => {
    try {
      setIsLoading(true);
      
      // Get device info to include in the logs
      const deviceInfo = {
        brand: Device.brand,
        manufacturer: Device.manufacturer,
        modelName: Device.modelName,
        osName: Device.osName,
        osVersion: Device.osVersion,
        deviceType: await Device.getDeviceTypeAsync(),
        maxMemory: await Device.getMaxMemoryAsync(),
        isDevice: Device.isDevice,
        network: networkInfo
      };
      
      // Log device info before export
      logger.info('Debug', 'Exporting logs with device info', deviceInfo);
      
      // Export logs to a file
      const filePath = await exportLogs();
      
      // Share the file
      try {
        await Share.share({
          title: 'App Logs',
          message: 'App logs for troubleshooting',
          url: Platform.OS === 'ios' ? filePath : `file://${filePath}`
        });
      } catch (error) {
        Alert.alert('Error', 'Failed to share logs');
        logger.error('Debug', 'Failed to share logs', { error });
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to export logs');
      logger.error('Debug', 'Failed to export logs', { error });
    } finally {
      setIsLoading(false);
    }
  };
  
  // Test API connectivity
  const testApiConnection = async () => {
    setApiTestResult({ status: 'loading' });
    try {
      const verified = await verifyConnection();
      
      if (verified) {
        setApiTestResult({ 
          status: 'success', 
          message: 'Successfully connected to Square API. Token is valid.'
        });
        logger.info('Debug', 'API connection test succeeded');
      } else {
        setApiTestResult({ 
          status: 'error', 
          message: 'Could not connect to Square API. Your authentication may have expired.'
        });
        logger.error('Debug', 'API connection test failed');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      setApiTestResult({ 
        status: 'error', 
        message: `API test failed: ${errorMessage}` 
      });
      logger.error('Debug', 'API connection test failed', { error });
    }
  };
  
  // Function to simulate a crash for testing
  const simulateCrash = () => {
    logger.warn('Debug', 'Simulating app crash');
    setTimeout(() => {
      // This will cause a JS exception
      throw new Error('This is a simulated crash for testing purposes');
    }, 500);
  };
  
  // Filter logs by level
  const filteredLogs = filter !== null
    ? logs.filter(log => log.level === filter)
    : logs;
  
  // Render a log item
  const renderLogItem = ({ item }: { item: any }) => {
    return (
      <TouchableOpacity 
        style={styles.logItem}
        onPress={() => {
          Alert.alert(
            `${LogLevel[item.level]} - ${item.tag}`,
            item.message,
            [
              { text: 'Close', style: 'cancel' },
              { 
                text: 'Copy', 
                onPress: () => {
                  Share.share({
                    message: `${formatTimestamp(item.timestamp)} [${LogLevel[item.level]}] [${item.tag}] ${item.message}\n\n${item.data ? JSON.stringify(item.data, null, 2) : ''}`
                  });
                }
              }
            ]
          );
        }}
      >
        <View style={styles.logHeader}>
          <Text style={styles.logTimestamp}>{formatTimestamp(item.timestamp)}</Text>
          <View 
            style={[
              styles.logLevelBadge, 
              { backgroundColor: getLogLevelColor(item.level) }
            ]}
          >
            <Text style={styles.logLevelText}>{LogLevel[item.level]}</Text>
          </View>
        </View>
        <Text style={styles.logTag}>{item.tag}</Text>
        <Text style={styles.logMessage} numberOfLines={2}>{item.message}</Text>
        {item.data && (
          <Text style={styles.logData} numberOfLines={1}>
            Data: {JSON.stringify(item.data).substring(0, 100)}
            {JSON.stringify(item.data).length > 100 ? '...' : ''}
          </Text>
        )}
      </TouchableOpacity>
    );
  };
  
  // View API calls timeline to identify potential loops
  const viewApiCallsTimeline = () => {
    const apiLogs = logs.filter(log => 
      (log.tag === 'API' || log.message.includes('API') || log.message.includes('api'))
    );
    
    if (apiLogs.length === 0) {
      Alert.alert('No API Logs', 'No API related logs were found.');
      return;
    }
    
    // Group by minute to identify potential loops
    const groupedByMinute: {[key: string]: number} = {};
    apiLogs.forEach(log => {
      const date = new Date(log.timestamp);
      const minute = `${date.getHours()}:${date.getMinutes()}`;
      groupedByMinute[minute] = (groupedByMinute[minute] || 0) + 1;
    });
    
    // Find potential loop issues (more than 10 API calls per minute)
    const potentialLoops = Object.entries(groupedByMinute)
      .filter(([_, count]) => count > 10)
      .map(([minute, count]) => `${minute} - ${count} calls`);
    
    if (potentialLoops.length > 0) {
      Alert.alert(
        'Potential API Loop Detected',
        `The following minutes have unusually high API activity:\n\n${potentialLoops.join('\n')}\n\nThis may indicate an infinite loop.`,
        [
          { text: 'OK' },
          { 
            text: 'View Recent API Logs', 
            onPress: () => setFilter(null) // Show all logs to inspect
          }
        ]
      );
    } else {
      Alert.alert(
        'API Calls Timeline',
        `API call distribution by minute:\n\n${Object.entries(groupedByMinute)
          .map(([minute, count]) => `${minute} - ${count} calls`)
          .join('\n')}`,
        [{ text: 'OK' }]
      );
    }
  };
  
  return (
    <SafeAreaView style={styles.container}>
      <Stack.Screen
        options={{
          title: 'Debug Logs',
          headerShown: true,
          headerStyle: { backgroundColor: lightTheme.colors.background },
          headerTitleStyle: { color: lightTheme.colors.text },
          headerLeft: () => (
            <TouchableOpacity 
              onPress={() => router.back()}
              style={{ marginLeft: 10 }}
            >
              <Ionicons name="close" size={24} color={lightTheme.colors.text} />
            </TouchableOpacity>
          ),
          headerRight: () => (
            <View style={styles.buttonGroup}>
              <TouchableOpacity
                style={styles.button}
                onPress={handleExportLogs}
              >
                <Ionicons name="share-outline" size={20} color="#fff" />
                <Text style={styles.buttonText}>Export Logs</Text>
              </TouchableOpacity>
              
              <TouchableOpacity
                style={styles.button}
                onPress={handleClearLogs}
              >
                <Ionicons name="trash-outline" size={20} color="#fff" />
                <Text style={styles.buttonText}>Clear Logs</Text>
              </TouchableOpacity>
              
              <TouchableOpacity
                style={[styles.button, { backgroundColor: '#2196F3' }]}
                onPress={viewApiCallsTimeline}
              >
                <Ionicons name="analytics-outline" size={20} color="#fff" />
                <Text style={styles.buttonText}>Analyze API Calls</Text>
              </TouchableOpacity>
            </View>
          ),
        }}
      />
      
      <View style={styles.networkSection}>
        <Text style={styles.sectionTitle}>Device & Network</Text>
        
        {networkInfo ? (
          <View style={styles.networkInfo}>
            <Text>
              <Text style={styles.labelText}>Connection: </Text>
              <Text style={networkInfo.isConnected ? styles.successText : styles.errorText}>
                {networkInfo.isConnected ? 'Connected' : 'Disconnected'}
              </Text>
            </Text>
            <Text>
              <Text style={styles.labelText}>Internet: </Text>
              <Text style={networkInfo.isInternetReachable ? styles.successText : styles.errorText}>
                {networkInfo.isInternetReachable ? 'Reachable' : 'Unreachable'}
              </Text>
            </Text>
            <Text>
              <Text style={styles.labelText}>Connection Type: </Text>
              <Text>{networkInfo.type}</Text>
            </Text>
            <Text>
              <Text style={styles.labelText}>IP Address: </Text>
              <Text>{networkInfo.ipAddress}</Text>
            </Text>
          </View>
        ) : (
          <ActivityIndicator size="small" color="#007AFF" />
        )}
        
        <View style={styles.apiTestSection}>
          <TouchableOpacity 
            style={[
              styles.button,
              apiTestResult.status === 'loading' && styles.disabledButton
            ]}
            onPress={testApiConnection}
            disabled={apiTestResult.status === 'loading'}
          >
            <Text style={styles.buttonText}>
              {apiTestResult.status === 'loading' ? 'Testing API...' : 'Test API Connection'}
            </Text>
          </TouchableOpacity>
          
          {apiTestResult.status !== 'idle' && (
            <View style={[
              styles.apiResultBox,
              apiTestResult.status === 'success' ? styles.successBox : 
              apiTestResult.status === 'error' ? styles.errorBox : 
              styles.loadingBox
            ]}>
              <Text style={[
                styles.apiResultText,
                apiTestResult.status === 'success' ? styles.successText : 
                apiTestResult.status === 'error' ? styles.errorText : 
                styles.loadingText
              ]}>
                {apiTestResult.message || 'Testing...'}
              </Text>
              {apiTestResult.status === 'loading' && (
                <ActivityIndicator size="small" color="#fff" style={styles.inlineLoader} />
              )}
            </View>
          )}
        </View>
        
        <TouchableOpacity 
          style={[styles.button, styles.dangerButton]}
          onPress={() => {
            Alert.alert(
              'Simulate Crash',
              'This will trigger a controlled crash to test error handling. Continue?',
              [
                { text: 'Cancel', style: 'cancel' },
                { text: 'Simulate Crash', style: 'destructive', onPress: simulateCrash }
              ]
            );
          }}
        >
          <Text style={styles.buttonText}>Simulate Crash</Text>
        </TouchableOpacity>
      </View>
      
      <View style={styles.filterSection}>
        <Text style={styles.sectionTitle}>Logs</Text>
        <View style={styles.filterButtons}>
          <TouchableOpacity
            style={[styles.filterButton, filter === null && styles.activeFilterButton]}
            onPress={() => setFilter(null)}
          >
            <Text style={[styles.filterText, filter === null && styles.activeFilterText]}>ALL</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.filterButton, filter === LogLevel.DEBUG && styles.activeFilterButton]}
            onPress={() => setFilter(LogLevel.DEBUG)}
          >
            <Text style={[styles.filterText, filter === LogLevel.DEBUG && styles.activeFilterText]}>DEBUG</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.filterButton, filter === LogLevel.INFO && styles.activeFilterButton]}
            onPress={() => setFilter(LogLevel.INFO)}
          >
            <Text style={[styles.filterText, filter === LogLevel.INFO && styles.activeFilterText]}>INFO</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.filterButton, filter === LogLevel.WARN && styles.activeFilterButton]}
            onPress={() => setFilter(LogLevel.WARN)}
          >
            <Text style={[styles.filterText, filter === LogLevel.WARN && styles.activeFilterText]}>WARN</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.filterButton, filter === LogLevel.ERROR && styles.activeFilterButton]}
            onPress={() => setFilter(LogLevel.ERROR)}
          >
            <Text style={[styles.filterText, filter === LogLevel.ERROR && styles.activeFilterText]}>ERROR</Text>
          </TouchableOpacity>
        </View>
      </View>
      
      {isLoading && !refreshing ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.loadingText}>Loading logs...</Text>
        </View>
      ) : (
        <>
          <Text style={styles.countText}>
            {filteredLogs.length} log entries {filter !== null ? `(${LogLevel[filter]})` : ''}
          </Text>
          
          <FlatList
            data={filteredLogs}
            renderItem={renderLogItem}
            keyExtractor={(item, index) => `${item.timestamp}-${index}`}
            contentContainerStyle={styles.listContent}
            onRefresh={handleRefresh}
            refreshing={refreshing}
            ListEmptyComponent={
              <View style={styles.emptyContainer}>
                <Ionicons name="document-text-outline" size={64} color="#BDBDBD" />
                <Text style={styles.emptyText}>No logs available</Text>
              </View>
            }
          />
        </>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f9f9f9',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#757575',
  },
  filterContainer: {
    flexDirection: 'row',
    padding: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  filterButton: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 15,
    marginRight: 5,
  },
  filterButtonActive: {
    backgroundColor: lightTheme.colors.primary,
  },
  filterText: {
    fontSize: 12,
    color: '#757575',
  },
  filterTextActive: {
    fontSize: 12,
    color: '#fff',
    fontWeight: 'bold',
  },
  listContent: {
    paddingBottom: 20,
  },
  logItem: {
    backgroundColor: '#fff',
    padding: 15,
    marginHorizontal: 10,
    marginTop: 10,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  logHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 5,
  },
  logTimestamp: {
    fontSize: 12,
    color: '#757575',
  },
  logLevelBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  logLevelText: {
    fontSize: 10,
    color: '#fff',
    fontWeight: 'bold',
  },
  logTag: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 5,
  },
  logMessage: {
    fontSize: 14,
    color: '#333',
    marginBottom: 5,
  },
  logData: {
    fontSize: 12,
    color: '#757575',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: 100,
  },
  emptyText: {
    fontSize: 16,
    color: '#757575',
    marginTop: 10,
  },
  countText: {
    paddingHorizontal: 15,
    paddingVertical: 10,
    fontSize: 14,
    color: '#757575',
  },
  networkInfoContainer: {
    padding: 10,
    backgroundColor: '#E3F2FD',
    borderBottomWidth: 1,
    borderBottomColor: '#BBDEFB',
  },
  networkInfoTitle: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#1976D2',
  },
  networkInfoText: {
    fontSize: 12,
    color: '#1976D2',
  },
  networkSection: {
    backgroundColor: '#f8f9fa',
    padding: 15,
    borderRadius: 8,
    marginHorizontal: 15,
    marginTop: 15,
    marginBottom: 10,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
    color: '#333',
  },
  networkInfo: {
    backgroundColor: '#fff',
    padding: 10,
    borderRadius: 6,
    marginBottom: 15,
  },
  labelText: {
    fontWeight: '600',
    color: '#555',
  },
  successText: {
    color: '#28a745',
    fontWeight: '500',
  },
  errorText: {
    color: '#dc3545',
    fontWeight: '500',
  },
  buttonGroup: {
    flexDirection: 'row',
    justifyContent: 'center',
    padding: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
    marginBottom: 10,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    marginHorizontal: 5,
  },
  buttonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
    marginLeft: 6,
  },
  dangerButton: {
    backgroundColor: '#dc3545',
  },
  disabledButton: {
    backgroundColor: '#6c757d',
    opacity: 0.7,
  },
  apiTestSection: {
    marginBottom: 15,
  },
  apiResultBox: {
    padding: 10,
    borderRadius: 6,
    marginTop: 5,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  apiResultText: {
    fontSize: 14,
    flex: 1,
  },
  successBox: {
    backgroundColor: 'rgba(40, 167, 69, 0.2)',
  },
  errorBox: {
    backgroundColor: 'rgba(220, 53, 69, 0.2)',
  },
  loadingBox: {
    backgroundColor: 'rgba(0, 123, 255, 0.2)',
  },
  inlineLoader: {
    marginLeft: 10,
  },
  filterSection: {
    padding: 15,
  },
  filterButtons: {
    flexDirection: 'row',
    marginBottom: 10,
  },
  activeFilterButton: {
    backgroundColor: '#007bff',
  },
  activeFilterText: {
    color: 'white',
  },
}); 