import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, Switch, StyleSheet, ActivityIndicator, Alert } from 'react-native';
import { lightTheme } from '../../src/themes'; // Assuming theme is used for styles
import logger from '../../src/utils/logger'; // Added logger
import * as notificationService from '../../src/services/notificationService'; // Import service
import * as notificationState from '../../src/services/notificationState'; // Import state service

const TAG = '[ProfileSettingsScreen]';

const ProfileSettingsScreen = () => {
  // State for settings
  const [notificationsEnabled, setNotificationsEnabled] = useState(false);
  const [darkModeEnabled, setDarkModeEnabled] = useState(false);
  // Added state for loading and token management
  const [isLoading, setIsLoading] = useState(true); // Start true to load initial state
  const [storedPushToken, setStoredPushToken] = useState<string | null>(null);
  const [isToggling, setIsToggling] = useState(false); // Separate loading state for toggle action

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

  // Render loading indicator while fetching initial state
  if (isLoading) {
    return (
      <View style={[styles.container, styles.centered]}>
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.sectionContent}>
        <Text style={styles.sectionTitle}>App Settings</Text>
        <View style={styles.settingItem}>
          <Text style={styles.settingLabel}>Enable Sync Notifications</Text>
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
        <View style={styles.settingItem}>
          <Text style={styles.settingLabel}>Dark Mode</Text>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={darkModeEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={darkModeEnabled}
            onValueChange={setDarkModeEnabled}
          />
        </View>
        {/* Add more settings as needed */}
      </View>
    </View>
  );
};

// Styles extracted and adapted from original app/profile.tsx
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
    // padding: 15, // Removed padding from container, add to sectionContent if needed per section
  },
  centered: { // Added style for centering loading indicator
    justifyContent: 'center',
    alignItems: 'center',
  },
  sectionContent: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 8,
    padding: 20,
    marginBottom: 20,
    marginHorizontal: 15, // Added horizontal margin
    marginTop: 15, // Added top margin
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
    minHeight: 50, // Ensure consistent height even with ActivityIndicator
    // borderBottomWidth: StyleSheet.hairlineWidth, // Optional: uncomment if you want separators
    // borderBottomColor: lightTheme.colors.border,
  },
  settingLabel: {
    fontSize: 16,
    color: lightTheme.colors.text,
  },
});

export default ProfileSettingsScreen; 