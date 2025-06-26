import { useEffect, useCallback, useState } from 'react';
import * as Notifications from 'expo-notifications';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { CatalogSyncService } from '../database/catalogSync';
import { fetchUserAttributes } from 'aws-amplify/auth';
import logger from '../utils/logger';

/**
 * Comprehensive webhook notification handler
 * Integrates real-time AppSync subscriptions with push notifications
 * for robust catalog update handling
 */
export const useWebhooks = () => {
  const { user } = useAuthenticator();
  const [merchantId, setMerchantId] = useState<string | null>(null);

  // Get merchant ID from user attributes (same logic as useCatalogSubscription)
  useEffect(() => {
    const getMerchantId = async () => {
      if (!user) {
        setMerchantId(null);
        return;
      }

      try {
        const attributes = await fetchUserAttributes();
        const merchantIdFromAttributes = attributes['custom:square_merchant_id'];

        if (merchantIdFromAttributes) {
          setMerchantId(merchantIdFromAttributes);
          logger.debug('useWebhooks', 'Merchant ID retrieved from user attributes', { merchantId: merchantIdFromAttributes });
        } else {
          logger.warn('useWebhooks', 'No merchant ID found in user attributes');
          setMerchantId(null);
        }
      } catch (error) {
        logger.error('useWebhooks', 'Failed to fetch user attributes for merchant ID', { error });
        setMerchantId(null);
      }
    };

    getMerchantId();
  }, [user]);

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

  // Note: Push notification listeners are now handled centrally in _layout.tsx
  // to avoid conflicts and ensure proper notification handling.
  // This hook now only provides webhook status and utility functions.

  return {
    isWebhookActive: !!merchantId, // Active if we have a merchant ID
    merchantId,
    handlePushNotification
  };
}; 