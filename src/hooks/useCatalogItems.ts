import { useState, useEffect, useCallback, useRef } from 'react';
import api, { apiClient, directSquareApi } from '../api';
import { useAppStore } from '../store';
import { CatalogObject, ConvertedItem } from '../types/api';
import { ScanHistoryItem } from '../types';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';
import { useApi } from '../providers/ApiProvider';
import logger from '../utils/logger';
import {
  getDatabase,
  getItemOrVariationRawById,
  upsertCatalogObjects
} from '../database/modernDb';
import { v4 as uuidv4 } from 'uuid';

// Define a more specific type for raw DB results if possible
type RawDbRow = any; // Replace 'any' if a better type exists

type CatalogObjectFromApi = any; // Reuse or define specific type

export const useCatalogItems = () => {
  const { 
    products: storeProducts, 
    setProducts, 
    addScanHistoryItem,
    isProductsLoading, 
    setProductsLoading, 
    productError,
    setProductError,
    categories
  } = useAppStore();
  
  // Get the Square connection status from the API context
  const { isConnected: isSquareConnected } = useApi();
  
  const [currentCursor, setCurrentCursor] = useState<string | null>(null);
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

  // Function to fetch products using DIRECT Square API call
  const fetchProducts = useCallback(async (showLoading = true, limit = 20) => {
    if (!isSquareConnected) {
      logger.info('CatalogItems', 'Skipping product fetch - no Square connection');
      return; // Early exit
    }
    if (showLoading && isProductsLoading) return;
    
    if (showLoading) setProductsLoading(true);
    else setIsRefreshing(true);
    setProductError(null);
    
    try {
      logger.info('CatalogItems', 'Fetching catalog items directly from Square', { cursor: currentCursor || 'start', limit });
      
      // Call direct listCatalog API - **FIXED: Use fetchCatalogPage instead of listCatalog**
      const response = await directSquareApi.fetchCatalogPage(
        limit,
         currentCursor || undefined, // Pass cursor as second arg
         'ITEM' // Pass types as third arg
       );
      
      // **FIXED: Check for top-level objects now**
      if (!response.success || !response.objects) {
        logger.error('CatalogItems', 'Direct listCatalog fetch failed', { responseError: response.error });
        throw response.error || new Error('Failed to fetch products directly');
      }
      
      // We get raw CatalogObjects back, transform them
      // **FIXED: Get objects from top level**
      const itemObjects: CatalogObject[] = response.objects;
      const transformedItems = itemObjects
        .map((item: CatalogObject) => transformCatalogItemToItem(item))
        .filter((item: ConvertedItem | null): item is ConvertedItem => item !== null)
        // Map additional fields if needed (category name was here before, might need adjustment)
        .map((item: ConvertedItem) => ({
          ...item,
          // Category name lookup might need rework if categories aren't pre-fetched
          // category: item.categoryId ? categoryMapRef.current[item.categoryId] || '' : '',
          price: item.price === undefined ? undefined : item.price, // Handle undefined explicitly
          description: item.description || '',
          sku: item.sku || '',
          barcode: item.barcode || '',
          abbreviation: item.abbreviation || '', // Ensure abbreviation is mapped
        }));
      
      if (currentCursor) {
        setProducts([...storeProducts, ...transformedItems]);
      } else {
        setProducts(transformedItems);
      }
      
      // **FIXED: Get cursor from top level**
      const responseCursor = response.cursor || null;
      setCurrentCursor(responseCursor); // Update cursor state
      setHasMore(!!responseCursor);
      logger.info('CatalogItems', `Successfully fetched ${transformedItems.length} products directly`);

    } catch (error: unknown) {
      logger.error('CatalogItems', 'Error fetching products directly', { error });
      const message = error instanceof Error ? error.message : 'Failed to fetch products';
      setProductError(message);
      // Consider setting hasMore to false on error?
    } finally {
      if (showLoading) setProductsLoading(false);
      else setIsRefreshing(false);
    }
  // Dependencies need to include currentCursor now
  }, [isProductsLoading, setProductsLoading, setProductError, setProducts, storeProducts, currentCursor, isSquareConnected]);

  // Function to refresh products - reset cursor
  const refreshProducts = useCallback(() => {
    if (!isSquareConnected) {
      logger.info('CatalogItems', 'Skipping product refresh - no Square connection');
      return Promise.resolve(); // Return empty promise
    }
    logger.info('CatalogItems', 'Refreshing catalog items directly');
    setCurrentCursor(null); // Reset cursor
    // Initial fetch after reset doesn't depend on the old cursor value
    // Fetch products immediately after resetting cursor
    return fetchProducts(false);
  }, [fetchProducts, isSquareConnected, setCurrentCursor]); // Add setCurrentCursor dependency

  // Function to load more products
  const loadMoreProducts = useCallback(() => {
    if (hasMore && !isProductsLoading && !isRefreshing && isSquareConnected && currentCursor) {
        fetchProducts(true);
    } else if (!currentCursor && hasMore && !isProductsLoading && !isRefreshing && isSquareConnected) {
        // Handle case where we want to load first page but cursor is null
      fetchProducts(true);
    }
  }, [hasMore, isProductsLoading, isRefreshing, fetchProducts, isSquareConnected, currentCursor]);

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

      // --- Extract Modifier List IDs --- 
      const modifierListInfo = itemData?.item_data?.modifier_list_info;
      let actualModifierListIds: string[] = [];

      if (modifierListInfo && Array.isArray(modifierListInfo) && modifierListInfo.length > 0) {
        actualModifierListIds = modifierListInfo
          .map((info: any) => info?.modifier_list_id)
          .filter((modId: any): modId is string => typeof modId === 'string');
        logger.debug('CatalogItems::getProductById', 'Extracted modifier IDs from item data', { itemId, count: actualModifierListIds.length, ids: actualModifierListIds });
      }
      // --- End: Extract Modifier List IDs ---

      // Reconstruct CatalogObject (ensure structure matches transformer expectations)
       const reconstructedCatalogObject: Partial<CatalogObjectFromApi> & { id: string } = {
          id: itemId, // Use the actual ITEM id
          type: 'ITEM',
          updated_at: itemUpdatedAt,
          version: itemData.version, // Include the version from parsed item JSON
          is_deleted: false,
          item_data: {
            ...(itemData.item_data || {}), // Spread item_data fields
            // Explicitly add reporting_category from the raw item data
            reporting_category: itemData?.item_data?.reporting_category, 
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

      // Call the transformer, passing the actual modifier list IDs
      const transformedItem = transformCatalogItemToItem(reconstructedCatalogObject as any, actualModifierListIds);

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

  // --- CREATE --- 
  // Create a new product using direct Square API call
  const createProduct = useCallback(async (productData: any) => {
    // Log the incoming productData object
    logger.debug('CatalogItems::createProductDirect', 'Received productData', { productData: JSON.stringify(productData) });

    if (!isSquareConnected) {
      console.error('Cannot create product - no Square connection');
      throw new Error('Not connected to Square');
    }
    setProductsLoading(true);
    try {
      // 1. Construct the Square CatalogObject payload for creation
      const idempotencyKey = uuidv4();
      const squarePayload = {
        id: `#${productData.name.replace(/\s+/g, '-')}-${Date.now()}`, // Temporary client ID
        type: 'ITEM',
        item_data: {
          name: productData.name,
          description: productData.description || undefined,
          abbreviation: productData.abbreviation || undefined,
          // **FIXED: Use reporting_category object structure**
          reporting_category: productData.reporting_category_id ? { id: productData.reporting_category_id } : undefined,
          // Create variations array from productData.variations if available
          variations: productData.variations && Array.isArray(productData.variations) && productData.variations.length > 0
            ? productData.variations.map((variation: any, index: number) => ({
                id: `#variation-${index}-${Date.now()}`, // Generate temporary client ID for each variation
                type: 'ITEM_VARIATION',
                item_variation_data: {
                  name: variation.name || 'Regular',
                  sku: variation.sku || undefined,
                  upc: variation.barcode || undefined,
                  pricing_type: variation.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: variation.price !== undefined ? {
                    amount: Math.round(variation.price * 100),
                    currency: 'USD'
                  } : undefined,
                }
              }))
            : [{
                id: '#default-variation', // Temporary client ID for default variation
                type: 'ITEM_VARIATION',
                item_variation_data: {
                  name: productData.variationName || 'Regular', // Fallback to variationName from input
                  sku: productData.sku || undefined, // SKU belongs here
                  upc: productData.barcode || undefined, // MAP BARCODE TO UPC
                  pricing_type: productData.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: productData.price !== undefined ? {
                    amount: Math.round(productData.price * 100),
                    currency: 'USD'
                  } : undefined,
                }
              }],
          // **FIXED: Tax IDs and Modifiers belong INSIDE item_data**
          tax_ids: productData.taxIds && productData.taxIds.length > 0 ? productData.taxIds : undefined, // MAP TAX IDS
          modifier_list_info: productData.modifierListIds && productData.modifierListIds.length > 0 ? productData.modifierListIds.map((modId: string) => ({ modifier_list_id: modId, enabled: true })) : undefined, // MAP MODIFIER LIST IDS
          product_type: 'REGULAR', // CORRECTED ENUM: Use REGULAR
        }
      };
      
      // Remove undefined fields from item_data
      Object.keys(squarePayload.item_data).forEach(key => {
        if (squarePayload.item_data[key as keyof typeof squarePayload.item_data] === undefined) {
          delete squarePayload.item_data[key as keyof typeof squarePayload.item_data];
        }
      });
      
      // Explicitly handle variation data cleanup for each variation
      if (squarePayload.item_data.variations && squarePayload.item_data.variations.length > 0) {
        squarePayload.item_data.variations.forEach((variation: any) => {
          if (variation.item_variation_data) {
            const variationData = variation.item_variation_data;
            // Remove undefined price_money
            if (variationData.price_money === undefined) {
              delete variationData.price_money;
            }
            // Remove undefined UPC
            if (variationData.upc === undefined) {
              delete variationData.upc;
            }
            // Remove undefined SKU
            if (variationData.sku === undefined) {
              delete variationData.sku;
            }
          }
        });
      }

      // Log the final payload BEFORE sending
      logger.debug('CatalogItems::createProductDirect', 'Final Payload for CREATE', { payload: JSON.stringify(squarePayload) });
      logger.debug('CatalogItems::createProductDirect', 'Calling directSquareApi.upsertCatalogObject for CREATE', { idempotencyKey });
      
      // 2. Call the direct Square API
      const response = await directSquareApi.upsertCatalogObject(squarePayload, idempotencyKey);
      
      if (!response.success || !response.data?.catalog_object) {
         logger.error('CatalogItems::createProductDirect', 'Direct Square upsert failed', { responseError: response.error });
        throw response.error || new Error('Failed to create product via direct Square API');
      }
      
      logger.info('CatalogItems::createProductDirect', 'Direct Square upsert successful', { newId: response.data.catalog_object.id });

      // 3. Fetch the newly created object to get full details
      const newId = response.data.catalog_object.id;
      let createdItem: ConvertedItem | null = null;
      try {
        const retrievedResponse = await directSquareApi.retrieveCatalogObject(newId, true); // Include related objects
        if (retrievedResponse.success && retrievedResponse.data?.object) {
          const rawCatalogObject = retrievedResponse.data.object;
          // 4. Update local DB
          const db = await getDatabase(); // Ensure DB is ready
          await upsertCatalogObjects([rawCatalogObject]); // Use modernDb helper

          // 5. Transform for UI state
          createdItem = transformCatalogItemToItem(rawCatalogObject as any);

          // 6. Update Zustand state (add to beginning of list)
          if (createdItem) {
            setProducts([createdItem, ...storeProducts]);
            // **FIXED: Also add to scan history**
            const historyItem: ScanHistoryItem = {
              ...createdItem,
              scanId: uuidv4(), // Generate unique ID for this scan event
              scanTime: new Date().toISOString(),
            };
            addScanHistoryItem(historyItem);
            logger.info('CatalogItems::createProductDirect', 'Added newly created item to local state and DB', { newId });
          } else {
            logger.warn('CatalogItems::createProductDirect', 'Failed to transform newly created item', { newId });
            // Fallback to full refresh if transformation fails?
            await refreshProducts(); 
          }
        } else {
          logger.error('CatalogItems::createProductDirect', 'Failed to retrieve newly created item', { newId, error: retrievedResponse.error });
          await refreshProducts(); // Fallback to full refresh if retrieval fails
        }
      } catch (fetchError) {
        logger.error('CatalogItems::createProductDirect', 'Error retrieving or processing newly created item', { newId, error: fetchError });
        await refreshProducts(); // Fallback to full refresh on any error during fetch/process
      }
      
      // 7. Return the transformed item (or null if retrieval/transform failed)
      return createdItem;

    } catch (error: unknown) {
      logger.error('CatalogItems::createProductDirect', 'Error creating product directly', { error });
      setProductError(error instanceof Error ? error.message : 'Failed to create product');
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected, setProducts, storeProducts, addScanHistoryItem]);

  // --- UPDATE --- 
  // Update an existing product using direct Square API call
  const updateProduct = useCallback(async (id: string, productData: ConvertedItem) => {
    // Log the incoming productData object
    logger.debug('CatalogItems::updateProductDirect', 'Received productData', { id, productData: JSON.stringify(productData) });

    if (!isSquareConnected) {
      console.error('Cannot update product - no Square connection');
      throw new Error('Not connected to Square');
    }
    
    setProductsLoading(true);
    try {
      // 1. Construct the Square CatalogObject payload for update
      const idempotencyKey = uuidv4();
      const squarePayload = {
        id: id, 
        type: 'ITEM',
        version: productData.version, 
        item_data: {
          name: productData.name,
          description: productData.description || undefined,
          abbreviation: productData.abbreviation || undefined,
          reporting_category: productData.reporting_category_id ? { id: productData.reporting_category_id } : undefined,
          
          // Handle multiple variations if available, otherwise fall back to single variation
          variations: productData.variations && Array.isArray(productData.variations) && productData.variations.length > 0
            ? productData.variations.map((variation: any) => ({
                id: variation.id || `#variation-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
                type: 'ITEM_VARIATION',
                version: variation.version, // Include version if it exists
                item_variation_data: {
                  name: variation.name || 'Regular',
                  sku: variation.sku || undefined,
                  upc: variation.barcode || undefined,
                  pricing_type: variation.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: variation.price !== undefined ? {
                    amount: Math.round(variation.price * 100),
                    currency: 'USD'
                  } : undefined,
                }
              }))
            : [{
                id: productData.variationId, // Use real ID from input
                type: 'ITEM_VARIATION',
                version: productData.variationVersion, // Use real version from input
                item_variation_data: {
                  name: productData.variationName || 'Regular', 
                  pricing_type: productData.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  sku: productData.sku || undefined, // SKU belongs here
                  upc: productData.barcode || undefined, // MAP BARCODE TO UPC
                  price_money: productData.price !== undefined ? {
                    amount: Math.round(productData.price * 100),
                    currency: 'USD'
                  } : undefined,
                }
              }],
          
          tax_ids: productData.taxIds && productData.taxIds.length > 0 ? productData.taxIds : undefined, // MAP TAX IDS
          modifier_list_info: productData.modifierListIds && productData.modifierListIds.length > 0 ? productData.modifierListIds.map((modId: string) => ({ modifier_list_id: modId, enabled: true })) : undefined, // MAP MODIFIER LIST IDS
          product_type: 'REGULAR', // CORRECTED ENUM: Use REGULAR
        }
      };

      // Clean undefined fields from item_data
      Object.keys(squarePayload.item_data).forEach(key => {
        if (squarePayload.item_data[key as keyof typeof squarePayload.item_data] === undefined) {
           delete squarePayload.item_data[key as keyof typeof squarePayload.item_data];
        }
      });
      
      // Explicitly handle variation data cleanup for each variation
      if (squarePayload.item_data.variations && squarePayload.item_data.variations.length > 0) {
        squarePayload.item_data.variations.forEach((variation: any) => {
          if (variation.item_variation_data) {
            const variationData = variation.item_variation_data;
            // Remove undefined price_money
            if (variationData.price_money === undefined) {
              delete variationData.price_money;
            }
            // Remove undefined UPC
            if (variationData.upc === undefined) {
              delete variationData.upc;
            }
            // Remove undefined SKU
            if (variationData.sku === undefined) {
              delete variationData.sku;
            }
          }
        });
      }
      
      // Log the final payload BEFORE sending
      logger.debug('CatalogItems::updateProductDirect', 'Final Payload for UPDATE', { payload: JSON.stringify(squarePayload) });
      logger.debug('CatalogItems::updateProductDirect', 'Calling directSquareApi.upsertCatalogObject for UPDATE', { id, version: productData.version, idempotencyKey });

      // 2. Call the direct Square API
      const response = await directSquareApi.upsertCatalogObject(squarePayload, idempotencyKey);

      if (!response.success || !response.data?.catalog_object) {
        logger.error('CatalogItems::updateProductDirect', 'Direct Square upsert failed for update', { responseError: response.error });
        throw response.error || new Error('Failed to update product via direct Square API');
      }
      
      logger.info('CatalogItems::updateProductDirect', 'Direct Square update successful', { updatedId: response.data.catalog_object.id, newVersion: response.data.catalog_object.version });

      // 3. Fetch the updated object to get full details
      const updatedId = response.data.catalog_object.id;
      let updatedItem: ConvertedItem | null = null;
      try {
        const retrievedResponse = await directSquareApi.retrieveCatalogObject(updatedId, true);
        if (retrievedResponse.success && retrievedResponse.data?.object) {
          const rawCatalogObject = retrievedResponse.data.object;
          // 4. Update local DB
          const db = await getDatabase();
          await upsertCatalogObjects([rawCatalogObject]);

          // 5. Transform for UI state
          updatedItem = transformCatalogItemToItem(rawCatalogObject as any);

          // 6. Update Zustand state (replace item in list)
          if (updatedItem) {
            setProducts(
              storeProducts.map(p => p.id === updatedId ? updatedItem! : p)
            );
            // **FIXED: Also update/add to scan history**
            const historyItem: ScanHistoryItem = {
              ...updatedItem,
              scanId: uuidv4(), // Generate unique ID for this scan event
              scanTime: new Date().toISOString(),
            };
            addScanHistoryItem(historyItem); // Add/Update in history
            logger.info('CatalogItems::updateProductDirect', 'Updated item in local state and DB', { updatedId });
          } else {
            logger.warn('CatalogItems::updateProductDirect', 'Failed to transform updated item', { updatedId });
            await refreshProducts(); // Fallback
          }
        } else {
          logger.error('CatalogItems::updateProductDirect', 'Failed to retrieve updated item', { updatedId, error: retrievedResponse.error });
          await refreshProducts(); // Fallback
        }
      } catch (fetchError) {
        logger.error('CatalogItems::updateProductDirect', 'Error retrieving or processing updated item', { updatedId, error: fetchError });
        await refreshProducts(); // Fallback
      }
      
      // 7. Return the transformed item (or null if retrieval/transform failed)
      return updatedItem;

    } catch (error: unknown) {
      logger.error('CatalogItems::updateProductDirect', 'Error updating product directly', { id, error });
      setProductError(error instanceof Error ? error.message : 'Failed to update product');
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected, setProducts, storeProducts, addScanHistoryItem]);

  // --- DELETE --- 
  // Delete a product using direct Square API call
  const deleteProduct = useCallback(async (id: string) => {
    if (!isSquareConnected) {
      console.error('Cannot delete product - no Square connection');
      throw new Error('Not connected to Square');
    }
    setProductsLoading(true);
    try {
      logger.debug('CatalogItems::deleteProductDirect', 'Calling directSquareApi.deleteCatalogObject', { id });

      // Call the direct Square API
      const response = await directSquareApi.deleteCatalogObject(id);
      
      if (!response.success) {
         logger.error('CatalogItems::deleteProductDirect', 'Direct Square delete failed', { responseError: response.error });
        throw response.error || new Error('Failed to delete product via direct Square API');
      }

      logger.info('CatalogItems::deleteProductDirect', 'Direct Square delete successful', { deletedIds: response.data?.deleted_object_ids });

      // Update local state immediately by filtering the current storeProducts
      // This avoids the function argument type issue with setProducts
      const updatedProducts = storeProducts.filter((product: ConvertedItem) => product.id !== id);
      setProducts(updatedProducts);
      
      // TODO: Optionally trigger a smaller refresh or update local DB directly

      return response.data; // Return Square's response data (deleted_object_ids, etc.)

    } catch (error: unknown) {
      logger.error('CatalogItems::deleteProductDirect', 'Error deleting product directly', { id, error });
      setProductError(error instanceof Error ? error.message : 'Failed to delete product');
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, setProducts, isSquareConnected, storeProducts]);

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