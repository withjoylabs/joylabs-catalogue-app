import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, Switch, StyleSheet, ActivityIndicator, Alert, TouchableOpacity, ScrollView } from 'react-native';
import { lightTheme } from '../../src/themes'; // Assuming theme is used for styles
import logger from '../../src/utils/logger'; // Added logger
import * as notificationService from '../../src/services/notificationService'; // Import service
import * as notificationState from '../../src/services/notificationState'; // Import state service
import { useRouter } from 'expo-router'; // Import router for navigation
import { Ionicons } from '@expo/vector-icons'; // Import icons
import { useAppStore } from '../../src/store'; // Import Zustand store for app settings

const TAG = '[ProfileSettingsScreen]';

const ProfileSettingsScreen = () => {
  const router = useRouter(); // Initialize router for navigation
  // State for settings
  const [notificationsEnabled, setNotificationsEnabled] = useState(false);
  const [darkModeEnabled, setDarkModeEnabled] = useState(false);
  const [scanSoundEnabled, setScanSoundEnabled] = useState(true);
  // Added state for loading and token management
  const [isLoading, setIsLoading] = useState(true); // Start true to load initial state
  const [storedPushToken, setStoredPushToken] = useState<string | null>(null);
  const [isToggling, setIsToggling] = useState(false); // Separate loading state for toggle action

  // Auto-search settings from the Zustand store
  const autoSearchOnEnter = useAppStore((state) => state.autoSearchOnEnter);
  const autoSearchOnTab = useAppStore((state) => state.autoSearchOnTab);
  const toggleAutoSearchOnEnter = useAppStore((state) => state.toggleAutoSearchOnEnter);
  const toggleAutoSearchOnTab = useAppStore((state) => state.toggleAutoSearchOnTab);

  // Load initial state on mount
  useEffect(() => {
    const loadInitialState = async () => {
      setIsLoading(true);
      try {
        const enabled = await notificationState.loadNotificationEnabledStatus();
        const token = await notificationState.loadPushToken();
        setNotificationsEnabled(enabled);
        setStoredPushToken(token);
        logger.debug(TAG, 'Loaded initial notification state', { enabled, hasToken: !!token });
      } catch (error) {
        logger.error(TAG, 'Failed to load initial notification state', { error });
        // Keep defaults (false, null)
      } finally {
        setIsLoading(false);
      }
    };
    loadInitialState();
  }, []);

  const handleToggleNotifications = useCallback(async (newValue: boolean) => {
    setIsToggling(true);
    const action = newValue ? 'Enabling' : 'Disabling';
    logger.info(TAG, `${action} notifications...`);

    if (newValue) {
      // --- Enabling Notifications ---
      try {
        const newPushToken = await notificationService.registerForPushNotificationsAsync();

        if (newPushToken) {
          // Successfully got token (backend registration might have failed, but service returns token)
          await notificationState.savePushToken(newPushToken);
          await notificationState.saveNotificationEnabledStatus(true);
          setStoredPushToken(newPushToken);
          setNotificationsEnabled(true);
          Alert.alert('Success', 'Sync notifications enabled.');
          logger.info(TAG, 'Notifications enabled successfully, token obtained and stored.');
        } else {
          // Failed to get permissions or token from Expo/OS
          Alert.alert('Error', 'Could not enable notifications. Please ensure permissions are granted in system settings.');
          logger.error(TAG, 'Failed to enable notifications (permission or token retrieval failed).');
          setNotificationsEnabled(false); // Keep toggle off
          await notificationState.saveNotificationEnabledStatus(false); // Ensure stored state is false
        }
      } catch (error: any) {
        // Catch unexpected errors during registration process
        logger.error(TAG, 'Unexpected error enabling notifications', { error: error.message });
        Alert.alert('Error', `An unexpected error occurred: ${error.message}`);
        setNotificationsEnabled(false); // Keep toggle off
        await notificationState.saveNotificationEnabledStatus(false);
      }
    } else {
      // --- Disabling Notifications ---
      logger.info(TAG, 'Disabling notifications and clearing token.');
      // TODO: Call backend to unregister token if implemented
      if (storedPushToken) {
         try {
            logger.info(TAG, 'Calling backend to unregister token (placeholder)... ');
            // await notificationService.unregisterPushNotificationsAsync(storedPushToken); // Use placeholder or actual API call
            // await apiClient.user.unregisterPushToken(storedPushToken); // Example direct call
            logger.info(TAG, 'Backend token unregistration simulated.');
         } catch (unregisterError) {
            logger.error(TAG, 'Failed to unregister token from backend', { unregisterError });
            // Decide if this should prevent disabling locally - likely not.
         }
      }
      await notificationState.clearPushToken();
      await notificationState.saveNotificationEnabledStatus(false);
      setStoredPushToken(null);
      setNotificationsEnabled(false);
      Alert.alert('Disabled', 'Sync notifications disabled.');
    }

    setIsToggling(false);
  }, [storedPushToken]); // Depend on storedPushToken for disabling logic

  // Handler for navigating to the modal test screen
  const navigateToModalTest = () => {
    router.push('/modal-test');
  };

  // Render loading indicator while fetching initial state
  if (isLoading) {
    return (
      <View style={[styles.container, styles.centered]}>
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* App Settings Section */}
      <View style={styles.sectionContent}>
        <Text style={styles.sectionTitle}>App Settings</Text>
        
        {/* Notifications toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Enable Sync Notifications</Text>
            <Text style={styles.settingDescription}>Receive alerts about inventory changes</Text>
          </View>
          {isToggling ? (
             <ActivityIndicator size="small" color={lightTheme.colors.primary} />
          ) : (
            <Switch
              trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
              thumbColor={notificationsEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
              ios_backgroundColor={lightTheme.colors.border}
              value={notificationsEnabled}
              onValueChange={handleToggleNotifications}
              disabled={isToggling} // Disable while action is in progress
            />
          )}
        </View>
        
        {/* Dark Mode toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Dark Mode</Text>
            <Text style={styles.settingDescription}>Use dark theme throughout the app</Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={darkModeEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={darkModeEnabled}
            onValueChange={setDarkModeEnabled}
          />
        </View>
        
        {/* Scan Sound toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Scan Sound</Text>
            <Text style={styles.settingDescription}>Play sound when item is scanned</Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={scanSoundEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={scanSoundEnabled}
            onValueChange={setScanSoundEnabled}
          />
        </View>
      </View>

      {/* Scanner Settings Section */}
      <View style={styles.sectionContent}>
        <Text style={styles.sectionTitle}>Scanner Settings</Text>
        
        {/* Auto-search on Enter Key toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Auto-search on Enter Key</Text>
            <Text style={styles.settingDescription}>Automatically search when Enter key is pressed</Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={autoSearchOnEnter ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={autoSearchOnEnter}
            onValueChange={toggleAutoSearchOnEnter}
          />
        </View>
        
        {/* Auto-search on Tab Key toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Auto-search on Tab Key</Text>
            <Text style={styles.settingDescription}>Automatically search when Tab key is pressed (for barcode scanners)</Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={autoSearchOnTab ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={autoSearchOnTab}
            onValueChange={toggleAutoSearchOnTab}
          />
        </View>
      </View>

      {/* Developer Options Section */}
      <View style={styles.sectionContent}>
        <Text style={styles.sectionTitle}>Developer Options</Text>
        
        {/* Modal Test Navigation Option */}
        <TouchableOpacity
          style={styles.navItem}
          onPress={navigateToModalTest}
        >
          <View style={styles.navItemContent}>
            <Text style={styles.settingLabel}>System Modal Examples</Text>
            <Ionicons 
              name="chevron-forward" 
              size={20} 
              color={lightTheme.colors.text} 
            />
          </View>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
};

// Styles for the settings screen
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  contentContainer: {
    paddingBottom: 30, // Add padding to the bottom so content isn't cut off
  },
  centered: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  sectionContent: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 8,
    padding: 20,
    marginBottom: 20,
    marginHorizontal: 15,
    marginTop: 15,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: lightTheme.colors.text,
    marginBottom: 15,
  },
  settingItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    minHeight: 50,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: lightTheme.colors.border,
  },
  settingTextContainer: {
    flex: 1,
    marginRight: 10,
  },
  settingLabel: {
    fontSize: 16,
    color: lightTheme.colors.text,
  },
  settingDescription: {
    fontSize: 12,
    color: lightTheme.colors.secondary || '#666',
    marginTop: 4,
  },
  navItem: {
    paddingVertical: 12,
  },
  navItemContent: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
});

export default ProfileSettingsScreen; 