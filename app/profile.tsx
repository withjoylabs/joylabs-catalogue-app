import React, { useState, useEffect, Dispatch, SetStateAction } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Switch, ActivityIndicator, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { Ionicons as IoniconsType } from '@expo/vector-icons/build/Icons';
import { lightTheme } from '../src/themes';
import ProfileTopTabs from '../src/components/ProfileTopTabs';
import ConnectionStatusBar from '../src/components/ConnectionStatusBar';
import { useApi } from '../src/providers/ApiProvider';
import { useSquareAuth } from '../src/hooks/useSquareAuth';
import * as SecureStore from 'expo-secure-store';
import config from '../src/config';
import tokenService from '../src/services/tokenService';
import SyncStatusComponent from '../src/components/SyncStatusComponent';
import SyncLogsView from '../src/components/SyncLogsView';
import * as modernDb from '../src/database/modernDb';
import logger from '../src/utils/logger';

// Update SectionType to remove 'categories'
type SectionType = 'profile' | 'settings' | 'sync';
type IoniconsName = React.ComponentProps<typeof Ionicons>['name'];

// Square secure storage key constant
const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';

export default function ProfileScreen() {
  const router = useRouter();
  const [activeSection, setActiveSection] = useState<SectionType>('profile');
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);
  const [darkModeEnabled, setDarkModeEnabled] = useState(false);
  const [scanSoundEnabled, setScanSoundEnabled] = useState(true);
  const [testingConnection, setTestingConnection] = useState(false);
  const [resettingState, setResettingState] = useState(false);
  const [testingExactCallback, setTestingExactCallback] = useState(false);
  const [debugTaps, setDebugTaps] = useState(0);
  const [showDebugTools, setShowDebugTools] = useState(false);
  const {
    isConnected,
    merchantId,
    isLoading: isConnectingToSquare,
    error: squareError,
    connectToSquare,
    disconnectFromSquare
  } = useApi();

  // Add the testDeepLink function
  const { testDeepLink } = useSquareAuth();

  // Get direct access to the useSquareAuth hook functions
  const {
    testConnection,
    forceResetConnectionState,
    testExactCallback
  } = useSquareAuth();

  // Handle any Square connection errors
  useEffect(() => {
    if (squareError) {
      Alert.alert('Error', `Square connection error: ${squareError instanceof Error ? squareError.message : String(squareError)}`);
    }
  }, [squareError]);

  // Add useEffect to check connection state on page load
  useEffect(() => {
    const checkSquareConnection = async () => {
      console.log('Profile screen mounted, checking Square connection state...');
      try {
        const tokenStatus = await forceResetConnectionState();
        console.log('Square connection check result:', tokenStatus);

        if (tokenStatus.hasAccessToken) {
          console.log('Found Square token on profile screen load, length:', tokenStatus.accessTokenLength);
        } else {
          console.log('No Square token found on profile screen load');
        }
      } catch (error) {
        console.error('Error checking Square connection on profile load:', error);
      }
    };

    checkSquareConnection();
  }, []); // Empty dependency array means this runs once when component mounts

  // Dummy user data
  const user = {
    name: 'John Doe',
    email: 'john.doe@example.com',
    role: 'Store Manager',
    joinDate: 'January 2024',
  };

  // Function to test Square connection
  const testSquareConnection = async () => {
    try {
      setTestingConnection(true);
      console.log('Testing Square API connection...');

      const result = await testConnection();

      console.log('Square API test result:', result);

      if (result.success) {
        Alert.alert(
          'Success',
          `Connected to Square!\n\nMerchant: ${result.data?.businessName || 'Unknown'}\nMerchant ID: ${result.data?.merchantId || 'Unknown'}`
        );
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

  // Function to reset connection state
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

        setTimeout(() => {
          setActiveSection(activeSection === 'profile' ? 'settings' : 'profile');
          setActiveSection('profile');
        }, 500);
      }
    } catch (error: any) {
      console.error('Error resetting connection state:', error);
      Alert.alert('Error', `Failed to reset connection state: ${error.message}`);
    } finally {
      setResettingState(false);
    }
  };

  // Add a function to test the exact callback URL
  const testExactSquareCallback = async () => {
    try {
      setTestingExactCallback(true);
      console.log('Testing exact Square callback URL...');

      const result = await testExactCallback();

      console.log('Square callback test result:', result);

      if (result.success) {
        Alert.alert(
          'Success',
          `Successfully processed test callback with Square tokens!\n\nAccess Token: ${result.hasAccessToken ? 'Yes' : 'No'}\nMerchant ID: ${result.hasMerchantId ? 'Yes' : 'No'}\nBusiness Name: ${result.hasBusinessName ? 'Yes' : 'No'}`
        );
      } else {
        Alert.alert(
          'Error',
          `Failed to process test callback: ${result.error || 'Unknown error'}`
        );
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

      Alert.alert(
        'Square Token',
        `Token found (${tokenInfo.accessToken.length} chars)\nStatus: ${tokenInfo.status}\nExpires: ${tokenInfo.expiresAt || 'unknown'}`
      );
    } catch (error: any) {
      console.error('Error checking token:', error);
      Alert.alert('Error', `Failed to check token: ${error.message}`);
    }
  };

  // Add this function after testSquareToken
  const testDirectSquareCatalog = async () => {
    try {
      const accessToken = await tokenService.getAccessToken();

      if (!accessToken) {
        Alert.alert('Error', 'No access token found');
        return;
      }

      console.log('Testing Square catalog API directly with token:', accessToken.substring(0, 10) + '...');

      const response = await fetch('https://connect.squareup.com/v2/catalog/list?types=CATEGORY', {
        method: 'GET',
        headers: {
          'Square-Version': '2023-09-25',
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        }
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

  // Add this function to test the backend endpoint directly
  const testBackendCatalogEndpoint = async () => {
    try {
      const accessToken = await tokenService.getAccessToken();

      if (!accessToken) {
        Alert.alert('Error', 'No access token found');
        return;
      }

      console.log('Testing backend catalog API with token:', accessToken.substring(0, 10) + '...');

      const response = await fetch(`${config.api.baseUrl}/api/catalog/list-categories`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        }
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

  // Function to reset the database
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

  // Function to handle logo tap for debug menu
  const handleLogoTap = () => {
    const newTapCount = debugTaps + 1;
    setDebugTaps(newTapCount);

    if (newTapCount >= 5) {
      setShowDebugTools(!showDebugTools);
      setDebugTaps(0);
    }
  };

  const renderSection = () => {
    switch (activeSection) {
      case 'profile':
        return (
          <View style={styles.sectionContent}>
            <View style={styles.avatarContainer}>
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>{user.name.charAt(0)}</Text>
              </View>
              <Text style={styles.userName}>{user.name}</Text>
              <Text style={styles.userRole}>{user.role}</Text>
            </View>

            <View style={styles.infoContainer}>
              <Text style={styles.infoLabel}>Email</Text>
              <Text style={styles.infoValue}>{user.email}</Text>
            </View>

            <View style={styles.infoContainer}>
              <Text style={styles.infoLabel}>Member since</Text>
              <Text style={styles.infoValue}>{user.joinDate}</Text>
            </View>

            <View style={styles.connectionContainer}>
              <Text style={styles.connectionTitle}>Square Connection</Text>
              <Text style={styles.connectionDescription}>
                Connect your Square account to sync your inventory, items, and categories.
              </Text>

              {isConnected ? (
                <View>
                  <View style={styles.connectedInfo}>
                    <Text style={styles.connectedText}>
                      Connected to Square
                    </Text>
                    {merchantId && (
                      <Text style={styles.merchantIdText}>
                        Merchant ID: {merchantId.substring(0, 8)}...
                      </Text>
                    )}
                  </View>

                  <TouchableOpacity
                    style={[styles.connectionButton, { backgroundColor: '#007bff', marginBottom: 10 }]}
                    onPress={testSquareConnection}
                    disabled={testingConnection}
                  >
                    {testingConnection ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={styles.connectionButtonText}>Test Square Connection</Text>
                    )}
                  </TouchableOpacity>

                  <TouchableOpacity
                    style={[styles.connectionButton, styles.disconnectButton]}
                    onPress={disconnectFromSquare}
                    disabled={isConnectingToSquare}
                  >
                    {isConnectingToSquare ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={styles.connectionButtonText}>Disconnect from Square</Text>
                    )}
                  </TouchableOpacity>
                </View>
              ) : (
                <View>
                  <TouchableOpacity
                    style={styles.connectionButton}
                    onPress={() => {
                      console.log('🔵 Square connect button pressed');
                      connectToSquare();
                    }}
                    disabled={isConnectingToSquare}
                  >
                    {isConnectingToSquare ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={styles.connectionButtonText}>Connect to Square</Text>
                    )}
                  </TouchableOpacity>

                  {/* Direct API Test Button */}
                  <TouchableOpacity
                    style={[styles.connectionButton, { backgroundColor: '#28a745', marginTop: 10 }]}
                    onPress={testDirectSquareCatalog}
                  >
                    <Text style={styles.connectionButtonText}>Direct API Test</Text>
                  </TouchableOpacity>
                </View>
              )}

              {/* Display Square connection error */}
              {squareError && (
                <Text style={styles.errorText}>Error: {squareError instanceof Error ? squareError.message : String(squareError)}</Text>
              )}
            </View>
          </View>
        );
      case 'settings':
        return (
          <View style={styles.sectionContent}>
            <View style={styles.settingContainer}>
              <View style={styles.settingTextContainer}>
                <Text style={styles.settingLabel}>Push Notifications</Text>
                <Text style={styles.settingDescription}>Receive alerts about inventory changes</Text>
              </View>
              <Switch
                trackColor={{ false: "#767577", true: lightTheme.colors.primary }}
                thumbColor={notificationsEnabled ? "#fff" : "#f4f3f4"}
                onValueChange={setNotificationsEnabled}
                value={notificationsEnabled}
              />
            </View>

            <View style={styles.settingContainer}>
              <View style={styles.settingTextContainer}>
                <Text style={styles.settingLabel}>Dark Mode</Text>
                <Text style={styles.settingDescription}>Use dark theme throughout the app</Text>
              </View>
              <Switch
                trackColor={{ false: "#767577", true: lightTheme.colors.primary }}
                thumbColor={darkModeEnabled ? "#fff" : "#f4f3f4"}
                onValueChange={setDarkModeEnabled}
                value={darkModeEnabled}
              />
            </View>

            <View style={styles.settingContainer}>
              <View style={styles.settingTextContainer}>
                <Text style={styles.settingLabel}>Scan Sound</Text>
                <Text style={styles.settingDescription}>Play sound when item is scanned</Text>
              </View>
              <Switch
                trackColor={{ false: "#767577", true: lightTheme.colors.primary }}
                thumbColor={scanSoundEnabled ? "#fff" : "#f4f3f4"}
                onValueChange={setScanSoundEnabled}
                value={scanSoundEnabled}
              />
            </View>
          </View>
        );
      case 'sync':
        return (
          <View style={styles.sectionContentFlex}>{
            /* Ensure no whitespace before/after components */
          }<ConnectionStatusBar
              connected={isConnected}
              message={isConnected ? "Connected to Square" : "Not connected to Square"}
            />{
          }<SyncStatusComponent />{
          }<SyncLogsView />{
          }<View style={styles.troubleshootingContainer}>
              <Text style={styles.sectionTitle}>Troubleshooting</Text>
              <Text style={styles.sectionDescription}>
                If you're experiencing database errors, you can try resetting the local database
              </Text>
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#dc3545', marginTop: 10 }]}
                onPress={resetDatabase}
                disabled={resettingState}
              >
                {resettingState ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <Text style={styles.connectionButtonText}>Reset Database</Text>
                )}
              </TouchableOpacity>
            </View>{
          /* Ensure no whitespace after last component */
          }</View>
        );
      default:
        return null;
    }
  };

  return (
    <View style={styles.container}>
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
          {/* Row 1 */}
          <View style={styles.debugRow}>
            <TouchableOpacity
              style={[styles.debugButton, testingConnection && styles.debugButtonDisabled]}
              onPress={testSquareConnection} disabled={testingConnection}
            >
              <Text style={styles.debugButtonText}>{testingConnection ? 'Testing...' : 'Test Connection'}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.debugButton, resettingState && styles.debugButtonDisabled]}
              onPress={resetConnectionState} disabled={resettingState}
            >
              <Text style={styles.debugButtonText}>{resettingState ? 'Resetting...' : 'Reset State'}</Text>
            </TouchableOpacity>
          </View>
          {/* Row 2 */}
          <View style={styles.debugRow}>
            <TouchableOpacity
              style={[styles.debugButton, testingExactCallback && styles.debugButtonDisabled]}
              onPress={testExactSquareCallback} disabled={testingExactCallback}
            >
              <Text style={styles.debugButtonText}>{testingExactCallback ? 'Testing...' : 'Test Exact Callback'}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.debugButton} onPress={testSquareToken}>
              <Text style={styles.debugButtonText}>Test Token</Text>
            </TouchableOpacity>
          </View>
          {/* Row 3 */}
          <View style={styles.debugRow}>
            <TouchableOpacity style={styles.debugButton} onPress={testDeepLink}>
              <Text style={styles.debugButtonText}>Test Deep Link</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.debugButton} onPress={testDirectSquareCatalog}>
              <Text style={styles.debugButtonText}>Test Direct Catalog</Text>
            </TouchableOpacity>
          </View>
          {/* Row 4 */}
          <View style={styles.debugRow}>
            <TouchableOpacity style={styles.debugButton} onPress={testBackendCatalogEndpoint}>
              <Text style={styles.debugButtonText}>Test Backend Catalog</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.debugButton} onPress={resetDatabase}>
              <Text style={styles.debugButtonText}>Reset Database</Text>
            </TouchableOpacity>
          </View>
          {/* Reset taps */}
          <TouchableOpacity style={[styles.debugButton, styles.resetTapsButton]} onPress={() => setDebugTaps(0)}>
            <Text style={styles.debugButtonText}>Reset Debug Taps</Text>
          </TouchableOpacity>
        </View>
      )}
      <ProfileTopTabs
        activeSection={activeSection}
        onChangeSection={(section) => setActiveSection(section as SectionType)}
      />
      {
        activeSection === 'sync' ? (
          <View style={styles.contentFlexContainer}>
            {renderSection()}
          </View>
        ) : (
          <ScrollView style={styles.contentScrollView}>
            {renderSection()}
          </ScrollView>
        )
      }
    </View>
  );
}

