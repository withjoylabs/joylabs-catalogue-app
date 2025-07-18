import { useState, useEffect, useCallback, useRef } from 'react';
import { apiClient, directSquareApi } from '../api';
import { useAppStore } from '../store';
import { CatalogObject, ConvertedItem, SearchResultItem } from '../types/api';
import { ScanHistoryItem } from '../types';
import { transformCatalogItemToItem, populateItemImagesForItems, populateItemImages } from '../utils/catalogTransformers';
import { crossReferenceService } from '../services/crossReferenceService';
import { useApi } from '../providers/ApiProvider';
import logger from '../utils/logger';
import {
  getDatabase,
  getItemOrVariationRawById,
  upsertCatalogObjects,
  searchCatalogItems,
  SearchFilters,
  RawSearchResult
} from '../database/modernDb';
import * as modernDb from '../database/modernDb';
import { v4 as uuidv4 } from 'uuid';
import { Platform } from 'react-native';
import { dataChangeNotifier, DataChangeEvent } from '../services/dataChangeNotifier';
import { generateClient } from 'aws-amplify/api';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import * as queries from '../graphql/queries';

// Define a more specific type for raw DB results if possible
type RawDbRow = any; // Replace 'any' if a better type exists

type CatalogObjectFromApi = any; // Reuse or define specific type

// Initialize GraphQL client
const client = generateClient();

// Add this helper function at the top level
const generateIdempotencyKey = () => {
  // Use a timestamp-based approach for idempotency keys
  return `joylabs-${Date.now()}-${Math.random().toString(36).substring(2, 15)}`;
};

