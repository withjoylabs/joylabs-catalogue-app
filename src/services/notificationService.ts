import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import logger from '../utils/logger';
import config from '../config'; // Assuming config holds expoProjectId
import apiClient from '../api'; // Use default import
// Import the API client function placeholder we'll create next
// import { registerPushToken } from '../api'; 

/**
 * Registers the app for push notifications, requests permissions, 
 * gets the token, and sends it to the backend.
 * 
 * @returns {Promise<string | null>} The Expo Push Token if successful, otherwise null.
 */
export async function registerForPushNotificationsAsync(): Promise<string | null> {
  let token = null;
  const tag = '[NotificationsService]';

  if (!Device.isDevice) {
    logger.warn(tag, 'Must use physical device for Push Notifications');
    // Optionally throw an error or display an alert to the user
    // throw new Error('Push notifications are not supported on simulators.');
    return null;
  }

  // --- Check/Request Permissions ---
  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;
  if (existingStatus !== 'granted') {
    logger.info(tag, 'Requesting push notification permissions...');
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }

  if (finalStatus !== 'granted') {
    logger.warn(tag, 'Push notification permission not granted!');
    // Optionally throw an error or display an alert
    // throw new Error('Failed to get push permissions.');
    return null;
  }
  logger.info(tag, 'Push notification permissions granted.');

  // --- Get Project ID ---
  // Note: expoConfig might be null in some environments, handle gracefully
  const projectId = Constants.expoConfig?.extra?.eas?.projectId;
  if (!projectId) {
    logger.error(tag, 'Expo Project ID not found in app config (expo.extra.eas.projectId). Cannot get push token.');
    // Optionally throw an error or display an alert
    // throw new Error('Configuration error: Expo Project ID is missing.');
    return null;
  }

  // --- Get Push Token ---
  try {
    logger.info(tag, 'Getting Expo push token with projectId:', { projectId });
    token = (await Notifications.getExpoPushTokenAsync({ projectId })).data;
    logger.info(tag, 'Expo Push Token obtained:', { token });
  } catch (e) {
    logger.error(tag, 'Failed to get push token', e);
    // Optionally throw an error or display an alert
    // throw new Error('Failed to retrieve push token.');
    return null; // Return null if token retrieval fails
  }

  // --- Configure Android Channel ---
  if (Platform.OS === 'android') {
    try {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'default',
        importance: Notifications.AndroidImportance.DEFAULT, // Suitable for background/data
        vibrationPattern: [0, 250, 250, 250], // Standard pattern
        lightColor: '#FF231F7C',
        sound: null, // Ensure channel is suitable for silent notifications
      });
      logger.info(tag, 'Default Android notification channel set/updated.');
    } catch (e) {
       logger.error(tag, 'Failed to set Android channel', e);
       // Decide if this is critical - maybe still return token?
    }
  }

  // --- Send Token to Backend (Placeholder) ---
  if (token) {
    try {
      logger.info(tag, 'Attempting to register push token with backend...');
      const registrationResult = await apiClient.user.registerPushToken(token);
      if (registrationResult.success) {
        logger.info(tag, 'Push token successfully registered with backend.');
      } else {
        // Log the specific error from the API response but DO NOT nullify the token
        logger.error(tag, 'Failed to register push token with backend. Token will still be returned to caller.', {
          error: registrationResult.error,
        });
        // Optionally, re-throw or handle this failure more explicitly
        // return null; // REMOVED: We want to return the token even if backend fails for now.
      }
    } catch (error) {
      // Catch unexpected errors during the API call itself but DO NOT nullify the token
      logger.error(tag, 'Unexpected error calling backend to register push token. Token will still be returned to caller.', {
        error,
      });
      // return null; // REMOVED: We want to return the token even if backend fails for now.
    }
  }

  // Return the token regardless of backend registration success/failure
  // The UI layer will store this token for potential future unregistration.
  return token;
}

// Optional: Function to unregister (requires backend support)
export async function unregisterPushNotificationsAsync(token: string): Promise<void> {
   const tag = '[NotificationsService]';
   logger.info(tag, 'Attempting to unregister push token from backend...', { token });
   try {
     await apiClient.user.unregisterPushToken(token);
     logger.info(tag, 'Successfully unregistered token (placeholder).');
   } catch (e) {
     logger.error(tag, 'Failed to unregister token.', e);
     // Handle error appropriately
   }
} 