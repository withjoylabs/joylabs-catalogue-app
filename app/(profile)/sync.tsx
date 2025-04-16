import React from 'react';
import { View, StyleSheet } from 'react-native';
import CatalogSyncStatus from '@/components/CatalogSyncStatus';
import SyncLogsView from '@/components/SyncLogsView';
import { lightTheme } from '@/themes';

const ProfileSyncScreen: React.FC = () => {
  return (
    <View style={styles.container}>
      <CatalogSyncStatus />
      <SyncLogsView />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: lightTheme.spacing.md,
    backgroundColor: lightTheme.colors.background,
  },
});

export default ProfileSyncScreen; 