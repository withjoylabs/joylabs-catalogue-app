import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, Switch, StyleSheet, ActivityIndicator, Alert, TouchableOpacity, ScrollView, TextInput } from 'react-native';
import { lightTheme } from '../../../src/themes'; // Corrected path
import logger from '../../../src/utils/logger'; // Corrected path
import * as notificationService from '../../../src/services/notificationService'; // Corrected path
import * as notificationState from '../../../src/services/notificationState'; // Corrected path
import { useRouter } from 'expo-router'; // Import router for navigation
import { Ionicons } from '@expo/vector-icons'; // Import icons
import { useAppStore } from '../../../src/store'; // Corrected path and assuming this is the intended import
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { fetchUserAttributes, updateUserAttributes } from 'aws-amplify/auth';
import { List } from 'react-native-paper';

const TAG = '[ProfileSettingsScreen]';

interface SettingsState {
  notificationsEnabled: boolean;
  backgroundSyncEnabled: boolean;
  darkModeEnabled: boolean;
  analyticsEnabled: boolean;
}

const ProfileSettingsScreen = () => {
  const router = useRouter(); // Initialize router for navigation
  const { user } = useAuthenticator((context) => [context.user]);

  const [settings, setSettings] = useState<SettingsState>({
    notificationsEnabled: false,
    backgroundSyncEnabled: false,
    darkModeEnabled: false,
    analyticsEnabled: true,
  });
  // Added state for loading and token management
  const [isLoading, setIsLoading] = useState(true); // Start true to load initial state
  const [storedPushToken, setStoredPushToken] = useState<string | null>(null);
  const [isToggling, setIsToggling] = useState(false); // Separate loading state for toggle action

  // Profile editing state
  const [name, setName] = useState('');
  const [title, setTitle] = useState('');
  const [initialName, setInitialName] = useState('');
  const [initialTitle, setInitialTitle] = useState('');
  const [isSavingProfile, setIsSavingProfile] = useState(false);

  // Auto-search settings from the Zustand store
  const autoSearchOnEnter = useAppStore((state) => state.autoSearchOnEnter);
  const autoSearchOnTab = useAppStore((state) => state.autoSearchOnTab);
  const toggleAutoSearchOnEnter = useAppStore((state) => state.toggleAutoSearchOnEnter);
  const toggleAutoSearchOnTab = useAppStore((state) => state.toggleAutoSearchOnTab);

  // Fetch user profile data
  const handleFetchUserAttributes = async () => {
    try {
      const attributes = await fetchUserAttributes();
      const fetchedName = attributes.name || '';
      const fetchedTitle = attributes['custom:title'] || '';
      setName(fetchedName);
      setTitle(fetchedTitle);
      setInitialName(fetchedName);
      setInitialTitle(fetchedTitle);
      logger.debug(TAG, 'Fetched user attributes', attributes);
    } catch (error) {
      logger.error(TAG, 'Error fetching user attributes', { error });
      Alert.alert('Error', 'Could not load your profile data.');
    }
  };

  // Load initial state on mount
  useEffect(() => {
    const loadInitialState = async () => {
      setIsLoading(true);
      try {
        await handleFetchUserAttributes(); // Fetch profile data
        const enabled = await notificationState.loadNotificationEnabledStatus();
        const token = await notificationState.loadPushToken();
        setSettings({
          notificationsEnabled: enabled,
          backgroundSyncEnabled: false,
          darkModeEnabled: false,
          analyticsEnabled: true,
        });
        setStoredPushToken(token);
        logger.debug(TAG, 'Loaded initial notification state', { enabled, hasToken: !!token });
      } catch (error) {
        logger.error(TAG, 'Failed to load initial notification state', { error });
        // Keep defaults (false, null)
      } finally {
        setIsLoading(false);
      }
    };
    if (user) {
    loadInitialState();
    }
  }, [user]);

  const handleUpdateProfile = async () => {
    if (name === initialName && title === initialTitle) {
      Alert.alert('No Changes', 'You have not made any changes to your profile.');
      return;
    }

    setIsSavingProfile(true);
    try {
      await updateUserAttributes({
        userAttributes: {
          name,
          'custom:title': title,
        },
      });
      setInitialName(name); // Update initial state to reflect saved changes
      setInitialTitle(title);
      Alert.alert('Success', 'Your profile has been updated.');
      logger.info(TAG, 'User profile updated successfully.');
    } catch (error) {
      logger.error(TAG, 'Error updating user profile', { error });
      Alert.alert('Error', 'There was a problem updating your profile. Please try again.');
    } finally {
      setIsSavingProfile(false);
    }
  };

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
          setSettings({
            ...settings,
            notificationsEnabled: true,
          });
          Alert.alert('Success', 'Sync notifications enabled.');
          logger.info(TAG, 'Notifications enabled successfully, token obtained and stored.');
        } else {
          // Failed to get permissions or token from Expo/OS
          Alert.alert('Error', 'Could not enable notifications. Please ensure permissions are granted in system settings.');
          logger.error(TAG, 'Failed to enable notifications (permission or token retrieval failed).');
          setSettings({
            ...settings,
            notificationsEnabled: false,
          });
          await notificationState.saveNotificationEnabledStatus(false); // Ensure stored state is false
        }
      } catch (error: any) {
        // Catch unexpected errors during registration process
        logger.error(TAG, 'Unexpected error enabling notifications', { error: error.message });
        Alert.alert('Error', `An unexpected error occurred: ${error.message}`);
        setSettings({
          ...settings,
          notificationsEnabled: false,
        });
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
      setSettings({
        ...settings,
        notificationsEnabled: false,
      });
      Alert.alert('Disabled', 'Sync notifications disabled.');
    }

    setIsToggling(false);
  }, [settings, storedPushToken]); // Depend on storedPushToken for disabling logic

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

  const isProfileChanged = name !== initialName || title !== initialTitle;

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* Profile Information Section */}
      <View style={styles.sectionContent}>
        <Text style={styles.sectionTitle}>Profile Information</Text>
        <View style={styles.inputContainer}>
          <Text style={styles.inputLabel}>Full Name</Text>
          <TextInput
            style={styles.input}
            value={name}
            onChangeText={setName}
            placeholder="e.g., Jane Doe"
            autoCapitalize="words"
            editable={!isSavingProfile}
          />
        </View>
        <View style={styles.inputContainer}>
          <Text style={styles.inputLabel}>Job Title</Text>
          <TextInput
            style={styles.input}
            value={title}
            onChangeText={setTitle}
            placeholder="e.g., Store Manager"
            autoCapitalize="words"
            editable={!isSavingProfile}
          />
        </View>
        <TouchableOpacity
          style={[styles.saveButton, (!isProfileChanged || isSavingProfile) && styles.saveButtonDisabled]}
          onPress={handleUpdateProfile}
          disabled={!isProfileChanged || isSavingProfile}
        >
          {isSavingProfile ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Text style={styles.saveButtonText}>Save Changes</Text>
          )}
        </TouchableOpacity>
      </View>

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
              thumbColor={settings.notificationsEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
              ios_backgroundColor={lightTheme.colors.border}
              value={settings.notificationsEnabled}
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
            thumbColor={settings.darkModeEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.darkModeEnabled}
            onValueChange={(newValue) => setSettings({ ...settings, darkModeEnabled: newValue })}
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
            thumbColor={settings.backgroundSyncEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.backgroundSyncEnabled}
            onValueChange={(newValue) => setSettings({ ...settings, backgroundSyncEnabled: newValue })}
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

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Manage Account</Text>
        <List.Item
          title="Edit Profile"
          onPress={() => router.push('/(profile)/edit-profile')}
          right={(props) => <List.Icon {...props} icon="chevron-right" />}
        />
        <List.Item
          title="Change Password"
          onPress={() => router.push('/(auth)/change-password')}
          right={(props) => <List.Icon {...props} icon="chevron-right" />}
        />
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
    paddingBottom: 20,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sectionContent: {
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
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 16,
  },
  inputContainer: {
    marginBottom: 16,
  },
  inputLabel: {
    fontSize: 14,
    fontWeight: '500',
    color: '#555',
    marginBottom: 6,
  },
  input: {
    backgroundColor: '#f0f0f5',
    borderRadius: 6,
    padding: 12,
    fontSize: 16,
    color: '#333',
  },
  saveButton: {
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 8,
  },
  saveButtonDisabled: {
    backgroundColor: '#a0c8ff', // Lighter shade of primary for disabled state
  },
  saveButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
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
  section: {
    backgroundColor: 'white',
    borderRadius: 8,
    marginHorizontal: 16,
    marginTop: 20,
    paddingVertical: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 2,
  },
});

export default ProfileSettingsScreen; 