import { 
  CatalogObject, 
  CatalogItemData, 
  CatalogCategoryData,
  ConvertedItem,
  ConvertedCategory
} from '../types/api';

/**
 * Transforms a Square CatalogObject with type ITEM to our frontend Item model
 */
export const transformCatalogItemToItem = (
  catalogObject: CatalogObject,
  crvType?: 'CRV5' | 'CRV10'
): ConvertedItem | null => {
  if (!catalogObject || catalogObject.type !== 'ITEM' || !catalogObject.item_data) {
    return null;
  }

  const itemData = catalogObject.item_data as CatalogItemData;
  const variations = itemData.variations || [];
  
  // Get the first variation price if available
  let price: number | undefined;
  if (variations.length > 0 && variations[0].item_variation_data?.price_money?.amount) {
    // Ensure amount is treated as a number before division
    const amount = Number(variations[0].item_variation_data.price_money.amount);
    if (!isNaN(amount)) {
      price = amount / 100; // Convert cents to dollars
    }
  }
  
  // Extract tax IDs
  const taxIds = itemData.tax_ids || [];

  // Get image URLs
  const imageUrls: string[] = [];
  
  return {
    id: catalogObject.id,
    name: itemData.name,
    description: itemData.description || '',
    price,
    sku: variations.length > 0 ? variations[0].item_variation_data?.sku : undefined,
    barcode: variations.length > 0 ? variations[0].item_variation_data?.upc : undefined, // Assuming barcode maps to upc
    isActive: !catalogObject.is_deleted,
    categoryId: itemData.category_id,
    category: '', // This would be filled in by a separate lookup if needed
    images: imageUrls,
    createdAt: catalogObject.created_at,
    updatedAt: catalogObject.updated_at,
    taxIds: taxIds, // Add extracted taxIds
    crvType: crvType // Add passed crvType
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

  const variations = [];
  
  // If we have a price, create a default variation
  if (priceMoney) {
    variations.push({
      type: 'ITEM_VARIATION',
      id: `#variation-${item.id}`,
      present_at_all_locations: true,
      item_variation_data: {
        name: 'Regular',
        price_money: priceMoney,
        pricing_type: 'FIXED_PRICING',
        sku: item.sku
      }
    });
  }

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