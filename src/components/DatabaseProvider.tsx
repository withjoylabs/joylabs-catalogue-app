import React, { useEffect, useState, memo } from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { SQLiteProvider } from 'expo-sqlite';
import * as modernDb from '../database/modernDb';
import logger from '../utils/logger';
import dataRecoveryService from '../services/dataRecoveryService';

interface DatabaseProviderProps {
  children: React.ReactNode;
}

const DatabaseProviderComponent: React.FC<DatabaseProviderProps> = ({ children }) => {
  logger.info('DatabaseProviderComponent', 'COMPONENT FUNCTION BODY EXECUTING');
  const [isInitialized, setIsInitialized] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Initialize the database
  useEffect(() => {
    logger.info('DatabaseProviderComponent', 'EFFECT for initDatabase: MOUNTING / EFFECT TRIGGERED');
    async function init() {
      try {
        logger.info('DatabaseProviderComponent', 'EFFECT: Calling modernDb.initDatabase()...');
        await modernDb.initDatabase();

        // ✅ CRITICAL: Check and recover data from DynamoDB after database initialization
        logger.info('DatabaseProviderComponent', 'EFFECT: Starting data recovery check...');
        await dataRecoveryService.checkAndRecoverData();

        setIsInitialized(true);
        logger.info('DatabaseProviderComponent', 'EFFECT: Database initialized and data recovery completed successfully');
      } catch (err: any) {
        logger.error('DatabaseProviderComponent', 'EFFECT: Error initializing database or recovering data:', err);
        setError(err);
      }
    }

    init();

    // Close the database when the component unmounts
    return () => {
      logger.info('DatabaseProviderComponent', 'EFFECT for initDatabase: UNMOUNTING');
    };
  }, []);

  // Show loading screen while initializing
  if (!isInitialized) {
    logger.info('DatabaseProviderComponent', 'RENDER: Not initialized, showing loading indicator.');
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" />
        <Text style={styles.loadingText}>Initializing Local Database...</Text>
      </View>
    );
  }

  // Show error screen if initialization failed
  if (error) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>Error initializing database: {error.message}</Text>
      </View>
    );
  }

  // Provide the database context to all children
  logger.info('DatabaseProviderComponent', 'RENDER: Initialized, rendering SQLiteProvider and children.');
  return (
    <SQLiteProvider databaseName="joylabs.db">
      {children}
    </SQLiteProvider>
  );
};

export const DatabaseProvider = memo(DatabaseProviderComponent, (prevProps, nextProps) => {
  const childrenChanged = prevProps.children !== nextProps.children;
  logger.info('DatabaseProvider.memo', 'Comparing props for memoization', { 
    childrenChanged: childrenChanged
  });
  // Default shallow comparison: return true if props are equal (no re-render)
  // We want to log, then let default behavior proceed (which is shallow compare)
  // Forcing a re-render for logging would be: return false;
  // Forcing no re-render for logging would be: return true;
  // To mimic default shallow, if childrenChanged is true, it should re-render (return false from comparison)
  // If childrenChanged is false, it should not re-render (return true from comparison)
  if (childrenChanged) {
    logger.warn('DatabaseProvider.memo', 'Children prop has a new identity. Re-render will occur if other props also changed or if this is the only prop.');
    return false; // Re-render if children changed
  }
  logger.info('DatabaseProvider.memo', 'Children prop identity is the same. No re-render based on children.');
  return true; // Don't re-render if children are the same
});

const styles = StyleSheet.create({
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
  },
  errorText: {
    marginTop: 10,
    fontSize: 16,
    color: 'red',
  },
}); 