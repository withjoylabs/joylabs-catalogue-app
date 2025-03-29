import { useEffect, useState } from 'react';
import { Linking } from 'react-native';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import * as ExpoLinking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import config from '../config';
import { useAppStore } from '../store';
import logger from '../utils/logger';
import Constants from 'expo-constants';

// Initialize WebBrowser
WebBrowser.maybeCompleteAuthSession();

// Constants for secure storage keys
const SQUARE_CODE_VERIFIER_KEY = 'square_code_verifier';
const SQUARE_STATE_KEY = 'square_state';
const SQUARE_ACCESS_TOKEN_KEY = 'square_access_token';
const SQUARE_REFRESH_TOKEN_KEY = 'square_refresh_token';
const MERCHANT_ID_KEY = 'square_merchant_id';
const BUSINESS_NAME_KEY = 'square_business_name';

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
}

export const useSquareAuth = (): UseSquareAuthResult => {
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [merchantId, setMerchantId] = useState<string | null>(null);
  const [businessName, setBusinessName] = useState<string | null>(null);
  
  const { setSquareConnected } = useAppStore();

  // Check for existing tokens on mount
  useEffect(() => {
    const checkExistingConnection = async () => {
      try {
        logger.info('SquareAuth', '🔄 Checking existing connection on component mount...');
        const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
        
        // Log token details for debugging
        if (accessToken) {
          logger.info('SquareAuth', '✅ Found access token on startup - length: ' + accessToken.length);
      setIsConnected(true);
      setSquareConnected(true);
      
          const storedMerchantId = await SecureStore.getItemAsync(MERCHANT_ID_KEY);
          if (storedMerchantId) {
            logger.info('SquareAuth', '✅ Found merchant ID: ' + storedMerchantId.substring(0, 4) + '...');
            setMerchantId(storedMerchantId);
          } else {
            logger.warn('SquareAuth', '⚠️ No merchant ID found despite having access token');
          }
          
          const storedBusinessName = await SecureStore.getItemAsync(BUSINESS_NAME_KEY);
          if (storedBusinessName) {
            logger.info('SquareAuth', '✅ Found business name: ' + storedBusinessName);
            setBusinessName(storedBusinessName);
          } else {
            logger.warn('SquareAuth', '⚠️ No business name found despite having access token');
          }
        } else {
          logger.info('SquareAuth', '❌ No access token found on startup');
          
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
  }, [setSquareConnected]);
  
  // Handle deep link callback
  useEffect(() => {
    let subscription: { remove: () => void } | null = null;
    
    const setupDeepLinkHandling = async () => {
      try {
        logger.debug('SquareAuth', 'Setting up deep link handler');
        
        // Define the deep link handler as a standalone function
        const handleDeepLink = async (event: { url: string }) => {
          logger.debug('SquareAuth', 'Received deep link', { url: event.url });
          
          // Only process Square callback URLs
          if (!event.url.includes('square-callback')) {
            logger.debug('SquareAuth', 'Ignoring non-Square callback URL');
            return;
          }
          
          logger.info('SquareAuth', '🔍 Processing Square callback URL');
          
          try {
            logger.debug('SquareAuth', 'Processing Square callback');
            setIsConnecting(true);
            setError(null);

            // More robust URL handling approach
            const originalUrl = event.url;
            
            // IMPORTANT: Handle hash fragments properly - Square adds #_=_ to callback URLs
            // This is a common pattern in OAuth providers (Facebook, Square) that can break parameter extraction
            let cleanUrl = originalUrl;
            if (originalUrl.includes('#')) {
              const fragmentIndex = originalUrl.indexOf('#');
              cleanUrl = originalUrl.substring(0, fragmentIndex);
              logger.info('SquareAuth', `🔧 Removed URL fragment at position ${fragmentIndex}. Original length: ${originalUrl.length}, New length: ${cleanUrl.length}`);
            }
            
            // Extract the query portion directly using string operations
            // This is more reliable than URL parsing which can fail with custom schemes
            let queryString = '';
            if (cleanUrl.includes('?')) {
              queryString = cleanUrl.split('?')[1];
              logger.debug('SquareAuth', `📝 Extracted query string: ${queryString}`);
            } else {
              logger.error('SquareAuth', '❌ No query parameters found in URL');
              throw new Error('No query string found in callback URL');
            }
            
            // Parse parameters directly from the query string using reliable string operations
            const params: Record<string, string> = {};
            
            // Split by & and process each key-value pair
            const pairs = queryString.split('&');
            for (const pair of pairs) {
              if (pair.includes('=')) {
                const [key, encodedValue] = pair.split('=');
                if (key && encodedValue) {
                  // Always try to decode the value
                  try {
                    params[key] = decodeURIComponent(encodedValue);
                    logger.debug('SquareAuth', `🔑 Extracted parameter: ${key}=${key.includes('token') ? '[REDACTED]' : params[key]}`);
                  } catch (decodeError) {
                    // If decoding fails, use the raw value
                    params[key] = encodedValue;
                    logger.warn('SquareAuth', `⚠️ Could not decode parameter value for ${key}, using raw value`);
                  }
                }
              }
            }
            
            // Log successful parameter extraction
            logger.info('SquareAuth', '✅ Extracted parameters from URL', {
              paramCount: Object.keys(params).length,
              hasAccessToken: !!params.access_token,
              accessTokenLength: params.access_token ? params.access_token.length : 0,
              hasRefreshToken: !!params.refresh_token,
              hasMerchantId: !!params.merchant_id,
              hasBusinessName: !!params.business_name
            });

            // Validate we have the required parameters
            if (!params.access_token) {
              logger.error('SquareAuth', '❌ Missing access_token in callback');
              throw new Error('Access token not found in callback URL');
            }

            // Extract token values
            const accessToken = params.access_token;
            const refreshToken = params.refresh_token;
            const merchantId = params.merchant_id;
            let businessName = params.business_name;
            
            // Fix potential double encoding issues with business name
            if (businessName && businessName.includes('%')) {
              try {
                businessName = decodeURIComponent(businessName);
                logger.debug('SquareAuth', 'Decoded business name from potential double encoding');
              } catch (decodeErr) {
                logger.warn('SquareAuth', 'Failed to decode business name', { businessName });
              }
            }
            
            // Store tokens immediately while we have them in memory
            logger.info('SquareAuth', '💾 Storing Square connection data to SecureStore');
            
            try {
              // Store access token with immediate verification
              logger.debug('SquareAuth', `Storing access token (length: ${accessToken.length})`);
              await SecureStore.setItemAsync(SQUARE_ACCESS_TOKEN_KEY, accessToken);
              
              // Verify the token was stored correctly
              const storedToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
              if (storedToken && storedToken === accessToken) {
                logger.info('SquareAuth', '✅ Access token stored and verified successfully');
              } else {
                logger.error('SquareAuth', '❌ Access token verification failed - not found after storage');
                throw new Error('Failed to store access token - verification failed');
              }
              
              // Store refresh token
              if (refreshToken) {
                logger.debug('SquareAuth', `Storing refresh token (length: ${refreshToken.length})`);
                await SecureStore.setItemAsync(SQUARE_REFRESH_TOKEN_KEY, refreshToken);
                logger.debug('SquareAuth', '✅ Refresh token stored');
              }
              
              // Store merchant ID
              if (merchantId) {
                logger.debug('SquareAuth', `Storing merchant ID: ${merchantId}`);
                await SecureStore.setItemAsync(MERCHANT_ID_KEY, merchantId);
                setMerchantId(merchantId);
                logger.debug('SquareAuth', '✅ Merchant ID stored');
              }
              
              // Store business name
              if (businessName) {
                logger.debug('SquareAuth', `Storing business name: ${businessName}`);
                await SecureStore.setItemAsync(BUSINESS_NAME_KEY, businessName);
                setBusinessName(businessName);
                logger.debug('SquareAuth', '✅ Business name stored');
              }
              
              // Clean up PKCE values
              await SecureStore.deleteItemAsync(SQUARE_CODE_VERIFIER_KEY);
              await SecureStore.deleteItemAsync(SQUARE_STATE_KEY);
              
              // Update app state
              setIsConnected(true);
              setIsConnecting(false);
              setSquareConnected(true);
              
              logger.info('SquareAuth', '🎉 Square connection successfully completed');
              
              // Verify token storage after a short delay
              setTimeout(async () => {
                const verificationResult = await verifyTokenStorage();
                logger.info('SquareAuth', '🔒 Verification after callback:', verificationResult);
              }, 500);
              
            } catch (storageErr) {
              logger.error('SquareAuth', '❌ Error storing tokens', storageErr);
              throw new Error(`Failed to store connection data: ${(storageErr as Error).message}`);
            }
          } catch (err) {
            logger.error('SquareAuth', 'Error handling Square callback', err);
            setError(err as Error);
            setIsConnected(false);
            setSquareConnected(false);
            setIsConnecting(false);
          }
        };
        
        // Make handleDeepLink accessible to the connect function
        // @ts-ignore - This is intentional to allow access from connect
        globalThis._joylabs_handleSquareDeepLink = handleDeepLink;
        
        // Add deep link listener
        subscription = Linking.addEventListener('url', handleDeepLink);
        logger.debug('SquareAuth', 'Deep link listener registered');

        // Check for initial URL (handles app opened from deep link)
        const initialUrl = await Linking.getInitialURL();
        logger.debug('SquareAuth', 'Checking initial URL', { initialUrl });
        if (initialUrl) {
          logger.debug('SquareAuth', 'App opened with deep link', { initialUrl });
          await handleDeepLink({ url: initialUrl });
        }
      } catch (err) {
        logger.error('SquareAuth', 'Error setting up deep link handling', err);
        setError(err as Error);
      }
    };

    setupDeepLinkHandling();

    return () => {
      logger.debug('SquareAuth', 'Cleaning up deep link handler');
      if (subscription) {
        subscription.remove();
      }
      // Clean up global reference
      // @ts-ignore
      if (globalThis._joylabs_handleSquareDeepLink) {
        // @ts-ignore
        delete globalThis._joylabs_handleSquareDeepLink;
      }
    };
  }, [setSquareConnected]);
  
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
    
    // Run this check when component mounts and whenever isConnecting changes
    checkAndResetState();
  }, [isConnecting, setSquareConnected]);

  // Update the connect function to access the handleDeepLink function
  const connect = async () => {
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
  
  const disconnect = async () => {
    try {
      logger.debug('SquareAuth', 'Starting Square disconnection');
      
      // Call Square API to revoke tokens
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      const refreshToken = await SecureStore.getItemAsync(SQUARE_REFRESH_TOKEN_KEY);
      
      if (accessToken) {
        try {
          logger.info('SquareAuth', 'Revoking Square access token');
          
          // Use the correct Square OAuth revocation endpoint
          const response = await fetch('https://connect.squareup.com/oauth2/revoke', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Square-Version': '2023-09-25',
              'Authorization': `Bearer ${accessToken}`
            },
            body: JSON.stringify({
              client_id: config.square.appId,
              access_token: accessToken
            }),
          });

          if (!response.ok) {
            const responseText = await response.text();
            logger.error('SquareAuth', 'Token revocation failed', {
              status: response.status,
              response: responseText
            });
            // Continue with local cleanup even if token revocation fails
          } else {
            logger.info('SquareAuth', 'Successfully revoked Square token');
          }
        } catch (revokeError) {
          // Log error but continue with cleanup
          logger.error('SquareAuth', 'Error revoking Square token', revokeError);
          // We'll still clean up local tokens even if the revocation request fails
        }
      }

      // Clean up stored tokens
      logger.info('SquareAuth', 'Cleaning up local tokens');
      await SecureStore.deleteItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      await SecureStore.deleteItemAsync(SQUARE_REFRESH_TOKEN_KEY);
      await SecureStore.deleteItemAsync(MERCHANT_ID_KEY);
      await SecureStore.deleteItemAsync(BUSINESS_NAME_KEY);
      
      logger.debug('SquareAuth', 'Successfully disconnected from Square');
      
      // Update local state
      setMerchantId(null);
      setBusinessName(null);
      setIsConnected(false);
      setSquareConnected(false);
      setError(null);
    } catch (err) {
      logger.error('SquareAuth', 'Error disconnecting from Square', err);
      setError(err as Error);
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

  // Add a new function to diagnose token storage near line 500
  const verifyTokenStorage = async () => {
    try {
      logger.info('SquareAuth', '🔍 Verifying token storage...');
      const accessToken = await SecureStore.getItemAsync(SQUARE_ACCESS_TOKEN_KEY);
      const refreshToken = await SecureStore.getItemAsync(SQUARE_REFRESH_TOKEN_KEY);
      const merchId = await SecureStore.getItemAsync(MERCHANT_ID_KEY);
      const bizName = await SecureStore.getItemAsync(BUSINESS_NAME_KEY);
      
      logger.info('SquareAuth', '🔒 Token verification result:', {
        hasAccessToken: !!accessToken,
        accessTokenLength: accessToken ? accessToken.length : 0,
        hasRefreshToken: !!refreshToken,
        hasMerchantId: !!merchId,
        hasBusinessName: !!bizName
      });
      
      return {
        hasAccessToken: !!accessToken,
        accessTokenLength: accessToken ? accessToken.length : 0,
        hasRefreshToken: !!refreshToken,
        hasMerchantId: !!merchId,
        hasBusinessName: !!bizName
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
  };
}; 