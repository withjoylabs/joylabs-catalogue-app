import React, { useEffect, createContext, useContext, useState } from 'react';
import { useSquareAuth } from '../hooks/useSquareAuth';
import logger from '../utils/logger';
import api from '../api';
import { useAppStore } from '../store';
import tokenService from '../services/tokenService';

// Create context with initial values
interface ApiContextType {
  isConnected: boolean;
  merchantId: string | null;
  isLoading: boolean;
  error: Error | null;
  connectToSquare: () => Promise<void>;
  disconnectFromSquare: () => Promise<void>;
  refreshData: (dataType?: 'categories' | 'items' | 'all') => Promise<void>;
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
  
  // Track last refresh times to prevent excessive API calls
  const [lastRefreshTimes, setLastRefreshTimes] = useState<Record<string, number>>({
    categories: 0,
    items: 0,
    all: 0
  });
  
  // Minimum time between refreshes (5 minutes)
  const MIN_REFRESH_INTERVAL = 5 * 60 * 1000;
  
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

  // Verify connection status on mount
  useEffect(() => {
    if (!initialConnectionChecked) {
      const checkInitialConnection = async () => {
        try {
          // Use tokenService to verify token validity
          const tokenInfo = await tokenService.getTokenInfo();
          logger.info('ApiProvider', 'Initial connection check', {
            hasToken: !!tokenInfo.accessToken,
            tokenStatus: tokenInfo.status
          });
          
          setInitialConnectionChecked(true);
        } catch (error) {
          logger.error('ApiProvider', 'Error in initial connection check', error);
          setInitialConnectionChecked(true);
        }
      };
      
      checkInitialConnection();
    }
  }, [initialConnectionChecked]);
  
  // Function to refresh data from the API
  const refreshData = async (dataType?: 'categories' | 'items' | 'all') => {
    if (!isConnected) {
      logger.info('ApiProvider', 'Skipping data refresh - not connected to Square');
      return;
    }
    
    const refreshType = dataType || 'all';
    const now = Date.now();
    const lastRefresh = lastRefreshTimes[refreshType] || 0;
    
    // Skip if refreshed recently (within last 5 minutes)
    if (now - lastRefresh < MIN_REFRESH_INTERVAL) {
      logger.info('ApiProvider', `Skipping ${refreshType} refresh - refreshed recently`);
      return;
    }
    
    logger.info('ApiProvider', `Manually refreshing data (type: ${refreshType})`);
    
    // Update last refresh time
    setLastRefreshTimes(prev => ({
      ...prev,
      [refreshType]: now
    }));
    
    try {
      // Refresh categories if specified
      if (refreshType === 'categories' || refreshType === 'all') {
        logger.info('ApiProvider', 'Refreshing catalog categories');
        await api.catalog.getCategories()
          .then(response => {
            logger.info('ApiProvider', 'Categories refresh response', { 
              success: response.success,
              hasObjects: !!response.objects,
              objectCount: response.objects?.length || 0
            });
          })
          .catch((error: Error) => {
            logger.error('ApiProvider', 'Failed to refresh categories', { error: error.message });
          });
      }
      
      // Refresh catalog items if specified
      if (refreshType === 'items' || refreshType === 'all') {
        logger.info('ApiProvider', 'Refreshing catalog items');
        await api.catalog.getItems(undefined, 100, 'ITEM')  // Only fetch ITEM type
          .catch((error: Error) => {
            logger.error('ApiProvider', 'Failed to refresh catalog items', { error: error.message });
          });
      }
      
      logger.info('ApiProvider', 'Data refresh completed');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('ApiProvider', 'Error during data refresh', { error: errorMessage });
    }
  };

  // Improved connection verification using tokenService
  const verifyConnection = async (): Promise<boolean> => {
    try {
      // Check if we have a valid token
      const tokenStatus = await tokenService.checkTokenStatus();
      
      // If token is missing or expired and we can't refresh, return false
      if (tokenStatus === 'missing') {
        logger.info('ApiProvider', 'Connection verification failed - no token');
        return false;
      }
      
      // If token is expired or unknown, try to refresh it
      if (tokenStatus === 'expired' || tokenStatus === 'unknown') {
        logger.info('ApiProvider', 'Token needs refresh during verification');
        const newToken = await tokenService.ensureValidToken();
        return !!newToken;
      }
      
      // If token is valid, return true
      return tokenStatus === 'valid';
    } catch (error) {
      logger.error('ApiProvider', 'Error verifying connection', error);
      return false;
    }
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