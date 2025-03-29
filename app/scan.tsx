import React, { useState, useEffect, useCallback } from 'react';
import {
  StyleSheet, 
  View, 
  TextInput, 
  TouchableOpacity, 
  Text, 
  Alert, 
  ActivityIndicator,
  Dimensions,
  SafeAreaView
} from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { Stack } from 'expo-router';
import * as Network from 'expo-network';
import api from '../src/api';
import { useApi } from '../src/providers/ApiProvider';
import logger from '../src/utils/logger';

// Component to handle product lookup
export default function ScanScreen() {
  const router = useRouter();
  const { isConnected: isSquareConnected } = useApi();
  const [searchQuery, setSearchQuery] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isOnline, setIsOnline] = useState(true);
  
  // Check network connectivity on mount and set up interval
  useEffect(() => {
    checkConnectivity();
    
    // Set up an interval to check connectivity
    const intervalId = setInterval(checkConnectivity, 10000); // Check every 10 seconds
    
    return () => {
      clearInterval(intervalId);
    };
  }, []);
  
  // Function to check network connectivity
  const checkConnectivity = async () => {
    try {
      const networkState = await Network.getNetworkStateAsync();
      const newIsOnline = networkState.isConnected === true && networkState.isInternetReachable === true;
      
      // Only log if the state changes
      if (newIsOnline !== isOnline) {
        if (newIsOnline) {
          logger.info('Connectivity', 'Device is now online');
        } else {
          logger.warn('Connectivity', 'Device is now offline');
        }
        setIsOnline(newIsOnline);
      }
    } catch (error) {
      logger.error('Connectivity', 'Error checking network state', { error });
    }
  };
  
  // Handle search submission
  const handleSearch = async () => {
    if (!searchQuery.trim()) {
      return;
    }
    
    if (!isOnline) {
      Alert.alert(
        "You're offline",
        "Please check your internet connection and try again.",
        [{ text: "OK" }]
      );
      return;
    }
    
    if (!isSquareConnected) {
      Alert.alert(
        "Not connected to Square",
        "Please connect to your Square account in the Profile tab before searching.",
        [{ text: "OK" }]
      );
      return;
    }
    
    setIsLoading(true);
    
    try {
      logger.info('Search', `Searching for product: ${searchQuery}`);
      
      // Search for product by name/SKU
      const response = await api.catalog.searchItems({
        query: {
          text: searchQuery
        }
      });
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to search products');
      }
      
      const items = response.data?.items || [];
      
      if (items.length === 0) {
        // No product found, show alert
        displayProductNotFound();
      } else if (items.length === 1) {
        // Single product found, navigate to it
        const productId = items[0].id;
        router.push(`/item/${productId}`);
      } else {
        // Multiple products found, let user select
        // Store the search query for the results page
        router.push({
          pathname: '/search-results',
          params: { query: searchQuery }
        });
      }
    } catch (error) {
      logger.error('Search', 'Error searching products', { error, query: searchQuery });
      Alert.alert('Error', 'An error occurred while searching. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };
  
  // Display product not found alert
  const displayProductNotFound = () => {
    Alert.alert(
      'Product Not Found',
      'Would you like to add this product to your catalog?',
      [
        {
          text: 'Cancel',
          style: 'cancel'
        },
        {
          text: 'Add Product',
          onPress: () => router.push({
            pathname: '/add-product',
            params: { name: searchQuery }
          })
        }
      ]
    );
  };
  
  return (
    <SafeAreaView style={styles.container}>
      <Stack.Screen
        options={{
          title: 'Product Search',
          headerShown: true,
        }}
      />
      
      <View style={styles.innerContainer}>
        <View style={styles.searchContainer}>
          <TextInput
            style={styles.input}
            placeholder="Search by product name or SKU"
            value={searchQuery}
            onChangeText={setSearchQuery}
            onSubmitEditing={handleSearch}
            autoCapitalize="none"
            returnKeyType="search"
          />
          <TouchableOpacity 
            style={styles.searchButton}
            onPress={handleSearch}
            disabled={isLoading}
          >
            {isLoading ? (
              <ActivityIndicator color="#FFFFFF" />
            ) : (
              <Ionicons name="search" size={24} color="#FFFFFF" />
            )}
          </TouchableOpacity>
        </View>
        
        {!isOnline && (
          <View style={styles.offlineMessage}>
            <Ionicons name="cloud-offline-outline" size={24} color="#ff6b6b" />
            <Text style={styles.offlineText}>
              You're currently offline. Search will be available when you're back online.
            </Text>
          </View>
        )}
        
        {!isSquareConnected && isOnline && (
          <View style={styles.offlineMessage}>
            <Ionicons name="alert-circle-outline" size={24} color="#ff9f43" />
            <Text style={styles.offlineText}>
              Please connect to your Square account in the Profile tab to search for products.
            </Text>
          </View>
        )}
      </View>
    </SafeAreaView>
  );
}

const { width } = Dimensions.get('window');

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  innerContainer: {
    flex: 1,
    padding: 20,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  input: {
    flex: 1,
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  searchButton: {
    backgroundColor: '#4b7bec',
    borderRadius: 8,
    padding: 12,
    marginLeft: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  offlineMessage: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    padding: 15,
    borderRadius: 8,
    marginTop: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  offlineText: {
    marginLeft: 10,
    color: '#555',
    flex: 1,
    fontSize: 14,
  },
}); 