import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, ScrollView } from 'react-native';
import { useApi } from '../../src/providers/ApiProvider';
import { useSquareAuth } from '../../src/hooks/useSquareAuth';
import logger from '../../src/utils/logger'; // Assuming logger might be needed

// Dummy user data (Consider fetching real data or passing via context/props)
const user = {
  name: 'John Doe',
  email: 'john.doe@example.com',
  role: 'Store Manager',
  joinDate: 'January 2024',
};

export default function ProfileTab() {
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
      logger.info('ProfileTab', 'Testing Square API connection...');
      const result = await testConnection();
      logger.info('ProfileTab', 'Square API test result:', result);
      if (result.success) {
        Alert.alert('Success', `Connected! Merchant: ${result.data?.businessName || 'N/A'}`);
      } else {
        Alert.alert('Error', `Connection failed: ${result.error || 'Unknown'}`);
      }
    } catch (error: any) {
      logger.error('ProfileTab', 'Error testing Square connection', { error });
      Alert.alert('Error', `Test failed: ${error.message}`);
    } finally {
      setTestingConnection(false);
    }
  };

  return (
    <ScrollView style={styles.sectionContent}>
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
              <Text style={styles.connectedText}>Connected to Square</Text>
              {merchantId && (
                <Text style={styles.merchantIdText}>Merchant ID: {merchantId.substring(0, 8)}...</Text>
              )}
            </View>

            <TouchableOpacity
              style={[styles.connectionButton, { backgroundColor: '#007bff', marginBottom: 10 }]}
              onPress={testSquareConnection} // Use local/passed function
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
                logger.info('ProfileTab', 'Connect to Square button pressed');
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
            {/* Removed Direct API Test button as it's in debug tools */}
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
  sectionContent: {
    padding: 16,
    backgroundColor: 'white', // Set background for the content area
    flex: 1, // Ensure it takes space if needed
  },
  avatarContainer: {
    alignItems: 'center',
    marginBottom: 24,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#e0e0e0',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  avatarText: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#666',
  },
  userName: {
    fontSize: 20,
    fontWeight: 'bold',
  },
  userRole: {
    fontSize: 16,
    color: '#666',
  },
  infoContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  infoLabel: {
    fontSize: 16,
    color: '#333',
  },
  infoValue: {
    fontSize: 16,
    color: '#666',
  },
  connectionContainer: {
    marginTop: 24,
    padding: 16,
    backgroundColor: '#f8f9fa',
    borderRadius: 8,
  },
  connectionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  connectionDescription: {
    fontSize: 14,
    color: '#666',
    marginBottom: 16,
  },
  connectionButton: {
    backgroundColor: '#007bff',
    paddingVertical: 12,
    borderRadius: 6,
    alignItems: 'center',
    marginBottom: 10,
  },
  connectionButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
  },
  disconnectButton: {
    backgroundColor: '#dc3545',
  },
  connectedInfo: {
    paddingVertical: 10,
    marginBottom: 10,
    alignItems: 'center',
  },
  connectedText: {
    fontSize: 16,
    color: '#28a745',
    fontWeight: '500',
  },
  merchantIdText: {
    fontSize: 12,
    color: '#6c757d',
    marginTop: 4,
  },
  errorText: {
    color: 'red',
    marginTop: 10,
    textAlign: 'center',
  },
}); 