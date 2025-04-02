import { Platform } from 'react-native';
import Constants from 'expo-constants';

// Production API URL - always use production
const API_BASE_URL = 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production';

// Configure only production settings
const config = {
  app: {
    name: 'JoyLabs',
    version: Constants.expoConfig?.version || '1.0.0',
    isDevMode: false, // Always false for production
  },
  api: {
    baseUrl: API_BASE_URL,
    timeout: 30000, // 30 seconds
  },
  square: {
    // Square App ID - always use production ID
    appId: 'sq0idp-WFTYv3An7NPv6ovGFLld1Q',
    // Square OAuth endpoints
    endpoints: {
      // Connection endpoints
      connect: `${API_BASE_URL}/api/auth/connect/url`,
      callback: Platform.OS === 'ios'
        ? 'joylabs://square-callback'
        : `${API_BASE_URL}/api/auth/square/callback`,
      token: 'https://connect.squareup.com/oauth2/token',
      registerState: `${API_BASE_URL}/api/auth/register-state`,
      storeVerifier: `${API_BASE_URL}/api/auth/store-verifier`,
      retrieveVerifier: `${API_BASE_URL}/api/auth/retrieve-verifier`,
      
      // Square Catalog API endpoints
      catalogItems: `${API_BASE_URL}/v2/catalog/list`,
      catalogItem: `${API_BASE_URL}/v2/catalog/item`,
      catalogSearch: `${API_BASE_URL}/v2/catalog/search`,
      catalogCategories: `${API_BASE_URL}/v2/catalog/categories`,
      catalogList: `${API_BASE_URL}/v2/catalog/list`,
      catalogListCategories: `${API_BASE_URL}/v2/catalog/list-categories`,
      
      // Webhook endpoints
      webhooks: `${API_BASE_URL}/api/webhooks/square`,
    },
  },
  logging: {
    level: 'warn',
    enableRemote: true, // Always enable remote logging for production
  },
};

export default config; 