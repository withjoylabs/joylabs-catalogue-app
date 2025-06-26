import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, StatusBar, AppState } from 'react-native';
import { GestureDetector, Gesture } from 'react-native-gesture-handler';
import { router } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import logger from './src/utils/logger';
import { CatalogSyncService } from './src/database/catalogSync';

// IMPORTANT: This must be called at the root of the app for AuthSession to work
WebBrowser.maybeCompleteAuthSession();

// Error boundary to capture uncaught errors
class ErrorBoundary extends React.Component<{children: React.ReactNode}, {hasError: boolean, error: Error | null}> {
  constructor(props: {children: React.ReactNode}) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    // Log the error to our logger
    logger.error('ErrorBoundary', 'Uncaught error in app', { 
      error: error.toString(), 
      stack: error.stack,
      componentStack: errorInfo.componentStack
    });
  }

  render() {
    if (this.state.hasError) {
      return (
        <View style={styles.errorContainer}>
          <StatusBar barStyle="dark-content" backgroundColor="#f8d7da" />
          <Text style={styles.errorTitle}>Something went wrong</Text>
          <Text style={styles.errorMessage}>{this.state.error?.message}</Text>
          <TouchableOpacity 
            style={styles.errorButton}
            onPress={() => {
              // Try to reset the error state
              this.setState({ hasError: false, error: null });
              // Go to the home screen
              router.replace('/');
            }}
          >
            <Text style={styles.errorButtonText}>Go Home</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.errorButton, { backgroundColor: '#17a2b8' }]}
            onPress={() => {
              // Go to debug screen
              router.push('/debug');
            }}
          >
            <Text style={styles.errorButtonText}>View Logs</Text>
          </TouchableOpacity>
        </View>
      );
    }

    return this.props.children;
  }
}

// App wrapper component with debug gesture handlers
export default function App() {
  const [appState, setAppState] = useState(AppState.currentState);
  
  // Set up app state change listener with catch-up sync
  useEffect(() => {
    const subscription = AppState.addEventListener('change', nextAppState => {
      logger.debug('App', `App state changed from ${appState} to ${nextAppState}`);
      
      // Only trigger catch-up sync when app comes to foreground if we have reason to believe we missed webhooks
      // This prevents unnecessary API calls on every foreground transition
      if (appState === 'background' && nextAppState === 'active') {
        logger.info('App', 'App came to foreground from background - checking if catch-up sync is needed');
        
        try {
          const syncService = CatalogSyncService.getInstance();
          
          // Use intelligent detection to only sync if we actually missed webhook events
          // This prevents wasteful API calls when webhooks are working properly
          syncService.checkAndRunCatchUpSync().catch(error => {
            logger.error('App', 'Catch-up sync check failed during foreground transition', { error });
          });
          
          logger.info('App', 'Intelligent catch-up sync check initiated during foreground transition');
        } catch (syncError) {
          // Don't fail app state transition if sync fails
          logger.error('App', 'Failed to initiate catch-up sync check during foreground transition', { syncError });
        }
      }
      
      setAppState(nextAppState);
    });

    return () => {
      subscription.remove();
    };
  }, [appState]);
  
  // Set up global error handler
  useEffect(() => {
    // Simple error logging function
    const errorHandler = (error: Error, isFatal?: boolean) => {
      logger.error('App', `Global error: ${isFatal ? 'FATAL' : 'NON-FATAL'}`, {
        error: error.toString(),
        stack: error.stack
      });
    };
    
    // For global error handling, we'll use a simpler approach
    // that doesn't rely on ErrorUtils directly
    const originalConsoleError = console.error;
    console.error = (message, ...args) => {
      // Log to our system
      if (message instanceof Error) {
        errorHandler(message, false);
      } else if (typeof message === 'string' && args[0] instanceof Error) {
        errorHandler(args[0], false);
      }
      // Still call original
      originalConsoleError(message, ...args);
    };
    
    // Capture unhandled promise rejections
    const rejectionHandler = (event: PromiseRejectionEvent) => {
      logger.error('App', 'Unhandled promise rejection', {
        reason: event.reason?.toString(),
        stack: event.reason?.stack
      });
    };
    
    if (global.addEventListener) {
      global.addEventListener('unhandledrejection', rejectionHandler);
    }
    
    return () => {
      console.error = originalConsoleError;
      if (global.removeEventListener) {
        global.removeEventListener('unhandledrejection', rejectionHandler);
      }
    };
  }, []);
  
  // Create a triple tap gesture to activate debug mode
  const tripleTap = Gesture.Tap()
    .numberOfTaps(3)
    .onStart(() => {
      logger.info('App', 'Triple tap activated - opening debug screen');
      router.push('/debug');
    });

  // Import actual app entry point
  const EntryPoint = require('./index').default;
  
  return (
    <ErrorBoundary>
      <GestureDetector gesture={tripleTap}>
        <View style={{ flex: 1 }}>
          <EntryPoint />
        </View>
      </GestureDetector>
    </ErrorBoundary>
  );
}

const styles = StyleSheet.create({
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f8d7da',
    padding: 20,
  },
  errorTitle: {
    fontSize: 22,
    fontWeight: 'bold',
    color: '#721c24',
    marginBottom: 10,
  },
  errorMessage: {
    fontSize: 16,
    color: '#721c24',
    textAlign: 'center',
    marginBottom: 20,
  },
  errorButton: {
    backgroundColor: '#dc3545',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    marginVertical: 10,
    width: 200,
    alignItems: 'center',
  },
  errorButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
