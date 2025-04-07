import React, { useEffect, useState } from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { SQLiteProvider } from 'expo-sqlite';
import * as modernDb from '../database/modernDb';
import logger from '../utils/logger';

interface DatabaseProviderProps {
  children: React.ReactNode;
}

export function DatabaseProvider({ children }: DatabaseProviderProps) {
  const [isInitialized, setIsInitialized] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  // Initialize the database
  useEffect(() => {
    async function init() {
      try {
        logger.info('DatabaseProvider', 'Initializing database...');
        await modernDb.initDatabase();
        setIsInitialized(true);
        logger.info('DatabaseProvider', 'Database initialized successfully');
      } catch (err) {
        const error = err instanceof Error ? err : new Error('Failed to initialize database');
        logger.error('DatabaseProvider', 'Failed to initialize database', { error });
        setError(error);
      }
    }

    init();

    // Close the database when the component unmounts
    return () => {
      async function cleanup() {
        try {
          await modernDb.closeDatabase();
          logger.info('DatabaseProvider', 'Database connection closed');
        } catch (err) {
          logger.error('DatabaseProvider', 'Failed to close database', { error: err });
        }
      }
      
      cleanup();
    };
  }, []);

  // Show loading screen while initializing
  if (!isInitialized) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0000ff" />
        <Text style={styles.text}>Initializing database...</Text>
      </View>
    );
  }

  // Show error screen if initialization failed
  if (error) {
    return (
      <View style={styles.container}>
        <Text style={styles.errorText}>Failed to initialize database</Text>
        <Text style={styles.errorDetails}>{error.message}</Text>
      </View>
    );
  }

  // Provide the database context to all children
  return (
    <SQLiteProvider databaseName="joylabs.db" useSuspense={false}>
      {children}
    </SQLiteProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  text: {
    marginTop: 10,
    fontSize: 16,
  },
  errorText: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#d32f2f',
    marginBottom: 10,
  },
  errorDetails: {
    fontSize: 14,
    color: '#333',
    textAlign: 'center',
  },
}); 