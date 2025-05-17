import React from 'react';
import { View, StyleSheet } from 'react-native';
import CatalogSyncStatus from '../../../src/components/CatalogSyncStatus';
// import SyncLogsView from '../../../src/components/SyncLogsView'; // Removed
import { lightTheme } from '../../../src/themes';

const ProfileSyncScreen: React.FC = () => {
  return (
    <View style={styles.container}>
      <CatalogSyncStatus />
      {/* <SyncLogsView /> */}{/* Removed */}
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