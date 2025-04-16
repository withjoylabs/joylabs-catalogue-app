import React, { useState } from 'react';
import { View, Text, Switch, StyleSheet } from 'react-native';
import { lightTheme } from '../../src/themes'; // Assuming theme is used for styles

const ProfileSettingsScreen = () => {
  // State for settings - might need to be lifted or use a settings provider/store later
  const [notificationsEnabled, setNotificationsEnabled] = useState(false);
  const [darkModeEnabled, setDarkModeEnabled] = useState(false);

  return (
    <View style={styles.container}> // Use a container style
        <View style={styles.sectionContent}>
          <Text style={styles.sectionTitle}>App Settings</Text>
          {/* Example Settings */}
          <View style={styles.settingItem}>
            <Text style={styles.settingLabel}>Enable Notifications</Text>
            <Switch
              trackColor={{ false: lightTheme.colors.border, true: lightTheme.colors.primary }}
              thumbColor={notificationsEnabled ? lightTheme.colors.background : lightTheme.colors.secondary}
              ios_backgroundColor={lightTheme.colors.border}
              value={notificationsEnabled}
              onValueChange={setNotificationsEnabled}
            />
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
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: lightTheme.colors.border,
  },
  settingLabel: {
    fontSize: 16,
    color: lightTheme.colors.text,
  },
});

export default ProfileSettingsScreen; 