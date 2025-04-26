import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import logger from '../utils/logger';

const NOTIFICATION_ENABLED_KEY = '@notifications_enabled';
const PUSH_TOKEN_KEY = '@push_token'; // Use SecureStore for the token

/**
 * Saves the user's preference for enabling/disabling notifications.
 * @param {boolean} enabled - True if enabled, false otherwise.
 */
export async function saveNotificationEnabledStatus(enabled: boolean): Promise<void> {
  try {
    await AsyncStorage.setItem(NOTIFICATION_ENABLED_KEY, JSON.stringify(enabled));
    logger.debug('[NotificationState]', 'Saved notification enabled status', { enabled });
  } catch (error) {
    logger.error('[NotificationState]', 'Failed to save notification enabled status', { error });
    // Decide if we should throw or just log
  }
}

/**
 * Loads the user's notification preference.
 * @returns {Promise<boolean>} - True if enabled, false otherwise (defaults to false).
 */
export async function loadNotificationEnabledStatus(): Promise<boolean> {
  try {
    const value = await AsyncStorage.getItem(NOTIFICATION_ENABLED_KEY);
    const enabled = value ? JSON.parse(value) === true : false;
    logger.debug('[NotificationState]', 'Loaded notification enabled status', { enabled });
    return enabled;
  } catch (error) {
    logger.error('[NotificationState]', 'Failed to load notification enabled status', { error });
    return false; // Default to false on error
  }
}

/**
 * Securely saves the obtained Expo Push Token.
 * @param {string} token - The Expo Push Token.
 */
export async function savePushToken(token: string | null): Promise<void> {
  const tag = '[NotificationState]';
  if (!token) {
    logger.warn(tag, 'Attempted to save a null push token. Clearing instead.');
    await clearPushToken();
    return;
  }
  try {
    await SecureStore.setItemAsync(PUSH_TOKEN_KEY, token);
    logger.info(tag, 'Saved push token securely.'); // Don't log the token itself
  } catch (error) {
    logger.error(tag, 'Failed to save push token securely', { error });
    // Decide if we should throw or just log
  }
}

/**
 * Securely loads the stored Expo Push Token.
 * @returns {Promise<string | null>} - The stored token or null if not found/error.
 */
export async function loadPushToken(): Promise<string | null> {
  const tag = '[NotificationState]';
  try {
    const token = await SecureStore.getItemAsync(PUSH_TOKEN_KEY);
    if (token) {
       logger.info(tag, 'Loaded push token securely.');
    }
    return token;
  } catch (error) {
    logger.error(tag, 'Failed to load push token securely', { error });
    return null; // Return null on error
  }
}

/**
 * Securely deletes the stored Expo Push Token.
 */
export async function clearPushToken(): Promise<void> {
  const tag = '[NotificationState]';
  try {
    await SecureStore.deleteItemAsync(PUSH_TOKEN_KEY);
    logger.info(tag, 'Cleared stored push token.');
  } catch (error) {
    logger.error(tag, 'Failed to clear push token', { error });
    // Decide if we should throw or just log
  }
} 