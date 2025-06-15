import { useEffect, useCallback } from 'react';
import * as Notifications from 'expo-notifications';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { CatalogSyncService } from '../database/catalogSync';
import { useCatalogSubscription } from './useCatalogSubscription';
import logger from '../utils/logger';

/**
 * Comprehensive webhook notification handler
 * Integrates real-time AppSync subscriptions with push notifications
 * for robust catalog update handling
 */
export const useWebhooks = () => {
  const { user } = useAuthenticator();
  const { isSubscribed, merchantId } = useCatalogSubscription();

  // Handle push notifications when app is backgrounded or foreground
  const handlePushNotification = useCallback(async (notification: Notifications.Notification) => {
    const notificationData = notification.request.content.data as { 
      type?: string; 
      eventType?: string;
      merchantId?: string;
      [key: string]: any 
    } | undefined;

    logger.info('WebhookHandler', 'Processing push notification', { 
      type: notificationData?.type,
      eventType: notificationData?.eventType,
      merchantId: notificationData?.merchantId
    });

    // Handle both old and new notification formats
    if (notificationData?.type === 'catalog_updated' || 
        notificationData?.type === 'catalog_update' ||
        notificationData?.eventType?.startsWith('catalog.') ||
        notificationData?.eventType?.startsWith('inventory.')) {
      
      logger.info('WebhookHandler', 'Catalog update notification detected, triggering sync');
      
      try {
        const syncService = CatalogSyncService.getInstance();
        await syncService.runIncrementalSync();
        logger.info('WebhookHandler', 'Push notification sync completed successfully');
      } catch (syncError: any) {
        logger.error('WebhookHandler', 'Error during push notification sync', { 
          error: syncError.message,
          details: syncError 
        });
      }
    } else {
      logger.debug('WebhookHandler', 'Non-catalog notification received', { 
        type: notificationData?.type,
        eventType: notificationData?.eventType
      });
    }
  }, []);

  // Set up push notification listeners
  useEffect(() => {
    if (!user?.signInDetails?.loginId) {
      logger.debug('WebhookHandler', 'User not authenticated, skipping notification setup');
      return;
    }

    logger.info('WebhookHandler', 'Setting up webhook notification handlers', { 
      isSubscribed,
      merchantId 
    });

    // Foreground notification listener
    const foregroundSubscription = Notifications.addNotificationReceivedListener(handlePushNotification);

    // Background notification listener (handled by TaskManager in _layout.tsx)
    // This is for when user taps on notification
    const responseSubscription = Notifications.addNotificationResponseReceivedListener(response => {
      logger.info('WebhookHandler', 'User tapped on notification', { 
        data: response.notification.request.content.data 
      });
      handlePushNotification(response.notification);
    });

    return () => {
      logger.info('WebhookHandler', 'Cleaning up webhook notification handlers');
      foregroundSubscription.remove();
      responseSubscription.remove();
    };
  }, [user, isSubscribed, merchantId, handlePushNotification]);

  return {
    isWebhookActive: isSubscribed,
    merchantId,
    handlePushNotification
  };
}; 