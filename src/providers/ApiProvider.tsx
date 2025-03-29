import React, { useEffect, createContext, useContext, useState } from 'react';
import { useSquareAuth } from '../hooks/useSquareAuth';
import logger from '../utils/logger';
import api from '../api';
import { useAppStore } from '../store';

// Create context with initial values
interface ApiContextType {
  isConnected: boolean;
  merchantId: string | null;
  isLoading: boolean;
  error: Error | null;
  connectToSquare: () => Promise<void>;
  disconnectFromSquare: () => Promise<void>;
  refreshData: () => Promise<void>;
  verifyConnection: () => Promise<boolean>;
}

const ApiContext = createContext<ApiContextType>({
  isConnected: false,
  merchantId: null,
  isLoading: false,
  error: null,
  connectToSquare: async () => {},
  disconnectFromSquare: async () => {},
  refreshData: async () => {},
  verifyConnection: async () => false,
});

export const useApi = () => useContext(ApiContext);

export const ApiProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  // Track connection status changes to avoid excessive refreshes
  const [initialConnectionChecked, setInitialConnectionChecked] = useState(false);
  
  // Access the app store to sync Square connection state
  const { setSquareConnected } = useAppStore();
  
  // Initialize Square auth hook
  const { 
    isConnected, 
    merchantId, 
    isConnecting: isLoading, 
    error: authError,
    connect,
    disconnect,
  } = useSquareAuth();
  
  // Update app store when connection status changes
  useEffect(() => {
    setSquareConnected(isConnected);
  }, [isConnected, setSquareConnected]);
  
  // Define function to refresh all data
  const refreshData = async () => {
    if (!isConnected) {
      logger.info('ApiProvider', 'Skipping data refresh - not connected to Square');
      return;
    }
    
    logger.info('ApiProvider', 'Manually refreshing data');
    
    try {
      // Refresh catalog items
      logger.info('ApiProvider', 'Refreshing catalog items');
      await api.catalog.getItems(undefined, 100)
        .catch((error: Error) => {
          logger.error('ApiProvider', 'Failed to refresh catalog items', { error: error.message });
        });
      
      logger.info('ApiProvider', 'Data refresh completed');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('ApiProvider', 'Error during data refresh', { error: errorMessage });
    }
  };

  // Simple connection verification
  const verifyConnection = async () => {
    return isConnected;
  };
  
  // Create the context value
  const contextValue: ApiContextType = {
    isConnected,
    merchantId,
    isLoading,
    error: authError,
    connectToSquare: connect,
    disconnectFromSquare: disconnect,
    refreshData,
    verifyConnection
  };
  
  return (
    <ApiContext.Provider value={contextValue}>
      {children}
    </ApiContext.Provider>
  );
}; 