import { useEffect, useCallback, useState } from 'react';
import { generateClient } from 'aws-amplify/api';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { fetchUserAttributes } from 'aws-amplify/auth';
import { useCatalogItems } from './useCatalogItems';
import catalogSyncService from '../database/catalogSync';
import NotificationService from '../services/notificationService';
import logger from '../utils/logger';
import appSyncMonitor from '../services/appSyncMonitor';

// GraphQL subscription for catalog updates - updated to match new schema
const CATALOG_UPDATE_SUBSCRIPTION = `
  subscription OnCatalogUpdate($owner: String!) {
    onCatalogUpdate(owner: $owner) {
      id
      eventType
      eventId
      merchantId
      timestamp
      processed
      owner
      data
    }
  }
`;

interface CatalogUpdateEvent {
  id: string;
  eventType: string;
  eventId: string;
  merchantId: string;
  timestamp: string;
  processed: boolean;
  owner: string;
  data?: any;
}

/**
 * Hook for subscribing to real-time catalog updates via AppSync
 * This integrates with the webhook system using dual authentication (Cognito + IAM)
 */
export const useCatalogSubscription = () => {
  const { user } = useAuthenticator();
  const { refreshProducts } = useCatalogItems();
  const client = generateClient();
  const [merchantId, setMerchantId] = useState<string | null>(null);
  const [reconnectAttempts, setReconnectAttempts] = useState(0);
  const [lastRequestTime, setLastRequestTime] = useState(0);

  const handleCatalogUpdate = useCallback(async (event: CatalogUpdateEvent) => {
    logger.info('CatalogSubscription', `Received catalog update: ${event.eventType}`, { 
      eventId: event.eventId,
      merchantId: event.merchantId,
      timestamp: event.timestamp,
      processed: event.processed
    });

    // Handle different Square webhook event types
    switch (event.eventType) {
      // Inventory events
      case 'inventory.count.updated':
        logger.info('CatalogSubscription', 'Inventory count updated, refreshing products');
        await refreshProducts();
        break;
      
      // Catalog events
      case 'catalog.version.updated':
        logger.info('CatalogSubscription', 'Catalog version updated, triggering webhook sync');
        
        // Create PROMINENT notification that webhook was received from Square
        NotificationService.addNotification({
          type: 'webhook_catalog_update',
          title: '🔔 Square Webhook Received!',
          message: `Webhook event: ${event.eventType} | Event ID: ${event.eventId.substring(0, 8)}... | Processing catalog changes...`,
          priority: 'high',
          source: 'webhook'
        });
        
        // Extract the updated_at timestamp from the webhook data
        let webhookTimestamp: string | null = null;
        if (event.data?.object?.catalog_version?.updated_at) {
          webhookTimestamp = event.data.object.catalog_version.updated_at;
        } else if (event.timestamp) {
          webhookTimestamp = event.timestamp;
        }
        
        if (webhookTimestamp) {
          // Trigger the proper webhook sync method that handles notifications
          try {
            await catalogSyncService.runIncrementalSyncFromTimestamp(webhookTimestamp);
            
            // Add success notification for webhook processing
            NotificationService.addNotification({
              type: 'sync_complete',
              title: '✅ Webhook Sync Complete',
              message: `Successfully processed Square webhook ${event.eventId.substring(0, 8)}... | Catalog updated with latest changes`,
              priority: 'normal',
              source: 'webhook'
            });
          } catch (error) {
            logger.error('CatalogSubscription', 'Webhook sync failed', { error });
            NotificationService.addNotification({
              type: 'sync_error',
              title: '❌ Webhook Sync Failed',
              message: `Failed to process webhook ${event.eventId.substring(0, 8)}...: ${error instanceof Error ? error.message : 'Unknown error'}`,
              priority: 'high',
              source: 'webhook'
            });
          }
        } else {
          logger.warn('CatalogSubscription', 'No timestamp found in webhook data, falling back to product refresh');
          
          // Add notification for fallback behavior
          NotificationService.addNotification({
            type: 'webhook_catalog_update',
            title: '⚠️ Webhook Data Issue',
            message: `Webhook ${event.eventId.substring(0, 8)}... missing timestamp - using fallback refresh`,
            priority: 'normal',
            source: 'webhook'
          });
          
        await refreshProducts();
        }
        break;
      
      // Item events
      case 'catalog.item.created':
      case 'catalog.item.updated':
      case 'catalog.item.deleted':
        logger.info('CatalogSubscription', `Item ${event.eventType.split('.').pop()}, refreshing products`);
        
        NotificationService.addNotification({
          type: 'webhook_catalog_update',
          title: 'Square Item Update',
          message: `Item ${event.eventType.split('.').pop()} - refreshing catalog`,
          priority: 'low',
          source: 'webhook'
        });
        
        await refreshProducts();
        break;
      
      // Category events
      case 'catalog.category.created':
      case 'catalog.category.updated':
      case 'catalog.category.deleted':
        logger.info('CatalogSubscription', `Category ${event.eventType.split('.').pop()}, refreshing products`);
        
        NotificationService.addNotification({
          type: 'webhook_catalog_update',
          title: 'Square Category Update',
          message: `Category ${event.eventType.split('.').pop()} - refreshing catalog`,
          priority: 'low',
          source: 'webhook'
        });
        
        await refreshProducts();
        break;
      
      // Variation events
      case 'catalog.item_variation.created':
      case 'catalog.item_variation.updated':
      case 'catalog.item_variation.deleted':
        logger.info('CatalogSubscription', `Item variation ${event.eventType.split('.').pop()}, refreshing products`);
        
        NotificationService.addNotification({
          type: 'webhook_catalog_update',
          title: 'Square Variation Update',
          message: `Item variation ${event.eventType.split('.').pop()} - refreshing catalog`,
          priority: 'low',
          source: 'webhook'
        });
        
        await refreshProducts();
        break;
      
      default:
        logger.debug('CatalogSubscription', `Unhandled catalog update event: ${event.eventType}`, {
          availableData: event.data ? Object.keys(event.data) : 'no data'
        });
    }
  }, [refreshProducts]);

  // Fetch merchant ID from user attributes
  useEffect(() => {
    const getMerchantId = async () => {
      if (!user?.signInDetails?.loginId) {
        setMerchantId(null);
        return;
      }
      
      try {
        // Try to get merchant ID from user attributes first
        const attributes = await fetchUserAttributes();
        const customMerchantId = attributes['custom:merchantId'];
        
        if (customMerchantId) {
          setMerchantId(customMerchantId);
          return;
        }
        
        // Fallback: use email as merchant identifier
        const email = user.signInDetails.loginId;
        setMerchantId(email);
        
        logger.debug('CatalogSubscription', 'Using email as merchant ID', { email });
      } catch (error) {
        logger.error('CatalogSubscription', 'Failed to fetch user attributes', { error });
        // Fallback to email if attribute fetch fails
        const email = user.signInDetails.loginId;
        setMerchantId(email);
      }
    };

    getMerchantId();
  }, [user]);

  useEffect(() => {
    if (!merchantId) {
      logger.debug('CatalogSubscription', 'Merchant ID not available, skipping AppSync catch-up listener');
      return;
    }

    logger.debug('CatalogSubscription', 'Setting up AppSync catch-up listener', { merchantId });

    // Set up AppSync subscription using the correct API
    let subscription: any;
    
    const setupSubscription = async () => {
      try {
        // 🚨 EMERGENCY FIX: Disable catalog subscription to prevent performance issues
        logger.warn('CatalogSubscription', '🚨 EMERGENCY FIX: Disabling catalog subscription to prevent performance issues');
        return;

        // Monitor AppSync request
        await appSyncMonitor.beforeRequest('onCatalogUpdate', 'useCatalogSubscription', { owner: merchantId });

        const sub = client.graphql({
          query: CATALOG_UPDATE_SUBSCRIPTION,
          variables: { owner: merchantId }
        });

        // Handle subscription response
        if ('subscribe' in sub) {
          subscription = (sub as any).subscribe({
            next: (data: any) => {
              if (data?.data?.onCatalogUpdate) {
                logger.info('CatalogSubscription', 'Received catch-up signal from AppSync', {
                  data: data.data.onCatalogUpdate
                });

                // Show notification only when we actually receive catch-up data
                NotificationService.addNotification({
                  type: 'general_info',
                  title: '🔄 Catch-up Sync Triggered',
                  message: 'Syncing missed changes while offline...',
                  priority: 'low',
                  source: 'internal'
                });

                handleCatalogUpdate(data.data.onCatalogUpdate);
              }
            },
            error: (error: any) => {
              logger.debug('CatalogSubscription', 'AppSync subscription error (background reconnection)', {
                error: error.message || error,
                merchantId,
                reconnectAttempts
              });

              // Exponential backoff with max attempts to prevent infinite loops
              setReconnectAttempts(prev => {
                const newAttempts = prev + 1;
                if (newAttempts < 3) {
                  const delay = Math.min(30000 * Math.pow(2, newAttempts), 300000); // Max 5 minutes
                  logger.debug('CatalogSubscription', `Reconnecting in ${delay}ms (attempt ${newAttempts}/3)`);
                  setTimeout(() => {
                    setupSubscription();
                  }, delay);
                } else {
                  logger.warn('CatalogSubscription', 'Max reconnection attempts reached, stopping reconnections');
                }
                return newAttempts;
              });
            }
          });
          
          logger.debug('CatalogSubscription', 'AppSync subscription established (background catch-up listener)');

          // No notifications - this is just a silent background listener for catch-up metadata
          // The real webhook flow is Lambda → Push Notifications → Direct Square API sync
        } else {
          // Handle as promise if not subscribable
          const result = await sub;
          logger.debug('CatalogSubscription', 'Received catalog update result', { result });
        }
      } catch (error) {
        logger.error('CatalogSubscription', 'Failed to set up catalog subscription', { 
          error: error instanceof Error ? error.message : String(error),
          merchantId 
        });
      }
    };

    setupSubscription();

    // Cleanup subscription
    return () => {
      logger.info('CatalogSubscription', 'Cleaning up catalog subscription', { merchantId });
      if (subscription && typeof subscription.unsubscribe === 'function') {
        subscription.unsubscribe();
      }
    };
  }, [merchantId, client, handleCatalogUpdate]);

  return {
    merchantId
  };
}; 