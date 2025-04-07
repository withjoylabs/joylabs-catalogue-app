import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import catalogSyncService from '../database/catalogSync';

interface SyncProgressBarProps {
  showWhenComplete?: boolean;
}

const SyncProgressBar: React.FC<SyncProgressBarProps> = ({ showWhenComplete = false }) => {
  const [isSyncing, setIsSyncing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [syncedItems, setSyncedItems] = useState(0);
  const [totalItems, setTotalItems] = useState(0);
  const [animatedWidth] = useState(new Animated.Value(0));

  useEffect(() => {
    // Get initial sync status
    const checkStatus = async () => {
      const status = await catalogSyncService.getSyncStatus();
      if (status) {
        setIsSyncing(status.isSyncing);
        setSyncedItems(status.syncedItems || 0);
        setTotalItems(status.totalItems || 0);
        
        // Calculate progress
        const calculatedProgress = status.totalItems > 0 
          ? status.syncedItems / status.totalItems 
          : 0;
        setProgress(calculatedProgress);
        
        // Animate progress bar
        Animated.timing(animatedWidth, {
          toValue: calculatedProgress,
          duration: 300,
          useNativeDriver: false,
        }).start();
      }
    };
    
    checkStatus();
    
    // Register listener for updates
    catalogSyncService.registerListener('progressBar', (status) => {
      setIsSyncing(status.isSyncing);
      setSyncedItems(status.syncedItems || 0);
      setTotalItems(status.totalItems || 0);
      
      // Calculate progress
      const calculatedProgress = status.totalItems > 0 
        ? status.syncedItems / status.totalItems 
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
      catalogSyncService.unregisterListener('progressBar');
    };
  }, [animatedWidth]);

  // Don't render if not syncing and showWhenComplete is false
  if (!isSyncing && !showWhenComplete && progress === 0) {
    return null;
  }

  // Don't render if sync is complete and showWhenComplete is false
  if (!isSyncing && !showWhenComplete && progress === 1) {
    return null;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>
        {isSyncing ? 'Syncing Catalog...' : 'Sync Complete'}
      </Text>
      
      <View style={styles.progressContainer}>
        <Animated.View 
          style={[
            styles.progressBar,
            { width: animatedWidth.interpolate({
                inputRange: [0, 1],
                outputRange: ['0%', '100%'],
              }) 
            }
          ]} 
        />
      </View>
      
      <Text style={styles.infoText}>
        {syncedItems} / {totalItems > 0 ? totalItems : '?'} items
        {progress > 0 && ` (${Math.round(progress * 100)}%)`}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 16,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
    margin: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1.5,
    elevation: 2,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  progressContainer: {
    height: 10,
    backgroundColor: '#e0e0e0',
    borderRadius: 5,
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#4caf50',
  },
  infoText: {
    marginTop: 8,
    fontSize: 14,
    color: '#757575',
  },
});

export default SyncProgressBar; 