// ** Use original styles **
const styles = StyleSheet.create({
   container: {
     flex: 1,
     backgroundColor: '#fff',
   },
   header: {
     flexDirection: 'row',
     justifyContent: 'space-between',
     alignItems: 'center',
     paddingHorizontal: 16,
     paddingTop: 60, // Adjust as needed for status bar height
     paddingBottom: 10,
     backgroundColor: '#fff',
     borderBottomWidth: 1,
     borderBottomColor: '#eee',
   },
   backButton: {
      padding: 8,
   },
   headerTitle: {
     fontSize: 20,
     fontWeight: 'bold',
     color: '#333',
     textAlign: 'center',
   },
   headerActions: {
      width: 40,
      height: 40,
   },
   contentScrollView: {
     flex: 1, // Make ScrollView take remaining space
   },
   sectionContent: {
     padding: 20,
   },
   avatarContainer: {
     alignItems: 'center',
     marginBottom: 20,
   },
   avatar: {
     width: 100,
     height: 100,
     borderRadius: 50,
     backgroundColor: lightTheme.colors.primary,
     justifyContent: 'center',
     alignItems: 'center',
     marginBottom: 10,
   },
   avatarText: {
     color: 'white',
     fontSize: 36,
     fontWeight: 'bold',
   },
   userName: {
     fontSize: 24,
     fontWeight: 'bold',
     textAlign: 'center',
     marginBottom: 4,
   },
   userRole: {
     fontSize: 16,
     color: '#666',
     textAlign: 'center',
   },
   infoContainer: {
     marginBottom: 15,
     paddingBottom: 10,
     borderBottomWidth: 1,
     borderBottomColor: '#f0f0f0',
   },
   infoLabel: {
     fontSize: 14,
     color: '#888',
     marginBottom: 4,
   },
   infoValue: {
     fontSize: 16,
     fontWeight: '500',
     color: '#333',
   },
   connectionContainer: {
     marginTop: 30,
     marginBottom: 20,
     padding: 15,
     backgroundColor: '#f8f8f8',
     borderRadius: 8,
     borderWidth: 1,
     borderColor: '#eee',
   },
   connectionTitle: {
     fontSize: 16,
     fontWeight: '600',
     color: '#333',
     marginBottom: 8,
   },
   connectionDescription: {
     fontSize: 14,
     color: '#666',
     marginBottom: 15,
     lineHeight: 20,
   },
   connectedInfo: {
     flexDirection: 'row',
     alignItems: 'center',
     marginBottom: 15,
     paddingVertical: 10,
     paddingHorizontal: 15,
     backgroundColor: '#e7f3ff',
     borderRadius: 6,
   },
   connectedText: {
     fontSize: 15,
     fontWeight: '500',
     color: '#00529B',
   },
   merchantIdText: {
     fontSize: 13,
     color: '#00529B',
     marginLeft: 8,
     fontFamily: 'monospace',
   },
   connectionButton: {
     backgroundColor: lightTheme.colors.primary,
     paddingVertical: 12,
     borderRadius: 8,
     alignItems: 'center',
     marginTop: 10,
   },
   connectionButtonText: {
     color: 'white',
     fontSize: 15,
     fontWeight: '600',
   },
   disconnectButton: {
     backgroundColor: '#e74c3c',
     marginTop: 10,
   },
   settingContainer: {
     flexDirection: 'row',
     justifyContent: 'space-between',
     alignItems: 'center',
     paddingVertical: 15,
     borderBottomWidth: 1,
     borderBottomColor: '#eee',
   },
   settingTextContainer: {
     flex: 1,
     marginRight: 10,
   },
   settingLabel: {
     fontSize: 16,
     color: '#333',
     marginBottom: 2,
   },
   settingDescription: {
     fontSize: 13,
     color: '#777',
   },
   sectionTitle: { // Style for Troubleshooting title
     fontSize: 18,
     fontWeight: 'bold',
     marginTop: 20,
     marginBottom: 15,
     color: '#444',
   },
    sectionDescription: { // Style for Troubleshooting description
        fontSize: 14,
        color: '#666',
        marginBottom: 16,
        lineHeight: 20,
    },
   troubleshootingContainer: {
     marginTop: 30,
     marginBottom: 40,
     padding: 15,
     backgroundColor: '#fff8e1',
     borderRadius: 8,
     borderWidth: 1,
     borderColor: '#ffecb3',
   },
   // Debug styles
   debugContainer: {
     padding: 16,
     backgroundColor: '#f0f0f0',
     borderTopWidth: 1,
     borderTopColor: '#ddd',
   },
   debugTitle: {
     fontSize: 16,
     fontWeight: 'bold',
     marginBottom: 16,
     color: '#555',
   },
   debugRow: {
     flexDirection: 'row',
     justifyContent: 'space-around',
     alignItems: 'center',
     marginBottom: 12,
   },
   debugButton: {
     backgroundColor: '#555',
     paddingVertical: 10,
     paddingHorizontal: 15,
     borderRadius: 6,
     flex: 1,
     marginHorizontal: 5,
     alignItems: 'center',
   },
   debugButtonDisabled: {
     backgroundColor: '#bbb',
     opacity: 0.7,
   },
   debugButtonText: {
     color: 'white',
     fontSize: 13,
     fontWeight: '500',
     textAlign: 'center',
   },
   resetTapsButton: {
     backgroundColor: '#e74c3c',
     marginTop: 10,
   },
   // General Error Text Style
   errorText: {
     color: '#e74c3c',
     fontSize: 14,
     marginTop: 10,
     textAlign: 'center',
   },
   sectionContentFlex: {
     flex: 1,
     padding: 20,
   },
   contentFlexContainer: { // New style for the sync tab wrapper
     flex: 1, // Make View take remaining space
   },
 }); 