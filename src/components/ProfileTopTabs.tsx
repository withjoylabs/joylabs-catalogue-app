import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

type ProfileTopTabsProps = {
  activeSection: string;
  onChangeSection: (section: string) => void;
};

export default function ProfileTopTabs({ activeSection, onChangeSection }: ProfileTopTabsProps) {
  // Define the tabs to display
  const tabs = [
    { key: 'profile', label: 'Profile', icon: 'person' as const },
    { key: 'settings', label: 'Settings', icon: 'settings' as const },
    { key: 'sync', label: 'Sync Catalog', icon: 'sync' as const },
  ];

  return (
    <View style={styles.tabBar}>
      {tabs.map((tab) => (
        <TouchableOpacity
          key={tab.key}
          style={[
            styles.tab,
            activeSection === tab.key && styles.activeTab
          ]}
          onPress={() => onChangeSection(tab.key)}
        >
          <Ionicons
            name={tab.icon}
            size={24}
            color={activeSection === tab.key ? lightTheme.colors.primary : '#888'}
          />
          <Text
            style={[
              styles.tabLabel,
              activeSection === tab.key && styles.activeTabLabel
            ]}
          >
            {tab.label}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  tabBar: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    backgroundColor: '#fff',
  },
  tab: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
  },
  activeTab: {
    borderBottomWidth: 2,
    borderBottomColor: lightTheme.colors.primary,
  },
  tabLabel: {
    fontSize: 12,
    marginTop: 4,
    color: '#888',
  },
  activeTabLabel: {
    color: lightTheme.colors.primary,
    fontWeight: '600',
  },
}); 