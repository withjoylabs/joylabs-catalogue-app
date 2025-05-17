import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, ScrollView } from 'react-native';
import { useApi } from '../../../src/providers/ApiProvider';
import { useSquareAuth } from '../../../src/hooks/useSquareAuth';
import logger from '../../../src/utils/logger';
import { useRouter } from 'expo-router'; // Added for navigation
import { Ionicons } from '@expo/vector-icons'; // For icons

// Dummy user data (Consider fetching real data or passing via context/props)
const user = {
  name: 'John Doe',
  email: 'john.doe@example.com',
  role: 'Store Manager',
  joinDate: 'January 2024',
};

export default function ProfileScreen() { // Renamed from ProfileTab to ProfileScreen for clarity
  const router = useRouter(); // Added router hook
  // Get connection state and actions from context/hooks
  const {
    isConnected,
    merchantId,
    isLoading: isConnectingToSquare,
    error: squareError,
    connectToSquare,
    disconnectFromSquare
  } = useApi();
  
  // Get test connection function (or pass it down if needed)
  const { testConnection } = useSquareAuth(); 
  const [testingConnection, setTestingConnection] = React.useState(false);

  // Replicated test function (or pass down from layout)
  const testSquareConnection = async () => {
    try {
      setTestingConnection(true);
      logger.info('ProfileScreen', 'Testing Square API connection...');
      const result = await testConnection();
      logger.info('ProfileScreen', 'Square API test result:', result);
      if (result.success) {
        Alert.alert('Success', `Connected! Merchant: ${result.data?.businessName || 'N/A'}`);
      } else {
        Alert.alert('Error', `Connection failed: ${result.error || 'Unknown'}`);
      }
    } catch (error: any) {
      logger.error('ProfileScreen', 'Error testing Square connection', { error });
      Alert.alert('Error', `Test failed: ${error.message}`);
    } finally {
      setTestingConnection(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      <View style={styles.section}>
        <View style={styles.avatarContainer}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{user.name.charAt(0)}</Text>
          </View>
          <Text style={styles.userName}>{user.name}</Text>
          <Text style={styles.userRole}>{user.role}</Text>
        </View>

        <View style={styles.infoItem}>
          <Text style={styles.infoLabel}>Email</Text>
          <Text style={styles.infoValue}>{user.email}</Text>
        </View>

        <View style={styles.infoItem}>
          <Text style={styles.infoLabel}>Member since</Text>
          <Text style={styles.infoValue}>{user.joinDate}</Text>
        </View>
      </View>

      {/* Navigation Links Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Manage Account</Text>
        <TouchableOpacity style={styles.navButton} onPress={() => router.push('/(profile)/settings')}>
          <Ionicons name="settings-outline" size={22} color={styles.navButtonText.color} style={styles.navButtonIcon} />
          <Text style={styles.navButtonText}>App Settings</Text>
          <Ionicons name="chevron-forward" size={20} color={styles.navButtonText.color} />
        </TouchableOpacity>
        <TouchableOpacity style={styles.navButton} onPress={() => router.push('/(profile)/sync')}>
          <Ionicons name="sync-circle-outline" size={22} color={styles.navButtonText.color} style={styles.navButtonIcon} />
          <Text style={styles.navButtonText}>Sync Catalog</Text>
          <Ionicons name="chevron-forward" size={20} color={styles.navButtonText.color} />
        </TouchableOpacity>
      </View>

      <View style={[styles.section, styles.connectionContainer]}>
        <Text style={styles.sectionTitle}>Square Connection</Text>
        <Text style={styles.connectionDescription}>
          Connect your Square account to sync your inventory, items, and categories.
        </Text>

        {isConnected ? (
          <View>
            <View style={styles.connectedInfo}>
              <Text style={styles.connectedText}>Connected to Square</Text>
              {merchantId && (
                <Text style={styles.merchantIdText}>Merchant ID: {merchantId.substring(0, 8)}...</Text>
              )}
            </View>

            <TouchableOpacity
              style={[styles.actionButton, { backgroundColor: '#007bff', marginBottom: 10 }]}
              onPress={testSquareConnection}
              disabled={testingConnection}
            >
              {testingConnection ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <Text style={styles.actionButtonText}>Test Square Connection</Text>
              )}
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.actionButton, styles.disconnectButton]}
              onPress={disconnectFromSquare}
              disabled={isConnectingToSquare}
            >
              {isConnectingToSquare ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <Text style={styles.actionButtonText}>Disconnect from Square</Text>
              )}
            </TouchableOpacity>
          </View>
        ) : (
          <View>
            <TouchableOpacity
              style={styles.actionButton}
              onPress={() => {
                logger.info('ProfileScreen', 'Connect to Square button pressed');
                connectToSquare();
              }}
              disabled={isConnectingToSquare}
            >
              {isConnectingToSquare ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <Text style={styles.actionButtonText}>Connect to Square</Text>
              )}
            </TouchableOpacity>
          </View>
        )}

        {/* Display Square connection error */}
        {squareError && (
          <Text style={styles.errorText}>Error: {squareError instanceof Error ? squareError.message : String(squareError)}</Text>
        )}
      </View>
    </ScrollView>
  );
}

// Styles extracted from original profile.tsx for the 'profile' section
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f0f0f5', // Light grey background for the whole screen
  },
  contentContainer: {
    paddingBottom: 20, // Ensure space at the bottom
  },
  section: {
    backgroundColor: 'white',
    borderRadius: 8,
    marginHorizontal: 16,
    marginTop: 20,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 2,
  },
  avatarContainer: {
    alignItems: 'center',
    marginBottom: 16,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#e0e0e0',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  avatarText: {
    fontSize: 36,
    fontWeight: 'bold',
    color: '#555',
  },
  userName: {
    fontSize: 22,
    fontWeight: '600',
    color: '#333',
  },
  userRole: {
    fontSize: 16,
    color: '#777',
    marginTop: 4,
  },
  infoItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  infoLabel: {
    fontSize: 16,
    color: '#555',
  },
  infoValue: {
    fontSize: 16,
    color: '#333',
    fontWeight: '500',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 12,
  },
  navButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  navButtonIcon: {
    marginRight: 15,
  },
  navButtonText: {
    flex: 1, // Allows text to take available space
    fontSize: 16,
    color: '#333',
  },
  connectionContainer: {
    //marginTop: 20, // Already handled by section margin
    //padding: 16, // Already handled by section padding
    //backgroundColor: '#f8f9fa', // Handled by section style
    //borderRadius: 8, // Handled by section style
  },
  connectionDescription: {
    fontSize: 14,
    color: '#666',
    marginBottom: 16,
    lineHeight: 20,
  },
  connectedInfo: {
    paddingVertical: 10,
    backgroundColor: '#e6f7ff',
    borderRadius: 6,
    marginBottom: 15,
    paddingHorizontal: 12,
    alignItems: 'center',
  },
  connectedText: {
    fontSize: 15,
    fontWeight: '500',
    color: '#005f99',
  },
  merchantIdText: {
    fontSize: 13,
    color: '#005f99',
    marginTop: 4,
  },
  actionButton: {
    backgroundColor: '#007bff', // Primary action color
    paddingVertical: 14,
    borderRadius: 6,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 10, // Default margin for buttons
  },
  actionButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  disconnectButton: {
    backgroundColor: '#dc3545', // Red for disconnect/destructive action
  },
  errorText: {
    color: '#dc3545',
    marginTop: 10,
    textAlign: 'center',
    fontSize: 14,
  },
}); 