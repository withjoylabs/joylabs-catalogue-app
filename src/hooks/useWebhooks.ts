import { useEffect, useCallback } from 'react';
import { useCatalogItems } from './useCatalogItems';
import api from '../api';
import { WebhookData } from '../types/api';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useApi } from '../providers/ApiProvider';
import logger from '../utils/logger';

/**
 * Hook for managing and responding to Square webhooks.
 * This hook will check for new webhooks and trigger appropriate actions.
 */
export const useWebhooks = () => {
  const { refreshProducts } = useCatalogItems();
  const { isConnected: isSquareConnected } = useApi();
  
  const checkForWebhooks = useCallback(async () => {
    // Skip webhook check if not connected to Square
    if (!isSquareConnected) {
      logger.debug('Webhooks', 'Skipping webhook check - not connected to Square');
      return;
    }
    
    try {
      // Check if we have a merchant ID stored
      const merchantId = await AsyncStorage.getItem('square_merchant_id');
      if (!merchantId) {
        logger.debug('Webhooks', 'No merchant ID found, skipping webhook check');
        return;
      }
      
      // Get most recent webhook timestamp
      const lastWebhookTimestamp = await AsyncStorage.getItem('last_webhook_timestamp') || '0';
      
      logger.debug('Webhooks', 'Checking for webhooks', { since: lastWebhookTimestamp });
      
      // Fetch any new webhooks since the last one we processed
      const response = await api.webhooks.getWebhooks(parseInt(lastWebhookTimestamp, 10));
      
      if (!response.success || !response.data) {
        logger.error('Webhooks', 'Failed to fetch webhooks', { error: response.error });
        return;
      }
      
      // Process webhooks
      const webhooks = response.data;
      if (webhooks.length === 0) {
        logger.debug('Webhooks', 'No new webhooks found');
        return;
      }
      
      // Update the timestamp with the most recent webhook time
      const latestTimestamp = Math.max(...webhooks.map((webhook: WebhookData) => webhook.created_at));
      await AsyncStorage.setItem('last_webhook_timestamp', latestTimestamp.toString());
      
      logger.info('Webhooks', `Processing ${webhooks.length} webhooks`);
      
      // Process each webhook
      for (const webhook of webhooks) {
        await processWebhook(webhook);
      }
    } catch (error) {
      logger.error('Webhooks', 'Error processing webhooks', { error });
    }
  }, [refreshProducts, isSquareConnected]);
  
  const processWebhook = useCallback(async (webhook: WebhookData) => {
    // Determine the webhook type and take appropriate action
    const eventType = webhook.event_type;
    
    logger.info('Webhooks', `Processing webhook event: ${eventType}`, { webhookId: webhook.id });
    
    // Handle different event types
    switch (eventType) {
      case 'inventory.count.updated':
      case 'catalog.version.updated':
      case 'item.created':
      case 'item.updated':
      case 'item.deleted':
      case 'category.created':
      case 'category.updated':
      case 'category.deleted':
        // Refresh products for any catalog-related changes
        await refreshProducts();
        break;
      
      default:
        logger.debug('Webhooks', `Unhandled webhook event type: ${eventType}`);
    }
  }, [refreshProducts]);
  
  // Set up polling to check for webhooks - only if connected to Square
  useEffect(() => {
    // Only set up polling if connected to Square
    if (!isSquareConnected) {
      logger.debug('Webhooks', 'Webhook polling disabled - not connected to Square');
      return;
    }
    
    logger.info('Webhooks', 'Setting up webhook polling');
    
    // Check for webhooks immediately on mount
    checkForWebhooks();
    
    // Set up an interval to check for webhooks
    const intervalId = setInterval(checkForWebhooks, 60000); // Check every minute
    
    return () => {
      clearInterval(intervalId);
      logger.debug('Webhooks', 'Webhook polling stopped');
    };
  }, [checkForWebhooks, isSquareConnected]);
  
  return {
    checkForWebhooks
  };
}; 