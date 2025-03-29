import { useState, useEffect, useCallback } from 'react';
import * as SecureStore from 'expo-secure-store';
import { Alert } from 'react-native';
import logger from '../utils/logger';
import config from '../config';

// Type definitions for categories
interface Category {
  id: string;
  name: string;
  imageUrl?: string;
}

// Add an interface for catalog objects
interface CatalogObject {
  id: string;
  type: string;
  categoryData?: {
    name: string;
    imageIds?: string[];
  };
}

interface UseCategoriesResult {
  categories: Category[];
  isLoading: boolean;
  error: string | null;
  refreshCategories: () => Promise<void>;
}

export function useCatalogCategories(): UseCategoriesResult {
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Constants for accessing tokens
  const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';

  // Function to fetch categories from the API
  const fetchCategories = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);
      
      // Get the Square access token
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      
      if (!accessToken) {
        setError('No Square access token found. Please connect to Square first.');
        setIsLoading(false);
        return;
      }
      
      console.log('DEBUG: Using access token (first 10 chars):', accessToken.substring(0, 10) + '...');
      console.log('DEBUG: Token length:', accessToken.length);
      
      logger.info('Categories', 'Fetching catalog categories');
      
      // Make request to the catalog API
      const url = `${config.square.endpoints.catalogItems}?types=CATEGORY`;
      console.log('DEBUG: API URL:', url);
      
      const response = await fetch(
        url,
        {
          method: 'GET',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json'
          }
        }
      );
      
      if (!response.ok) {
        // Handle different types of errors
        if (response.status === 401) {
          console.log('DEBUG: Received 401 Unauthorized error');
          const responseText = await response.text();
          console.log('DEBUG: Response body:', responseText);
          
          setError('Your Square access token has expired. Please reconnect to Square.');
          logger.error('Categories', 'Authentication error when fetching categories', { status: response.status });
        } else {
          const errorData = await response.json();
          console.log('DEBUG: Error response:', JSON.stringify(errorData));
          
          setError(errorData.message || `Error fetching categories: ${response.status}`);
          logger.error('Categories', 'Error fetching categories', { status: response.status, error: errorData });
        }
        setIsLoading(false);
        return;
      }
      
      const data = await response.json();
      
      if (!data.success) {
        setError(data.message || 'Failed to fetch categories');
        logger.error('Categories', 'API returned error', data);
        setIsLoading(false);
        return;
      }
      
      // Process categories from the response
      const categoryObjects = data.objects ? data.objects.filter((obj: CatalogObject) => obj.type === 'CATEGORY') : [];
      
      const formattedCategories: Category[] = categoryObjects.map((obj: CatalogObject) => ({
        id: obj.id,
        name: obj.categoryData?.name || 'Unnamed Category',
        imageUrl: obj.categoryData?.imageIds?.[0] ? `https://image.squarecdn.com/${obj.categoryData.imageIds[0]}` : undefined
      }));
      
      logger.info('Categories', `Fetched ${formattedCategories.length} categories`);
      setCategories(formattedCategories);
    } catch (err: any) {
      setError(`Error: ${err.message || 'Unknown error'}`);
      logger.error('Categories', 'Exception when fetching categories', err);
      
      // Show alert for network errors
      if (!err.response && err.message?.includes('Network')) {
        Alert.alert(
          'Network Error',
          'Unable to connect to Square. Please check your internet connection.'
        );
      }
    } finally {
      setIsLoading(false);
    }
  }, []);
  
  // Fetch categories on mount
  useEffect(() => {
    fetchCategories();
  }, [fetchCategories]);
  
  // Public function to manually refresh categories
  const refreshCategories = useCallback(async () => {
    await fetchCategories();
  }, [fetchCategories]);
  
  return {
    categories,
    isLoading,
    error,
    refreshCategories
  };
} 