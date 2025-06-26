import React from 'react';
import { View, StyleSheet, Platform } from 'react-native';
import { StatusBar } from 'react-native';
import { lightTheme } from '../themes';
import ConnectionStatusBar from './ConnectionStatusBar';
import NotificationBell from './NotificationBell';

interface SearchHeaderProps {
  isConnected: boolean;
}

export default function SearchHeader({ isConnected }: SearchHeaderProps) {
  return (
    <View style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
      
      <View style={styles.topBar}>
        <ConnectionStatusBar 
          connected={isConnected} 
          message="Connection Status" 
        />
        <NotificationBell />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: lightTheme.colors.background,
    paddingTop: Platform.OS === 'ios' ? 24 : 24, // Status bar height + safe area
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
  },
}); 