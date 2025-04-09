import { useState, useEffect, useCallback, useRef } from 'react';
import api from '../api';
import { useAppStore } from '../store';
import { CatalogObject, ConvertedItem } from '../types/api';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';
import { useApi } from '../providers/ApiProvider';
import logger from '../utils/logger';
import {
  getDatabase,
  getItemOrVariationRawById
} from '../database/modernDb';

// Define a more specific type for raw DB results if possible
type RawDbRow = any; // Replace 'any' if a better type exists

type CatalogObjectFromApi = any; // Reuse or define specific type

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

  // Get a product by ID - now async and checks DB
  const getProductById = useCallback(async (id: string): Promise<ConvertedItem | null> => {
    // 1. Check Zustand store first
    const storeItem = storeProducts.find(product => product.id === id);
    if (storeItem) {
      logger.debug('CatalogItems::getProductById', 'Item found in store', { id });
      return storeItem;
    }

    logger.debug('CatalogItems::getProductById', 'Item not in store, querying local DB', { id });

    // 2. If not in store, query the database
    try {
      const db = await getDatabase(); // Ensure DB is ready
      // Use getItemOrVariationRawById which checks both items and variations
      const rawResult = await getItemOrVariationRawById(id);

      if (!rawResult || !rawResult.data_json) {
        logger.warn('CatalogItems::getProductById', 'Item/Variation not found in DB or missing data_json', { id });
        return null;
      }

      // Determine if we found an item or a variation
      let itemJson: string | null = null;
      let variationJson: string | null = null;
      let itemId = id; // Default to the passed ID
      let itemUpdatedAt = new Date().toISOString(); // Default timestamp

      if (rawResult.found_in === 'item') {
        itemJson = rawResult.data_json;
        // Need to find the *first* variation associated with this item
        const firstVariation = await db.getFirstAsync<RawDbRow>(
          `SELECT data_json FROM item_variations WHERE item_id = ? AND is_deleted = 0 LIMIT 1`,
          [id]
        );
        variationJson = firstVariation?.data_json || null;
        itemUpdatedAt = rawResult.updated_at || itemUpdatedAt;
      } else if (rawResult.found_in === 'variation') {
        variationJson = rawResult.data_json;
        itemId = rawResult.item_id; // Get the parent item ID
        // Need to fetch the parent item's data
        const parentItem = await db.getFirstAsync<RawDbRow>(
          `SELECT data_json, updated_at FROM catalog_items WHERE id = ? AND is_deleted = 0`,
          [itemId]
        );
        itemJson = parentItem?.data_json || null;
        itemUpdatedAt = parentItem?.updated_at || itemUpdatedAt;
      }
      
      if (!itemJson) {
        logger.warn('CatalogItems::getProductById', 'Could not retrieve necessary item JSON from DB', { id, variationId: rawResult.id });
        return null;
      }

      // 3. Parse JSON and reconstruct for transformer
      const itemData = JSON.parse(itemJson);
      const variationData = variationJson ? JSON.parse(variationJson) : {};

      // --- Start: Determine CRV Type (Copied & adapted from searchLocalItems) ---
      let crvType: 'CRV5' | 'CRV10' | undefined = undefined;
      const modifierListInfo = itemData?.item_data?.modifier_list_info;

      if (modifierListInfo && Array.isArray(modifierListInfo) && modifierListInfo.length > 0) {
        const modifierListIds = modifierListInfo
          .map((info: any) => info?.modifier_list_id)
          .filter((modId: any): modId is string => typeof modId === 'string');

        if (modifierListIds.length > 0) {
          try {
            const placeholders = modifierListIds.map(() => '?').join(',');
            const modifierLists = await db.getAllAsync<{ name: string }>(
              `SELECT name FROM modifier_lists WHERE id IN (${placeholders}) AND is_deleted = 0`,
              modifierListIds
            );

            for (const list of modifierLists) {
              if (list.name === "Modifier Set - CRV10 >24oz") {
                crvType = 'CRV10';
                break;
              }
              if (list.name === "Modifier Set - CRV5 <24oz") {
                crvType = 'CRV5';
              }
            }
          } catch (dbError) {
            logger.error('CatalogItems::getProductById', 'Error querying modifier_lists for CRV type', { itemId, modifierListIds, error: dbError });
          }
        }
      }
      // --- End: Determine CRV Type ---

      // Reconstruct CatalogObject (ensure structure matches transformer expectations)
       const reconstructedCatalogObject: Partial<CatalogObjectFromApi> & { id: string } = {
          id: itemId, // Use the actual ITEM id
          type: 'ITEM',
          updated_at: itemUpdatedAt,
          version: itemData.version || '0', 
          is_deleted: false,
          item_data: {
            ...(itemData.item_data || {}), // Spread item_data fields
             // Ensure variations array exists for transformer
            variations: variationData.id ? [{
              id: variationData.id, 
              type: 'ITEM_VARIATION',
              updated_at: variationData.updated_at, 
              version: variationData.version, 
              item_variation_data: variationData.item_variation_data // Pass variation data nested
            }] : []
          }
        };

      // 4. Transform the reconstructed data
      const transformedItem = transformCatalogItemToItem(reconstructedCatalogObject as any, crvType);

      if (transformedItem) {
        logger.debug('CatalogItems::getProductById', 'Item successfully fetched and transformed from DB', { id });
        return transformedItem;
      } else {
         logger.warn('CatalogItems::getProductById', 'Failed to transform item fetched from DB', { id });
        return null;
      }

    } catch (error) {
      logger.error('CatalogItems::getProductById', 'Error fetching item from DB', { id, error });
      return null;
    }

  }, [storeProducts]); // Dependency: only storeProducts

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