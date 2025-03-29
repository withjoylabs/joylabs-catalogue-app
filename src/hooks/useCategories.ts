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
  const { isConnected: isSquareConnected } = useApi();
  
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
      // Call the catalog API to get items of type CATEGORY
      const response = await api.catalog.getItems();
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to fetch categories');
      }
      
      // Filter for just the categories and transform them
      const categoryObjects = response.data?.items?.filter((item: CatalogObject) => item.type === 'CATEGORY') || [];
      const transformedCategories = categoryObjects
        .map((item: CatalogObject) => transformCatalogCategoryToCategory(item))
        .filter((category: ConvertedCategory | null): category is ConvertedCategory => category !== null) // Remove null values
        .map((category: ConvertedCategory) => ({
          ...category,
          itemCount: 0 // We'll update this separately if needed
        }));
      
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
  }, [isCategoriesLoading, setCategoriesLoading, setCategoryError, setCategories, isSquareConnected]);

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