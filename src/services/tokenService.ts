import * as SecureStore from 'expo-secure-store';
import logger from '../utils/logger';
import axios from 'axios';
import config from '../config';

// Token storage keys
export const TOKEN_KEYS = {
  ACCESS_TOKEN: 'square_access_token',
  REFRESH_TOKEN: 'square_refresh_token',
  MERCHANT_ID: 'square_merchant_id',
  BUSINESS_NAME: 'square_business_name',
  TOKEN_EXPIRY: 'square_token_expiry',
};

// Token validation statuses
export type TokenStatus = 'valid' | 'expired' | 'missing' | 'unknown';

// Token info interface
export interface TokenInfo {
  accessToken: string | null;
  refreshToken: string | null;
  merchantId: string | null;
  businessName: string | null;
  expiresAt: string | null;
  status: TokenStatus;
}

/**
 * TokenService provides a centralized way to manage authentication tokens
 * throughout the application, serving as a single source of truth.
 */
class TokenService {
  private tokenRefreshPromise: Promise<string | null> | null = null;

  /**
   * Get the current access token
   * @returns Promise resolving to the token string or null if not available
   */
  async getAccessToken(): Promise<string | null> {
    try {
      const token = await SecureStore.getItemAsync(TOKEN_KEYS.ACCESS_TOKEN);
      
      if (token) {
        logger.debug('TokenService', `Retrieved access token (length: ${token.length})`);
        return token;
      } else {
        logger.debug('TokenService', 'No access token found');
        return null;
      }
    } catch (error) {
      logger.error('TokenService', 'Error retrieving access token', error);
      return null;
    }
  }

  /**
   * Get authorization headers for API requests
   * @returns Object containing Authorization header with Bearer token
   */
  async getAuthHeaders(): Promise<Record<string, string>> {
    const token = await this.getAccessToken();
    if (token) {
      return { 'Authorization': `Bearer ${token}` };
    }
    return {};
  }

  /**
   * Store a new access token
   * @param token The access token to store
   * @returns Promise that resolves when the token is stored
   */
  async setAccessToken(token: string): Promise<void> {
    try {
      logger.debug('TokenService', `Storing access token (length: ${token.length})`);
      await SecureStore.setItemAsync(TOKEN_KEYS.ACCESS_TOKEN, token);
      
      // Verify storage
      const storedToken = await SecureStore.getItemAsync(TOKEN_KEYS.ACCESS_TOKEN);
      if (!storedToken || storedToken !== token) {
        logger.error('TokenService', 'Token verification failed after storage');
        throw new Error('Failed to store access token - verification failed');
      }
      
      logger.info('TokenService', '✅ Access token stored and verified');
    } catch (error) {
      logger.error('TokenService', 'Error storing access token', error);
      throw error;
    }
  }

  /**
   * Store refresh token
   * @param token The refresh token to store
   */
  async setRefreshToken(token: string): Promise<void> {
    try {
      logger.debug('TokenService', `Storing refresh token (length: ${token.length})`);
      await SecureStore.setItemAsync(TOKEN_KEYS.REFRESH_TOKEN, token);
      logger.debug('TokenService', '✅ Refresh token stored');
    } catch (error) {
      logger.error('TokenService', 'Error storing refresh token', error);
      throw error;
    }
  }

  /**
   * Store merchant information
   * @param merchantId Square merchant ID
   * @param businessName Business name
   */
  async setMerchantInfo(merchantId: string, businessName: string): Promise<void> {
    try {
      await SecureStore.setItemAsync(TOKEN_KEYS.MERCHANT_ID, merchantId);
      await SecureStore.setItemAsync(TOKEN_KEYS.BUSINESS_NAME, businessName);
      logger.debug('TokenService', '✅ Merchant info stored');
    } catch (error) {
      logger.error('TokenService', 'Error storing merchant info', error);
      throw error;
    }
  }

  /**
   * Store token expiration time
   * @param expiryTime ISO string representing expiry time
   */
  async setTokenExpiry(expiryTime: string): Promise<void> {
    try {
      await SecureStore.setItemAsync(TOKEN_KEYS.TOKEN_EXPIRY, expiryTime);
      logger.debug('TokenService', `✅ Token expiry set: ${expiryTime}`);
    } catch (error) {
      logger.error('TokenService', 'Error storing token expiry', error);
      throw error;
    }
  }

  /**
   * Clear all authentication data
   */
  async clearAuthData(): Promise<void> {
    try {
      await SecureStore.deleteItemAsync(TOKEN_KEYS.ACCESS_TOKEN);
      await SecureStore.deleteItemAsync(TOKEN_KEYS.REFRESH_TOKEN);
      await SecureStore.deleteItemAsync(TOKEN_KEYS.TOKEN_EXPIRY);
      logger.info('TokenService', '🧹 Auth tokens cleared');
    } catch (error) {
      logger.error('TokenService', 'Error clearing auth data', error);
      throw error;
    }
  }

