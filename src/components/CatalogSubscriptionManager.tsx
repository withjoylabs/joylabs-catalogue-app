import React from 'react';
import { useCatalogSubscription } from '../hooks/useCatalogSubscription';

/**
 * Component that manages catalog subscriptions within the authentication context
 * This component must be rendered inside Authenticator.Provider
 */
export const CatalogSubscriptionManager: React.FC = () => {
  // This hook uses useAuthenticator, so it must be called within Authenticator.Provider
  const { isSubscribed } = useCatalogSubscription();
  
  // This component doesn't render anything visible - it just manages the subscription
  return null;
}; 