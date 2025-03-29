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
      
      logger.info('Categories', 'Fetching catalog categories');
      
      // Make request to the catalog API through our proxy server
      // This uses the v2/catalog/list endpoint with proper pagination parameters
      const url = `${config.api.baseUrl}/v2/catalog/list?page=1&limit=20&types=CATEGORY`;
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
          const errorData = await response.json().catch(() => ({}));
          console.log('DEBUG: Error response:', JSON.stringify(errorData));
          
          setError(errorData.message || `Error fetching categories: ${response.status}`);
          logger.error('Categories', 'Error fetching categories', { status: response.status, error: errorData });
        }
        setIsLoading(false);
        return;
      }
      
      const data = await response.json();
      
      // Check for Square API response structure
      if (!data.objects) {
        setError('Invalid response format from Square API');
        logger.error('Categories', 'Invalid API response format', data);
        setIsLoading(false);
        return;
      }
      
      // Process categories from the response
      const categoryObjects = data.objects.filter((obj: CatalogObject) => obj.type === 'CATEGORY');
      
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