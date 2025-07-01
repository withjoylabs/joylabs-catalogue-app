import { useEffect, useState, useRef } from 'react';
import { Linking } from 'react-native';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import * as ExpoLinking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import config from '../config';
import { useAppStore } from '../store';
import logger from '../utils/logger';
import Constants from 'expo-constants';
import tokenService, { TOKEN_KEYS } from '../services/tokenService';
import api from '../api';

// Initialize WebBrowser
WebBrowser.maybeCompleteAuthSession();

// Extend global for debugging flags
declare global {
  interface Window {
    _squareAuthLoggedDeepLink?: boolean;
    _squareAuthLoggedSetup?: boolean;
    _squareAuthLoggedMount?: boolean;
  }
}

// Constants for secure storage keys
// DEPRECATED: Use TOKEN_KEYS from tokenService instead
const SQUARE_CODE_VERIFIER_KEY = 'square_code_verifier';
const SQUARE_STATE_KEY = 'square_state';
const SQUARE_ACCESS_TOKEN_KEY = TOKEN_KEYS.ACCESS_TOKEN;
const SQUARE_REFRESH_TOKEN_KEY = TOKEN_KEYS.REFRESH_TOKEN;
const MERCHANT_ID_KEY = TOKEN_KEYS.MERCHANT_ID;
const BUSINESS_NAME_KEY = TOKEN_KEYS.BUSINESS_NAME;

// Base64URL encode utility
const base64URLEncode = (buffer: Uint8Array): string => {
  try {
    return btoa(String.fromCharCode(...Array.from(buffer)))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  } catch (err) {
    logger.error('SquareAuth', 'Error encoding base64URL', err);
    throw new Error('Failed to encode base64URL');
  }
};

// Convert string to Uint8Array
const stringToUint8Array = (str: string): Uint8Array => {
  const arr = new Uint8Array(str.length);
  for (let i = 0; i < str.length; i++) {
    arr[i] = str.charCodeAt(i);
  }
  return arr;
};

// Generate PKCE code verifier (random string)
const generateCodeVerifier = async (): Promise<string> => {
  try {
    logger.debug('SquareAuth', 'Generating code verifier');
    const bytes = await Crypto.getRandomBytesAsync(32);
    const verifier = base64URLEncode(bytes);
    logger.debug('SquareAuth', 'Generated code verifier', { length: verifier.length });
    return verifier;
  } catch (err) {
    logger.error('SquareAuth', 'Error generating code verifier', err);
    throw err;
  }
};

// Generate PKCE code challenge (SHA256 hash of verifier)
const generateCodeChallenge = async (verifier: string): Promise<string> => {
  try {
    logger.debug('SquareAuth', 'Generating code challenge');
    const verifierBytes = stringToUint8Array(verifier);
    const hash = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      verifier,
      { encoding: Crypto.CryptoEncoding.BASE64 }
    );
    logger.debug('SquareAuth', 'Generated code challenge');
    return hash
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  } catch (err) {
    logger.error('SquareAuth', 'Error generating code challenge', err);
    throw err;
  }
};

// Generate random state for CSRF protection
const generateState = async (): Promise<string> => {
  try {
    logger.debug('SquareAuth', 'Generating state parameter');
    const bytes = await Crypto.getRandomBytesAsync(16);
    const state = base64URLEncode(bytes);
    logger.debug('SquareAuth', 'Generated state parameter', { length: state.length });
    return state;
  } catch (err) {
    logger.error('SquareAuth', 'Error generating state', err);
    throw err;
  }
};

export interface UseSquareAuthResult {
  isConnected: boolean;
  isConnecting: boolean;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  error: Error | null;
  merchantId: string | null;
  businessName: string | null;
  testDeepLink: () => Promise<void>;
  forceResetConnectionState: () => Promise<{
    hasAccessToken: boolean;
    accessTokenLength?: number;
    hasRefreshToken?: boolean;
    hasMerchantId?: boolean;
    hasBusinessName?: boolean;
    error?: unknown;
  }>;
  testConnection: () => Promise<{success: boolean, data?: any, error?: string, tokenStatus?: any}>;
  testExactCallback: () => Promise<{success: boolean, hasAccessToken: boolean, accessTokenLength?: number, hasRefreshToken?: boolean, hasMerchantId?: boolean, hasBusinessName?: boolean, error?: string}>;
  processCallback: (url: string) => Promise<any>;
  hasValidToken: () => Promise<boolean>;
}

