import React from 'react';
import { useCatalogSubscription } from '../hooks/useCatalogSubscription';

/**
 * Component that manages background AppSync subscription for catch-up signals.
 * Listens for metadata signals when users return from offline to trigger catch-up sync.
 * This component must be rendered inside Authenticator.Provider.
 *
 * Note: Real webhooks flow through Lambda → Push Notifications → Direct Square API.
 * This AppSync subscription is just for catch-up metadata, not primary webhook data.
 */
export const CatalogSubscriptionManager: React.FC = () => {
  // This hook uses useAuthenticator, so it must be called within Authenticator.Provider
  // It establishes a silent background listener for catch-up signals
  useCatalogSubscription();

  // This component doesn't render anything visible - it just manages the background subscription
  return null;
};