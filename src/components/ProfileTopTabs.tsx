import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

type ProfileTopTabsProps = {
  activeSection: string;
  onTabChange: (section: string) => void;
};

export default function ProfileTopTabs({ activeSection, onTabChange }: ProfileTopTabsProps) {
  return (
    <View style={styles.tabBar}>
      <TouchableOpacity 
        style={[
          styles.tab, 
          activeSection === 'profile' && styles.activeTab
        ]}
        onPress={() => onTabChange('profile')}
      >
        <Ionicons 
          name="person" 
          size={24} 
          color={activeSection === 'profile' ? lightTheme.colors.primary : '#888'} 
        />
        <Text 
          style={[
            styles.tabLabel, 
            activeSection === 'profile' && styles.activeTabLabel
          ]}
        >
          Profile
        </Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={[
          styles.tab, 
          activeSection === 'settings' && styles.activeTab
        ]}
        onPress={() => onTabChange('settings')}
      >
        <Ionicons 
          name="settings" 
          size={24} 
          color={activeSection === 'settings' ? lightTheme.colors.primary : '#888'} 
        />
        <Text 
          style={[
            styles.tabLabel, 
            activeSection === 'settings' && styles.activeTabLabel
          ]}
        >
          Settings
        </Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={[
          styles.tab, 
          activeSection === 'categories' && styles.activeTab
        ]}
        onPress={() => onTabChange('categories')}
      >
        <Ionicons 
          name="grid" 
          size={24} 
          color={activeSection === 'categories' ? lightTheme.colors.primary : '#888'} 
        />
        <Text 
          style={[
            styles.tabLabel, 
            activeSection === 'categories' && styles.activeTabLabel
          ]}
        >
          Categories
        </Text>
      </TouchableOpacity>
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