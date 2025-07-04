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
  const [isInitialized, setIsInitialized] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Initialize the database
  useEffect(() => {
    async function init() {
      try {
        await modernDb.initDatabase();
        await dataRecoveryService.checkAndRecoverData();
        setIsInitialized(true);
        logger.info('DatabaseProvider', 'Database initialized and data recovery completed');
      } catch (err: any) {
        logger.error('DatabaseProvider', 'Error initializing database:', err);
        setError(err);
      }
    }

    init();
  }, []);

  // Show loading screen while initializing
  if (!isInitialized) {
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
  return (
    <SQLiteProvider databaseName="joylabs.db">
      {children}
    </SQLiteProvider>
  );
};

// REMOVED PROBLEMATIC MEMO: React creates new JSX trees on every render,
// causing children prop to always have new identity. This memo was causing
// more re-renders than it prevented and spamming console logs.
export const DatabaseProvider = DatabaseProviderComponent;

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