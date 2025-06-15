import { useEffect, useCallback, useState } from 'react';
import { generateClient } from 'aws-amplify/api';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import { fetchUserAttributes } from 'aws-amplify/auth';
import { useCatalogItems } from './useCatalogItems';
import logger from '../utils/logger';

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
        logger.info('CatalogSubscription', 'Catalog version updated, full refresh needed');
        await refreshProducts();
        break;
      
      // Item events
      case 'catalog.item.created':
      case 'catalog.item.updated':
      case 'catalog.item.deleted':
        logger.info('CatalogSubscription', `Item ${event.eventType.split('.').pop()}, refreshing products`);
        await refreshProducts();
        break;
      
      // Category events
      case 'catalog.category.created':
      case 'catalog.category.updated':
      case 'catalog.category.deleted':
        logger.info('CatalogSubscription', `Category ${event.eventType.split('.').pop()}, refreshing products`);
        await refreshProducts();
        break;
      
      // Variation events
      case 'catalog.item_variation.created':
      case 'catalog.item_variation.updated':
      case 'catalog.item_variation.deleted':
        logger.info('CatalogSubscription', `Item variation ${event.eventType.split('.').pop()}, refreshing products`);
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
      logger.debug('CatalogSubscription', 'Merchant ID not available, skipping catalog subscription');
      return;
    }

    logger.info('CatalogSubscription', 'Setting up catalog update subscription', { merchantId });

    // Set up AppSync subscription using the correct API
    let subscription: any;
    
    const setupSubscription = async () => {
      try {
        const sub = client.graphql({
          query: CATALOG_UPDATE_SUBSCRIPTION,
          variables: { owner: merchantId }
        });

        // Handle subscription response
        if ('subscribe' in sub) {
          subscription = (sub as any).subscribe({
            next: (data: any) => {
              if (data?.data?.onCatalogUpdate) {
                handleCatalogUpdate(data.data.onCatalogUpdate);
              }
            },
            error: (error: any) => {
              logger.error('CatalogSubscription', 'Catalog subscription error', { 
                error: error.message || error,
                merchantId 
              });
              
              // Attempt to reconnect after a delay
              setTimeout(() => {
                logger.info('CatalogSubscription', 'Attempting to reconnect catalog subscription');
                setupSubscription();
              }, 5000);
            }
          });
          
          logger.info('CatalogSubscription', 'Catalog subscription established successfully');
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
    isSubscribed: !!merchantId,
    merchantId
  };
}; 