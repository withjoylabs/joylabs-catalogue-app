import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, Switch, ActivityIndicator, TextInput, TouchableOpacity, Alert } from 'react-native';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { fetchUserAttributes, updateUserAttributes } from 'aws-amplify/auth';
import { lightTheme } from '../../../src/themes';
import { useAppStore } from '../../../src/store';
import logger from '../../../src/utils/logger';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

const TAG = '[ProfileSettingsScreen]';

interface SettingsState {
  backgroundSyncEnabled: boolean;
  darkModeEnabled: boolean;
  analyticsEnabled: boolean;
}

const ProfileSettingsScreen = () => {
  const { user } = useAuthenticator((context) => [context.user]);
  const router = useRouter();
  
  // Loading states
  const [isLoading, setIsLoading] = useState(true);
  const [isSavingProfile, setIsSavingProfile] = useState(false);
  
  // Profile editing state
  const [name, setName] = useState('');
  const [title, setTitle] = useState('');
  const [initialName, setInitialName] = useState('');
  const [initialTitle, setInitialTitle] = useState('');
  
  // Settings state
  const [settings, setSettings] = useState<SettingsState>({
    backgroundSyncEnabled: false,
    darkModeEnabled: false,
    analyticsEnabled: true,
  });
  
  // Zustand store integration
  const autoSearchOnEnter = useAppStore((state) => state.autoSearchOnEnter);
  const autoSearchOnTab = useAppStore((state) => state.autoSearchOnTab);
  const use12HourFormat = useAppStore((state) => state.use12HourFormat);
  const toggleAutoSearchOnEnter = useAppStore((state) => state.toggleAutoSearchOnEnter);
  const toggleAutoSearchOnTab = useAppStore((state) => state.toggleAutoSearchOnTab);
  const toggleUse12HourFormat = useAppStore((state) => state.toggleUse12HourFormat);

  // Load initial state with proper authentication handling
  useEffect(() => {
    const loadInitialState = async () => {
      logger.info(TAG, 'Starting settings load...');
      setIsLoading(true);
      
      // Add timeout protection
      const timeoutId = setTimeout(() => {
        logger.warn(TAG, 'Settings load timeout reached, forcing completion');
        setIsLoading(false);
      }, 8000); // 8 second timeout
      
      try {
        if (user?.signInDetails?.loginId) {
          logger.info(TAG, 'User is authenticated, loading profile...');
          
          try {
            const attributes = await fetchUserAttributes();
            logger.info(TAG, 'User attributes loaded successfully');
            
            const fetchedName = attributes.name || '';
            const fetchedTitle = attributes['custom:title'] || '';
            setName(fetchedName);
            setTitle(fetchedTitle);
            setInitialName(fetchedName);
            setInitialTitle(fetchedTitle);
          } catch (attributeError) {
            logger.error(TAG, 'Failed to load user attributes', { error: attributeError });
            // Continue with empty values
          }
        } else {
          logger.info(TAG, 'User not authenticated, using default values');
          // Set default empty values for non-authenticated users
          setName('');
          setTitle('');
          setInitialName('');
          setInitialTitle('');
        }
        
        logger.info(TAG, 'Settings loaded successfully');
      } catch (error) {
        logger.error(TAG, 'Failed to load settings', { error });
      } finally {
        clearTimeout(timeoutId);
        logger.info(TAG, 'Setting loading to false');
        setIsLoading(false);
      }
    };

    logger.info(TAG, 'useEffect triggered', { 
      hasUser: !!user, 
      loginId: user?.signInDetails?.loginId,
      userType: typeof user
    });

    loadInitialState();
  }, [user?.signInDetails?.loginId]);

  // Handle profile update
  const handleUpdateProfile = async () => {
    if (!user?.signInDetails?.loginId) {
      Alert.alert('Error', 'You must be logged in to update your profile.');
      return;
    }

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
      setInitialName(name);
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

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
        <Text style={styles.loadingText}>Loading settings...</Text>
      </View>
    );
  }

  const isProfileChanged = name !== initialName || title !== initialTitle;
  const isAuthenticated = !!user?.signInDetails?.loginId;

  return (
    <ScrollView style={styles.container}>
      {/* Profile Information Section - Only show if authenticated */}
      {isAuthenticated && (
        <View style={styles.section}>
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
      )}

      {/* Scanner Settings Section */}
      <View style={styles.section}>
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
        
        {/* 12-hour time format toggle */}
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>12-Hour Time Format</Text>
            <Text style={styles.settingDescription}>Display time in 12-hour format with AM/PM</Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={use12HourFormat ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={use12HourFormat}
            onValueChange={toggleUse12HourFormat}
          />
        </View>
      </View>

      {/* App Settings Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>App Settings</Text>
        
        {/* Notification Settings Navigation */}
        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/(tabs)/(profile)/notification-settings')}
        >
          <View style={styles.navItemContent}>
          <View style={styles.settingTextContainer}>
              <Text style={styles.settingLabel}>Notification Settings</Text>
              <Text style={styles.settingDescription}>Configure which notifications you receive</Text>
          </View>
            <Ionicons 
              name="chevron-forward" 
              size={20} 
              color={lightTheme.colors.text} 
          />
        </View>
        </TouchableOpacity>
        
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
      </View>

      {/* Developer Options Section */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Developer Options</Text>
        
        {/* Modal Test Navigation Option */}
        <TouchableOpacity
          style={styles.navItem}
          onPress={() => router.push('/modal-test')}
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

      {/* Authentication Status */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Account Status</Text>
        <Text style={styles.text}>
          Status: {isAuthenticated ? 'Authenticated' : 'Not Authenticated'}
        </Text>
        {isAuthenticated && (
          <Text style={styles.text}>
            User: {user.signInDetails?.loginId}
          </Text>
        )}
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: lightTheme.colors.background,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: lightTheme.colors.text,
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
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 16,
  },
  text: {
    fontSize: 16,
    marginBottom: 10,
    color: lightTheme.colors.text,
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
    backgroundColor: '#a0c8ff',
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
});

export default ProfileSettingsScreen; 