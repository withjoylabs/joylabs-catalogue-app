import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import logger from '../utils/logger';
import config from '../config'; // Assuming config holds expoProjectId
import { apiClient } from '../api'; // Use named import
import { generateClient } from 'aws-amplify/api';
import * as mutations from '../graphql/mutations';
import AsyncStorage from '@react-native-async-storage/async-storage';
// Import the API client function placeholder we'll create next
// import { registerPushToken } from '../api'; 

const client = generateClient();

// Notification types
export type NotificationType = 
  | 'webhook_catalog_update' 
  | 'sync_complete' 
  | 'sync_error' 
  | 'sync_pending'
  | 'reorder_added'
  | 'auth_success'
  | 'general_info'
  | 'system_error';

export interface AppNotification {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  data?: Record<string, any>;
  timestamp: string;
  read: boolean;
  priority: 'low' | 'normal' | 'high';
  source: 'internal' | 'webhook' | 'appsync' | 'push';
}

export interface NotificationServiceState {
  notifications: AppNotification[];
  unreadCount: number;
  pushToken: string | null;
  isInitialized: boolean;
}

class NotificationService {
  private static instance: NotificationService;
  private state: NotificationServiceState = {
    notifications: [],
    unreadCount: 0,
    pushToken: null,
    isInitialized: false
  };
  
  private listeners: Set<(state: NotificationServiceState) => void> = new Set();
  private readonly STORAGE_KEY = '@joylabs_notifications';
  private readonly MAX_NOTIFICATIONS = 100; // Keep only last 100 notifications

  public static getInstance(): NotificationService {
    if (!NotificationService.instance) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  /**
   * Initialize the notification service
   */
  public async initialize(): Promise<void> {
    const tag = 'NotificationService:initialize';
    logger.info(tag, 'Initializing notification service...');

    try {
      // Configure notification behavior
      await this.configureNotifications();
      
      // Note: Push notification registration is handled by PushNotificationService
      // to avoid conflicts and ensure proper backend integration
      
      // Load persisted notifications
      await this.loadPersistedNotifications();
      
      // Set up notification listeners
      this.setupNotificationListeners();
      
      this.state.isInitialized = true;
      this.notifyListeners();
      
      logger.info(tag, 'Notification service initialized successfully');
    } catch (error) {
      logger.error(tag, 'Failed to initialize notification service', { error });
      throw error;
    }
  }

  /**
   * Configure Expo notification behavior
   * Note: Notification handler is now configured centrally in _layout.tsx
   */
  private async configureNotifications(): Promise<void> {
    // Notification handler configuration moved to _layout.tsx to avoid conflicts
    logger.debug('NotificationService', 'Notification handler configured centrally in _layout.tsx');
  }

  /**
   * Register for push notifications and get token
   */
  private async registerForPushNotifications(): Promise<void> {
    const tag = 'NotificationService:registerForPushNotifications';
    
    try {
      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('default', {
          name: 'default',
          importance: Notifications.AndroidImportance.MAX,
          vibrationPattern: [0, 250, 250, 250],
          lightColor: '#FF231F7C',
        });
      }

  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;
      
  if (existingStatus !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }

  if (finalStatus !== 'granted') {
        logger.warn(tag, 'Push notification permission not granted');
        return;
      }

      const token = (await Notifications.getExpoPushTokenAsync()).data;
      this.state.pushToken = token;
      
      logger.info(tag, 'Push notification token obtained', { 
        token: token.substring(0, 20) + '...' 
      });

      // Store token in backend for webhook notifications
      await this.storePushTokenInBackend(token);
      
    } catch (error) {
      logger.error(tag, 'Failed to register for push notifications', { error });
    }
  }

  /**
   * Store push token in backend via AppSync
   */
  private async storePushTokenInBackend(token: string): Promise<void> {
    const tag = 'NotificationService:storePushTokenInBackend';
    
    try {
      // This would require adding a mutation to store push tokens
      // For now, we'll just log it
      logger.info(tag, 'Push token ready for backend storage', { 
        tokenPreview: token.substring(0, 20) + '...' 
      });
      
      // TODO: Implement AppSync mutation to store push token
      // await client.graphql({
      //   query: mutations.storePushToken,
      //   variables: { token }
      // });
      
    } catch (error) {
      logger.error(tag, 'Failed to store push token in backend', { error });
    }
  }

