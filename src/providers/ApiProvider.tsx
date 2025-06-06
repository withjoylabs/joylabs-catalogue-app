import React, { useEffect, createContext, useContext, useState, useMemo, useCallback } from 'react';
import { useSquareAuth } from '../hooks/useSquareAuth';
import logger from '../utils/logger';
import { apiClientInstance } from '../api';
import tokenService from '../services/tokenService';
import { useAppStore } from '../store';
import {
  transformCatalogItemToItem, 
  transformCatalogCategoryToCategory 
} from '../utils/catalogTransformers';
import { CatalogObject, ConvertedItem, ConvertedCategory } from '../types/api';
import { Category } from '../store';

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

// Original component function (restored from previous state, React.memo removed)
const ApiProviderComponent: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [initialConnectionChecked, setInitialConnectionChecked] = useState(false);
  const [lastRefreshTimes, setLastRefreshTimes] = useState<Record<string, number>>({
    categories: 0,
    items: 0,
    all: 0
  });
  const MIN_REFRESH_INTERVAL = 5 * 60 * 1000;
  const { setProducts, setCategories } = useAppStore();
  const { 
    isConnected, 
    merchantId, 
    isConnecting: isLoading, 
    error: authError,
    connect,
    disconnect,
  } = useSquareAuth();
  
  useEffect(() => {
    if (!initialConnectionChecked) {
      const checkInitialConnection = async () => {
        try {
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
  
  const refreshData = useCallback(async (dataType?: 'categories' | 'items' | 'all') => {
    if (!isConnected) {
      logger.info('ApiProvider', 'Skipping data refresh - not connected to Square');
      return;
    }
    const refreshType = dataType || 'all';
    const now = Date.now();
    const lastRefresh = lastRefreshTimes[refreshType] || 0;
    if (now - lastRefresh < MIN_REFRESH_INTERVAL) {
      logger.info('ApiProvider', `Skipping ${refreshType} refresh - refreshed recently`);
      return;
    }
    logger.info('ApiProvider', `Manually refreshing data (type: ${refreshType})`);
    setLastRefreshTimes(prev => ({
      ...prev,
      [refreshType]: now
    }));
    try {
      if (refreshType === 'categories' || refreshType === 'all') {
        logger.info('ApiProvider', 'Refreshing catalog categories');
        await apiClientInstance.get('/v2/catalog/list', { params: { types: 'CATEGORY' } })
          .then((response) => {
             if (response?.data?.objects && Array.isArray(response.data.objects)) {
               const rawCategories = response.data.objects as CatalogObject[];
               const transformedCategories = rawCategories
                 .map(transformCatalogCategoryToCategory)
                 .filter((cat): cat is ConvertedCategory => cat !== null);
               setCategories(transformedCategories as Category[]); 
               logger.info('ApiProvider', 'Categories refresh processed', { 
                 success: true, 
                 objectCount: transformedCategories.length
               });
             } else {
                logger.warn('ApiProvider', 'Categories refresh response missing expected data', {responseData: response?.data});
             }
          })
          .catch((error: Error) => {
            logger.error('ApiProvider', 'Failed to refresh categories', { error: error.message });
          });
      }
      if (refreshType === 'items' || refreshType === 'all') {
        logger.info('ApiProvider', 'Refreshing catalog items');
        await apiClientInstance.get('/v2/catalog/list', { params: { types: 'ITEM', limit: 100 } })
          .then((response) => {
             if (response?.data?.objects && Array.isArray(response.data.objects)) {
               const rawItems = response.data.objects as CatalogObject[];
               const transformedItems = rawItems
                 .map(item => transformCatalogItemToItem(item))
                 .filter((item): item is ConvertedItem => item !== null);
               setProducts(transformedItems);
               logger.info('ApiProvider', 'Items refresh processed', { 
                 success: true, 
                 objectCount: transformedItems.length
               });
             } else {
               logger.warn('ApiProvider', 'Items refresh response missing expected data', {responseData: response?.data});
             }
          })
          .catch((error: Error) => {
            logger.error('ApiProvider', 'Failed to refresh catalog items', { error: error.message });
          });
      }
      logger.info('ApiProvider', 'Data refresh completed');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('ApiProvider', 'Error during data refresh', { error: errorMessage });
    }
  }, [isConnected, lastRefreshTimes, setProducts, setCategories, MIN_REFRESH_INTERVAL]);

  const verifyConnection = useCallback(async (): Promise<boolean> => {
    try {
      const tokenStatus = await tokenService.checkTokenStatus();
      if (tokenStatus === 'missing') {
        logger.info('ApiProvider', 'Connection verification failed - no token');
        return false;
      }
      if (tokenStatus === 'expired' || tokenStatus === 'unknown') {
        logger.info('ApiProvider', 'Token needs refresh during verification');
        const newToken = await tokenService.ensureValidToken();
        return !!newToken;
      }
      return tokenStatus === 'valid';
    } catch (error) {
      logger.error('ApiProvider', 'Error verifying connection', error);
      return false;
    }
  }, []);
  
  const contextValue = useMemo(() => ({
    isConnected,
    merchantId,
    isLoading,
    error: authError,
    connectToSquare: connect,
    disconnectFromSquare: disconnect,
    refreshData,
    verifyConnection,
  }), [
    isConnected, 
    merchantId, 
    isLoading, 
    authError, 
    connect, 
    disconnect, 
    refreshData,
    verifyConnection
  ]);
  
  return (
    <ApiContext.Provider value={contextValue}>
      {children}
    </ApiContext.Provider>
  );
}; 

export const ApiProvider = ApiProviderComponent; 