import Constants from 'expo-constants';
import { Platform } from 'react-native';

// Define config interface
interface Config {
  api: {
    baseUrl: string;
    timeout: number;
    retryCount: number;
  };
  square: {
    appId: string;
    endpoints: {
      callback: string;
      token: string;
      registerState: string;
      storeVerifier: string;
      retrieveVerifier: string;
    };
  };
  app: {
    name: string;
    version: string;
  };
}

// Get the release channel from expo-constants
const getEnvironment = () => {
  // Try to get release channel safely from Constants
  let releaseChannel;
  try {
    // Try multiple ways to access releaseChannel for backward compatibility
    releaseChannel = 
      // @ts-ignore - Accessing releaseChannel which may exist at runtime
      Constants.expoConfig?.extra?.releaseChannel || 
      // @ts-ignore - For older Expo SDK versions
      Constants.manifest?.releaseChannel ||
      // @ts-ignore - For newer Expo SDK versions
      Constants.manifest2?.extra?.expoClient?.releaseChannel;
  } catch (e) {
    console.warn('Error accessing releaseChannel:', e);
  }
  
  // Default to development if not found
  releaseChannel = releaseChannel || 'development';
  
  if (releaseChannel === 'prod' || releaseChannel === 'production') {
    return 'production';
  } else if (releaseChannel === 'staging') {
    return 'staging';
  } else {
    return 'development';
  }
};

// Set config based on environment
const env = getEnvironment();
console.log(`App running in ${env} environment`);

// Define configuration
const config: Config = {
  api: {
    // Production AWS Lambda URL (critical for OAuth flow)
    baseUrl: 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production',
    timeout: 30000, // 30 seconds
    retryCount: 3
  },
  square: {
    // Square application ID
    appId: 'sq0idp-WFTYv3An7NPv6ovGFLld1Q',
    endpoints: {
      // Use joylabs://square-callback for both platforms with AuthSession
      callback: 'joylabs://square-callback',
      token: 'https://connect.squareup.com/oauth2/token',
      registerState: 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/register-state',
      storeVerifier: 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/store-verifier',
      retrieveVerifier: 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/retrieve-verifier'
    }
  },
  app: {
    name: 'JoyLabs',
    version: Constants.expoConfig?.version || '1.0.0'
  }
};

export default config; 