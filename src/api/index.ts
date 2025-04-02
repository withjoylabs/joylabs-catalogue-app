import axios, { AxiosInstance, AxiosError, AxiosRequestConfig, AxiosResponse } from 'axios';
import * as SecureStore from 'expo-secure-store';
import * as Network from 'expo-network';
import { NetworkState } from 'expo-network';
import AsyncStorage from '@react-native-async-storage/async-storage';
import config from '../config';
import logger from '../utils/logger';
import tokenService, { TOKEN_KEYS } from '../services/tokenService';

// API Error Types
export class ApiError extends Error {
  code: string;
  status: number;
  details?: any;
  
  constructor(message: string, code: string = 'UNKNOWN_ERROR', status: number = 500, details?: any) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

// Cache related constants and types
const CACHE_PREFIX = 'api_cache_';
const CACHE_EXPIRY_PREFIX = 'api_cache_expiry_';
const DEFAULT_CACHE_TTL = 5 * 60 * 1000; // 5 minutes in milliseconds

interface CacheConfig {
  ttl?: number;        // Time to live in milliseconds
  key?: string;        // Custom cache key, default is URL
  ignoreParams?: boolean; // Whether to ignore URL params in cache key
}

interface RetryConfig {
  count: number;       // Number of retry attempts
  delay: number;       // Delay between retries in milliseconds
  statusCodes?: number[]; // Status codes to retry on
}

// Extend AxiosRequestConfig to include our custom properties
interface RequestConfig extends AxiosRequestConfig {
  cache?: boolean | CacheConfig;
  retry?: boolean | RetryConfig;
  forceRefresh?: boolean;
  bypassConnectionCheck?: boolean;
  _retryCount?: number;
  _authRetry?: boolean;
}

// Add type declaration so TypeScript knows these properties exist
declare module 'axios' {
  interface AxiosRequestConfig {
    cache?: boolean | CacheConfig;
    retry?: boolean | RetryConfig;
    forceRefresh?: boolean;
    bypassConnectionCheck?: boolean;
    _retryCount?: number;
    _authRetry?: boolean;
  }
}

// Connection state management and monitoring
let isConnected = true; // Assume connected initially
let isConnectedToInternet = false; // Assume no internet connectivity initially
let pendingRequests: {
  config: RequestConfig;
  resolve: (value: any) => void;
  reject: (reason?: any) => void;
}[] = [];

// Network connectivity check
const checkNetworkConnectivity = async (): Promise<{
  isConnected: boolean;
  isInternetReachable: boolean;
}> => {
  try {
    const networkState: NetworkState = await Network.getNetworkStateAsync();
    
    // Check if network is connected, defaulting to false if undefined
    isConnected = networkState.isConnected === true;
    
    // Check if internet is reachable, defaulting to false if undefined
    isConnectedToInternet = networkState.isInternetReachable === true;
    
    logger.debug('API', 'Network connectivity check', {
      isConnected,
      isInternetReachable: isConnectedToInternet,
      type: networkState.type
    });
    
    return {
      isConnected,
      isInternetReachable: isConnectedToInternet
    };
  } catch (error) {
    logger.error('API', 'Failed to check network connectivity', { error });
    return {
      isConnected: false,
      isInternetReachable: false
    };
  }
};

// Token management - DEPRECATED: Use tokenService instead
// These remain for backward compatibility but delegate to tokenService
const TOKEN_STORAGE_KEY = TOKEN_KEYS.ACCESS_TOKEN;
const REFRESH_TOKEN_STORAGE_KEY = TOKEN_KEYS.REFRESH_TOKEN;
const MERCHANT_ID_STORAGE_KEY = TOKEN_KEYS.MERCHANT_ID;
const BUSINESS_NAME_STORAGE_KEY = TOKEN_KEYS.BUSINESS_NAME;

// Use tokenService for token operations
const getAuthToken = async (): Promise<string | null> => {
  return tokenService.getAccessToken();
};

const getAuthHeaders = async (): Promise<Record<string, string>> => {
  return tokenService.getAuthHeaders();
};

const setAuthToken = async (token: string): Promise<void> => {
  return tokenService.setAccessToken(token);
};

const clearAuthToken = async (): Promise<void> => {
  return tokenService.clearAuthData();
};

// Secret name management for AWS Secrets
const getSecretName = (): string => {
  // Always use production credentials
    return 'square-credentials-production';
};

// Add AWS region parameter (us-west-1 is common for west coast)
const appendSecretName = (url: string): string => {
  // As per backend feedback, we should not need to append secret names to URLs
  // Just returning the original URL as the backend should handle secrets internally
  return url;
};

// Cache utility functions
const getCacheKey = (config: RequestConfig): string => {
  if (typeof config.cache === 'object' && config.cache.key) {
    return `${CACHE_PREFIX}${config.cache.key}`;
  }
  
  let url = config.url || '';
  // Include query params in cache key unless explicitly ignored
  if (config.params && (typeof config.cache !== 'object' || !config.cache.ignoreParams)) {
    const params = new URLSearchParams();
    Object.entries(config.params).forEach(([key, value]) => {
      params.append(key, String(value));
    });
    const queryString = params.toString();
    if (queryString) {
      url += `?${queryString}`;
    }
  }
  
  // Include HTTP method in cache key
  const method = config.method?.toLowerCase() || 'get';
  return `${CACHE_PREFIX}${method}_${url}`;
};

const getCacheExpiryKey = (cacheKey: string): string => {
  return cacheKey.replace(CACHE_PREFIX, CACHE_EXPIRY_PREFIX);
};

const getFromCache = async <T>(cacheKey: string): Promise<T | null> => {
  try {
    // Check if cache is expired
    const expiryKey = getCacheExpiryKey(cacheKey);
    const expiryTimeStr = await AsyncStorage.getItem(expiryKey);
    
    if (!expiryTimeStr) {
      return null; // No expiry time means no cache
    }
    
    const expiryTime = parseInt(expiryTimeStr, 10);
    if (Date.now() > expiryTime) {
      // Cache is expired, clean it up
      await AsyncStorage.multiRemove([cacheKey, expiryKey]);
      return null;
    }
    
    // Get cache data
    const cachedDataStr = await AsyncStorage.getItem(cacheKey);
    if (!cachedDataStr) {
      return null;
    }
    
    const cachedData = JSON.parse(cachedDataStr) as T;
    logger.debug('API', 'Retrieved from cache', { cacheKey });
    return cachedData;
  } catch (error) {
    logger.error('API', 'Failed to get from cache', { error, cacheKey });
    return null;
  }
};

const saveToCache = async <T>(
  cacheKey: string, 
  data: T, 
  ttl: number = DEFAULT_CACHE_TTL
): Promise<void> => {
  try {
    const expiryTime = Date.now() + ttl;
    const expiryKey = getCacheExpiryKey(cacheKey);
    
    await AsyncStorage.multiSet([
      [cacheKey, JSON.stringify(data)],
      [expiryKey, expiryTime.toString()]
    ]);
    
    logger.debug('API', 'Saved to cache', { cacheKey, ttl, expiryTime });
  } catch (error) {
    logger.error('API', 'Failed to save to cache', { error, cacheKey });
  }
};

const clearCache = async (pattern?: string): Promise<void> => {
  try {
    // Get all keys
    const allKeys = await AsyncStorage.getAllKeys();
    
    // Filter keys that match our cache pattern
    const cacheKeys = allKeys.filter(key => 
      key.startsWith(CACHE_PREFIX) || key.startsWith(CACHE_EXPIRY_PREFIX)
    );
    
    // If a specific pattern is provided, further filter the keys
    const keysToRemove = pattern 
      ? cacheKeys.filter(key => key.includes(pattern))
      : cacheKeys;
    
    if (keysToRemove.length > 0) {
      await AsyncStorage.multiRemove(keysToRemove);
      logger.info('API', `Cleared ${keysToRemove.length} cache entries`, { pattern });
    }
  } catch (error) {
    logger.error('API', 'Failed to clear cache', { error, pattern });
  }
};

// Create and configure Axios instance
const createApiClient = (): AxiosInstance => {
  const client = axios.create({
    baseURL: config.api.baseUrl,
    timeout: config.api.timeout,
  headers: {
    'Content-Type': 'application/json',
  },
});

  // Request interceptor for adding auth token and handling request config
  client.interceptors.request.use(
    async (config) => {
      const requestConfig = config as RequestConfig;
      
      // Check network connectivity before making request unless bypassed
      if (!requestConfig.bypassConnectionCheck) {
        // Use cached connectivity state if available, or check connectivity
        const { isConnected: connected, isInternetReachable } = await checkNetworkConnectivity();
        
        if (!connected) {
          logger.warn('API', 'Request cancelled - device is offline', { 
            url: requestConfig.url,
            method: requestConfig.method
          });
          throw new ApiError(
            'Your device appears to be offline. Please check your connection and try again.',
            'OFFLINE',
            0
          );
        }
        
        if (!isInternetReachable) {
          logger.warn('API', 'Request may fail - internet not reachable', { 
            url: requestConfig.url,
            method: requestConfig.method
          });
        }
      }
      
      // Check if we should try to get from cache
      if (requestConfig.cache && requestConfig.method?.toLowerCase() === 'get' && !requestConfig.forceRefresh) {
        const cacheKey = getCacheKey(requestConfig);
        const cachedResponse = await getFromCache<AxiosResponse>(cacheKey);
        
        if (cachedResponse) {
          // Return the cached response in a way that Axios will recognize
          // to short-circuit the actual HTTP request
          throw {
            config,
            response: cachedResponse,
            isAxiosCachedResponse: true
          };
        }
      }
      
      // Log the request
      logger.debug('API', `Request: ${config.method?.toUpperCase()} ${config.url}`, {
        headers: config.headers,
        params: config.params,
        data: config.data
      });
      
      // Get valid token using tokenService to ensure we always have a working token
      // This will automatically refresh token if needed
      const token = await tokenService.ensureValidToken();
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      } else {
        logger.debug('API', 'No auth token available for request');
      }
      
      return config;
    },
    (error) => {
      logger.error('API', 'Request setup error', { error: error.message });
      return Promise.reject(error);
    }
  );

