import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Switch, ActivityIndicator, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { Ionicons as IoniconsType } from '@expo/vector-icons/build/Icons';
import { lightTheme } from '../src/themes';
import BottomTabBar from '../src/components/BottomTabBar';
import ProfileTopTabs from '../src/components/ProfileTopTabs';
import ConnectionStatusBar from '../src/components/ConnectionStatusBar';
import { useCategories } from '../src/hooks';
import { Category } from '../src/store';
import { useApi } from '../src/providers/ApiProvider';
import { useSquareAuth } from '../src/hooks/useSquareAuth';
import * as SecureStore from 'expo-secure-store';
import config from '../src/config';
import tokenService from '../src/services/tokenService';

type SectionType = 'profile' | 'settings' | 'categories';
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
  const { 
    categories, 
    isCategoriesLoading, 
    categoryError, 
    connected, 
    fetchCategories 
  } = useCategories();
  
  // Use the API context
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
  
  // Fetch categories when the categories tab is selected
  useEffect(() => {
    if (activeSection === 'categories') {
      fetchCategories();
    }
  }, [activeSection]);

  // Handle any Square connection errors
  useEffect(() => {
    if (squareError) {
      Alert.alert('Error', `Square connection error: ${squareError}`);
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

  // Get appropriate icon for a category based on its name
  const getCategoryIcon = (categoryName: string): IoniconsName => {
    const name = categoryName.toLowerCase();
    if (name.includes('food') || name.includes('beverage') || name.includes('drink')) {
      return 'fast-food-outline';
    } else if (name.includes('clothing') || name.includes('apparel') || name.includes('wear')) {
      return 'shirt-outline';
    } else if (name.includes('home') || name.includes('kitchen') || name.includes('house')) {
      return 'home-outline';
    } else if (name.includes('sport') || name.includes('outdoor') || name.includes('fitness')) {
      return 'fitness-outline';
    } else if (name.includes('electronic') || name.includes('tech') || name.includes('digital')) {
      return 'desktop-outline';
    } else if (name.includes('beauty') || name.includes('health') || name.includes('personal')) {
      return 'medical-outline';
    } else if (name.includes('toy') || name.includes('game') || name.includes('play')) {
      return 'game-controller-outline';
    } else {
      return 'pricetag-outline'; // Default icon
    }
  };
  
  // Function to handle adding a new category
  const handleAddCategory = () => {
    // In a real app, this would open a modal or navigate to a new screen
    console.log('Add category clicked');
    // Example implementation:
    // router.push('/category/new');
  };
  
  // Function to test Square connection
  const testSquareConnection = async () => {
    try {
      setTestingConnection(true);
      console.log('Testing Square API connection...');
      
      // Use the direct test function from the hook
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
      
      // Call the hook function to reset state
      const tokenStatus = await forceResetConnectionState();
      console.log('Connection state reset complete', tokenStatus);
      
      // Force update UI immediately based on token status
      if (tokenStatus.hasAccessToken) {
        Alert.alert('Success', `Connection state has been reset. Found active token (length: ${tokenStatus.accessTokenLength}).`);
      } else {
        Alert.alert('Success', 'Connection state has been reset. No active tokens found.');
        
        // Force refresh the UI
        setTimeout(() => {
          // This will trigger a UI refresh by reconnecting the API hook
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
          'Successfully processed test callback with Square tokens!\n\n' +
          `Access Token: ${result.hasAccessToken ? 'Yes' : 'No'}\n` +
          `Merchant ID: ${result.hasMerchantId ? 'Yes' : 'No'}\n` +
          `Business Name: ${result.hasBusinessName ? 'Yes' : 'No'}`
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
      
      // Make a direct call to Square's catalog API
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
      
      console.log('Testing backend catalog endpoint with token:', accessToken.substring(0, 10) + '...');
      console.log('Token length:', accessToken.length);
      
      // Make a direct call to the backend catalog endpoint
      const url = `${config.api.baseUrl}/v2/catalog/list?types=CATEGORY`;
      console.log('Backend URL:', url);
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        }
      });
      
      console.log('Backend response status:', response.status);
      
      // Try to get response body regardless of status
      let responseText;
      try {
        responseText = await response.text();
        console.log('Backend response body:', responseText);
      } catch (e) {
        console.log('Failed to get response text:', e);
      }
      
      // If we have text, try to parse it as JSON
      let data;
      try {
        if (responseText) {
          data = JSON.parse(responseText);
          console.log('Backend response data:', JSON.stringify(data).substring(0, 200) + '...');
        }
      } catch (e) {
        console.log('Response is not valid JSON:', e);
      }
      
      if (response.ok) {
        Alert.alert('Success', `Backend catalog endpoint works! ${data?.objects?.length || 0} objects found`);
      } else {
        Alert.alert('Error', `Backend catalog endpoint failed (${response.status}): ${data?.message || responseText || response.statusText}`);
      }
    } catch (error: any) {
      console.error('Error testing backend catalog endpoint:', error);
      Alert.alert('Error', `Failed to test backend endpoint: ${error.message}`);
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
                  
                  {/* Add a button to directly test Square API regardless of connection state */}
                  <TouchableOpacity
                    style={[styles.connectionButton, { backgroundColor: '#28a745', marginTop: 10 }]}
                    onPress={testSquareConnection}
                    disabled={testingConnection}
                  >
                    {testingConnection ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={styles.connectionButtonText}>Direct API Test</Text>
                    )}
                  </TouchableOpacity>
                </View>
              )}
              
              {/* Add reset connection state button */}
              <TouchableOpacity
                style={[
                  styles.connectionButton, 
                  { backgroundColor: '#dc3545', marginTop: 10 }
                ]}
                onPress={resetConnectionState}
                disabled={resettingState}
              >
                {resettingState ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <Text style={styles.connectionButtonText}>Reset Connection State</Text>
                )}
              </TouchableOpacity>
            </View>
            
            {/* Add deep link testing section */}
            <View style={[styles.connectionContainer, { marginTop: 20 }]}>
              <Text style={styles.connectionTitle}>Deep Link Testing</Text>
              <Text style={styles.connectionDescription}>
                Test the deep linking functionality{'\n'}
                {/* Hash fragments like #_=_ in callback URLs are now automatically handled */}
              </Text>
              
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#666' }]}
                onPress={() => {
                  console.log('Testing deep link');
                  testDeepLink();
                }}
              >
                <Text style={styles.connectionButtonText}>Test Deep Link</Text>
              </TouchableOpacity>
              
              {/* Add token validity check button */}
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#6200ee', marginTop: 10 }]}
                onPress={testSquareToken}
              >
                <Text style={styles.connectionButtonText}>Check Square Token Validity</Text>
              </TouchableOpacity>
              
              {/* Add direct catalog test button */}
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#009688', marginTop: 10 }]}
                onPress={testDirectSquareCatalog}
              >
                <Text style={styles.connectionButtonText}>Test Direct Square Catalog</Text>
              </TouchableOpacity>
              
              {/* Add backend test button */}
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#ff5722', marginTop: 10 }]}
                onPress={testBackendCatalogEndpoint}
              >
                <Text style={styles.connectionButtonText}>Test Backend Endpoint</Text>
              </TouchableOpacity>
              
              {/* Add a button for the exact callback test */}
              <TouchableOpacity
                style={[styles.connectionButton, { backgroundColor: '#8e44ad', marginTop: 10 }]}
                onPress={testExactSquareCallback}
                disabled={testingExactCallback}
              >
                {testingExactCallback ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <Text style={styles.connectionButtonText}>Test Exact Callback</Text>
                )}
              </TouchableOpacity>
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
      
      case 'categories':
        return (
          <View style={styles.sectionContent}>
            <ConnectionStatusBar 
              connected={connected || isConnected} 
              message={connected || isConnected ? "Connected to Square" : "Not connected to Square"}
            />
            
            {isCategoriesLoading ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={lightTheme.colors.primary} />
                <Text style={styles.loadingText}>Loading categories...</Text>
              </View>
            ) : categoryError ? (
              <View style={styles.errorContainer}>
                <Ionicons name="alert-circle-outline" size={24} color="red" />
                <Text style={styles.errorText}>{categoryError}</Text>
                <TouchableOpacity 
                  style={styles.retryButton} 
                  onPress={() => fetchCategories()}
                >
                  <Text style={styles.retryButtonText}>Retry</Text>
                </TouchableOpacity>
              </View>
            ) : (
              <>
                <TouchableOpacity 
                  style={styles.addCategoryButton}
                  onPress={handleAddCategory}
                >
                  <Ionicons name="add-circle-outline" size={24} color={lightTheme.colors.primary} />
                  <Text style={styles.addCategoryText}>Add Category</Text>
                </TouchableOpacity>
                
                {categories.length === 0 ? (
                  <View style={styles.emptyContainer}>
                    <Ionicons name="folder-open-outline" size={48} color="#ccc" />
                    <Text style={styles.emptyText}>No categories found</Text>
                    <Text style={styles.emptySubtext}>
                      {connected || isConnected 
                        ? "Create categories to organize your items"
                        : "Connect to Square to sync your categories"}
                    </Text>
                  </View>
                ) : (
                  categories.map((category: Category) => (
                    <View key={category.id} style={styles.categoryItem}>
                      <View style={[styles.categoryIcon, { backgroundColor: category.color }]}>
                        <Ionicons 
                          name={getCategoryIcon(category.name)} 
                          size={24} 
                          color="#fff" 
                        />
                      </View>
                      <View style={styles.categoryInfo}>
                        <Text style={styles.categoryName}>{category.name}</Text>
                        {category.description && (
                          <Text style={styles.categoryDescription}>{category.description}</Text>
                        )}
                      </View>
                    </View>
                  ))
                )}
              </>
            )}
          </View>
        );
      
      default:
        return null;
    }
  };

  return (
    <View style={styles.container}>
      <StatusBar style="dark" />
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Profile</Text>
      </View>
      
      <ProfileTopTabs 
        activeSection={activeSection} 
        onChangeSection={(section) => setActiveSection(section as SectionType)} 
      />
      
      <ScrollView style={styles.content}>
        {renderSection()}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: 60,
    paddingBottom: 16,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  content: {
    flex: 1,
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
    marginBottom: 24,
  },
  infoLabel: {
    fontSize: 16,
    color: '#666',
  },
  infoValue: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
  },
  connectionContainer: {
    marginTop: 20,
    marginBottom: 20,
  },
  connectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 10,
  },
  connectionDescription: {
    fontSize: 14,
    color: '#666',
    marginBottom: 10,
  },
  connectedInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  connectedText: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
  },
  merchantIdText: {
    fontSize: 14,
    color: '#666',
    marginLeft: 8,
  },
  connectionButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  connectionButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  disconnectButton: {
    backgroundColor: '#FFF0F0',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 10,
  },
  settingContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  settingTextContainer: {
    flexDirection: 'column',
  },
  settingLabel: {
    fontSize: 16,
    color: '#333',
  },
  settingDescription: {
    fontSize: 14,
    color: '#666',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  loadingText: {
    color: '#666',
    fontSize: 16,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  errorText: {
    color: '#FF3B30',
    fontSize: 16,
    marginBottom: 20,
    textAlign: 'center',
  },
  retryButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
  },
  retryButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  addCategoryButton: {
    flexDirection: 'row',
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 20,
  },
  addCategoryText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  emptyContainer: {
    justifyContent: 'center',
    alignItems: 'center',
    padding: 40,
  },
  emptyText: {
    color: '#666',
    fontSize: 18,
    marginTop: 16,
    marginBottom: 8,
    fontWeight: '500',
  },
  emptySubtext: {
    color: '#999',
    fontSize: 14,
    textAlign: 'center',
  },
  categoryItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 16,
    paddingRight: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  categoryIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  categoryInfo: {
    flexDirection: 'column',
    marginLeft: 16,
    flex: 1,
  },
  categoryName: {
    fontSize: 16,
    color: '#333',
    fontWeight: '500',
  },
  categoryDescription: {
    fontSize: 14,
    color: '#666',
  },
}); 