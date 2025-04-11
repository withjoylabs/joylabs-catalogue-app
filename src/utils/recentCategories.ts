import AsyncStorage from '@react-native-async-storage/async-storage';
import logger from './logger';

const RECENT_CATEGORY_IDS_KEY = 'RECENT_CATEGORY_IDS';
const MAX_RECENT_CATEGORIES = 10;

/**
 * Retrieves the list of recently used category IDs from AsyncStorage.
 * @returns A promise resolving to an array of category IDs.
 */
export async function getRecentCategoryIds(): Promise<string[]> {
  try {
    const jsonValue = await AsyncStorage.getItem(RECENT_CATEGORY_IDS_KEY);
    return jsonValue != null ? JSON.parse(jsonValue) : [];
  } catch (e) {
    logger.error('RecentCategories', 'Failed to get recent category IDs', { error: e });
    return []; // Return empty array on error
  }
}

/**
 * Adds a category ID to the list of recently used categories in AsyncStorage.
 * The list is kept unique and limited to a maximum size.
 * @param categoryId The ID of the category to add.
 */
export async function addRecentCategoryId(categoryId: string): Promise<void> {
  if (!categoryId) return; // Do nothing if ID is invalid

  try {
    const currentIds = await getRecentCategoryIds();
    
    // Remove the ID if it already exists to move it to the front
    const filteredIds = currentIds.filter(id => id !== categoryId);
    
    // Add the new ID to the beginning
    const newIds = [categoryId, ...filteredIds];
    
    // Limit the list size
    const limitedIds = newIds.slice(0, MAX_RECENT_CATEGORIES);
    
    // Save the updated list
    const jsonValue = JSON.stringify(limitedIds);
    await AsyncStorage.setItem(RECENT_CATEGORY_IDS_KEY, jsonValue);

    logger.debug('RecentCategories', 'Updated recent category IDs', { newIds: limitedIds });

  } catch (e) {
    logger.error('RecentCategories', 'Failed to add recent category ID', { categoryId, error: e });
  }
} 