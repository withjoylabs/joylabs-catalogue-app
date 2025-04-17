import { 
  CatalogObject, 
  CatalogItemData, 
  CatalogCategoryData,
  ConvertedItem,
  ConvertedCategory
} from '../types/api';
import logger from './logger';

/**
 * Transforms a CatalogObject (typically of type ITEM) into a ConvertedItem 
 * suitable for the UI state, extracting key fields and handling variations/price.
 * @param catalogObject The raw CatalogObject from the API or database JSON.
 * @param modifierListIds Array of modifier list IDs associated with the item.
 * @returns A ConvertedItem object or null if transformation is not possible.
 */
export const transformCatalogItemToItem = (
  catalogObject: Partial<CatalogObject> & { id: string }, // Ensure ID is always present
  modifierListIds?: string[] // Accept the array of modifier list IDs
): ConvertedItem | null => {
  if (!catalogObject || catalogObject.type !== 'ITEM' || !catalogObject.item_data) {
    logger.warn('Transform', 'Cannot transform object: not a valid ITEM type or missing item_data', { id: catalogObject?.id });
    return null;
  }

  const itemData = catalogObject.item_data;
  const variations = itemData.variations || [];

  // Extract the first variation for default price/sku
  let price: number | undefined = undefined;
  let sku: string | null = null;
  let barcode: string | undefined = undefined;
  let variationId: string | undefined = undefined;
  let variationVersion: number | undefined = undefined;
  let variationName: string | undefined = undefined;

  // Get first variation data for backward compatibility
  if (variations.length > 0) {
    const firstVariation = variations[0];
    const firstVariationData = firstVariation.item_variation_data;
    
    variationId = firstVariation.id;
    variationVersion = firstVariation.version;
    variationName = firstVariationData?.name || 'Regular';
    
    const firstVariationPrice = firstVariationData?.price_money?.amount;
    if (typeof firstVariationPrice === 'number' && !isNaN(firstVariationPrice)) {
      price = firstVariationPrice / 100; // Convert from cents
    }
    
    sku = firstVariationData?.sku || null;
    barcode = firstVariationData?.upc;
  }

  // Extract all variations into properly formatted objects
  const transformedVariations = variations.map((variation: CatalogObject) => {
    const variationData = variation.item_variation_data || {};
    let variationPrice: number | undefined = undefined;
    
    const rawPrice = variationData.price_money?.amount;
    if (typeof rawPrice === 'number' && !isNaN(rawPrice)) {
      variationPrice = rawPrice / 100; // Convert from cents
    }
    
    return {
      id: variation.id,
      version: variation.version,
      name: variationData.name || 'Regular',
      sku: variationData.sku || null,
      price: variationPrice,
      barcode: variationData.upc
    };
  });

  // Extract image URLs
  const imageUrls = (itemData.image_ids || []) 
    .map((imageId: string) => {
      // Find the corresponding image object if available (depends on what's fetched)
      // This part might need adjustment based on how images are stored/retrieved
      // For now, assume we might have image objects nested or need a separate lookup
      // Placeholder: return { id: imageId, url: 'lookup_needed', name: 'lookup_needed' };
      return imageId; // Simplified: just return ID for now
    })
    .filter((url: string | null): url is string => url !== null); 
    
  // Extract Tax IDs directly if available
  const taxIds = itemData.tax_ids || [];
  
  // Determine reporting category ID if available
  const reportingCategoryId = itemData.reporting_category?.id || undefined;

  // Construct the ConvertedItem
  return {
    id: catalogObject.id,
    name: itemData.name || '', // Ensure name is always a string
    description: itemData.description || '',
    price,
    sku,
    variationId,
    variationVersion,
    variationName,
    barcode,
    isActive: !catalogObject.is_deleted,
    reporting_category_id: reportingCategoryId,
    category: '', // Keep as placeholder or perform lookup if needed
    images: [], // Placeholder - image handling needs refinement based on actual data structure
    createdAt: catalogObject.created_at,
    updatedAt: catalogObject.updated_at,
    taxIds: taxIds,
    modifierListIds: modifierListIds || [], // Use the passed array
    variations: transformedVariations // Add all variations
  };
};

/**
 * Transforms a Square CatalogObject with type CATEGORY to our frontend Category model
 */
export const transformCatalogCategoryToCategory = (
  catalogObject: CatalogObject
): ConvertedCategory | null => {
  if (!catalogObject || catalogObject.type !== 'CATEGORY' || !catalogObject.category_data) {
    return null;
  }

  const categoryData = catalogObject.category_data as CatalogCategoryData;
  
  // Use a default color if none is specified
  const getRandomColor = () => {
    const colors = ['#4CD964', '#5AC8FA', '#FF9500', '#FF2D55', '#5856D6'];
    return colors[Math.floor(Math.random() * colors.length)];
  };
  
  return {
    id: catalogObject.id,
    name: categoryData.name,
    description: '',
    color: getRandomColor(), // Square doesn't have color in categories, so we assign one
    isActive: !catalogObject.is_deleted,
    createdAt: catalogObject.created_at,
    updatedAt: catalogObject.updated_at
  };
};

/**
 * Transforms a frontend Item model to a Square CatalogObject
 */
export const transformItemToCatalogItem = (
  item: ConvertedItem
): Partial<CatalogObject> => {
  // Convert dollars to cents for price
  const priceMoney = item.price !== undefined
    ? { amount: Math.round(item.price * 100), currency: 'USD' }
    : undefined;

  // Always create a default variation object
  const defaultVariation = {
    type: 'ITEM_VARIATION',
    id: `#variation-${item.id}`, // Note: This ID generation might need adjustment for updates vs creates
    present_at_all_locations: true,
    item_variation_data: {
      name: 'Regular', // Default variation name
      pricing_type: item.price !== undefined ? 'FIXED_PRICING' : 'VARIABLE_PRICING',
      price_money: priceMoney, // Include price_money only if defined (it's undefined otherwise)
      sku: item.sku, // Include SKU
      upc: item.barcode // Include barcode/UPC
    }
  };

  // If price is variable, explicitly remove the price_money field as required by Square API
  if (defaultVariation.item_variation_data.pricing_type === 'VARIABLE_PRICING') {
    delete defaultVariation.item_variation_data.price_money;
  }

  const variations = [defaultVariation];

  return {
    type: 'ITEM',
    id: item.id.startsWith('#') ? item.id : `#${item.id}`, // Square expects new item IDs to start with #
    present_at_all_locations: true,
    item_data: {
      name: item.name,
      description: item.description,
      category_id: item.categoryId,
      variations
    }
  };
};

/**
 * Transforms a frontend Category model to a Square CatalogObject
 */
export const transformCategoryToCatalogCategory = (
  category: ConvertedCategory
): Partial<CatalogObject> => {
  return {
    type: 'CATEGORY',
    id: category.id.startsWith('#') ? category.id : `#${category.id}`, // Square expects new item IDs to start with #
    present_at_all_locations: true,
    category_data: {
      name: category.name
    }
  };
}; 