export const useCatalogItems = () => {
  const { 
    products: storeProducts, 
    setProducts, 
    addScanHistoryItem,
    isProductsLoading, 
    setProductsLoading, 
    productError,
    setProductError,
    categories,
    setLastUpdatedItem,
    scanHistory,
    removeScanHistoryItem
  } = useAppStore();
  
  // Get the Square connection status from the API context
  const { isConnected: isSquareConnected } = useApi();
  
  // Get authentication status
  const { user } = useAuthenticator((context) => [context.user]);
  
  const [currentCursor, setCurrentCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [connected, setConnected] = useState(false);
  
  // Cache category lookup for performance
  const categoryMapRef = useRef<Record<string, string>>({});
  
  // Update category map when categories change
  useEffect(() => {
    const map: Record<string, string> = {};
    if (categories && Array.isArray(categories)) {
    categories.forEach(category => {
        if (category && category.id && category.name) {
      map[category.id] = category.name;
        }
    });
    }
    categoryMapRef.current = map;
  }, [categories]);

  // Use ref to access current products without causing re-renders
  const storeProductsRef = useRef(storeProducts);

  // Update ref when products change
  useEffect(() => {
    storeProductsRef.current = storeProducts;
  }, [storeProducts]);

  // Listen for data changes to trigger targeted cache invalidation
  useEffect(() => {
    const handleDataChange = (event: DataChangeEvent) => {
      logger.debug('useCatalogItems', 'Data change detected', {
        table: event.table,
        operation: event.operation,
        itemId: event.itemId
      });

      // For catalog items and images, invalidate specific item from Zustand store
      // This forces getProductById to fetch fresh data from database on next call
      if (event.table === 'catalog_items' || event.table === 'images') {
        const affectedItemId = event.table === 'images' ? event.data?.itemId : event.itemId;

        if (affectedItemId) {
          // Add a small delay to prevent race conditions with modal operations
          // This allows any ongoing modal state changes to complete first
          setTimeout(() => {
            // Use ref to get current products without dependency issues
            const currentProducts = storeProductsRef.current;
            const updatedProducts = currentProducts.filter(p => p.id !== affectedItemId);
            setProducts(updatedProducts);

            logger.info('useCatalogItems', 'Invalidated item cache for targeted refresh (delayed)', {
              table: event.table,
              operation: event.operation,
              itemId: event.itemId,
              affectedItemId,
              removedFromStore: currentProducts.length !== updatedProducts.length
            });
          }, 200); // Small delay to avoid modal state conflicts
        }
      }
    };

    const unsubscribe = dataChangeNotifier.addListener(handleDataChange);
    logger.debug('useCatalogItems', 'Added data change listener');

    return () => {
      unsubscribe();
      logger.debug('useCatalogItems', 'Removed data change listener');
    };
  }, [setProducts]); // FIXED: Removed storeProducts dependency to prevent infinite loops



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
      let transformedItems = itemObjects
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

      // Populate image URLs for all transformed items
      transformedItems = await populateItemImagesForItems(transformedItems);
      
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
      let variations: any[] = [];
      let itemId = id; // Default to the passed ID
      let itemUpdatedAt = new Date().toISOString(); // Default timestamp

      if (rawResult.found_in === 'item') {
        itemJson = rawResult.data_json;
        // Need to fetch ALL variations associated with this item
        const allVariations = await db.getAllAsync<RawDbRow>(
          `SELECT data_json FROM item_variations WHERE item_id = ? AND is_deleted = 0`,
          [id]
        );
        
        // Parse all variation JSON
        variations = allVariations.map(v => {
          try {
            const parsedData = JSON.parse(v.data_json || '{}');

            
            // Log location overrides if they exist
            if (parsedData.item_variation_data?.location_overrides) {
              const overrides = parsedData.item_variation_data.location_overrides;
              logger.debug('CatalogItems::getProductById', 'Found location overrides', {
                variationId: parsedData.id,
                overrideCount: overrides.length,
                overrides: JSON.stringify(overrides)
              });
            }
            
            return parsedData;
          } catch (e) {
            logger.error('CatalogItems::getProductById', 'Error parsing variation JSON', { error: e });
            return null;
          }
        }).filter(Boolean);
        
        itemUpdatedAt = rawResult.updated_at || itemUpdatedAt;
      } else if (rawResult.found_in === 'variation') {
        // We found a specific variation, need to get the parent item and all its variations
        itemId = rawResult.item_id; // Get the parent item ID
        
        // Need to fetch the parent item's data
        const parentItem = await db.getFirstAsync<RawDbRow>(
          `SELECT data_json, updated_at FROM catalog_items WHERE id = ? AND is_deleted = 0`,
          [itemId]
        );
        
        if (!parentItem || !parentItem.data_json) {
          logger.warn('CatalogItems::getProductById', 'Parent item not found for variation', { variationId: id, itemId });
          return null;
        }
        
        itemJson = parentItem.data_json;
        itemUpdatedAt = parentItem.updated_at || itemUpdatedAt;
        
        // Fetch ALL variations for this parent item
        const allVariations = await db.getAllAsync<RawDbRow>(
          `SELECT data_json FROM item_variations WHERE item_id = ? AND is_deleted = 0`,
          [itemId]
        );
        
        // Parse all variation JSON
        variations = allVariations.map(v => {
          try {
            const parsedData = JSON.parse(v.data_json || '{}');

            
            // Log location overrides if they exist
            if (parsedData.item_variation_data?.location_overrides) {
              const overrides = parsedData.item_variation_data.location_overrides;
              logger.debug('CatalogItems::getProductById', 'Found location overrides', {
                variationId: parsedData.id,
                overrideCount: overrides.length,
                overrides: JSON.stringify(overrides)
              });
            }
            
            return parsedData;
          } catch (e) {
            logger.error('CatalogItems::getProductById', 'Error parsing variation JSON', { error: e });
            return null;
          }
        }).filter(Boolean);
      }
      
      if (!itemJson) {
        logger.warn('CatalogItems::getProductById', 'Could not retrieve necessary item JSON from DB', { id, variationId: rawResult.id });
        return null;
      }

      // 3. Parse JSON and reconstruct for transformer
      const itemData = JSON.parse(itemJson);


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
            // CRITICAL FIX: Include image_ids from root level of itemData
            image_ids: itemData.image_ids || [],
          // Include ALL variations for transformer
          variations: variations.map(v => ({
            id: v.id,
              type: 'ITEM_VARIATION',
            updated_at: v.updated_at,
            version: v.version,
            item_variation_data: v.item_variation_data
          }))
          }
        };

      // Use CrossReferenceService to get item with category name populated (like reorders page)
      const transformedItem = await crossReferenceService.getSquareItem(itemId);

      if (transformedItem) {
        // Add location names to each override using default locations if the DB query fails
        if (transformedItem.variations && transformedItem.variations.length > 0) {
          try {
            // Try to get locations from DB, fall back to defaults if error
            let locations: {id: string, name: string}[] = [];
            try {
              locations = await db.getAllAsync<{id: string, name: string}>(
                `SELECT id, name FROM locations WHERE is_deleted = 0`
              );

            } catch (locDbError) {
              logger.warn('CatalogItems::getProductById', 'Error fetching locations from DB, using defaults', { error: locDbError });
              // Use default locations as fallback
              locations = [
                { id: 'L1', name: 'JOY 1 Redondo' },
                { id: 'L2', name: 'JOY 1 Torrance' }
              ];
            }
            
            // Create a map for quick lookup
            const locationMap = new Map<string, string>();
            locations.forEach(loc => locationMap.set(loc.id, loc.name));
            
            // Update location names in overrides
            transformedItem.variations = transformedItem.variations.map(variation => {
              // Define proper type for variation with locationOverrides
              type VariationWithOverrides = {
                id?: string;
                version?: number;
                name: string | null;
                sku: string | null;
                price?: number;
                barcode?: string;
                locationOverrides?: Array<{
                  locationId: string;
                  locationName?: string;
                  price?: number;
                }>;
              };
              
              // Cast variation to the proper type
              const variationWithOverrides = variation as VariationWithOverrides;
              
              if (variationWithOverrides.locationOverrides) {
                variationWithOverrides.locationOverrides = variationWithOverrides.locationOverrides.map(override => ({
                  ...override,
                  locationName: locationMap.get(override.locationId) || 'Unknown Location'
                }));
              }
              return variationWithOverrides;
            });
            

          } catch (locError) {
            logger.warn('CatalogItems::getProductById', 'Failed to add location names to overrides', { error: locError });
          }
        }

        // Populate image URLs before returning
        const itemWithImages = await populateItemImages(transformedItem);
        return itemWithImages;
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
      const idempotencyKey = generateIdempotencyKey();
      const squarePayload = {
        id: `#${productData.name.replace(/\s+/g, '-')}-${Date.now()}`,
        type: 'ITEM',
        item_data: {
          name: productData.name,
          description: productData.description,
          abbreviation: productData.abbreviation,
          reporting_category: productData.reporting_category_id ? { id: productData.reporting_category_id } : undefined,
          categories: productData.categories ? productData.categories.map((cat: { id: string; ordinal?: number }) => ({
            id: cat.id,
            ordinal: cat.ordinal
          })) : undefined, // Send categories array to Square
          variations: productData.variations && Array.isArray(productData.variations) && productData.variations.length > 0
            ? productData.variations.map((variation: any, index: number) => ({
                id: `#variation-${index}-${Date.now()}`,
                type: 'ITEM_VARIATION',
                item_variation_data: {
                  name: variation.name,
                  sku: variation.sku,
                  upc: variation.barcode,
                  pricing_type: variation.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: variation.price !== undefined ? {
                    amount: Math.round(variation.price * 100),
                    currency: 'USD'
                  } : undefined,
                  // Add location_overrides if they exist
                  location_overrides: variation.locationOverrides?.map((override: any) => ({
                    location_id: override.locationId,
                    price_money: override.price !== undefined ? {
                      amount: Math.round(override.price * 100),
                      currency: 'USD'
                    } : undefined
                  })) || undefined
                }
              }))
            : [{
                id: '#default-variation', // Temporary client ID for default variation
            type: 'ITEM_VARIATION',
            item_variation_data: {
                  name: productData.variationName,
                  sku: productData.sku,
                  upc: productData.barcode,
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
              scanId: generateIdempotencyKey(),
              scanTime: new Date().toISOString(),
            };
            addScanHistoryItem(historyItem);
            logger.info('CatalogItems::createProductDirect', 'Added newly created item to local state and DB', { newId });
            
            setLastUpdatedItem(createdItem);
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
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected, setProducts, storeProducts, addScanHistoryItem, setLastUpdatedItem]);

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
      // --- Single Stage Update --- 
      const idempotencyKey = generateIdempotencyKey();
      const squarePayload = {
        id: id, 
        type: 'ITEM',
        version: productData.version, // Crucial: Use the item's version
        item_data: {
          name: productData.name,
          description: productData.description,
          abbreviation: productData.abbreviation,
          reporting_category: productData.reporting_category_id ? { id: productData.reporting_category_id } : undefined,
          categories: productData.categories ? productData.categories.map((cat: { id: string; ordinal?: number }) => ({
            id: cat.id,
            ordinal: cat.ordinal
          })) : undefined, // Send categories array to Square
          
          // Construct the variations array for the single update call
          variations: (productData.variations || []).map((variation: any, index: number) => {
            // Log location overrides if present
            if (variation.locationOverrides && variation.locationOverrides.length > 0) {
              logger.debug('CatalogItems::updateProductDirect', 'Processing variation with price overrides', { 
                variationId: variation.id || `new-${index}`,
                variationName: variation.name,
                overrideCount: variation.locationOverrides.length,
                overrides: JSON.stringify(variation.locationOverrides)
              });
            }
            
            // Check if it's an existing variation (has id and version)
            if (variation.id && variation.version) {
              return { // Payload for EXISTING variation update
                id: variation.id,
                type: 'ITEM_VARIATION',
                version: variation.version,
                item_variation_data: {
                  name: variation.name,
                  sku: variation.sku,
                  upc: variation.barcode,
                  pricing_type: variation.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: variation.price !== undefined ? {
                    amount: Math.round(variation.price * 100),
                    currency: 'USD'
                  } : undefined,
                  // Add location_overrides if they exist
                  location_overrides: variation.locationOverrides?.map((override: any) => ({
                    location_id: override.locationId,
                    price_money: override.price !== undefined ? {
                      amount: Math.round(override.price * 100),
                      currency: 'USD'
                    } : undefined
                  })) || undefined
                }
              };
            } else {
              // Payload for NEW variation creation within the item update
              return { 
                id: `#new-variation-${index}-${Date.now()}`, // Must start with # for new objects
            type: 'ITEM_VARIATION',
                // NO version for new variations
            item_variation_data: {
                  name: variation.name,
                  sku: variation.sku,
                  upc: variation.barcode,
                  pricing_type: variation.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
                  price_money: variation.price !== undefined ? {
                    amount: Math.round(variation.price * 100),
                currency: 'USD'
              } : undefined,
                  // Add location_overrides for new variations too
                  location_overrides: variation.locationOverrides?.map((override: any) => ({
                    location_id: override.locationId,
                    price_money: override.price !== undefined ? {
                      amount: Math.round(override.price * 100),
                      currency: 'USD'
                    } : undefined
                  })) || undefined
            }
              };
            }
          }),
          
          tax_ids: productData.taxIds && productData.taxIds.length > 0 ? productData.taxIds : undefined,
          modifier_list_info: productData.modifierListIds && productData.modifierListIds.length > 0 
            ? productData.modifierListIds.map((modId: string) => ({ modifier_list_id: modId, enabled: true })) 
            : undefined,
          product_type: 'REGULAR',
        }
      };

      // Clean undefined fields from item_data
      Object.keys(squarePayload.item_data).forEach(key => {
        if (squarePayload.item_data[key as keyof typeof squarePayload.item_data] === undefined) {
           delete squarePayload.item_data[key as keyof typeof squarePayload.item_data];
        }
      });
      
      // Clean undefined fields within each variation's item_variation_data
      if (squarePayload.item_data.variations) {
          squarePayload.item_data.variations.forEach(variation => {
              if (variation.item_variation_data) {
                  const variationData = variation.item_variation_data;
                   Object.keys(variationData).forEach(key => {
                      if (variationData[key as keyof typeof variationData] === undefined) {
                         delete variationData[key as keyof typeof variationData];
        }
                   });
              }
          });
      }
      
      logger.debug('CatalogItems::updateProductDirect', 'Final Payload for Combined Update', { payload: JSON.stringify(squarePayload) });
      
      // Call the single upsert API
      const response = await directSquareApi.upsertCatalogObject(squarePayload, idempotencyKey);

      if (!response.success || !response.data?.catalog_object) {
        logger.error('CatalogItems::updateProductDirect', 'Combined Square upsert failed', { responseError: response.error });
        throw response.error || new Error('Failed to update product via direct Square API');
      }
      
      logger.info('CatalogItems::updateProductDirect', 'Combined Square update successful', { updatedId: response.data.catalog_object.id, newVersion: response.data.catalog_object.version });

      // --- Fetch final updated object & update state (same as before) --- 
      let finalUpdatedItem: ConvertedItem | null = null;
      try {
        const updatedId = response.data.catalog_object.id;
        const retrievedResponse = await directSquareApi.retrieveCatalogObject(updatedId, true);
        if (retrievedResponse.success && retrievedResponse.data?.object) {
          const rawCatalogObject = retrievedResponse.data.object;
          
          // Log raw data returned from Square to debug missing overrides
          if (rawCatalogObject.item_data && rawCatalogObject.item_data.variations) {
            rawCatalogObject.item_data.variations.forEach((variation: any) => {
              if (variation.item_variation_data && variation.item_variation_data.location_overrides) {
                logger.debug('CatalogItems::updateProductDirect', 'Retrieved variation contains location overrides', {
                  variationId: variation.id,
                  overrideCount: variation.item_variation_data.location_overrides.length,
                  overrides: JSON.stringify(variation.item_variation_data.location_overrides)
                });
              }
            });
          }
          
          // Update local DB
          const db = await getDatabase();
          await upsertCatalogObjects([rawCatalogObject]);

          // Transform for UI state
          finalUpdatedItem = transformCatalogItemToItem(rawCatalogObject as any);
          
          // Log what comes out of the transformer
          if (finalUpdatedItem && finalUpdatedItem.variations) {
            logger.debug('CatalogItems::updateProductDirect', 'Transformed item contains variations with overrides', {
              variationCount: finalUpdatedItem.variations.length,
              variations: JSON.stringify(finalUpdatedItem.variations.map((v: any) => ({
                id: v.id,
                name: v.name,
                hasOverrides: !!v.locationOverrides,
                overrideCount: v.locationOverrides?.length || 0
              })))
            });
          }

          // Update Zustand state
          if (finalUpdatedItem) {
            setProducts(
              storeProducts.map(p => p.id === id ? finalUpdatedItem! : p)
            );
            const historyItem: ScanHistoryItem = {
              ...finalUpdatedItem,
              scanId: generateIdempotencyKey(),
              scanTime: new Date().toISOString(),
            };
            addScanHistoryItem(historyItem);
            logger.info('CatalogItems::updateProductDirect', 'Updated item in local state and DB after combined update', { id });
            
            setLastUpdatedItem(finalUpdatedItem);
            
          } else {
            logger.warn('CatalogItems::updateProductDirect', 'Failed to transform item after combined update', { id });
            await refreshProducts(); // Fallback
          }
        } else {
          logger.error('CatalogItems::updateProductDirect', 'Failed to retrieve item after combined update', { id, error: retrievedResponse.error });
          await refreshProducts(); // Fallback
        }
      } catch (fetchError) {
        logger.error('CatalogItems::updateProductDirect', 'Error retrieving/processing item after combined update', { id, error: fetchError });
        await refreshProducts(); // Fallback
      }
      
      return finalUpdatedItem;

    } catch (error: unknown) {
      logger.error('CatalogItems::updateProductDirect', 'Error updating product directly', { id, error });
      setProductError(error instanceof Error ? error.message : 'Failed to update product');
      throw error;
    } finally {
      setProductsLoading(false);
    }
  }, [setProductsLoading, setProductError, refreshProducts, isSquareConnected, setProducts, storeProducts, addScanHistoryItem, setLastUpdatedItem]);

  // --- DELETE --- 
  // Delete an item by ID
  const deleteProduct = useCallback(async (id: string) => {
    if (!isSquareConnected) {
      console.error('Cannot delete product - no Square connection');
      throw new Error('Not connected to Square');
    }

    try {
      // 1. Call the direct Square API to delete the item
      logger.debug('CatalogItems::deleteProductDirect', 'Calling directSquareApi.deleteCatalogObject', { id });
      const response = await directSquareApi.deleteCatalogObject(id);
      
      if (!response.success) {
        logger.error('CatalogItems::deleteProductDirect', 'Direct Square delete failed', { id, responseError: response.error });
        throw response.error || new Error('Failed to delete item via direct Square API');
      }
      
      logger.info('CatalogItems::deleteProductDirect', 'Direct Square delete successful', { deletedId: id });

      // 2. If API call is successful, update the local database
      try {
        const db = await getDatabase();
        // Mark the item as deleted
        await db.runAsync('UPDATE catalog_items SET is_deleted = 1, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
        // Also mark all its variations as deleted
        await db.runAsync('UPDATE item_variations SET is_deleted = 1, updated_at = ? WHERE item_id = ?', [new Date().toISOString(), id]);
        
        logger.info('CatalogItems::deleteProduct', 'Successfully marked item and its variations as deleted in local DB', { id });
      } catch (dbError) {
        logger.error('CatalogItems::deleteProduct', 'Error updating local DB after delete', { id, error: dbError });
        // Log the error but let the UI update proceed, as the remote delete was successful.
      }

      // 3. Update the Zustand state to remove the item from the UI
      setProducts(storeProducts.filter(p => p.id !== id));
      
      // 4. Remove the item from scan history
      const historyItemsToRemove = scanHistory.filter(item => item.id === id);
      historyItemsToRemove.forEach(item => removeScanHistoryItem(item.scanId));
      logger.info('CatalogItems::deleteProduct', 'Removed item from scan history', { count: historyItemsToRemove.length });
      
      // 5. Signal to the rest of the app that an item was deleted to trigger refreshes
      setLastUpdatedItem({ id: id, isDeleted: true } as any);

      logger.info('CatalogItems::deleteProduct', 'Successfully deleted item and updated state', { id });
      return true; // Indicate success

    } catch (error: unknown) {
      logger.error('CatalogItems::deleteProduct', 'Error during delete process', { id, error });
      throw error; // Re-throw to be caught by the UI
    }
  }, [isSquareConnected, storeProducts, setProducts, directSquareApi, scanHistory, removeScanHistoryItem, setLastUpdatedItem]);

  const [isSearching, setIsSearching] = useState<boolean>(false);
  const [searchResults, setSearchResults] = useState<SearchResultItem[]>([]);
  const [searchError, setSearchError] = useState<string | null>(null);



  // Function to perform search using local DB and GraphQL for Case UPC
  const performSearch = useCallback(async (searchTerm: string, filters: SearchFilters): Promise<SearchResultItem[]> => {
    if (!searchTerm.trim()) {
      setSearchResults([]);
      return [];
    }
    setIsSearching(true);
    setSearchError(null);
    try {
      // Start with local SQLite search
      const rawResults = await searchCatalogItems(searchTerm, filters);

      // Use getProductById for unified item loading (replaces transformDbResultToItem)
      const localItemPromises = rawResults.map(async (rawResult) => {
        const item = await getProductById(rawResult.id);
        if (item) {
          // Convert ConvertedItem to SearchResultItem with match metadata
          return {
            ...item,
            matchType: rawResult.match_type,
            matchContext: rawResult.match_context,
          } as SearchResultItem;
        }
        return null;
      });

      const localResults = (await Promise.all(localItemPromises))
        .filter((item): item is SearchResultItem => item !== null);

      // If barcode filter is enabled, search Case UPC locally (LOCAL-FIRST ARCHITECTURE)
      // Note: Case UPC search is local-only and doesn't require Square connection
      let caseUpcResults: SearchResultItem[] = [];
      if (filters.barcode) {
        // Only search case UPC for numerical values (case UPCs are always numbers)
        const trimmedSearchTerm = searchTerm.trim();
        const isNumericSearch = /^\d+$/.test(trimmedSearchTerm);

        if (!isNumericSearch) {
          logger.debug('useCatalogItems:performSearch', '⏭️ Skipping case UPC search for non-numeric input', { searchTerm: trimmedSearchTerm });
        } else {
          try {
            logger.info('useCatalogItems:performSearch', '🔍 Searching Case UPC locally (LOCAL-FIRST)', {
              searchTerm: trimmedSearchTerm,
              isSquareConnected,
              hasUser: !!user
            });

            // Get case UPC item IDs first
            const localCaseUpcItems = await modernDb.searchItemsByCaseUpc(trimmedSearchTerm);

          if (localCaseUpcItems && localCaseUpcItems.length > 0) {
            logger.info('useCatalogItems:performSearch', `✅ Found ${localCaseUpcItems.length} Case UPC matches locally`);

            // Use getProductById for unified loading (instead of manual transformation)
            const caseUpcItemPromises = localCaseUpcItems.map(async (item) => {
              try {
                const fullItem = await getProductById(item.id);
                if (fullItem) {
                  // Convert ConvertedItem to SearchResultItem with case UPC match metadata
                  return {
                    ...fullItem,
                    matchType: 'case_upc',
                    matchContext: searchTerm.trim(),
                  } as SearchResultItem;
                }
                return null;
              } catch (itemError) {
                logger.warn('useCatalogItems:performSearch', 'Failed to load case UPC item', {
                  itemId: item.id,
                  error: itemError
                });
                return null;
              }
            });

            caseUpcResults = (await Promise.all(caseUpcItemPromises))
              .filter((item): item is SearchResultItem => item !== null);

            logger.info('useCatalogItems:performSearch', `✅ Transformed ${caseUpcResults.length} local case UPC matches`);
          } else {
            logger.info('useCatalogItems:performSearch', '📭 No local case UPC matches found (table may be empty or user not signed in)');
          }
          } catch (error) {
            logger.warn('useCatalogItems:performSearch', '⚠️ Case UPC search unavailable', {
              error: error instanceof Error ? error.message : 'Unknown error',
              searchTerm: trimmedSearchTerm
            });
            // Gracefully continue with regular search results only
          }
        }
      }

      // Combine and deduplicate results
      const allResults = [...localResults, ...caseUpcResults];
      const uniqueResults = new Map<string, SearchResultItem>();

      allResults.forEach(item => {
        if (item && item.id) {
          // Prioritize case_upc matches if they exist
          if (!uniqueResults.has(item.id) || item.matchType === 'case_upc') {
            uniqueResults.set(item.id, item);
          }
        }
      });

      const finalResults = Array.from(uniqueResults.values());
      logger.info('useCatalogItems:performSearch', `Search completed: ${localResults.length} local + ${caseUpcResults.length} Case UPC = ${finalResults.length} total unique results`);

      // Note: getProductById already includes image population via populateItemImages,
      // so we don't need the separate populateItemImagesForItems call
      setSearchResults(finalResults);
      return finalResults;
    } catch (err) {
      logger.error('useCatalogItems', 'Error during search', { error: err });
      setSearchError(err instanceof Error ? err.message : 'An unknown error occurred.');
      return [];
    } finally {
      setIsSearching(false);
    }
  }, [isSquareConnected, getProductById, user]);

  // Debug method to check case UPC data availability
  const debugCaseUpcData = async () => {
    try {
      const db = await modernDb.getDatabase();

      // Check team data count
      const teamDataCount = await db.getFirstAsync<{ count: number }>(
        'SELECT COUNT(*) as count FROM team_data WHERE case_upc IS NOT NULL'
      );

      // Get sample case UPCs
      const sampleCaseUpcs = await db.getAllAsync<{ case_upc: string, item_id: string }>(
        'SELECT case_upc, item_id FROM team_data WHERE case_upc IS NOT NULL LIMIT 5'
      );

      logger.info('useCatalogItems:debugCaseUpcData', 'Case UPC data status', {
        teamDataWithCaseUpc: teamDataCount?.count || 0,
        sampleCaseUpcs,
        isSquareConnected,
        hasUser: !!user
      });

      return {
        teamDataWithCaseUpc: teamDataCount?.count || 0,
        sampleCaseUpcs
      };
    } catch (error) {
      logger.error('useCatalogItems:debugCaseUpcData', 'Failed to check case UPC data', { error });
      return null;
    }
  };

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
    deleteProduct,
    performSearch,
    isSearching,
    searchError,
    debugCaseUpcData
  };
}; 