export const useSquareAuth = (): UseSquareAuthResult => {
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [merchantId, setMerchantId] = useState<string | null>(null);
  const [businessName, setBusinessName] = useState<string | null>(null);

  const { setSquareConnected } = useAppStore();

  // Use ref to store processCallback to avoid dependency issues
  const processCallbackRef = useRef<((url: string) => Promise<any>) | null>(null);

  // Moved processCallback earlier to resolve linter errors
  const processCallback = async (url: string): Promise<any> => {
    try {
      logger.info('SquareAuth', '🔄 Processing callback URL', { url: url.substring(0, 30) + '...' });
      
      let cleanUrl = url;
      if (cleanUrl.includes('#')) {
        const fragmentIndex = cleanUrl.indexOf('#');
        cleanUrl = cleanUrl.substring(0, fragmentIndex);
        logger.debug('SquareAuth', `Removed URL fragment at position ${fragmentIndex}`);
      }
      
      const params: Record<string, string> = {};
      if (cleanUrl.includes('?')) {
        const queryStr = cleanUrl.split('?')[1];
        const pairs = queryStr.split('&');
        for (const pair of pairs) {
          if (pair.includes('=')) {
            const [key, value] = pair.split('=');
            if (key && value) {
              try {
                params[key] = decodeURIComponent(value);
              } catch (e) {
                params[key] = value;
                logger.warn('SquareAuth', `Failed to decode param ${key}, using raw value`);
              }
            }
          }
        }
      } else {
        logger.warn('SquareAuth', 'No query string found in callback URL');
      }
      
      logger.info('SquareAuth', 'Extracted parameters from callback URL', {
        paramCount: Object.keys(params).length,
        hasCode: !!params.code,
        hasState: !!params.state
      });
      
      if (params.code && params.state) {
        logger.info('SquareAuth', 'Processing OAuth code grant callback');
        const codeVerifier = await SecureStore.getItemAsync(SQUARE_CODE_VERIFIER_KEY);
        if (!codeVerifier) {
          throw new Error('Code verifier not found. Cannot complete OAuth flow.');
        }
        const tokenResponse = await api.auth.exchangeToken(params.code, codeVerifier);
        await tokenService.storeAuthData({
          access_token: tokenResponse.access_token,
          refresh_token: tokenResponse.refresh_token,
          merchant_id: tokenResponse.merchant_id,
          business_name: tokenResponse.business_name,
          expires_in: tokenResponse.expires_in
        });
        setIsConnected(true);
        setIsConnecting(false);
        setSquareConnected(true);
        if (tokenResponse.merchant_id) setMerchantId(tokenResponse.merchant_id);
        if (tokenResponse.business_name) setBusinessName(tokenResponse.business_name);
        await SecureStore.deleteItemAsync(SQUARE_CODE_VERIFIER_KEY);
        await SecureStore.deleteItemAsync(SQUARE_STATE_KEY);
        logger.info('SquareAuth', '🎉 OAuth code exchange completed successfully');
        return { success: true, data: { accessToken: true, merchantId: tokenResponse.merchant_id, businessName: tokenResponse.business_name } };
      } 
      else if (params.access_token) {
        logger.info('SquareAuth', 'Processing direct token callback');
        await tokenService.storeAuthData({
          access_token: params.access_token,
          refresh_token: params.refresh_token,
          merchant_id: params.merchant_id,
          business_name: params.business_name,
          expires_in: params.expires_in ? parseInt(params.expires_in) : undefined
        });
        setIsConnected(true);
        setIsConnecting(false);
        setSquareConnected(true);
        if (params.merchant_id) setMerchantId(params.merchant_id);
        if (params.business_name) setBusinessName(params.business_name);
        logger.info('SquareAuth', '🎉 Direct token callback processed successfully');
        return { success: true, data: { accessToken: true, merchantId: params.merchant_id, businessName: params.business_name } };
      } else {
        logger.error('SquareAuth', 'Invalid callback URL - missing code/state or access_token');
        throw new Error('Invalid callback URL format. Missing required parameters.');
      }
    } catch (error) {
      logger.error('SquareAuth', 'Error processing callback URL', error);
      setError(error as Error);
      setIsConnecting(false);
      throw error;
    }
  };

  // Store processCallback in ref for stable access in deep link handler
  processCallbackRef.current = processCallback;

  // Check for existing Square connection on mount
  useEffect(() => {
    const checkExistingConnection = async () => {
      try {
        // Reduce console spam by only logging mount once per session
        if (!window._squareAuthLoggedMount) {
          logger.debug('SquareAuth', 'Checking for existing Square connection');
          window._squareAuthLoggedMount = true;
        }
        
        // Use tokenService to check for tokens
        const tokenInfo = await tokenService.getTokenInfo();
        
        if (tokenInfo.accessToken) {
          logger.info('SquareAuth', '✅ Found existing Square connection');
          setIsConnected(true);
          setSquareConnected(true);
          
          // Set merchant info if available
          if (tokenInfo.merchantId) {
            setMerchantId(tokenInfo.merchantId);
          }
          
          if (tokenInfo.businessName) {
            setBusinessName(tokenInfo.businessName);
          }
        } else {
          logger.info('SquareAuth', '❌ No existing Square connection found');
          setIsConnected(false);
          setSquareConnected(false);
        }
        
        // Test SecureStore is working
        try {
          const testKey = 'square_test_key';
          const testValue = 'test_value_' + new Date().getTime();
          logger.info('SquareAuth', '🧪 Testing SecureStore with test key');
          
          await SecureStore.setItemAsync(testKey, testValue);
          const retrievedValue = await SecureStore.getItemAsync(testKey);
          
          if (retrievedValue === testValue) {
            logger.info('SquareAuth', '✅ SecureStore test passed');
          } else {
            logger.error('SquareAuth', '❌ SecureStore test failed - retrieved value does not match');
          }
          
          await SecureStore.deleteItemAsync(testKey);
        } catch (storeErr) {
          logger.error('SquareAuth', '❌ SecureStore test failed with error', storeErr);
        }
      } catch (err) {
        logger.error('SquareAuth', '❌ Error checking existing connection', err);
        setError(err as Error);
      }
    };
    
    checkExistingConnection();
    
    // Run token verification after a short delay to make sure it runs after any mounting operations
    const verifyTimer = setTimeout(() => {
      verifyTokenStorage();
    }, 2000);
    
    return () => clearTimeout(verifyTimer);
  }, []); // Remove setSquareConnected dependency to prevent re-runs
  
  // Handle deep link callback
  useEffect(() => {
    let subscription: { remove: () => void } | null = null;
    
    const setupDeepLinkHandling = async () => {
      try {
        // Reduce console spam by only logging setup once per session
        if (!window._squareAuthLoggedSetup) {
          logger.debug('SquareAuth', 'Setting up deep link handler');
          window._squareAuthLoggedSetup = true;
        }
        
        // Define the deep link handler as a standalone function
        const handleDeepLink = async (event: { url: string }) => {
          // Reduce console spam by only logging non-Square URLs once per session
          if (!event.url.includes('square-callback')) {
            if (!window._squareAuthLoggedDeepLink) {
              logger.debug('SquareAuth', 'Received deep link', { url: event.url });
              logger.debug('SquareAuth', 'Ignoring non-Square callback URL');
              window._squareAuthLoggedDeepLink = true;
            }
            return;
          }

          logger.debug('SquareAuth', 'Received Square callback deep link', { url: event.url });
          
          logger.info('SquareAuth', '🔍 Processing Square callback URL');
          
          try {
            // Use ref to access current processCallback function
            if (processCallbackRef.current) {
              await processCallbackRef.current(event.url);
              logger.info('SquareAuth', '✅ Deep link processing completed successfully via event listener.');
            } else {
              logger.error('SquareAuth', '❌ processCallback not available in deep link handler');
            }
          } catch (procError) {
            logger.error('SquareAuth', '❌ Error processing deep link via event listener', procError);
            setError(procError as Error); // Update error state
            setIsConnecting(false); // Ensure connecting state is reset
          }
        };
        
        // @ts-ignore
        globalThis._joylabs_handleSquareDeepLink = handleDeepLink;
        if (!window._squareAuthLoggedSetup) {
          logger.debug('SquareAuth', 'Assigned handleDeepLink to globalThis._joylabs_handleSquareDeepLink');
        }

        subscription = ExpoLinking.addEventListener('url', handleDeepLink);
        if (!window._squareAuthLoggedSetup) {
          logger.debug('SquareAuth', 'Deep link listener registered');
        }

        // Check initial URL
        const initialUrl = await ExpoLinking.getInitialURL();
        logger.debug('SquareAuth', 'Checking initial URL', { initialUrl });
        if (initialUrl) {
          logger.debug('SquareAuth', 'App opened with deep link', { initialUrl });
          // No await here, let it run in background if needed, or await if critical
          // Consider if initial URL processing needs setIsConnecting flags
          handleDeepLink({ url: initialUrl });
        }
      } catch (err) {
        logger.error('SquareAuth', 'Error setting up deep link handler', err);
        setError(err as Error);
      }
    };

    setupDeepLinkHandling();

    // Interval to check if connection state is stuck
    const repairInterval = setInterval(async () => {
      if (isConnecting) {
        logger.debug('SquareAuth', 'Connection flow is in progress');
        const pkceState = await SecureStore.getItemAsync(SQUARE_STATE_KEY);
        if (!pkceState) { // If state cleared but still connecting, reset
          logger.warn('SquareAuth', 'Connection state stuck, resetting...');
          setIsConnecting(false);
          setError(new Error('Connection timed out or was interrupted.'));
        }
      }
    }, 5000); // Check every 5 seconds

    return () => {
      subscription?.remove();
        // @ts-ignore
        delete globalThis._joylabs_handleSquareDeepLink;
      logger.debug('SquareAuth', 'Deep link listener removed and global reference cleaned on unmount');
      clearInterval(repairInterval); // Clear interval on unmount
    };
  }, []); // Remove dependencies to prevent re-runs - deep link setup should only happen once
  
  // Cleanup WebBrowser session when component unmounts
  useEffect(() => {
    // Ensure WebBrowser is initialized
    WebBrowser.maybeCompleteAuthSession();
    
    // Return cleanup function
    return () => {
      try {
        logger.debug('SquareAuth', 'Cooling down WebBrowser session');
        WebBrowser.coolDownAsync().catch(err => {
          logger.warn('SquareAuth', 'Error cooling down WebBrowser', err);
        });
        
        // Force dismiss any open browser
        try {
          WebBrowser.dismissBrowser();
        } catch (dismissErr) {
          // Ignore, this function might not be available on all platforms
        }
        
        // Try to dismiss auth session
        try {
          WebBrowser.dismissAuthSession();
        } catch (dismissAuthErr) {
          // Ignore, this function might not be available on all platforms
        }
      } catch (cleanupErr) {
        logger.error('SquareAuth', 'Error cleaning up WebBrowser', cleanupErr);
      }
    };
  }, []);

  // Add a new useEffect to debug and log connection state and ensure isConnecting is reset
  useEffect(() => {
    if (isConnecting) {
      logger.debug('SquareAuth', 'Connection flow is in progress');
    } else {
      logger.debug('SquareAuth', 'Connection flow not in progress', { isConnected });
    }
  }, [isConnecting, isConnected]);

  // Add another useEffect to force reset isConnecting if there's an accessToken
  useEffect(() => {
    // Only run this check if we're actually in a connecting state
    if (!isConnecting) return;

    const checkAndResetState = async () => {
      try {
        const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
        if (accessToken && isConnecting) {
          logger.info('SquareAuth', 'Found access token while still in connecting state, resetting connecting state');
          setIsConnecting(false);
          setIsConnected(true);
          setSquareConnected(true);
        }
      } catch (err) {
        logger.error('SquareAuth', 'Error in connection state check', err);
      }
    };

    checkAndResetState();
  }, [isConnecting]); // Remove setSquareConnected dependency

  // Update the connect function to use tokenService for validation
  const connect = async (): Promise<void> => {
    logger.debug('SquareAuth', 'Starting Square connection flow');
    try {
      logger.debug('SquareAuth', 'Setting connecting state');
      setIsConnecting(true);
      setError(null);

      // Generate and store PKCE values
      logger.debug('SquareAuth', 'Generating PKCE parameters');
      const codeVerifier = await generateCodeVerifier();
      const codeChallenge = await generateCodeChallenge(codeVerifier);
      const state = await generateState();

      // Register state with backend before proceeding
      logger.debug('SquareAuth', 'Registering state with backend');
      
      // Make sure the callback URL is properly formed with correct encoding
      let appCallback;
      try {
        // Create URL with proper formatting and make sure it's properly URL encoded
        appCallback = ExpoLinking.createURL('square-callback');
        logger.debug('SquareAuth', 'Generated app callback URL', { appCallback });
        
        // Test for valid URL format
        new URL(appCallback); // This will throw if invalid
      } catch (urlErr: any) {
        logger.error('SquareAuth', 'Error creating callback URL', urlErr);
        throw new Error(`Failed to create valid callback URL: ${urlErr.message}`);
      }

      try {
        const registerStateResponse = await fetch('https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/register-state', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            state: state,
            code_verifier: codeVerifier,
            redirectUrl: appCallback
          }),
        });

        const responseText = await registerStateResponse.text();
        logger.debug('SquareAuth', 'Register state response', {
          status: registerStateResponse.status,
          statusText: registerStateResponse.statusText,
          response: responseText
        });
        
        if (!registerStateResponse.ok) {
          throw new Error(`Failed to register state: ${registerStateResponse.status} ${registerStateResponse.statusText}\nResponse: ${responseText}`);
        }

        logger.debug('SquareAuth', 'Successfully registered state with backend');

        logger.debug('SquareAuth', 'Storing PKCE values');
        await SecureStore.setItemAsync(SQUARE_CODE_VERIFIER_KEY, codeVerifier);
        await SecureStore.setItemAsync(SQUARE_STATE_KEY, state);

        // Use the fixed Square redirect URI
        const squareRedirectUri = 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/square/callback';
        
        logger.debug('SquareAuth', 'Using Square redirect URI:', squareRedirectUri);

        const params = new URLSearchParams({
          client_id: config.square.appId,
          scope: 'MERCHANT_PROFILE_READ ITEMS_READ ITEMS_WRITE',
          response_type: 'code',
          code_challenge: codeChallenge,
          code_challenge_method: 'S256',
          state: state,
          redirect_uri: squareRedirectUri,
        });

        // Add app's callback URL as a parameter for the backend to use
        params.append('app_callback', appCallback);

        const authUrl = `https://connect.squareup.com/oauth2/authorize?${params.toString()}`;
        logger.debug('SquareAuth', 'Built Square authorization URL:', authUrl);

        // Use WebBrowser instead of Linking
        logger.debug('SquareAuth', 'Opening auth session with WebBrowser');
        try {
          const result = await WebBrowser.openAuthSessionAsync(
            authUrl,
            'joylabs://square-callback', // Use direct scheme without ExpoLinking.createURL
            {
              showInRecents: true,
              preferEphemeralSession: true
            }
          );
          
          logger.debug('SquareAuth', 'WebBrowser session result:', result);

          // Update the connect function to access the handleDeepLink function
          if (result.type === 'success' && result.url) {
            logger.info('SquareAuth', '⚠️ WebBrowser returned success but deep link handler may not have triggered');
            logger.info('SquareAuth', '🔄 Manually processing WebBrowser result URL');
            
            // Use the global reference to the deep link handler
            // @ts-ignore - Access the globally stored handleDeepLink function
            if (globalThis._joylabs_handleSquareDeepLink) {
              // @ts-ignore
              await globalThis._joylabs_handleSquareDeepLink({ url: result.url });
              logger.info('SquareAuth', '✅ Manual processing of WebBrowser URL completed');
            } else {
              logger.error('SquareAuth', '❌ Cannot manually process URL - deep link handler not available');
              setError(new Error('Deep link handler not initialized'));
              setIsConnecting(false);
            }
            
            // Double check after processing
            setTimeout(async () => {
              const status = await verifyTokenStorage();
              logger.info('SquareAuth', '🔍 Token status after manual processing:', status);
              
              if (!status.hasAccessToken) {
                logger.error('SquareAuth', '❌ Tokens still not stored after manual processing');
                setError(new Error('Failed to store tokens after authentication'));
                setIsConnecting(false);
              }
            }, 1000);
          } else if (result.type === 'cancel') {
            logger.info('SquareAuth', '❌ Authentication cancelled by user');
            setError(new Error('Authentication cancelled'));
            setIsConnecting(false);
          }
        } catch (webErr: any) {
          logger.error('SquareAuth', 'WebBrowser error:', webErr);
          // Fallback to direct opening if WebBrowser fails
          logger.debug('SquareAuth', 'Falling back to Linking.openURL');
          await Linking.openURL(authUrl);
        }

      } catch (err) {
        logger.error('SquareAuth', 'Error registering state with backend', err);
        setError(err as Error);
        setIsConnecting(false);
      }
    } catch (err) {
      logger.error('SquareAuth', 'Error starting Square connection', err);
      setError(err as Error);
      setIsConnecting(false);
    }
  };
  
  // Update disconnect function to use tokenService
  const disconnect = async (): Promise<void> => {
    try {
      logger.debug('SquareAuth', 'Disconnecting from Square');
      
      // Clear all tokens using tokenService
      await tokenService.clearAuthData();
      
      // Update state
      setIsConnected(false);
      setSquareConnected(false);
      setMerchantId(null);
      setBusinessName(null);
      setError(null);
      
      logger.info('SquareAuth', '✅ Disconnected from Square successfully');
      
      return Promise.resolve();
    } catch (err) {
      logger.error('SquareAuth', '❌ Error disconnecting from Square', err);
      setError(err as Error);
      return Promise.reject(err);
    }
  };

  // Update the testDeepLink function
  const testDeepLink = async () => {
    try {
      logger.debug('SquareAuth', 'Testing deep link handling');
      
      // Create a test URL that exactly matches the format from the backend logs
      const testUrl = 'joylabs://square-callback?access_token=EAAATestToken123&refresh_token=EQAATestRefresh123&merchant_id=TestMerchant123&business_name=JOY%25201';
      
      logger.debug('SquareAuth', 'Simulating deep link with URL', { testUrl });
      
      // Test if URL can be properly parsed
      try {
        const url = new URL(testUrl);
        logger.debug('SquareAuth', 'Test URL structure', {
          protocol: url.protocol,
          host: url.host,
          hostname: url.hostname,
          pathname: url.pathname,
          search: url.search
        });

        // Try extracting parameters to make sure our parsing logic works
        const params: Record<string, string> = {};
        url.searchParams.forEach((value, key) => {
          params[key] = value;
        });
        logger.debug('SquareAuth', 'Test URL parameters', params);
        
        // Test decoding logic
        if (params.business_name && params.business_name.includes('%')) {
          try {
            const decoded = decodeURIComponent(params.business_name);
            logger.debug('SquareAuth', 'Test decode result', { 
              original: params.business_name, 
              decoded 
            });
          } catch (decodeErr: any) {
            logger.error('SquareAuth', 'Test decode error', { error: decodeErr.message });
          }
        }
      } catch (urlErr: any) {
        logger.error('SquareAuth', 'Failed to parse test URL', { error: urlErr.message });
      }
      
      // Try to open the URL
      logger.debug('SquareAuth', 'Attempting to open test URL');
      await Linking.openURL(testUrl);
      
      logger.debug('SquareAuth', 'Test URL opened successfully');
    } catch (err) {
      logger.error('SquareAuth', 'Error testing deep link', err);
      setError(err as Error);
    }
  };
  
  // Add a more aggressive state reset function
  const forceResetConnectionState = async () => {
    logger.info('SquareAuth', '🔄 Force resetting connection state');
    
    // Verify token storage first
    const tokenStatus = await verifyTokenStorage();
    
    // Reset all state regardless of the values
    setIsConnecting(false);
    
    if (tokenStatus.hasAccessToken) {
      logger.info('SquareAuth', '✅ Found access token, setting connected state');
      setIsConnected(true);
      setSquareConnected(true);
      
      const storedMerchantId = await SecureStore.getItemAsync(MERCHANT_ID_KEY);
      if (storedMerchantId) {
        setMerchantId(storedMerchantId);
      }
      
      const storedBusinessName = await SecureStore.getItemAsync(BUSINESS_NAME_KEY);
      if (storedBusinessName) {
        setBusinessName(storedBusinessName);
      }
    } else {
      logger.info('SquareAuth', '❌ No access token found, setting disconnected state');
      setIsConnected(false);
      setSquareConnected(false);
      setMerchantId(null);
      setBusinessName(null);
    }
    
    return tokenStatus;
  };
  
  // Add hasValidToken method to check if the token is valid
  const hasValidToken = async (): Promise<boolean> => {
    try {
      logger.debug('SquareAuth', 'Checking if token is valid');
      
      // Check if we have an access token
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      if (!accessToken) {
        logger.debug('SquareAuth', 'No access token found');
        return false;
      }
      
      // Check if token has expired based on stored expiry
      const expiryTime = await SecureStore.getItemAsync(TOKEN_KEYS.TOKEN_EXPIRY);
      if (expiryTime) {
        const expiry = new Date(expiryTime);
        const now = new Date();
        
        // If token is expired, return false
        if (expiry < now) {
          logger.debug('SquareAuth', 'Token is expired');
          return false;
        }
      }
      
      // Token exists and is not expired
      logger.debug('SquareAuth', 'Token exists and is not expired');
      return true;
    } catch (error) {
      logger.error('SquareAuth', 'Error checking token validity', error);
      return false;
    }
  };
  
  // Update the testConnection function
  const testConnection = async () => {
    try {
      logger.debug('SquareAuth', 'Testing Square API connection');
      
      // Get the access token
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      
      if (!accessToken) {
        logger.error('SquareAuth', 'No access token available');
        
        // Run token verification to diagnose the issue
        const tokenStatus = await verifyTokenStorage();
        
        return { 
          success: false, 
          error: 'No Square access token found. Please connect to Square first.',
          tokenStatus
        };
      }
      
      logger.info('SquareAuth', `✅ Found access token for API test (length: ${accessToken.length})`);
      
      // Make a simple API call to Square directly to test token validity
      try {
        logger.debug('SquareAuth', 'Making direct API call to Square');
        
        const response = await fetch('https://connect.squareup.com/v2/merchants/me', {
          method: 'GET',
          headers: {
            'Square-Version': '2023-09-25',
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json'
          }
        });
        
        // Parse response data
        const data = await response.json();
        
        // If we get a 401 unauthorized, the token is likely expired
        if (!response.ok) {
          logger.error('SquareAuth', 'Square API returned error', { 
            status: response.status,
            statusText: response.statusText,
            data
          });
          
          if (response.status === 401) {
            logger.warn('SquareAuth', 'Token appears to be expired or invalid');
            
            // Check if we have a refresh token
            const refreshToken = await SecureStore.getItemAsync(SQUARE_REFRESH_TOKEN_KEY);
            
            if (refreshToken) {
              logger.info('SquareAuth', 'Refresh token found, token could be refreshed');
              return {
                success: false,
                error: 'Your Square access token has expired. The app will try to refresh it automatically.',
                canRefresh: true
              };
            } else {
              logger.warn('SquareAuth', 'No refresh token found, reconnection required');
              // Clear invalid token
              await SecureStore.deleteItemAsync(SQUARE_ACCESS_TOKEN_KEY);
              setIsConnected(false);
              setSquareConnected(false);
              
              return {
                success: false,
                error: 'Your Square access token has expired and cannot be refreshed. Please reconnect to Square.',
                canRefresh: false
              };
            }
          }
          
          return {
            success: false,
            error: data.errors?.[0]?.detail || `API error: ${response.status} ${response.statusText}`,
            data: data
          };
        }
        
        logger.debug('SquareAuth', 'Square API response', data);
        
        // Force update the connection state based on the successful API call
        if (!isConnected) {
          logger.info('SquareAuth', 'API call successful but state shows disconnected, fixing state');
          setIsConnected(true);
          setSquareConnected(true);
          if (data.merchant?.id) {
            setMerchantId(data.merchant.id);
            await SecureStore.setItemAsync(MERCHANT_ID_KEY, data.merchant.id);
          }
          if (data.merchant?.business_name) {
            setBusinessName(data.merchant.business_name);
            await SecureStore.setItemAsync(BUSINESS_NAME_KEY, data.merchant.business_name);
          }
        }
        
        logger.info('SquareAuth', 'Successfully connected to Square API');
        return {
          success: true, 
          data: {
            merchantId: data.merchant?.id,
            businessName: data.merchant?.business_name,
          }
        };
      } catch (error: any) {
        logger.error('SquareAuth', 'Error calling Square API directly', error);
        return {
          success: false,
          error: error.message || 'Network error while testing Square connection',
          isNetworkError: true
        };
      }
    } catch (error: any) {
      logger.error('SquareAuth', 'Error testing Square connection', error);
      return {
        success: false,
        error: error.message || 'Unknown error'
      };
    }
  };

  // Add additional state checking every 5 seconds to ensure consistency
  useEffect(() => {
    // Only run this if we're in a potentially inconsistent state
    if (isConnecting) {
      logger.debug('SquareAuth', 'Setting up connection state repair interval');
      const interval = setInterval(async () => {
        try {
          // Check if we've been in connecting state for too long (over 30 seconds)
          const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
          if (accessToken) {
            logger.info('SquareAuth', 'Found token while in connecting state, repairing state');
            setIsConnecting(false);
            setIsConnected(true);
            setSquareConnected(true);
            
            // Update merchant info if available
            const storedMerchantId = await SecureStore.getItemAsync(MERCHANT_ID_KEY);
            if (storedMerchantId) {
              setMerchantId(storedMerchantId);
            }
            
            const storedBusinessName = await SecureStore.getItemAsync(BUSINESS_NAME_KEY);
            if (storedBusinessName) {
              setBusinessName(storedBusinessName);
            }
          }
        } catch (err) {
          logger.error('SquareAuth', 'Error in connection state repair interval', err);
        }
      }, 5000); // Check every 5 seconds
      
      return () => clearInterval(interval);
    }
  }, [isConnecting, setSquareConnected]);

  // Update the verifyTokenStorage function to use tokenService
  const verifyTokenStorage = async () => {
    try {
      logger.info('SquareAuth', '🔍 Verifying token storage...');
      const tokenInfo = await tokenService.getTokenInfo();
      
      logger.info('SquareAuth', '🔒 Token verification result:', {
        hasAccessToken: !!tokenInfo.accessToken,
        accessTokenLength: tokenInfo.accessToken ? tokenInfo.accessToken.length : 0,
        hasRefreshToken: !!tokenInfo.refreshToken,
        hasMerchantId: !!tokenInfo.merchantId,
        hasBusinessName: !!tokenInfo.businessName,
        status: tokenInfo.status
      });
      
      return {
        hasAccessToken: !!tokenInfo.accessToken,
        accessTokenLength: tokenInfo.accessToken ? tokenInfo.accessToken.length : 0,
        hasRefreshToken: !!tokenInfo.refreshToken,
        hasMerchantId: !!tokenInfo.merchantId,
        hasBusinessName: !!tokenInfo.businessName,
        status: tokenInfo.status
      };
    } catch (err) {
      logger.error('SquareAuth', '❌ Error verifying token storage', err);
      return {
        hasAccessToken: false,
        error: err
      };
    }
  };
  
  // Fix the testExactCallback function to address TypeScript errors
  const testExactCallback = async () => {
    logger.info('SquareAuth', '🧪 Testing exact callback URL from logs');
    
    // Use the exact URL that we saw in the logs, including the hash fragment
    const testUrl = 'joylabs://square-callback?access_token=EAAAl4zVxrfgG6nqgbKYuiSKvZUdqNUelOREorB8gLqlPeoTKyodTnssJQUNUtWw&refresh_token=EQAAl6RdQO_Zp15aqJzS7LUS9SN7mLae4XIANK6VyPfqvoBXGDXXjWInEUpfS1Fj&merchant_id=MLZWK2638HTS0&business_name=JOY%201#_=_';
    
    try {
      // Test if we can manually process this URL
      const event = { url: testUrl };
      
      // Log that we're simulating the URL event
      logger.info('SquareAuth', '🧪 Simulating deep link with test URL');
      
      // Instead of using getEventListeners which doesn't exist,
      // directly simulate processing the URL
      logger.info('SquareAuth', '🧪 Processing URL manually');
      
      // Extract and clean the URL
      let cleanUrl = testUrl;
      if (cleanUrl.includes('#')) {
        cleanUrl = cleanUrl.split('#')[0];
      }
      
      // Extract parameters
      const params: Record<string, string> = {};
      if (cleanUrl.includes('?')) {
        const queryStr = cleanUrl.split('?')[1];
        const pairs = queryStr.split('&');
        
        for (const pair of pairs) {
          if (pair.includes('=')) {
            const [key, value] = pair.split('=');
            if (key && value) {
              params[key] = decodeURIComponent(value);
            }
          }
        }
      }
      
      // Log extracted parameters
      logger.info('SquareAuth', '🔑 Extracted parameters from test URL', {
        hasAccessToken: !!params.access_token,
        accessTokenLength: params.access_token?.length || 0,
        hasRefreshToken: !!params.refresh_token,
        hasMerchantId: !!params.merchant_id,
        merchantId: params.merchant_id,
        hasBusinessName: !!params.business_name,
        businessName: params.business_name
      });
      
      // Store tokens directly
      if (params.access_token) {
        try {
          await SecureStore.setItemAsync(SQUARE_ACCESS_TOKEN_KEY, params.access_token);
          logger.info('SquareAuth', '✅ Test access token stored successfully');
          
          // Verify storage
          const storedToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
          if (storedToken) {
            logger.info('SquareAuth', `✅ Verified access token storage (length: ${storedToken.length})`);
            
            // Update app state to reflect successful connection
            setIsConnected(true);
            setIsConnecting(false);
            setSquareConnected(true);
            
            // Update merchant info if available
            if (params.merchant_id) {
              await SecureStore.setItemAsync(MERCHANT_ID_KEY, params.merchant_id);
              setMerchantId(params.merchant_id);
              logger.info('SquareAuth', '✅ Test merchant ID stored');
            }
            
            if (params.business_name) {
              await SecureStore.setItemAsync(BUSINESS_NAME_KEY, params.business_name);
              setBusinessName(params.business_name);
              logger.info('SquareAuth', '✅ Test business name stored');
            }
            
            if (params.refresh_token) {
              await SecureStore.setItemAsync(SQUARE_REFRESH_TOKEN_KEY, params.refresh_token);
              logger.info('SquareAuth', '✅ Test refresh token stored');
            }
          } else {
            logger.error('SquareAuth', '❌ Failed to verify access token storage');
          }
        } catch (storageErr) {
          logger.error('SquareAuth', '❌ Error storing test tokens', storageErr);
        }
      }
      
      // Verify token storage after processing
      await new Promise(resolve => setTimeout(resolve, 1000));
      const verificationResult = await verifyTokenStorage();
      logger.info('SquareAuth', '🔒 Test callback verification result:', verificationResult);
      
      return {
        success: verificationResult.hasAccessToken,
        hasAccessToken: verificationResult.hasAccessToken,
        accessTokenLength: verificationResult.accessTokenLength,
        hasRefreshToken: verificationResult.hasRefreshToken,
        hasMerchantId: verificationResult.hasMerchantId,
        hasBusinessName: verificationResult.hasBusinessName,
        error: verificationResult.error ? String(verificationResult.error) : undefined
      };
    } catch (err) {
      logger.error('SquareAuth', '❌ Error testing exact callback', err);
      return {
        success: false,
        hasAccessToken: false,
        error: String((err as Error).message)
      };
    }
  };

  // Return hook values and methods
  return {
    isConnected,
    isConnecting,
    connect,
    disconnect,
    error,
    merchantId,
    businessName,
    testDeepLink,
    forceResetConnectionState,
    testConnection,
    testExactCallback,
    processCallback,
    hasValidToken
  };
}; 