  // Response interceptor for error handling, caching, and retries
  client.interceptors.response.use(
    async (response) => {
      const config = response.config as RequestConfig;
      
      // Cache the successful GET response if caching is enabled
      if (config.cache && config.method?.toLowerCase() === 'get') {
        const cacheKey = getCacheKey(config);
        const ttl = typeof config.cache === 'object' && config.cache.ttl 
          ? config.cache.ttl 
          : DEFAULT_CACHE_TTL;
          
        await saveToCache(cacheKey, response, ttl);
      }
      
      // Log successful response
      logger.debug('API', `Response: ${response.status} ${response.config.url}`, {
        data: response.data
      });
      
      return response;
    },
    async (error) => {
      // Check if this is our special cached response marker
      if (error.isAxiosCachedResponse) {
        logger.debug('API', 'Returned cached response', { url: error.config.url });
        return Promise.resolve(error.response);
      }
      
      const originalRequest = error.config as RequestConfig;
      const url = originalRequest?.url || 'unknown';
      const method = originalRequest?.method?.toUpperCase() || 'UNKNOWN';
      
      // Prepare detailed error info for logging
      const errorDetails = {
        url,
        method,
        status: error.response?.status,
        statusText: error.response?.statusText,
        headers: originalRequest?.headers,
        data: originalRequest?.data,
        responseData: error.response?.data,
        isNetworkError: !error.response,
        isTimeout: error.code === 'ECONNABORTED',
        errorName: error.name,
        errorMessage: error.message,
        errorCode: error.code
      };
      
      // Handle network connectivity errors
      if (!error.response) {
        // Update connectivity state
        await checkNetworkConnectivity();
        
        logger.error('API', `Network error for request: ${url}`, errorDetails);
        
        // Configure retry logic for network errors
        const shouldRetry = originalRequest.retry !== false;
        const retryConfig = typeof originalRequest.retry === 'object' 
          ? originalRequest.retry 
          : { count: 2, delay: 1000 };
        
        // Get current retry attempt
        const currentRetryAttempt = originalRequest._retryCount || 0;
        
        if (shouldRetry && currentRetryAttempt < retryConfig.count) {
          logger.info('API', `Retrying request due to network error (${currentRetryAttempt + 1}/${retryConfig.count})`, { 
            url, 
            method 
          });
          
          // Increment retry count
          originalRequest._retryCount = currentRetryAttempt + 1;
          
          // Create a new promise that will resolve after the retry delay
          return new Promise(resolve => {
            setTimeout(() => {
              resolve(apiClient(originalRequest));
            }, retryConfig.delay);
          });
        }
        
        // If we're out of retries, reject with a user-friendly message
        return Promise.reject(
          new ApiError(
            'Network connection error. Please check your internet connection and try again.',
            'NETWORK_ERROR',
            0,
            errorDetails
          )
        );
      }
      
      // Handle timeout errors
      if (error.code === 'ECONNABORTED') {
        logger.error('API', `Request timeout: ${url}`, errorDetails);
        return Promise.reject(
          new ApiError(
            'Request timed out. The server took too long to respond.',
            'TIMEOUT_ERROR',
            0,
            errorDetails
          )
        );
      }
      
      // Handle 401 Unauthorized errors (token expired)
      if (error.response?.status === 401 && !originalRequest._authRetry) {
        logger.warn('API', 'Authentication error, token might be expired', errorDetails);
        originalRequest._authRetry = true;
        
        // Try to refresh the token first
        try {
          logger.info('API', 'Attempting to refresh token due to 401 response');
          
          // Use tokenService to refresh token
          const newToken = await tokenService.ensureValidToken();
          
          if (newToken) {
            logger.info('API', 'Token refresh successful, retrying the original request');
            
            // Set the new auth token on the original request
            if (!originalRequest.headers) {
              originalRequest.headers = {};
            }
            originalRequest.headers.Authorization = `Bearer ${newToken}`;
            
            // Retry the original request with the new token
            return axios(originalRequest);
          } else {
            logger.warn('API', 'Token refresh failed - no new token returned');
          }
        } catch (refreshError) {
          logger.error('API', 'Error refreshing token', refreshError);
        }
        
        // If refresh failed, clear the invalid token
        await tokenService.clearAuthData();
        
        // Perform API reachability check (unchanged from before)
        try {
          const healthCheckResponse = await apiClient.get('/api/webhooks/health', {
            bypassConnectionCheck: true
          });
          
          // If we can reach the API but got a 401, it's definitely an auth issue
          if (healthCheckResponse.status === 200) {
            logger.info('API', 'API is reachable but auth token is invalid');
          }
        } catch (healthCheckError) {
          // Ignore any errors from the health check
        }
        
        return Promise.reject(
          new ApiError(
            'Your session has expired. Please reconnect to Square.',
            'AUTH_ERROR',
            401,
            errorDetails
          )
        );
      }
      
      // Handle server errors with retry
      if (error.response?.status >= 500) {
        const shouldRetry = originalRequest.retry !== false;
        const retryConfig = typeof originalRequest.retry === 'object' 
          ? originalRequest.retry 
          : { count: 1, delay: 1000, statusCodes: [502, 503, 504] };
          
        // Check if we should retry based on status code
        const shouldRetryStatus = !retryConfig.statusCodes || 
          retryConfig.statusCodes.includes(error.response.status);
        
        const currentRetryAttempt = originalRequest._retryCount || 0;
        
        if (shouldRetry && shouldRetryStatus && currentRetryAttempt < retryConfig.count) {
          logger.info('API', `Retrying request due to server error ${error.response.status} (${currentRetryAttempt + 1}/${retryConfig.count})`, { 
            url, 
            method 
          });
          
          // Increment retry count
          originalRequest._retryCount = currentRetryAttempt + 1;
          
          // Create a new promise that will resolve after the retry delay
          return new Promise(resolve => {
            setTimeout(() => {
              resolve(apiClient(originalRequest));
            }, retryConfig.delay);
          });
        }
      }
      
      // Log other response errors
      logger.error('API', `Response error: ${error.response?.status} ${url}`, errorDetails);
      
      // Format error response
      const errorData = error.response?.data as { error?: { message?: string, code?: string } } | undefined;
      const message = errorData?.error?.message || error.message || 'An error occurred while contacting the server';
      const code = errorData?.error?.code || `HTTP_${error.response?.status || 'ERROR'}`;
      const status = error.response?.status || 500;
      
      return Promise.reject(
        new ApiError(message, code, status, errorDetails)
      );
    }
  );

