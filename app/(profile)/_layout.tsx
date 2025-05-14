import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Switch, ActivityIndicator, Alert, TextInput } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { createMaterialTopTabNavigator } from '@react-navigation/material-top-tabs';
import { SafeAreaView } from 'react-native-safe-area-context';
import { lightTheme } from '../../src/themes';
import ConnectionStatusBar from '../../src/components/ConnectionStatusBar';
import { useApi } from '../../src/providers/ApiProvider';
import { useSquareAuth } from '../../src/hooks/useSquareAuth';
import * as SecureStore from 'expo-secure-store';
import config from '../../src/config';
import tokenService from '../../src/services/tokenService';
import logger from '../../src/utils/logger';

// Import the screen components directly
import ProfileTab from './index';
import SettingsTab from './settings';
import SyncTab from './sync';

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
    error: squareError
  } = useApi();

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="black" />
        </TouchableOpacity>
        <Text 
          style={styles.headerTitle}
          // Debug mode activation
          onPress={() => {
            setDebugTaps(prev => prev + 1);
            if (debugTaps >= 6) {
              setShowDebugTools(true);
              setDebugTaps(0);
              Alert.alert('Debug Mode', 'Debug tools activated');
            }
          }}
        >
          Profile
        </Text>
        <View style={styles.headerActions}></View>
      </View>

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
          name="Profile" 
          component={ProfileTab}
        />
        <Tab.Screen 
          name="Settings" 
          component={SettingsTab}
        />
        <Tab.Screen 
          name="Sync Catalog" 
          component={SyncTab}
        />
      </Tab.Navigator>

      {showDebugTools && (
        <View style={styles.debugContainer}>
          <View style={styles.debugHeader}>
            <Text style={styles.debugTitle}>Debug Tools</Text>
            <TouchableOpacity onPress={() => setShowDebugTools(false)}>
              <Ionicons name="close" size={24} color="#333" />
            </TouchableOpacity>
          </View>
          
          <View style={styles.debugControls}>
            <TextInput
              style={styles.debugInput}
              placeholder="Inspect by ID"
              value={inspectId}
              onChangeText={setInspectId}
            />
            
            <TouchableOpacity 
              style={styles.debugButton}
              onPress={() => {
                if (inspectId) {
                  setIsInspectingById(true);
                  // Implement inspection logic here
                  Alert.alert('Debug', `Inspecting item with ID: ${inspectId}`);
                  setIsInspectingById(false);
                } else {
                  Alert.alert('Debug', 'Please enter an ID to inspect');
                }
              }}
              disabled={isInspectingById || !inspectId}
            >
              <Text style={styles.debugButtonText}>
                {isInspectingById ? 'Inspecting...' : 'Inspect by ID'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      )}
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
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#f5f5f5',
    borderTopWidth: 1,
    borderTopColor: '#ddd',
    padding: 16,
    paddingBottom: 32,
  },
  debugHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  debugTitle: {
    fontWeight: 'bold',
    fontSize: 16,
  },
  debugControls: {
    marginTop: 5,
  },
  debugInput: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    padding: 8,
    marginBottom: 10,
  },
  debugButton: {
    backgroundColor: '#2196f3',
    padding: 10,
    borderRadius: 5,
    alignItems: 'center', 
  },
  debugButtonText: {
    color: 'white',
    fontWeight: '600',
  },
}); 