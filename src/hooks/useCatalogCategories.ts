import { useState, useCallback, useEffect } from 'react';
import * as SecureStore from 'expo-secure-store';
import config from '../config';
import logger from '../utils/logger';
import tokenService from '../services/tokenService';
import api from '../api';

export interface Category {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  version: number;
  isDeleted: boolean;
  presentAtAllLocations: boolean;
}

export interface CategoriesResponse {
  categories: Category[];
  cursor?: string;
}

export interface UseCategoriesResult {
  categories: Category[];
  isLoading: boolean;
  error: string | null;
  fetchCategories: () => Promise<void>;
  refetchCategories: () => Promise<void>;
}

// Main hook for accessing catalog categories
export function useCatalogCategories(): UseCategoriesResult {
  const [categories, setCategories] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Function to fetch categories from the API
  const fetchCategories = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);
      
      // Get the Square access token using tokenService
      const accessToken = await tokenService.getAccessToken();
      
      if (!accessToken) {
        setError('No Square access token found. Please connect to Square first.');
        setIsLoading(false);
        return;
      }
      
      logger.info('Categories', 'Fetching catalog categories');
      
      // Use the api.catalog.getCategories method which handles all the details
      const response = await api.catalog.getCategories();
      
      if (!response || !response.success) {
        throw new Error(response?.error?.message || 'Failed to fetch categories');
      }
      
      // Handle either response format (objects array or direct categories array)
      let categoriesData: Category[] = [];
      
      if (Array.isArray(response.objects)) {
        // Square API format - objects array with type CATEGORY
        categoriesData = response.objects
          ?.filter((obj: any) => obj.type === 'CATEGORY' && !obj.is_deleted)
          ?.map((obj: any) => ({
            id: obj.id,
            name: obj.category_data?.name || 'Unnamed Category',
            createdAt: obj.created_at,
            updatedAt: obj.updated_at,
            version: obj.version,
            isDeleted: obj.is_deleted || false,
            presentAtAllLocations: obj.present_at_all_locations || false
          })) || [];
      } else if (Array.isArray(response.categories)) {
        // Direct categories array - backend may return in this format
        categoriesData = response.categories.map((cat: any) => ({
          id: cat.id,
          name: cat.name || cat.category_data?.name || 'Unnamed Category',
          createdAt: cat.created_at || cat.createdAt,
          updatedAt: cat.updated_at || cat.updatedAt,
          version: cat.version || 0,
          isDeleted: cat.is_deleted || cat.isDeleted || false,
          presentAtAllLocations: cat.present_at_all_locations || cat.presentAtAllLocations || false
        }));
      }
      
      setCategories(categoriesData);
      logger.info('Categories', `Fetched ${categoriesData.length} categories`);
    } catch (err: any) {
      logger.error('Categories', 'Error fetching categories', err);
      setError(err.message || 'Failed to fetch categories');
    } finally {
      setIsLoading(false);
    }
  }, []);
  
  // Function to force a refetch
  const refetchCategories = useCallback(async () => {
    await fetchCategories();
  }, [fetchCategories]);
  
  // Initial fetch on mount
  useEffect(() => {
    fetchCategories();
  }, [fetchCategories]);
  
  return {
    categories,
    isLoading,
    error,
    fetchCategories,
    refetchCategories
  };
} 