import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import { useSQLiteContext } from 'expo-sqlite';
import { CatalogSyncService, SyncStatus } from '../database/catalogSync';

interface SyncProgressBarProps {
  showWhenComplete?: boolean;
}

const ModernSyncProgressBar: React.FC<SyncProgressBarProps> = ({ showWhenComplete = false }) => {
  const db = useSQLiteContext();
  const [isSyncing, setIsSyncing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [syncedItems, setSyncedItems] = useState(0);
  const [totalItems, setTotalItems] = useState(0);
  const [animatedWidth] = useState(new Animated.Value(0));
  
  // Get instance of sync service
  const syncService = CatalogSyncService.getInstance();
  
  useEffect(() => {
    // Get initial sync status
    const checkStatus = async () => {
      try {
        const status = await syncService.getSyncStatus();
        if (status) {
          setIsSyncing(status.isSyncing);
          setSyncedItems(status.syncedItems || 0);
          setTotalItems(status.totalItems || 0);
          
          // Calculate progress
          const calculatedProgress = (status.totalItems || 0) > 0 
            ? (status.syncedItems || 0) / (status.totalItems || 0) 
            : 0;
          setProgress(calculatedProgress);
          
          // Animate progress bar
          Animated.timing(animatedWidth, {
            toValue: calculatedProgress,
            duration: 300,
            useNativeDriver: false,
          }).start();
        }
      } catch (error) {
        console.error('Failed to get sync status:', error);
      }
    };
    
    checkStatus();
    
    // Register listener for updates - properly typed now
    syncService.registerListener('modernProgressBar', (status: SyncStatus) => {
      setIsSyncing(status.isSyncing);
      setSyncedItems(status.syncedItems || 0);
      setTotalItems(status.totalItems || 0);
      
      // Calculate progress
      const calculatedProgress = (status.totalItems || 0) > 0 
        ? (status.syncedItems || 0) / (status.totalItems || 0) 
        : 0;
      setProgress(calculatedProgress);
      
      // Animate progress bar
      Animated.timing(animatedWidth, {
        toValue: calculatedProgress,
        duration: 300,
        useNativeDriver: false,
      }).start();
    });
    
    // Cleanup
    return () => {
      syncService.unregisterListener('modernProgressBar');
    };
  }, [animatedWidth, syncService]);

  // Don't render if not syncing and showWhenComplete is false
  if (!isSyncing && !showWhenComplete && progress === 0) {
    return null;
  }
  
  // Calculate percentage for display
  const percentage = Math.round(progress * 100);

  return (
    <View style={styles.container}>
      <View style={styles.progressContainer}>
        <Animated.View 
          style={[
            styles.progressBar,
            { width: animatedWidth.interpolate({
                inputRange: [0, 1],
                outputRange: ['0%', '100%']
              })
            }
          ]}
        />
      </View>
      <Text style={styles.progressText}>
        {syncedItems} / {totalItems} items ({percentage}%)
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    marginVertical: 8,
  },
  progressContainer: {
    height: 8,
    backgroundColor: '#e0e0e0',
    borderRadius: 4,
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#2196f3',
  },
  progressText: {
    fontSize: 12,
    color: '#757575',
    marginTop: 4,
    textAlign: 'center',
  }
});

export default ModernSyncProgressBar; 