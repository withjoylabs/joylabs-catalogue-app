import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Switch, ActivityIndicator, Alert, TextInput } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../../src/themes';
import ConnectionStatusBar from '../../src/components/ConnectionStatusBar';
import { useApi } from '../../src/providers/ApiProvider';
import { useSquareAuth } from '../../src/hooks/useSquareAuth';
import * as SecureStore from 'expo-secure-store';
import config from '../../src/config';
import tokenService from '../../src/services/tokenService';
import SyncStatusComponent from '../../src/components/SyncStatusComponent';
import SyncLogsView from '../../src/components/SyncLogsView';
import * as modernDb from '../../src/database/modernDb';
import logger from '../../src/utils/logger';
import { useAppStore } from '../../src/store';
import { createMaterialTopTabNavigator } from '@react-navigation/material-top-tabs';
import { SafeAreaView } from 'react-native-safe-area-context';

const Tab = createMaterialTopTabNavigator();

const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';

export default function Layout() {
  const router = useRouter();
  const [debugTaps, setDebugTaps] = useState(0);
  const [showDebugTools, setShowDebugTools] = useState(false);
  const [inspectId, setInspectId] = useState('');
  const [isInspectingById, setIsInspectingById] = useState(false);
  
  const {
    isConnected,
    merchantId,
    isLoading: isConnectingToSquare,
    error: squareError,
    connectToSquare,
    disconnectFromSquare
  } = useApi();

  const { 
    testDeepLink,
    testConnection,
    forceResetConnectionState,
    testExactCallback
  } = useSquareAuth();
  
  const [testingConnection, setTestingConnection] = useState(false);
  const [resettingState, setResettingState] = useState(false);
  const [testingExactCallback, setTestingExactCallback] = useState(false);

  const user = {
    name: 'John Doe',
    email: 'john.doe@example.com',
    role: 'Store Manager',
    joinDate: 'January 2024',
  };
  
  const testSquareConnection = async () => {
    try {
      setTestingConnection(true);
      console.log('Testing Square API connection...');
      const result = await testConnection();
      console.log('Square API test result:', result);
      if (result.success) {
        Alert.alert('Success', `Connected to Square!\n\nMerchant: ${result.data?.businessName || 'Unknown'}\nMerchant ID: ${result.data?.merchantId || 'Unknown'}`);
      } else {
        Alert.alert('Error', `Failed to connect: ${result.error || 'Unknown error'}`);
      }
    } catch (error: any) {
      console.error('Error testing Square connection:', error);
      Alert.alert('Error', `Failed to test connection: ${error.message}`);
    } finally {
      setTestingConnection(false);
    }
  };

  const resetConnectionState = async () => {
     try {
      setResettingState(true);
      console.log('Resetting connection state...');
      const tokenStatus = await forceResetConnectionState();
      console.log('Connection state reset complete', tokenStatus);
      if (tokenStatus.hasAccessToken) {
        Alert.alert('Success', `Connection state has been reset. Found active token (length: ${tokenStatus.accessTokenLength}).`);
      } else {
        Alert.alert('Success', 'Connection state has been reset. No active tokens found.');
      }
    } catch (error: any) {
      console.error('Error resetting connection state:', error);
      Alert.alert('Error', `Failed to reset connection state: ${error.message}`);
    } finally {
      setResettingState(false);
    }
  };

  const testExactSquareCallback = async () => {
    try {
      setTestingExactCallback(true);
      console.log('Testing exact Square callback URL...');
      const result = await testExactCallback();
      console.log('Square callback test result:', result);
      if (result.success) {
        Alert.alert('Success', `Successfully processed test callback with Square tokens!\n\nAccess Token: ${result.hasAccessToken ? 'Yes' : 'No'}\nMerchant ID: ${result.hasMerchantId ? 'Yes' : 'No'}\nBusiness Name: ${result.hasBusinessName ? 'Yes' : 'No'}`);
      } else {
        Alert.alert('Error', `Failed to process test callback: ${result.error || 'Unknown error'}`);
      }
    } catch (error: any) {
      console.error('Error in exact callback test:', error);
      Alert.alert('Error', `Failed to run callback test: ${error.message}`);
    } finally {
      setTestingExactCallback(false);
    }
  };

  const testSquareToken = async () => {
     try {
      const tokenInfo = await tokenService.getTokenInfo();
      if (!tokenInfo.accessToken) {
        Alert.alert('No Token', 'No Square access token found');
        return;
      }
      console.log('Access token found with length:', tokenInfo.accessToken.length);
      console.log('First few characters:', tokenInfo.accessToken.substring(0, 10) + '...');
      console.log('Token status:', tokenInfo.status);
      Alert.alert('Square Token', `Token found (${tokenInfo.accessToken.length} chars)\nStatus: ${tokenInfo.status}\nExpires: ${tokenInfo.expiresAt || 'unknown'}`);
    } catch (error: any) {
      console.error('Error checking token:', error);
      Alert.alert('Error', `Failed to check token: ${error.message}`);
    }
  };
  
  const testDirectSquareCatalog = async () => {
    try {
      const accessToken = await tokenService.getAccessToken();
      if (!accessToken) { Alert.alert('Error', 'No access token found'); return; }
      console.log('Testing Square catalog API directly...');
      const response = await fetch('https://connect.squareup.com/v2/catalog/list?types=CATEGORY', {
        method: 'GET',
        headers: { 'Square-Version': '2023-09-25', 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }
      });
      console.log('Square direct catalog response status:', response.status);
      const data = await response.json();
      console.log('Square direct catalog response:', JSON.stringify(data).substring(0, 200) + '...');
      if (response.ok) {
        Alert.alert('Success', `Direct Square catalog API works! Found ${data.objects?.length || 0} catalog objects`);
      } else {
        Alert.alert('Error', `Direct Square catalog API failed: ${data.errors?.[0]?.detail || response.statusText}`);
      }
    } catch (error: any) {
      console.error('Error testing direct Square catalog:', error);
      Alert.alert('Error', `Failed to test direct catalog: ${error.message}`);
    }
  };

  const testBackendCatalogEndpoint = async () => {
    try {
      const accessToken = await tokenService.getAccessToken();
      if (!accessToken) { Alert.alert('Error', 'No access token found'); return; }
      console.log('Testing backend catalog API...');
      const response = await fetch(`${config.api.baseUrl}/api/catalog/list-categories`, {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }
      });
      console.log('Backend catalog response status:', response.status);
      const data = await response.json();
      console.log('Backend catalog response:', JSON.stringify(data).substring(0, 200) + '...');
      if (response.ok && data.success && data.categories) {
        Alert.alert('Success', `Backend catalog API works! Found ${data.categories?.length || 0} categories`);
      } else {
        const errorMessage = data?.error?.message || data?.message || (response.ok ? 'Unknown success error' : response.statusText);
        Alert.alert('Error', `Backend catalog API failed: ${errorMessage}`);
      }
    } catch (error: any) {
      console.error('Error testing backend catalog endpoint:', error);
      Alert.alert('Error', `Failed to test backend catalog: ${error.message}`);
    }
  };

  const resetDatabase = async () => {
    try {
      setResettingState(true);
      logger.info('Profile', 'Starting database reset...');
      await modernDb.resetDatabase();
      logger.info('Profile', 'Database reset successful');
      Alert.alert('Success', 'Local database has been reset.');
    } catch (error: any) {
      logger.error('Profile', 'Database reset failed', { error });
      Alert.alert('Error', `Failed to reset database: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setResettingState(false);
    }
  };

  const handleLogoTap = () => {
    const newTapCount = debugTaps + 1;
    setDebugTaps(newTapCount);
    if (newTapCount >= 5) {
      setShowDebugTools(!showDebugTools);
      setDebugTaps(0);
    }
  };

  const handleInspectById = async () => {
    if (!inspectId.trim()) { Alert.alert('Input Needed', 'Please enter an Item or Variation ID to inspect.'); return; }
    const idToInspect = inspectId.trim();
    setIsInspectingById(true);
    logger.info('ProfileLayout', `Attempting to inspect DB for ID: ${idToInspect}`);
    try {
      const result = await modernDb.getItemOrVariationRawById(idToInspect);
      logger.info('ProfileLayout', `Raw DB Inspection Result for ID: ${idToInspect}`, { result: result ? 'Found' : 'Not Found' });
      console.log(`--- Inspect DB Result for ID: ${idToInspect} ---`);
      console.log(JSON.stringify(result, null, 2));
      console.log('--- End Inspect DB --- ');
      if (result) {
        Alert.alert('Inspect ID', `Found data for ID: ${idToInspect}. Check console/logs.`);
      } else {
        Alert.alert('Inspect ID', `No data found for ID: ${idToInspect}. Fetching table samples...`);
        try {
          logger.info('ProfileLayout', `Fetching table samples because ID ${idToInspect} was not found.`);
          const firstItems = await modernDb.getFirstTenItemsRaw();
          const firstVariations = await modernDb.getFirstTenVariationsRaw();
          console.log(`--- Sample: First ${firstItems.length} Items ---`);
          console.log(JSON.stringify(firstItems, null, 2));
          console.log(`--- End Sample: Items --- `);
          console.log(`--- Sample: First ${firstVariations.length} Variations ---`);
          console.log(JSON.stringify(firstVariations, null, 2));
          console.log(`--- End Sample: Variations --- `);
        } catch (sampleError) {
          logger.error('ProfileLayout', 'Failed to fetch table samples', { sampleError });
        }
      }
    } catch (error) {
      logger.error('ProfileLayout', `Failed to inspect database for ID: ${idToInspect}`, { error });
      Alert.alert('Error', `Failed to inspect database for ID: ${idToInspect}. Check logs.`);
    } finally {
      setIsInspectingById(false);
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}> 
      <StatusBar style="dark" />
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="black" />
        </TouchableOpacity>
        <TouchableOpacity onPress={handleLogoTap}>
          <Text style={styles.headerTitle}>Profile</Text>
        </TouchableOpacity>
        <View style={styles.headerActions}></View> 
      </View>
      
      {showDebugTools && (
         <View style={styles.debugContainer}>
          <Text style={styles.debugTitle}>Debug Tools</Text>
          <View style={styles.debugRow}>
            <TouchableOpacity style={[styles.debugButton, testingConnection && styles.debugButtonDisabled]} onPress={testSquareConnection} disabled={testingConnection}>
              <Text style={styles.debugButtonText}>{testingConnection ? 'Testing...' : 'Test Connection'}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.debugButton, resettingState && styles.debugButtonDisabled]} onPress={resetConnectionState} disabled={resettingState}>
              <Text style={styles.debugButtonText}>{resettingState ? 'Resetting...' : 'Reset State'}</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.debugRow}>
            <TouchableOpacity style={[styles.debugButton, testingExactCallback && styles.debugButtonDisabled]} onPress={testExactSquareCallback} disabled={testingExactCallback}>
              <Text style={styles.debugButtonText}>{testingExactCallback ? 'Testing...' : 'Test Exact Callback'}</Text>
            </TouchableOpacity>
             <TouchableOpacity style={styles.debugButton} onPress={testSquareToken}>
              <Text style={styles.debugButtonText}>Test Token</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.debugRow}>
             <TouchableOpacity style={styles.debugButton} onPress={testDeepLink}>
              <Text style={styles.debugButtonText}>Test Deep Link</Text>
            </TouchableOpacity>
             <TouchableOpacity style={styles.debugButton} onPress={testDirectSquareCatalog}>
              <Text style={styles.debugButtonText}>Test Direct Catalog</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.debugRow}>
             <TouchableOpacity style={styles.debugButton} onPress={testBackendCatalogEndpoint}>
              <Text style={styles.debugButtonText}>Test Backend Catalog</Text>
            </TouchableOpacity>
             <TouchableOpacity style={styles.debugButton} onPress={resetDatabase}>
              <Text style={styles.debugButtonText}>Reset Database</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.inspectSection}>
            <TextInput
              style={styles.inspectInput}
              placeholder="Enter Item/Variation ID"
              value={inspectId}
              onChangeText={setInspectId}
              placeholderTextColor="#888"
              autoCapitalize="none"
            />
             <TouchableOpacity
              style={[styles.debugButton, styles.inspectButton, isInspectingById && styles.buttonDisabled]}
              onPress={handleInspectById}
              disabled={isInspectingById}
            >
              {isInspectingById ? (<ActivityIndicator size="small" color="#fff" />) : (<Text style={styles.debugButtonText}>Inspect by ID</Text>)}
            </TouchableOpacity>
          </View>
           <TouchableOpacity style={[styles.debugButton, styles.resetTapsButton]} onPress={() => setDebugTaps(0)}>
            <Text style={styles.debugButtonText}>Reset Debug Taps</Text>
          </TouchableOpacity>
        </View>
      )}

      <Tab.Navigator
        screenOptions={{
          tabBarLabelStyle: { fontSize: 12, textTransform: 'none', fontWeight: '600' },
          tabBarItemStyle: { /* Add item style if needed */ },
          tabBarStyle: { backgroundColor: 'white' },
          tabBarIndicatorStyle: { backgroundColor: lightTheme.colors.primary },
          tabBarActiveTintColor: lightTheme.colors.primary,
          tabBarInactiveTintColor: '#888',
        }}
      >
        <Tab.Screen 
          name="index"
          options={{ title: 'Profile' }} 
        />
        <Tab.Screen 
          name="settings"
          options={{ title: 'Settings' }} 
        />
        <Tab.Screen 
          name="sync"
          options={{ title: 'Sync Catalog' }} 
        />
      </Tab.Navigator>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: 'white',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  headerActions: {
    width: 24,
  },
  debugContainer: {
    padding: 10,
    backgroundColor: '#fff7e6',
    borderBottomWidth: 1,
    borderBottomColor: '#ffe8b3',
  },
  debugTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    textAlign: 'center',
  },
  debugRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 8,
  },
  debugButton: {
    backgroundColor: '#ffc107',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 5,
    flex: 1,
    marginHorizontal: 4,
    alignItems: 'center',
  },
  debugButtonDisabled: {
    opacity: 0.6,
  },
  debugButtonText: {
    color: '#333',
    fontWeight: '500',
    fontSize: 12,
    textAlign: 'center'
  },
  inspectSection: {
    flexDirection: 'row',
    marginTop: 8,
    alignItems: 'center',
  },
  inspectInput: {
    flex: 2,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 5,
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginRight: 8,
    backgroundColor: 'white',
    fontSize: 12,
  },
  inspectButton: {
    flex: 1,
    backgroundColor: '#007bff',
  },
  resetTapsButton: {
    backgroundColor: '#6c757d',
    marginTop: 8,
  },
   buttonDisabled: {
    opacity: 0.6,
  },
}); 