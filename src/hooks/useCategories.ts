import { useState, useEffect } from 'react';
import { categoriesApi } from '../api';
import { useAppStore } from '../store';

interface Category {
  id: string;
  name: string;
  itemCount?: number;
}

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
  const [dropdownItems, setDropdownItems] = useState<DropdownItem[]>([]);
  const [connected, setConnected] = useState(false);

  // Fetch categories on mount if not already loaded
  useEffect(() => {
    if (storeCategories.length === 0 && !isCategoriesLoading) {
      fetchCategories();
    } else {
      updateDropdownItems(storeCategories);
    }
  }, [storeCategories, isCategoriesLoading]);

  // Function to fetch categories from the API
  const fetchCategories = async () => {
    if (isCategoriesLoading) return;
    
    setCategoriesLoading(true);
    setCategoryError(null);
    
    try {
      const response = await categoriesApi.getAll();
      setCategories(response);
      updateDropdownItems(response);
      setConnected(true);
      setCategoriesLoading(false);
    } catch (error) {
      console.error('Error fetching categories:', error);
      setCategoryError(error instanceof Error ? error.message : 'Failed to fetch categories');
      setConnected(false);
      setCategoriesLoading(false);
    }
  };

  // Convert categories to dropdown format
  const updateDropdownItems = (categories: Category[]) => {
    const items = categories.map(category => ({
      label: category.name,
      value: category.name // Using name as both label and value for compatibility
    }));
    setDropdownItems(items);
  };

  // Get a category by name
  const getCategoryById = (id: string) => {
    return storeCategories.find(category => category.id === id);
  };

  // Get a category by name
  const getCategoryByName = (name: string) => {
    return storeCategories.find(category => category.name === name);
  };

  return {
    categories: storeCategories,
    dropdownItems,
    isCategoriesLoading,
    categoryError,
    connected,
    fetchCategories,
    getCategoryById,
    getCategoryByName
  };
}; 