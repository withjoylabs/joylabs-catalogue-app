import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { Platform } from 'react-native';
import logger from '../utils/logger';
import { apiClientInstance } from '../api/client';

// Note: Notification handler is now configured centrally in _layout.tsx
// to avoid conflicts between multiple handlers

interface PushTokenResponse {
  success: boolean;
  message?: string;
  error?: string;
}

class PushNotificationService {
  private static instance: PushNotificationService;
  private expoPushToken: string | null = null;
  private isRegistered: boolean = false;

  private constructor() {}

  public static getInstance(): PushNotificationService {
    if (!PushNotificationService.instance) {
      PushNotificationService.instance = new PushNotificationService();
    }
    return PushNotificationService.instance;
  }

  /**
   * Initialize push notifications - register for permissions and get token
   */
  public async initialize(): Promise<void> {
    const tag = 'PushNotificationService:initialize';
    
    try {
      logger.info(tag, 'Initializing push notifications...');

      // Check if we're on a physical device
      if (!Device.isDevice) {
        logger.warn(tag, 'Push notifications only work on physical devices');
        return;
      }

      // Set up notification channel for Android
      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('default', {
          name: 'default',
          importance: Notifications.AndroidImportance.MAX,
          vibrationPattern: [0, 250, 250, 250],
          lightColor: '#FF231F7C',
        });
      }

      // Get push token
      const token = await this.registerForPushNotifications();
      
      if (token) {
        this.expoPushToken = token;
        logger.info(tag, 'Push notifications initialized successfully');
        
        // Save token to backend
        await this.savePushTokenToBackend(token);
      }

    } catch (error: any) {
      logger.error(tag, 'Failed to initialize push notifications', { error: error.message });
    }
  }

  /**
   * Register for push notification permissions and get Expo push token
   */
  private async registerForPushNotifications(): Promise<string | null> {
    const tag = 'PushNotificationService:registerForPushNotifications';
    
    try {
      // Check existing permissions
      const { status: existingStatus } = await Notifications.getPermissionsAsync();
      let finalStatus = existingStatus;

      // Request permissions if not already granted
      if (existingStatus !== 'granted') {
        logger.info(tag, 'Requesting push notification permissions...');
        const { status } = await Notifications.requestPermissionsAsync();
        finalStatus = status;
      }

      if (finalStatus !== 'granted') {
        logger.warn(tag, 'Push notification permissions not granted');
        return null;
      }

      // Get Expo push token
      const token = await Notifications.getExpoPushTokenAsync({
        projectId: Constants.expoConfig?.extra?.eas?.projectId,
      });

      logger.info(tag, 'Expo push token obtained successfully');
      return token.data;

    } catch (error: any) {
      logger.error(tag, 'Failed to register for push notifications', { error: error.message });
      return null;
    }
  }

  /**
   * Save push token to backend
   */
  private async savePushTokenToBackend(token: string): Promise<void> {
    const tag = 'PushNotificationService:savePushTokenToBackend';

    try {
      logger.info(tag, 'Saving push token to backend...');

      // Get merchant ID from token service
      const tokenService = (await import('./tokenService')).default;
      const tokenInfo = await tokenService.getTokenInfo();
      const merchantId = tokenInfo.merchantId;

      if (!merchantId) {
        logger.error(tag, 'No merchant ID available - cannot register push token');
        this.isRegistered = false;
        return;
      }

      logger.info(tag, 'Registering push token with merchant ID', {
        merchantId,
        tokenPreview: token.substring(0, 20) + '...',
        fullToken: token,
        endpoint: '/api/merchant/push-token'
      });

      const response = await apiClientInstance.post<PushTokenResponse>('/api/merchant/push-token', {
        merchantId: merchantId,
        expoPushToken: token,
        platform: Platform.OS,
        deviceInfo: {
          deviceName: Device.deviceName,
          osName: Device.osName,
          osVersion: Device.osVersion,
        }
      });

      if (response.data.success) {
        this.isRegistered = true;
        logger.info(tag, '✅ Push token saved to backend successfully', { merchantId });
      } else {
        this.isRegistered = false;
        logger.error(tag, '❌ Failed to save push token to backend', {
          merchantId,
          message: response.data.message,
          error: response.data.error,
          responseData: response.data
        });
      }

    } catch (error: any) {
      this.isRegistered = false;
      logger.error(tag, '❌ Error saving push token to backend', {
        error: error.message,
        status: error.response?.status,
        statusText: error.response?.statusText,
        responseData: error.response?.data
      });
    }
  }

  /**
   * Set up notification listeners
   */
  public setupNotificationListeners(): void {
    const tag = 'PushNotificationService:setupNotificationListeners';
    
    // Handle notification received while app is in foreground
    const notificationListener = Notifications.addNotificationReceivedListener(notification => {
      logger.info(tag, 'Notification received while app in foreground', {
        title: notification.request.content.title,
        body: notification.request.content.body,
        data: notification.request.content.data,
      });

      // Handle different notification types
      this.handleNotificationReceived(notification);
    });

    // Handle notification tapped/opened
    const responseListener = Notifications.addNotificationResponseReceivedListener(response => {
      logger.info(tag, 'Notification tapped/opened', {
        title: response.notification.request.content.title,
        data: response.notification.request.content.data,
      });

      // Handle notification tap
      this.handleNotificationTapped(response);
    });

    // Store listeners for cleanup
    this.notificationListener = notificationListener;
    this.responseListener = responseListener;
  }

  /**
   * Handle notification received while app is in foreground
   */
  private handleNotificationReceived(notification: Notifications.Notification): void {
    const tag = 'PushNotificationService:handleNotificationReceived';
    const notificationData = notification.request.content.data;

    // Handle catalog update notifications
    if (notificationData?.type === 'catalog_updated') {
      logger.info(tag, 'Catalog update notification received - triggering sync');
      
      // Add prominent notification that push notification was received
      import('../services/notificationService').then(({ default: NotificationService }) => {
        NotificationService.addNotification({
          type: 'webhook_catalog_update',
          title: '📱 Push Notification Received!',
          message: `Square sent push notification: ${notification.request.content.title || 'Catalog Updated'} | Triggering catch-up sync...`,
          priority: 'high',
          source: 'push'
        });
      });
      
      // Import and trigger catalog sync
      import('../database/catalogSync').then(({ CatalogSyncService }) => {
        const syncService = CatalogSyncService.getInstance();
        syncService.checkAndRunCatchUpSync().catch(error => {
          logger.error(tag, 'Failed to trigger sync from notification', { error });
          
          // Add error notification if sync fails
          import('../services/notificationService').then(({ default: NotificationService }) => {
            NotificationService.addNotification({
              type: 'sync_error',
              title: '❌ Push Sync Failed',
              message: `Failed to sync after push notification: ${error instanceof Error ? error.message : 'Unknown error'}`,
              priority: 'high',
              source: 'push'
            });
          });
        });
      });
    }
  }

  /**
   * Handle notification tapped/opened
   */
  private handleNotificationTapped(response: Notifications.NotificationResponse): void {
    const tag = 'PushNotificationService:handleNotificationTapped';
    const notificationData = response.notification.request.content.data;

    // Handle different notification types
    if (notificationData?.type === 'catalog_updated') {
      logger.info(tag, 'User tapped catalog update notification');
      
      // Add notification that user tapped the push notification
      import('../services/notificationService').then(({ default: NotificationService }) => {
        NotificationService.addNotification({
          type: 'general_info',
          title: '👆 Push Notification Tapped',
          message: `User opened app from push notification: ${response.notification.request.content.title || 'Catalog Updated'}`,
          priority: 'low',
          source: 'push'
        });
      });
    }
  }

  /**
   * Clean up notification listeners
   */
  public cleanup(): void {
    if (this.notificationListener) {
      Notifications.removeNotificationSubscription(this.notificationListener);
    }
    if (this.responseListener) {
      Notifications.removeNotificationSubscription(this.responseListener);
    }
  }

  /**
   * Get current push token
   */
  public getPushToken(): string | null {
    return this.expoPushToken;
  }

  /**
   * Check if push notifications are registered
   */
  public isRegisteredForPushNotifications(): boolean {
    return this.isRegistered;
  }

  /**
   * Get detailed push notification status for debugging
   */
  public async getDetailedStatus(): Promise<{ hasToken: boolean; isRegistered: boolean; token?: string; merchantId?: string }> {
    try {
      const tokenService = (await import('./tokenService')).default;
      const tokenInfo = await tokenService.getTokenInfo();

      return {
        hasToken: !!this.expoPushToken,
        isRegistered: this.isRegistered,
        token: this.expoPushToken || undefined,
        merchantId: tokenInfo.merchantId || undefined
      };
    } catch (error) {
      return {
        hasToken: !!this.expoPushToken,
        isRegistered: this.isRegistered,
        token: this.expoPushToken || undefined,
        merchantId: 'ERROR_GETTING_MERCHANT_ID'
      };
    }
  }

  // Private properties to store listeners
  private notificationListener: Notifications.Subscription | null = null;
  private responseListener: Notifications.Subscription | null = null;
}

export default PushNotificationService; 