  /**
   * Check if token is valid or needs refresh
   */
  async checkTokenStatus(): Promise<TokenStatus> {
    try {
      // Check if token exists
      const token = await this.getAccessToken();
      if (!token) {
        logger.debug('TokenService', 'No token found');
        return 'missing';
      }
      
      // Check if token has expired based on stored expiry
      const expiryTime = await SecureStore.getItemAsync(TOKEN_KEYS.TOKEN_EXPIRY);
      if (expiryTime) {
        const expiry = new Date(expiryTime);
        const now = new Date();
        
        // If token will expire in the next 5 minutes, consider it expired
        const fiveMinutesFromNow = new Date(now.getTime() + 5 * 60 * 1000);
        
        if (expiry < fiveMinutesFromNow) {
          logger.debug('TokenService', 'Token is expired or will expire soon');
          return 'expired';
        }
      }
      
      // Skip server validation since endpoint is missing (404 error in logs)
      // Just assume token is valid if we have one and it's not expired based on local data
      if (token && (!expiryTime || new Date(expiryTime) > new Date())) {
        logger.debug('TokenService', 'Using local validation only - assuming token is valid');
        return 'valid';
      }
      
      return 'unknown';
    } catch (error) {
      logger.error('TokenService', 'Error checking token status', error);
      return 'unknown';
    }
  }

  /**
   * Validate token and refresh if necessary
   * Uses promise caching to prevent multiple simultaneous refresh attempts
   */
  async ensureValidToken(): Promise<string | null> {
    const status = await this.checkTokenStatus();
    
    if (status === 'valid') {
      return this.getAccessToken();
    }
    
    if (status === 'expired' || status === 'unknown') {
      // If a refresh is already in progress, return that promise
      if (this.tokenRefreshPromise) {
        logger.debug('TokenService', 'Token refresh already in progress, reusing promise');
        return this.tokenRefreshPromise;
      }
      
      // Start a new refresh
      this.tokenRefreshPromise = this.refreshToken();
      
      try {
        const newToken = await this.tokenRefreshPromise;
        return newToken;
      } finally {
        this.tokenRefreshPromise = null;
      }
    }
    
    return null;
  }

  /**
   * Refresh the authentication token
   */
  private async refreshToken(): Promise<string | null> {
    try {
      logger.info('TokenService', 'Attempting to refresh access token');
      
      // Get the refresh token
      const refreshToken = await SecureStore.getItemAsync(TOKEN_KEYS.REFRESH_TOKEN);
      
      if (!refreshToken) {
        logger.error('TokenService', 'No refresh token available for token refresh');
        return null;
      }
      
      // Build the request
      const clientId = config.square.appId;
      const payload = {
        client_id: clientId,
        grant_type: 'refresh_token',
        refresh_token: refreshToken
      };
      
      const tokenUrl = config.square.endpoints.token;
      
      // Make the request to Square API
      const response = await axios.post(tokenUrl, payload, {
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'JoyLabsApp/1.0.0',
          'Square-Version': '2025-01-23' // Latest version
        },
        timeout: 15000
      });
      
      // Store the new tokens
      if (response.data.access_token) {
        await this.setAccessToken(response.data.access_token);
        
        // Store new refresh token if provided
        if (response.data.refresh_token) {
          await this.setRefreshToken(response.data.refresh_token);
        }
        
        // Calculate and store expiry time
        if (response.data.expires_in) {
          const expiresInMs = response.data.expires_in * 1000;
          const expiryTime = new Date(Date.now() + expiresInMs).toISOString();
          await this.setTokenExpiry(expiryTime);
        }
        
        logger.info('TokenService', '🔄 Access token refreshed successfully');
        return response.data.access_token;
      }
      
      return null;
    } catch (error) {
      logger.error('TokenService', 'Failed to refresh token', error);
      return null;
    }
  }

  /**
   * Store complete auth data from OAuth callback
   */
  async storeAuthData(data: {
    access_token: string;
    refresh_token?: string;
    merchant_id?: string;
    business_name?: string;
    expires_in?: number;
  }): Promise<void> {
    try {
      // Store access token
      await this.setAccessToken(data.access_token);
      
      // Store refresh token if available
      if (data.refresh_token) {
        await this.setRefreshToken(data.refresh_token);
      }
      
      // Store merchant info if available
      if (data.merchant_id && data.business_name) {
        await this.setMerchantInfo(data.merchant_id, data.business_name);
      }
      
      // Calculate and store expiry time
      if (data.expires_in) {
        const expiresInMs = data.expires_in * 1000;
        const expiryTime = new Date(Date.now() + expiresInMs).toISOString();
        await this.setTokenExpiry(expiryTime);
      }
      
      logger.info('TokenService', '✅ Complete auth data stored successfully');
    } catch (error) {
      logger.error('TokenService', 'Error storing complete auth data', error);
      throw error;
    }
  }

  /**
   * Get all token information
   */
  async getTokenInfo(): Promise<TokenInfo> {
    try {
      const [accessToken, refreshToken, merchantId, businessName, expiresAt] = await Promise.all([
        SecureStore.getItemAsync(TOKEN_KEYS.ACCESS_TOKEN),
        SecureStore.getItemAsync(TOKEN_KEYS.REFRESH_TOKEN),
        SecureStore.getItemAsync(TOKEN_KEYS.MERCHANT_ID),
        SecureStore.getItemAsync(TOKEN_KEYS.BUSINESS_NAME),
        SecureStore.getItemAsync(TOKEN_KEYS.TOKEN_EXPIRY)
      ]);
      
      const status = await this.checkTokenStatus();
      
      return {
        accessToken,
        refreshToken,
        merchantId,
        businessName,
        expiresAt,
        status
      };
    } catch (error) {
      logger.error('TokenService', 'Error getting token info', error);
      return {
        accessToken: null,
        refreshToken: null,
        merchantId: null,
        businessName: null,
        expiresAt: null,
        status: 'unknown'
      };
    }
  }
}

// Export singleton instance
export const tokenService = new TokenService();
export default tokenService; 