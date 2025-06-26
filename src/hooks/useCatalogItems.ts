import { useState, useEffect, useCallback, useRef } from 'react';
import { apiClient, directSquareApi } from '../api';
import { useAppStore } from '../store';
import { CatalogObject, ConvertedItem, SearchResultItem } from '../types/api';
import { ScanHistoryItem } from '../types';
import { transformCatalogItemToItem } from '../utils/catalogTransformers';
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
            logger.debug('CatalogItems::getProductById', 'Parsed variation data', { 
              variationId: parsedData.id, 
              variationName: parsedData.item_variation_data?.name,
              hasLocationOverrides: !!parsedData.item_variation_data?.location_overrides
            });
            
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
            logger.debug('CatalogItems::getProductById', 'Parsed variation data', { 
              variationId: parsedData.id, 
              variationName: parsedData.item_variation_data?.name,
              hasLocationOverrides: !!parsedData.item_variation_data?.location_overrides
            });
            
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
      logger.debug('CatalogItems::getProductById', 'Parsed item data before reconstruction', { 
        itemId: itemData.id,
        variationCount: variations.length,
        hasPayload: !!itemData.item_data
      });

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

      // Call the transformer, it now handles modifier extraction internally
      const transformedItem = transformCatalogItemToItem(reconstructedCatalogObject as any);

      if (transformedItem) {
        logger.debug('CatalogItems::getProductById', 'Item successfully fetched and transformed from DB', { id });
        logger.debug('CatalogItems::getProductById', 'Transformed item data check', {
          itemId: transformedItem.id,
          variationCount: transformedItem.variations?.length || 0,
          variations: JSON.stringify(transformedItem.variations?.map(v => {
            // Define proper type to avoid linter errors
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
            
            // Use type assertion to avoid linter errors
            const variation = v as VariationWithOverrides;
            
            return {
              id: variation.id,
              name: variation.name,
              hasOverrides: !!variation.locationOverrides,
              overrideCount: variation.locationOverrides?.length || 0
            };
          }))
        });

        // Add location names to each override using default locations if the DB query fails
        if (transformedItem.variations && transformedItem.variations.length > 0) {
          try {
            // Try to get locations from DB, fall back to defaults if error
            let locations: {id: string, name: string}[] = [];
            try {
              locations = await db.getAllAsync<{id: string, name: string}>(
                `SELECT id, name FROM locations WHERE is_deleted = 0`
              );
              logger.debug('CatalogItems::getProductById', 'Fetched locations for overrides', { locationCount: locations.length });
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
            
            logger.debug('CatalogItems::getProductById', 'Successfully added location names to overrides');
          } catch (locError) {
            logger.warn('CatalogItems::getProductById', 'Failed to add location names to overrides', { error: locError });
          }
        }
        
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

  // Helper function to transform raw DB search results to SearchResultItem
  const transformDbResultToItem = useCallback((rawResult: RawSearchResult): SearchResultItem | null => {
    if (!rawResult.data_json) {
      logger.warn('useCatalogItems', 'transformDbResultToItem received item with no data_json', { id: rawResult.id });
      return null;
    }
    try {
      const parsedItemData = JSON.parse(rawResult.data_json);
      const transformedItem = transformCatalogItemToItem(parsedItemData as CatalogObject);

      if (!transformedItem) return null;

      let finalCategoryName = transformedItem.category; 
      if (rawResult.match_type === 'category' && rawResult.match_context) {
        finalCategoryName = rawResult.match_context;
      } else if (!finalCategoryName && transformedItem.categoryId) {
        finalCategoryName = categoryMapRef.current[transformedItem.categoryId] || undefined;
      } else if (!finalCategoryName && transformedItem.reporting_category_id) {
        finalCategoryName = categoryMapRef.current[transformedItem.reporting_category_id] || undefined;
      }
      
      return {
        ...transformedItem,
        category: finalCategoryName, 
        categoryId: transformedItem.categoryId || transformedItem.reporting_category_id, 
        matchType: rawResult.match_type,
        matchContext: rawResult.match_context,
      } as SearchResultItem;
    } catch (error) {
      logger.error('useCatalogItems', 'Error transforming DB search result', { id: rawResult.id, error });
      return null;
    }
  }, [categoryMapRef]);

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
      const localResults = rawResults
          .map(rawResult => transformDbResultToItem(rawResult))
          .filter((item): item is SearchResultItem => item !== null);
      
      // If barcode filter is enabled, search Case UPC locally (LOCAL-FIRST ARCHITECTURE)
      let caseUpcResults: SearchResultItem[] = [];
      if (filters.barcode && isSquareConnected) {
        try {
          logger.info('useCatalogItems:performSearch', '🔍 Searching Case UPC locally (LOCAL-FIRST)', { searchTerm });

          // ✅ CRITICAL FIX: Search local SQLite database instead of AppSync
          const localCaseUpcItems = await modernDb.searchItemsByCaseUpc(searchTerm.trim());

          if (localCaseUpcItems && localCaseUpcItems.length > 0) {
            logger.info('useCatalogItems:performSearch', `✅ Found ${localCaseUpcItems.length} Case UPC matches locally`);

            // Transform local results to SearchResultItem format
            caseUpcResults = localCaseUpcItems.map(item => ({
              id: item.id,
              name: item.name || 'Unknown Item',
              description: item.description || '',
              category_id: item.category_id || '',
              variations: item.variations || [],
              matchType: 'case_upc',
              matchContext: item.team_data?.case_upc || searchTerm.trim(),
              team_data: item.team_data
            } as SearchResultItem));

            logger.info('useCatalogItems:performSearch', `✅ Transformed ${caseUpcResults.length} local case UPC matches`);
          } else {
            logger.info('useCatalogItems:performSearch', '📭 No local case UPC matches found');
          }
        } catch (error) {
          logger.error('useCatalogItems:performSearch', '❌ Local case UPC search failed', { error });
          // Don't fail the entire search if Case UPC search fails
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
      
      setSearchResults(finalResults);
      return finalResults;
    } catch (err) {
      logger.error('useCatalogItems', 'Error during search', { error: err });
      setSearchError(err instanceof Error ? err.message : 'An unknown error occurred.');
      return [];
    } finally {
      setIsSearching(false);
    }
  }, [transformDbResultToItem, isSquareConnected, getProductById, user]);

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
    searchError
  };
}; 