import { useState, useEffect, useCallback, useRef } from 'react';
import api from '../api';
import { useAppStore } from '../store';
import { CatalogObject, ConvertedItem } from '../types/api';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';
import { useApi } from '../providers/ApiProvider';
import logger from '../utils/logger';

export const useCatalogItems = () => {
  const { 
    products: storeProducts, 
    setProducts, 
    isProductsLoading, 
    setProductsLoading, 
    productError,
    setProductError,
    categories
  } = useAppStore();
  
  // Get the Square connection status from the API context
  const { isConnected: isSquareConnected } = useApi();
  
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [connected, setConnected] = useState(false);
  
  // Cache category lookup for performance
  const categoryMapRef = useRef<Record<string, string>>({});
  
  // Update category map when categories change
  useEffect(() => {
    const map: Record<string, string> = {};
    categories.forEach(category => {
      map[category.id] = category.name;
    });
    categoryMapRef.current = map;
  }, [categories]);

  // DO NOT fetch products on mount - wait for explicit refresh call
  // This prevents the app from making API calls before Square connection

  // Function to fetch products from the API
  const fetchProducts = useCallback(async (showLoading = true, limit = 20) => {
    // Only proceed if we have a valid Square connection
    if (!isSquareConnected) {
      logger.info('CatalogItems', 'Skipping product fetch - no Square connection');
      setConnected(false);
      return;
    }
    
    if (showLoading && isProductsLoading) return;
    
    if (showLoading) setProductsLoading(true);
    else setIsRefreshing(true);
    
    setProductError(null);
    
    try {
      logger.info('CatalogItems', 'Fetching catalog items', { cursor: cursor || undefined, limit });
      // Call the catalog API to get items with explicit ITEM type parameter
      const response = await api.catalog.getItems(
        cursor ? parseInt(cursor as string, 10) : undefined, 
        limit,
        'ITEM' // Always include ITEM type parameter
      );
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to fetch products');
      }
      
      // Filter for just the items and transform them - handle different response formats
      let itemObjects: CatalogObject[] = [];
      
      if (Array.isArray(response.objects)) {
        // If response has objects array (from search endpoint)
        itemObjects = response.objects.filter((item: CatalogObject) => 
          item.type === 'ITEM' && !item.is_deleted
        );
      } else if (Array.isArray(response.items)) {
        // If response has items array (from list endpoint)
        itemObjects = response.items.filter((item: CatalogObject) => 
          item.type === 'ITEM' && !item.is_deleted
        );
      } else if (response.data?.items) {
        // If response has data.items (nested structure)
        itemObjects = response.data.items.filter((item: CatalogObject) => 
          item.type === 'ITEM' && !item.is_deleted
        );
      }
      
      const transformedItems = itemObjects
        .map((item: CatalogObject) => transformCatalogItemToItem(item))
        .filter((item: ConvertedItem | null): item is ConvertedItem => item !== null)
        .map((item: ConvertedItem) => ({
          ...item,
          // Fill in category name from ID
          category: item.categoryId ? categoryMapRef.current[item.categoryId] || '' : '',
          // Ensure required properties have default values
          price: item.price || 0,
          description: item.description || '',
          sku: item.sku || '',
          barcode: item.barcode || '',
          stockQuantity: item.stockQuantity || 0
        }));
      
      if (cursor) {
        // Append to existing products
        setProducts([...storeProducts, ...transformedItems]);
      } else {
        // Replace products
        setProducts(transformedItems);
      }
      
      // Update cursor - handle different response formats
      const responseCursor = response.cursor || response.data?.cursor || null;
      setCursor(responseCursor);
      setHasMore(!!responseCursor);
      setConnected(true);
      logger.info('CatalogItems', `Successfully fetched ${transformedItems.length} products`);
    } catch (error: unknown) {
      logger.error('CatalogItems', 'Error fetching products', { error });
      let errorMessage = 'Failed to fetch products';
      
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      setProductError(errorMessage);
      setConnected(false);
    } finally {
      if (showLoading) setProductsLoading(false);
      else setIsRefreshing(false);
    }
  }, [isProductsLoading, setProductsLoading, setProductError, setProducts, storeProducts, cursor, isSquareConnected]);

  // Function to refresh products without showing the loading state
  const refreshProducts = useCallback(() => {
    // Only refresh if we have a Square connection
    if (!isSquareConnected) {
      logger.info('CatalogItems', 'Skipping product refresh - no Square connection');
      return Promise.resolve({ items: [], hasMore: false });
    }
    
    logger.info('CatalogItems', 'Refreshing catalog items');
    setCursor(null); // Reset cursor to fetch from the beginning
    return fetchProducts(false);
  }, [fetchProducts, isSquareConnected]);

  // Function to load more products
  const loadMoreProducts = useCallback(() => {
    if (hasMore && !isProductsLoading && !isRefreshing && isSquareConnected) {
      fetchProducts(true);
    }
  }, [hasMore, isProductsLoading, isRefreshing, fetchProducts, isSquareConnected]);

  // Get a product by ID
  const getProductById = useCallback((id: string) => {
    return storeProducts.find(product => product.id === id);
  }, [storeProducts]);

  // Create a new product
  const createProduct = useCallback(async (product: Partial<ConvertedItem>) => {
    // Only proceed if we have a Square connection
    if (!isSquareConnected) {
      console.error('Cannot create product - no Square connection');
      throw new Error('Not connected to Square');
    }
    
    setProductsLoading(true);
    
    try {
      const response = await api.catalog.createItem(product);
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to create product');
      }
      
      // Refresh the product list
      await refreshProducts();
      
      return response.data;
    } catch (error: unknown) {
      console.error('Error creating product:', error);
      let errorMessage = 'Failed to create product';
      
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      setProductError(errorMessage);
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected]);

  // Update an existing product
  const updateProduct = useCallback(async (id: string, product: Partial<ConvertedItem>) => {
    // Only proceed if we have a Square connection
    if (!isSquareConnected) {
      console.error('Cannot update product - no Square connection');
      throw new Error('Not connected to Square');
    }
    
    setProductsLoading(true);
    
    try {
      const response = await api.catalog.updateItem(id, product);
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to update product');
      }
      
      // Refresh the product list
      await refreshProducts();
      
      return response.data;
    } catch (error: unknown) {
      console.error('Error updating product:', error);
      let errorMessage = 'Failed to update product';
      
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      setProductError(errorMessage);
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected]);

  // Delete a product
  const deleteProduct = useCallback(async (id: string) => {
    // Only proceed if we have a Square connection
    if (!isSquareConnected) {
      console.error('Cannot delete product - no Square connection');
      throw new Error('Not connected to Square');
    }
    
    setProductsLoading(true);
    
    try {
      const response = await api.catalog.deleteItem(id);
      
      if (!response.success) {
        throw new Error(response.error?.message || 'Failed to delete product');
      }
      
      // Update local state
      setProducts(storeProducts.filter(product => product.id !== id));
      
      return response.data;
    } catch (error: unknown) {
      console.error('Error deleting product:', error);
      let errorMessage = 'Failed to delete product';
      
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      setProductError(errorMessage);
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, setProducts, storeProducts, isSquareConnected]);

  return {
    products: storeProducts,
    isProductsLoading,
    isRefreshing,
    productError,
    hasMore,
    connected,
    isSquareConnected,
    fetchProducts,
    refreshProducts,
    loadMoreProducts,
    getProductById,
    createProduct,
    updateProduct,
    deleteProduct
  };
}; 