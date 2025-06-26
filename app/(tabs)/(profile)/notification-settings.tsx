import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, Switch, ActivityIndicator } from 'react-native';
import { lightTheme } from '../../../src/themes';
import NotificationService from '../../../src/services/notificationService';
import logger from '../../../src/utils/logger';

const TAG = '[NotificationSettingsScreen]';

interface NotificationSettings {
  webhookCatalogUpdate: boolean;
  syncComplete: boolean;
  syncError: boolean;
  syncPending: boolean;
  reorderAdded: boolean;
  authSuccess: boolean;
  generalInfo: boolean;
  systemError: boolean;
  pushNotifications: boolean;
}

const NOTIFICATION_DESCRIPTIONS = {
  webhookCatalogUpdate: 'Notifications when Square catalog changes are detected',
  syncComplete: 'Notifications when catalog sync completes successfully',
  syncError: 'Notifications when catalog sync encounters errors',
  syncPending: 'Notifications when sync is waiting due to no internet connection',
  reorderAdded: 'Notifications when items are added to reorder list',
  authSuccess: 'Notifications when authentication is successful',
  generalInfo: 'General informational notifications',
  systemError: 'Critical system error notifications',
  pushNotifications: 'Enable iOS push notifications (requires app restart)',
};

const NotificationSettingsScreen = () => {
  const [isLoading, setIsLoading] = useState(true);
  const [settings, setSettings] = useState<NotificationSettings>({
    webhookCatalogUpdate: true,
    syncComplete: true,
    syncError: true,
    syncPending: true,
    reorderAdded: true,
    authSuccess: false,
    generalInfo: true,
    systemError: true,
    pushNotifications: true,
  });

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      setIsLoading(true);
      const loadedSettings = await NotificationService.getNotificationSettings();
      setSettings(loadedSettings);
      logger.info(TAG, 'Notification settings loaded', { settings: loadedSettings });
    } catch (error) {
      logger.error(TAG, 'Failed to load notification settings', { error });
    } finally {
      setIsLoading(false);
    }
  };

  const updateSetting = async (key: keyof NotificationSettings, value: boolean) => {
    try {
      const newSettings = { ...settings, [key]: value };
      setSettings(newSettings);
      await NotificationService.updateNotificationSettings(newSettings);
      logger.info(TAG, 'Notification setting updated', { key, value });
    } catch (error) {
      logger.error(TAG, 'Failed to update notification setting', { key, value, error });
      // Revert on error
      setSettings(settings);
    }
  };

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
        <Text style={styles.loadingText}>Loading notification settings...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Notification Preferences</Text>
        <Text style={styles.headerSubtitle}>
          Control which notifications you receive in the notification center and as push notifications.
        </Text>
      </View>

      {/* Square Integration Notifications */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Square Integration</Text>
        
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Catalog Updates</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.webhookCatalogUpdate}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.webhookCatalogUpdate ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.webhookCatalogUpdate}
            onValueChange={(value) => updateSetting('webhookCatalogUpdate', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Sync Complete</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.syncComplete}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.syncComplete ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.syncComplete}
            onValueChange={(value) => updateSetting('syncComplete', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Sync Errors</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.syncError}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.syncError ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.syncError}
            onValueChange={(value) => updateSetting('syncError', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Sync Pending</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.syncPending}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.syncPending ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.syncPending}
            onValueChange={(value) => updateSetting('syncPending', value)}
          />
        </View>
      </View>

      {/* App Notifications */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>App Notifications</Text>
        
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Reorder Added</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.reorderAdded}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.reorderAdded ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.reorderAdded}
            onValueChange={(value) => updateSetting('reorderAdded', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>Authentication Success</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.authSuccess}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.authSuccess ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.authSuccess}
            onValueChange={(value) => updateSetting('authSuccess', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>General Information</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.generalInfo}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.generalInfo ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.generalInfo}
            onValueChange={(value) => updateSetting('generalInfo', value)}
          />
        </View>

        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>System Errors</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.systemError}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.systemError ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.systemError}
            onValueChange={(value) => updateSetting('systemError', value)}
          />
        </View>
      </View>

      {/* Push Notification Settings */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Push Notifications</Text>
        
        <View style={styles.settingItem}>
          <View style={styles.settingTextContainer}>
            <Text style={styles.settingLabel}>iOS Push Notifications</Text>
            <Text style={styles.settingDescription}>
              {NOTIFICATION_DESCRIPTIONS.pushNotifications}
            </Text>
          </View>
          <Switch
            trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
            thumbColor={settings.pushNotifications ? lightTheme.colors.background : lightTheme.colors.secondary}
            ios_backgroundColor={lightTheme.colors.border}
            value={settings.pushNotifications}
            onValueChange={(value) => updateSetting('pushNotifications', value)}
          />
        </View>
      </View>

      {/* Info Section */}
      <View style={styles.infoSection}>
        <Text style={styles.infoText}>
          • In-app notifications appear in the notification center regardless of these settings
        </Text>
        <Text style={styles.infoText}>
          • Push notifications only work when the app is in the background or closed
        </Text>
        <Text style={styles.infoText}>
          • Changes to push notification settings may require restarting the app
        </Text>
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
  header: {
    padding: 20,
    backgroundColor: 'white',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: lightTheme.colors.border,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: '700',
    color: '#333',
    marginBottom: 8,
  },
  headerSubtitle: {
    fontSize: 16,
    color: '#666',
    lineHeight: 22,
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
  settingItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    minHeight: 60,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: lightTheme.colors.border,
  },
  settingTextContainer: {
    flex: 1,
    marginRight: 10,
  },
  settingLabel: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.text,
    marginBottom: 4,
  },
  settingDescription: {
    fontSize: 13,
    color: '#666',
    lineHeight: 18,
  },
  infoSection: {
    backgroundColor: '#f8f9fa',
    margin: 16,
    padding: 16,
    borderRadius: 8,
    marginBottom: 40,
  },
  infoText: {
    fontSize: 13,
    color: '#666',
    lineHeight: 18,
    marginBottom: 4,
  },
});

export default NotificationSettingsScreen; 