import { useState, useEffect, useCallback } from 'react';
import api from '../api';
import { useAppStore } from '../store';
import { ConvertedCategory, CatalogObject } from '../types/api';
import { transformCatalogCategoryToCategory } from '../utils/catalogTransformers';
import logger from '../utils/logger';
import { useApi } from '../providers/ApiProvider';

interface DropdownItem {
  label: string;
  value: string;
}

export const useCategories = () => {
  const { 
    categories: storeCategories, 
    setCategories, 
    isCategoriesLoading, 
    setCategoriesLoading, 
    categoryError, 
    setCategoryError
  } = useAppStore();
  
  // Get Square connection status from ApiProvider
  const { isConnected: isSquareConnected, refreshData } = useApi();
  
  const [dropdownItems, setDropdownItems] = useState<DropdownItem[]>([]);
  const [connected, setConnected] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  
  // Transform existing categories to dropdown items on mount, but don't fetch from API
  useEffect(() => {
    if (storeCategories.length > 0) {
      updateDropdownItems(storeCategories);
    }
  }, [storeCategories]);

  // Function to fetch categories from the API
  const fetchCategories = useCallback(async (showLoading = true) => {
    // Check for Square connection first
    if (!isSquareConnected) {
      logger.info('Categories', 'Skipping category fetch - no Square connection');
      return;
    }
    
    if (showLoading && isCategoriesLoading) return;
    
    if (showLoading) setCategoriesLoading(true);
    else setIsRefreshing(true);
    
    setCategoryError(null);
    
    try {
      logger.info('Categories', 'Fetching catalog categories');
      
      // Try the direct API call first, since refreshData might be causing issues
      const response = await api.catalog.getCategories();
      
      // Log response for debugging - include more details
      logger.debug('Categories', 'Categories API response structure', {
        success: response.success,
        hasObjects: !!response.objects,
        objectCount: response.objects?.length || 0,
        responseKeys: Object.keys(response),
        hasCursor: !!response.cursor,
        count: response.count,
        metadataPresent: !!response.metadata
      });
      
      // Use refreshData as a background refresh only if available
      if (refreshData) {
        try {
          // Don't await this to avoid blocking UI
          refreshData('categories').catch(err => {
            logger.warn('Categories', 'Background refresh failed', { error: err.message });
          });
        } catch (refreshError) {
          // Ignore refresh errors since we already have the data
          logger.warn('Categories', 'Error in background refresh', { error: refreshError });
        }
      }
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to fetch categories');
      }
      
      // Handle different response formats with simplified priority
      let categoryObjects: CatalogObject[] = [];
      
      if (Array.isArray(response.objects)) {
        // Backend now returns objects directly
        logger.debug('Categories', 'Using objects array from response', { 
          count: response.objects.length
        });
        categoryObjects = response.objects.filter((item: CatalogObject) => 
          item.type === 'CATEGORY' && !item.is_deleted
        );
      } else if (Array.isArray(response.categories)) {
        // Fallback for previous response format
        logger.debug('Categories', 'Using categories array from response', { 
          count: response.categories.length
        });
        categoryObjects = response.categories.filter((item: CatalogObject) => 
          item.type === 'CATEGORY' && !item.is_deleted
        );
      } else if (Array.isArray(response.items)) {
        // Fallback for old list endpoint format
        categoryObjects = response.items.filter((item: CatalogObject) => 
          item.type === 'CATEGORY' && !item.is_deleted
        );
      } else if (response.data?.items) {
        // Fallback for nested structure
        categoryObjects = response.data.items.filter((item: CatalogObject) => 
          item.type === 'CATEGORY' && !item.is_deleted
        );
      }
      
      const transformedCategories = categoryObjects
        .map((item: CatalogObject) => transformCatalogCategoryToCategory(item))
        .filter((category: ConvertedCategory | null): category is ConvertedCategory => category !== null) // Remove null values
        .map((category: ConvertedCategory) => ({
          ...category,
          itemCount: 0 // We'll update this separately if needed
        }))
        // Sort categories alphabetically by name
        .sort((a, b) => a.name.localeCompare(b.name));
      
      setCategories(transformedCategories);
      updateDropdownItems(transformedCategories);
      setConnected(true);
      logger.info('Categories', `Successfully fetched ${transformedCategories.length} categories`);
    } catch (error: unknown) {
      logger.error('Categories', 'Error fetching categories', { error });
      let errorMessage = 'Failed to fetch categories';
      
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      setCategoryError(errorMessage);
      setConnected(false);
    } finally {
      if (showLoading) setCategoriesLoading(false);
      else setIsRefreshing(false);
    }
  }, [isCategoriesLoading, setCategoriesLoading, setCategoryError, setCategories, isSquareConnected, refreshData]);

  // Function to refresh categories without showing the loading state
  const refreshCategories = useCallback(() => {
    if (!isSquareConnected) {
      logger.info('Categories', 'Skipping category refresh - no Square connection');
      return Promise.resolve();
    }
    return fetchCategories(false);
  }, [fetchCategories, isSquareConnected]);

  // Convert categories to dropdown format
  const updateDropdownItems = (categories: ConvertedCategory[]) => {
    const items = categories.map(category => ({
      label: category.name,
      value: category.id // Use ID as value for better matching
    }));
    setDropdownItems(items);
  };

  // Get a category by ID
  const getCategoryById = useCallback((id: string) => {
    return storeCategories.find(category => category.id === id);
  }, [storeCategories]);

  // Get a category by name
  const getCategoryByName = useCallback((name: string) => {
    return storeCategories.find(category => category.name === name);
  }, [storeCategories]);

  return {
    categories: storeCategories,
    dropdownItems,
    isCategoriesLoading,
    isRefreshing,
    categoryError,
    connected,
    fetchCategories,
    refreshCategories,
    getCategoryById,
    getCategoryByName
  };
}; 