  return client;
};

// Create API instance
const apiClient = createApiClient();

// Initialize with a connectivity check
checkNetworkConnectivity();

// API service object
const api = {
  // Cache management
  cache: {
    clear: clearCache
  },
  
  // Network checks
  network: {
    checkConnectivity: checkNetworkConnectivity
  },
  
  // Authentication endpoints
  auth: {
    getConnectUrl: async () => {
      try {
        logger.info('API', 'Getting Square connect URL');
        // Note: Not used anymore as we build the URL manually
        const response = await apiClient.get(config.square.endpoints.connect);
        return response.data;
      } catch (error) {
        logger.error('API', 'Failed to get Square connect URL', { error });
        throw error;
      }
    },
    
    validateToken: async () => {
      try {
        // Check if there's a token first
        const token = await getAuthToken();
        if (!token) {
          console.log('API - No token found for validation');
          return {
            success: false,
            isValid: false,
            error: 'No authentication token found'
          };
        }
        
        // Set authorization header with token
        const headers = await getAuthHeaders();
        
        // Make a simple request to verify token
        const response = await axios.get(`${config.api.baseUrl}/api/auth/validate-token`, { 
          headers 
        });
        
        return { 
          success: true,
          isValid: true,
          data: response.data
        };
      } catch (error: any) {
        logger.error('API', 'Token validation failed', { error });
        
        // Check for specific error types
        if (error.response?.status === 401) {
          console.log('API - Token is invalid (401 Unauthorized)');
          return {
            success: false,
            isValid: false,
            error: 'Authentication token is invalid or expired'
          };
        }
        
        return { 
          success: false,
          isValid: false,
          error: error instanceof Error ? error.message : 'Unknown error'
        };
      }
    },
    
    registerState: async (payload: { state: string; request_id: string; code_verifier: string; client_id: string; timestamp: number }): Promise<any> => {
      try {
        logger.info('API', 'Registering state with backend', {
          requestId: payload.request_id,
          timestamp: new Date().toISOString()
        });
        
        console.log('API - Registering state with backend');
        
        // Ensure the endpoint is correctly defined in config
        const registerStateUrl = config.square.endpoints.registerState;
        if (!registerStateUrl) {
          logger.error('API', 'State registration URL not configured');
          throw new Error('State registration URL not configured');
        }
        
        // Make the request with proper headers
        const response = await axios.post(registerStateUrl, payload, {
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'JoyLabsApp/1.0.0',
            // Add Square version header for consistency
            'Square-Version': '2025-01-23'
          },
          timeout: 10000 // 10 second timeout
        });
        
        logger.info('API', 'State registration successful', {
          statusCode: response.status,
          responseData: JSON.stringify(response.data || {}).substring(0, 100)
        });
        
        return {
          success: true,
          data: response.data
        };
      } catch (error: any) {
        // Handle 403 Forbidden errors specifically
        if (error.response && error.response.status === 403) {
          logger.error('API', 'State registration failed with 403 Forbidden', {
            message: error.message,
            serverMessage: error.response.data?.message || 'No message from server',
            errorCode: error.response.data?.error || 'unknown_error',
            timestamp: new Date().toISOString()
          });
          
          throw new Error('Authorization denied for state registration. Please check API credentials (403 Forbidden)');
        }
        
        // Handle network timeouts
        if (error.code === 'ECONNABORTED') {
          logger.error('API', 'State registration request timed out', {
            message: error.message,
            timestamp: new Date().toISOString()
          });
          
          throw new Error('Server took too long to respond during state registration. Please try again.');
        }
        
        // Log other errors
        logger.error('API', 'State registration failed', {
          message: error.message,
          statusCode: error.response?.status,
          errorData: error.response?.data,
          isAxiosError: error.isAxiosError,
          timestamp: new Date().toISOString()
        });
        
        // Provide a specific error message based on the status code
        if (error.response) {
          switch (error.response.status) {
            case 400:
              throw new Error('Invalid state registration request (400 Bad Request)');
            case 401:
              throw new Error('Unauthorized state registration request (401 Unauthorized)');
            case 404:
              throw new Error('State registration endpoint not found (404 Not Found)');
            case 500:
            case 502:
            case 503:
            case 504:
              throw new Error('Server error during state registration. Please try again later.');
            default:
              throw new Error(`State registration failed: ${error.message}`);
          }
        }
        
        throw error;
      }
    },
    
    exchangeToken: async (code: string, codeVerifier: string): Promise<any> => {
      try {
        logger.info('API', 'Starting Square token exchange', {
          timestamp: new Date().toISOString()
        });
        
        console.log('API - Exchanging code for Square token');
        
        // Make sure Square credentials are loaded
        if (!config.square || !config.square.appId) {
          throw new Error('Square configuration not loaded');
        }
        
        // Get client ID and redirect URI from config
        const clientId = config.square.appId;
        const redirectUri = config.square.endpoints.callback;
        
        // Log the parameters used (without exposing secrets)
        logger.debug('API', 'Token exchange parameters', {
          clientIdPresent: !!clientId,
          codeVerifierLength: codeVerifier?.length || 0,
          codeLength: code?.length || 0,
          redirectUri: redirectUri
        });
        
        // Create the request payload
        const payload = {
          client_id: clientId,
          grant_type: 'authorization_code',
          code,
          code_verifier: codeVerifier,
          redirect_uri: redirectUri,
          response_type: 'code'
        };
        
        logger.debug('API', 'Token exchange request details', {
          codePrefix: code.substring(0, 5),
          codeVerifierPrefix: codeVerifier.substring(0, 5),
          timestamp: new Date().toISOString()
        });
        
        console.log('API - Sending token exchange request to Square API');
        
        // Get the token URL from config
        const tokenUrl = config.square.endpoints.token;
        if (!tokenUrl) {
          logger.error('API', 'Square token URL not configured');
          throw new Error('Square token URL not configured');
        }
        
        // Make the request with proper headers required by Square
        const response = await axios.post(tokenUrl, payload, {
                headers: { 
                  'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'JoyLabsApp/1.0.0',
            'Square-Version': '2025-01-23' // Latest version
          },
          timeout: 15000 // 15 second timeout for token exchange
        });
        
        logger.info('API', 'Square token exchange successful', {
          statusCode: response.status,
          hasAccessToken: !!response.data.access_token,
          hasMerchantId: !!response.data.merchant_id,
          tokenType: response.data.token_type,
          expiresIn: response.data.expires_in,
          responseData: JSON.stringify(response.data).substring(0, 100) + '...'
        });
        
        console.log('API - Square token exchange successful');
        
        // Save the access token
        await setAuthToken(response.data.access_token);
        
        return response.data;
      } catch (error: any) {
        // Check if this is a 403 Forbidden error, which could indicate server-side validation issues
        if (error.response && error.response.status === 403) {
          logger.error('API', 'Square token exchange failed with 403 Forbidden', {
            message: error.message,
            serverMessage: error.response.data?.message || 'No message from server',
            errorCode: error.response.data?.error || 'unknown_error',
            timestamp: new Date().toISOString(),
            request: {
              url: error.config?.url,
              headers: error.config?.headers,
              data: JSON.stringify(error.config?.data || {}).substring(0, 500)
            },
            response: JSON.stringify(error.response?.data || {}).substring(0, 500)
          });
          
          console.error('API - Square token exchange 403 Forbidden error', error.response.data);
          
          // Provide more detailed error information based on the response
          let errorMessage = 'Authorization rejected by Square (403 Forbidden)';
          if (error.response.data?.error === 'invalid_request') {
            errorMessage = 'Invalid request parameters for token exchange';
          } else if (error.response.data?.error === 'invalid_grant') {
            errorMessage = 'Invalid authorization code or code verifier';
          } else if (error.response.data?.error === 'invalid_client') {
            errorMessage = 'Invalid client credentials';
          }
          
          throw new Error(errorMessage);
        }
        
        // Handle network timeouts specifically
        if (error.code === 'ECONNABORTED') {
          logger.error('API', 'Square token exchange request timed out', {
            message: error.message,
            timestamp: new Date().toISOString()
          });
          
          throw new Error('Square server took too long to respond. Please try again.');
        }
        
        // Log other types of errors
        logger.error('API', 'Square token exchange failed', {
          message: error.message,
          statusCode: error.response?.status,
          errorData: error.response?.data,
          isAxiosError: error.isAxiosError,
          timestamp: new Date().toISOString(),
          fullError: JSON.stringify(error || {}).substring(0, 500)
        });
        
        console.error('API - Error exchanging code for Square token:', error);
        
        // Provide a specific error message based on the status code
        if (error.response) {
          switch (error.response.status) {
            case 400:
              throw new Error('Invalid request to Square API (400 Bad Request): ' + 
                (error.response.data?.message || error.message));
            case 401:
              throw new Error('Unauthorized request to Square API (401 Unauthorized)');
            case 404:
              throw new Error('Square API endpoint not found (404 Not Found)');
            case 500:
            case 502:
            case 503:
            case 504:
              throw new Error('Square API server error. Please try again later.');
            default:
              throw new Error(`Square token exchange failed: ${error.message}`);
          }
        }
        
        throw error;
      }
    },
    
    logout: async () => {
      try {
        logger.info('API', 'Logging out user and clearing auth token');
        await clearAuthToken();
        // Clear all cached API responses when logging out
        await clearCache();
        return { success: true };
      } catch (error) {
        logger.error('API', 'Error during logout', { error });
        throw error;
      }
    },

    // Get Square credentials directly from AWS Secrets Manager
    // This is a direct implementation based on AWS's example code
    fetchSquareCredentialsDirectly: async () => {
      // This function is no longer needed as backend team confirmed the correct URLs
      logger.info('API', 'This function is deprecated - backend handles secrets');
      return { success: true };
    },

    // Direct AWS Secrets Manager call using special endpoint
    // This bypasses any abstraction and directly calls AWS SDK
    getSecretFromAWS: async (secretName: string) => {
      // This function is no longer needed as backend team confirmed the correct URLs
      logger.info('API', 'This function is deprecated - backend handles secrets');
      return { success: true };
    },

    // Update token refresh method to use tokenService
    refreshToken: async () => {
      try {
        logger.info('API', 'Attempting to refresh Square access token');
        const newToken = await tokenService.ensureValidToken();
        
        if (newToken) {
          return {
            success: true,
            access_token: newToken
          };
        }
        
        return {
          success: false,
          error: 'Failed to refresh token'
        };
      } catch (error) {
        logger.error('API', 'Failed to refresh Square token', error);
        throw error;
      }
    },
  },
  
  // Catalog endpoints
  catalog: {
    getItems: async (page = 1, limit = 20, types = 'ITEM') => {
      try {
        const endpoint = config.square.endpoints.catalogItems;
        const url = `${endpoint}?page=${page}&limit=${limit}&types=${encodeURIComponent(types)}`;
        
        logger.info('API', 'Fetching catalog items', { page, limit, types });
        
        // Use caching for catalog items with a reasonable TTL
        const ttl = 5 * 60 * 1000; // 5 minutes
        
        const response = await apiClient.get(url, {
              cache: { ttl }
            });
        
        // Add basic validation of response
        if (!response.data || !response.data.success) {
          logger.warn('API', 'Catalog items response is missing success flag', { response: response.data });
        }
        
    return response.data;
      } catch (error) {
        logger.error('API', 'Failed to fetch catalog items', { error, page, limit, types });
        throw error;
      }
    },
    
    getItemById: async (id: string) => {
      try {
        logger.info('API', `Fetching catalog item by ID: ${id}`);
        const url = `${config.square.endpoints.catalogItem}/${id}`;
        const response = await apiClient.get(url, {
          cache: { ttl: 10 * 60 * 1000 } // Cache individual items longer - 10 minutes
        });
    return response.data;
      } catch (error) {
        logger.error('API', `Failed to fetch catalog item by ID: ${id}`, { error });
        throw error;
      }
    },
    
    createItem: async (itemData: any) => {
      try {
        logger.info('API', 'Creating new catalog item', { item: itemData });
        const url = config.square.endpoints.catalogItem;
        const response = await apiClient.post(url, itemData, {
          retry: { count: 2, delay: 1000 } // Retry important write operations
        });
        
        // Clear item cache after creating a new item
        await clearCache(config.square.endpoints.catalogItems);
        
    return response.data;
      } catch (error) {
        logger.error('API', 'Failed to create catalog item', { error, item: itemData });
        throw error;
      }
    },
    
    updateItem: async (id: string, itemData: any) => {
      try {
        logger.info('API', `Updating catalog item: ${id}`, { item: itemData });
        
        // For updates, we use the same endpoint as create but include the id in the data
        const url = config.square.endpoints.catalogItem;
        const response = await apiClient.post(url, {
          ...itemData,
          id // Make sure the ID is included in the update payload
        }, {
          retry: { count: 2, delay: 1000 } // Retry important write operations
        });
        
        // Clear specific item cache and list cache
        await clearCache(`${config.square.endpoints.catalogItem}/${id}`);
        await clearCache(config.square.endpoints.catalogItems);
        
    return response.data;
      } catch (error) {
        logger.error('API', `Failed to update catalog item: ${id}`, { error, item: itemData });
        throw error;
      }
    },
    
    deleteItem: async (id: string) => {
      try {
        logger.info('API', `Deleting catalog item: ${id}`);
        const url = `${config.square.endpoints.catalogItem}/${id}`;
        const response = await apiClient.delete(url, {
          retry: { count: 2, delay: 1000 } // Retry important write operations
        });
        
        // Clear item and list caches after deletion
        await clearCache(`${config.square.endpoints.catalogItem}/${id}`);
        await clearCache(config.square.endpoints.catalogItems);
        
    return response.data;
      } catch (error) {
        logger.error('API', `Failed to delete catalog item: ${id}`, { error });
        throw error;
      }
    },
    
    searchItems: async (searchParams: any) => {
      try {
        logger.info('API', 'Searching catalog items', { searchParams });
        
        // Ensure we're using the proper search format as documented
        // If object_types is not provided, default to ITEM
        const enhancedParams = {
          ...searchParams
        };
        
        // If object_types is not explicitly set and we're not using a complex query
        if (!searchParams.object_types && !searchParams.query?.exact_query) {
          enhancedParams.object_types = ['ITEM'];
        }
        
        // Use a custom cache key based on the search params to allow caching search results
        const cacheKey = `search_${JSON.stringify(enhancedParams)}`;
        
        // Use the properly formatted search endpoint directly
        const url = `${config.api.baseUrl}/v2/catalog/search`;
        const response = await apiClient.post(url, enhancedParams, {
          cache: { 
            key: cacheKey,
            ttl: 2 * 60 * 1000 // Cache search results for 2 minutes
          }
        });
        
        return response.data;
      } catch (error) {
        logger.error('API', 'Failed to search catalog items', { error, searchParams });
        throw error;
      }
    },
    
    getCategories: async () => {
      try {
        logger.info('API', 'Fetching catalog categories using dedicated endpoint');
        
        // Use the dedicated categories endpoint
        const url = config.square.endpoints.catalogListCategories;
        const cacheKey = 'categories_list';
        
        logger.debug('API', 'Categories request params', { url });
        
        const response = await apiClient.get(url, {
          cache: { 
            key: cacheKey,
            ttl: 5 * 60 * 1000 // Cache categories for 5 minutes
          }
        });
        
        // Add success flag if needed based on objects field
        if (!response.data.hasOwnProperty('success')) {
          response.data.success = !!response.data.objects;
        }
        
        // Log detailed response information for debugging
        logger.debug('API', 'Categories response details', {
          success: response.data.success,
          hasObjects: !!response.data.objects,
          objectCount: response.data.objects?.length || 0,
          hasCursor: !!response.data.cursor,
          count: response.data.count,
          metadataExists: !!response.data.metadata,
          status: response.status
        });
        
        return response.data;
      } catch (error) {
        logger.error('API', 'Failed to fetch categories', { error });
        throw error;
      }
    },
    
    searchCategories: async (namePrefix?: string, limit = 100) => {
      try {
        logger.info('API', 'Searching catalog categories', { namePrefix, limit });
        
        // Build the search request as specified in the backend documentation
        const searchParams: any = {
          object_types: ["CATEGORY"],
          limit
        };
        
        // Add appropriate query type based on input
        if (namePrefix) {
          // Use prefix query when a prefix is provided
          searchParams.query = {
            prefix_query: {
              attribute_name: "name",
              attribute_prefix: namePrefix
            }
          };
        } else {
          // Use text query with empty string to get all categories when no prefix
          searchParams.query = {
            text_query: {
              query: ""
            }
          };
        }
        
        // Use a custom cache key
        const cacheKey = `search_categories_${namePrefix || 'all'}_${limit}`;
        
        logger.debug('API', 'Category search request params', { 
          namePrefix, 
          limit,
          searchParams: JSON.stringify(searchParams)
        });
        
        // Use the search endpoint directly
        const url = config.square.endpoints.catalogSearch;
        const response = await apiClient.post(url, searchParams, {
          cache: { 
            key: cacheKey,
            ttl: 5 * 60 * 1000 // Cache category searches for 5 minutes
          }
        });
        
        // Add success flag if needed
        if (!response.data.hasOwnProperty('success')) {
          response.data.success = !!response.data.objects;
        }
        
        return response.data;
      } catch (error) {
        logger.error('API', 'Failed to search categories', { error, namePrefix });
        throw error;
      }
    }
  },
  
  // Products lookup by barcode
  products: {
    getByBarcode: async (barcode: string) => {
      try {
        logger.info('API', `Looking up product by barcode: ${barcode}`);
        
        const url = `/api/products/barcode/${encodeURIComponent(barcode)}`;
        const response = await apiClient.get(url, {
          cache: { ttl: 30 * 60 * 1000 }, // Cache barcode lookups for 30 minutes
          retry: { count: 2, delay: 1000 }
        });
        
    return response.data;
      } catch (error) {
        logger.error('API', `Failed to lookup product by barcode: ${barcode}`, { error });
        throw error;
      }
    }
  },
  
  // Webhook management
  webhooks: {
    healthCheck: async () => {
      try {
        logger.info('API', 'Performing API health check');
        const url = '/api/webhooks/health';
        const response = await apiClient.get(url, {
          // Don't cache health checks, and bypass connection check to avoid loops
          cache: false,
          bypassConnectionCheck: true,
          timeout: 5000 // Shorter timeout for health checks
        });
        
        if (response.data && response.data.success) {
          logger.info('API', 'Health check successful');
        } else {
          logger.warn('API', 'Health check response missing success flag', { response: response.data });
        }
        
    return response.data;
      } catch (error) {
        logger.error('API', 'Health check failed', { error });
        throw error;
      }
    },
    
    getWebhooks: async (page: number = 1, limit: number = 20) => {
      try {
        const url = `${config.square.endpoints.webhooks}?page=${page}&limit=${limit}`;
        
        logger.info('API', 'Fetching webhooks', { page, limit });
        
        // Check if we have permission to access webhooks
        const token = await getAuthToken();
        if (!token) {
          logger.info('API', 'Not authorized to fetch webhooks - no token');
          return { success: false, webhooks: [], message: 'Not authenticated' };
        }
        
        const response = await apiClient.get(url, {
          cache: { 
            ttl: 5 * 60 * 1000 // Cache webhooks for 5 minutes
          },
          // Disable retries for webhooks to prevent continuous 401 errors
          retry: false
        });
        return response.data;
      } catch (error: any) {
        // Handle 401 errors without rethrowing to prevent continuous retries
        if (error.response && error.response.status === 401) {
          logger.warn('API', 'Not authorized to fetch webhooks - 401 Unauthorized', { page, limit });
          return { success: false, webhooks: [], message: 'Unauthorized' };
        }
        
        // Handle 403 errors related to insufficient permissions
        if (error.response && error.response.status === 403) {
          logger.warn('API', 'Insufficient permissions to fetch webhooks - 403 Forbidden', { page, limit });
          return { success: false, webhooks: [], message: 'Insufficient permissions' };
        }
        
        // For other errors, log but don't throw
        logger.error('API', 'Failed to fetch webhooks', { 
          error: error.message, 
          status: error.response?.status, 
          page, 
          limit 
        });
        return { success: false, webhooks: [], message: error.message || 'Unknown error' };
      }
    }
  }
};

export { api, apiClient, getAuthToken, getAuthHeaders, setAuthToken, clearAuthToken, appendSecretName, getSecretName };
export default api;