  /**
   * Set up notification event listeners
   */
  private setupNotificationListeners(): void {
    // Handle received notifications when app is in foreground
    Notifications.addNotificationReceivedListener(this.handleNotificationReceived.bind(this));
    
    // Handle notification responses (when user taps notification)
    Notifications.addNotificationResponseReceivedListener(this.handleNotificationResponse.bind(this));
  }

  /**
   * Handle received notification when app is in foreground
   */
  private handleNotificationReceived(notification: Notifications.Notification): void {
    const tag = 'NotificationService:handleNotificationReceived';
    logger.info(tag, 'Notification received in foreground', {
      title: notification.request.content.title,
      body: notification.request.content.body
    });

    // Convert to our internal notification format
    const appNotification: AppNotification = {
      id: notification.request.identifier,
      type: (notification.request.content.data?.type as NotificationType) || 'general_info',
      title: notification.request.content.title || 'Notification',
      message: notification.request.content.body || '',
      data: notification.request.content.data || {},
      timestamp: new Date().toISOString(),
      read: false,
      priority: 'normal',
      source: 'push'
    };

    this.addNotification(appNotification);
  }

  /**
   * Handle notification response (when user taps notification)
   */
  private handleNotificationResponse(response: Notifications.NotificationResponse): void {
    const tag = 'NotificationService:handleNotificationResponse';
    const notification = response.notification;
    
    logger.info(tag, 'Notification tapped', {
      title: notification.request.content.title,
      data: notification.request.content.data
    });

    // Mark as read and handle navigation based on type
    this.markAsRead(notification.request.identifier);
    
    // Handle navigation based on notification type
    const notificationType = notification.request.content.data?.type;
    if (notificationType === 'webhook_catalog_update') {
      // Could navigate to sync status or catalog
      logger.info(tag, 'Webhook notification tapped - could navigate to sync status');
    }
  }

