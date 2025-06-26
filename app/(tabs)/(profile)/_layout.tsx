import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Alert, TextInput, Platform } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView } from 'react-native-safe-area-context';
import logger from '../../../src/utils/logger';

// Screen components are now routed via file system routing with Stack
// import ProfileTab from './index';
// import SettingsTab from './settings';
// import SyncTab from './sync';

// const Tab = createMaterialTopTabNavigator();

const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';

// Custom back button component for the main profile screen
const ProfileIndexBackButton = () => {
  const router = useRouter();
  return (
    <TouchableOpacity
      onPress={() => {
        logger.info('ProfileLayout', "Custom back button on profile index pressed, replacing with scan home");
        router.replace('/(tabs)/(scan)');
      }}
      style={{ marginLeft: Platform.OS === 'ios' ? 10 : 0, padding: 5 }} // Adjust styling as needed
    >
      <Ionicons name="arrow-back" size={24} color="black" />
    </TouchableOpacity>
  );
};

export default function ProfileLayout() {
  const [debugTaps, setDebugTaps] = useState(0);
  const [showDebugTools, setShowDebugTools] = useState(false);
  const [inspectId, setInspectId] = useState('');
  const [isInspectingById, setIsInspectingById] = useState(false);
  
  // const { isConnected, merchantId, isLoading: isConnectingToSquare, error: squareError } = useApi(); // Not used in this layout logic directly

  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}> 
      <StatusBar style="dark" />
      <Stack>
        <Stack.Screen 
          name="index" 
          options={{
            title: 'Profile',
            headerLeft: () => <ProfileIndexBackButton />,
            // headerTitleAlign: 'center', // Optional: if you want to center the title with a left button
          }} 
        />
        <Stack.Screen 
          name="settings" 
          options={{ 
            title: 'Settings', 
            // Gets default back button navigating to Profile index
          }} 
        />
        <Stack.Screen 
          name="settings-debug" 
          options={{ 
            title: 'Settings Debug', 
            // Gets default back button navigating to Profile index
          }} 
        />
        <Stack.Screen 
          name="sync" 
          options={{ 
            title: 'Sync Catalog',
            // Gets default back button navigating to Profile index
          }} 
        />
      </Stack>

      {/* Debug tools can remain, but their header activation is removed */}
      {/* Consider moving debug tools activation to a less intrusive place if header is default */}
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
  // Removed header, headerTitle, headerActions styles as they are not used with default header
  // backButton style is now used by ProfileIndexBackButton if needed, or can be inline
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
    zIndex: 10, 
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
  }
}); 