  /**
   * Add a new notification
   */
  public addNotification(notification: Omit<AppNotification, 'id' | 'timestamp' | 'read'>): void {
    const fullNotification: AppNotification = {
      ...notification,
      id: `notif_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      timestamp: new Date().toISOString(),
      read: false
    };

    // Add to beginning of array (most recent first)
    this.state.notifications.unshift(fullNotification);
    
    // Limit total notifications
    if (this.state.notifications.length > this.MAX_NOTIFICATIONS) {
      this.state.notifications = this.state.notifications.slice(0, this.MAX_NOTIFICATIONS);
    }
    
    // Update unread count
    this.updateUnreadCount();
    
    // Persist and notify
    this.persistNotifications();
    this.notifyListeners();
    
    logger.info('NotificationService:addNotification', 'Notification added', {
      type: notification.type,
      title: notification.title,
      priority: notification.priority
    });
  }

  /**
   * Mark notification as read
   */
  public markAsRead(notificationId: string): void {
    const notification = this.state.notifications.find(n => n.id === notificationId);
    if (notification && !notification.read) {
      notification.read = true;
      this.updateUnreadCount();
      this.persistNotifications();
      this.notifyListeners();
    }
  }

  /**
   * Mark all notifications as read
   */
  public markAllAsRead(): void {
    let hasChanges = false;
    this.state.notifications.forEach(notification => {
      if (!notification.read) {
        notification.read = true;
        hasChanges = true;
      }
    });
    
    if (hasChanges) {
      this.updateUnreadCount();
      this.persistNotifications();
      this.notifyListeners();
    }
  }

  /**
   * Delete a notification
   */
  public deleteNotification(notificationId: string): void {
    const index = this.state.notifications.findIndex(n => n.id === notificationId);
    if (index !== -1) {
      this.state.notifications.splice(index, 1);
      this.updateUnreadCount();
      this.persistNotifications();
      this.notifyListeners();
    }
  }

  /**
   * Clear all notifications
   */
  public clearAllNotifications(): void {
    this.state.notifications = [];
    this.state.unreadCount = 0;
    this.persistNotifications();
    this.notifyListeners();
  }

  /**
   * Get current state
   */
  public getState(): NotificationServiceState {
    return { ...this.state };
  }

  /**
   * Subscribe to state changes
   */
  public subscribe(listener: (state: NotificationServiceState) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Send a local push notification
   */
  public async sendLocalNotification(
    title: string, 
    body: string, 
    data?: Record<string, any>
  ): Promise<void> {
    try {
      await Notifications.scheduleNotificationAsync({
        content: {
          title,
          body,
          data: data || {},
          sound: 'default',
        },
        trigger: null, // Send immediately
      });
    } catch (error) {
      logger.error('NotificationService:sendLocalNotification', 'Failed to send local notification', { error });
    }
  }

  // Settings management
  public async getNotificationSettings(): Promise<any> {
    try {
      const settings = await AsyncStorage.getItem('notification_settings');
      return settings ? JSON.parse(settings) : {
        webhookCatalogUpdate: true,
        syncComplete: true,
        syncError: true,
        syncPending: true,
        reorderAdded: true,
        authSuccess: false,
        generalInfo: true,
        systemError: true,
        pushNotifications: true,
      };
    } catch (error) {
      logger.error('NotificationService', 'Failed to get notification settings', { error });
      return {
        webhookCatalogUpdate: true,
        syncComplete: true,
        syncError: true,
        syncPending: true,
        reorderAdded: true,
        authSuccess: false,
        generalInfo: true,
        systemError: true,
        pushNotifications: true,
      };
    }
  }

  public async updateNotificationSettings(settings: any): Promise<void> {
    try {
      await AsyncStorage.setItem('notification_settings', JSON.stringify(settings));
      logger.info('NotificationService', 'Notification settings updated', { settings });
    } catch (error) {
      logger.error('NotificationService', 'Failed to update notification settings', { error });
      throw error;
    }
  }

  // Convenience methods for common notification types
  
  public notifyWebhookUpdate(itemCount: number): void {
    this.addNotification({
      type: 'webhook_catalog_update',
      title: 'Catalog Updated',
      message: `${itemCount} items updated from Square`,
      priority: 'normal',
      source: 'webhook'
    });
  }

  public notifySyncComplete(itemCount: number, duration: number): void {
    this.addNotification({
      type: 'sync_complete',
      title: 'Sync Complete',
      message: `Synced ${itemCount} items in ${duration}ms`,
      priority: 'low',
      source: 'internal'
    });
  }

  public notifySyncError(error: string): void {
    this.addNotification({
      type: 'sync_error',
      title: 'Sync Failed',
      message: error,
      priority: 'high',
      source: 'internal'
    });
  }

  public notifySyncPending(itemCount: number): void {
    this.addNotification({
      type: 'sync_pending',
      title: 'Sync Pending',
      message: `${itemCount} items waiting to sync (no internet connection)`,
      priority: 'normal',
      source: 'internal'
    });
  }

  public notifyReorderAdded(itemName: string): void {
    this.addNotification({
      type: 'reorder_added',
      title: 'Added to Reorder',
      message: `"${itemName}" added to reorder list`,
      priority: 'low',
      source: 'internal'
    });
  }

  /**
   * Private helper methods
   */
  
  private updateUnreadCount(): void {
    this.state.unreadCount = this.state.notifications.filter(n => !n.read).length;
  }

  private notifyListeners(): void {
    this.listeners.forEach(listener => {
      try {
        listener({ ...this.state });
      } catch (error) {
        logger.error('NotificationService:notifyListeners', 'Error in listener', { error });
      }
    });
  }

  private async persistNotifications(): Promise<void> {
    try {
      await AsyncStorage.setItem(this.STORAGE_KEY, JSON.stringify(this.state.notifications));
    } catch (error) {
      logger.error('NotificationService:persistNotifications', 'Failed to persist notifications', { error });
    }
  }

  private async loadPersistedNotifications(): Promise<void> {
    try {
      const stored = await AsyncStorage.getItem(this.STORAGE_KEY);
      if (stored) {
        this.state.notifications = JSON.parse(stored);
        this.updateUnreadCount();
      }
    } catch (error) {
      logger.error('NotificationService:loadPersistedNotifications', 'Failed to load notifications', { error });
    }
  }
}

export default NotificationService.getInstance(); 