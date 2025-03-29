import React, { useEffect, useState } from 'react';
import { View, Text, ActivityIndicator, StyleSheet, Platform } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSquareAuth } from '../../src/hooks/useSquareAuth';
import * as SecureStore from 'expo-secure-store';
import logger from '../../src/utils/logger';

export default function AuthSuccess() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const { processCallback } = useSquareAuth();
  const [isReady, setIsReady] = useState(false);
  const [status, setStatus] = useState('Preparing authentication...');
  const [error, setError] = useState<string | null>(null);
  
  // First effect to ensure component is mounted before attempting any navigation
  useEffect(() => {
    // Log the component mount
    console.log(`AUTH SUCCESS - Component mounted on ${Platform.OS} at ${new Date().toISOString()}`);
    logger.info('Auth', 'Auth success component mounted', {
      platform: Platform.OS,
      timestamp: new Date().toISOString()
    });
    
    // Give the app time to mount properly before doing any navigation
    const timer = setTimeout(() => {
      console.log('AUTH SUCCESS - Component ready to process callback');
      setIsReady(true);
    }, 1000);
    
    return () => clearTimeout(timer);
  }, []);
  
  // Second effect that only runs after the component is fully ready
  useEffect(() => {
    // Only proceed if the component is ready
    if (!isReady) return;
    
    const handleCallback = async () => {
      try {
        logger.info('Auth', 'Starting callback processing');
        console.log('AUTH SUCCESS - Starting callback processing');
        console.log('AUTH SUCCESS - Raw params:', JSON.stringify(params, null, 2));
        
        // Get the code and state from URL params
        const code = params.code as string;
        const state = params.state as string;
        const reqId = params.request_id as string;
        
        // Detect test values with IMPROVED detection
        const isTestCode = !code || 
                          code === 'undefined' || 
                          code?.includes('test') || 
                          code === 'sq0csp-test' || 
                          code === 'sq0csp-123';
        
        const isTestState = !state || 
                           state === 'undefined' || 
                           state?.includes('test') || 
                           state === 'test_state' || 
                           state === 'test_success_state';
        
        const isTestRequestId = !reqId || 
                               reqId === 'undefined' || 
                               reqId === '123' || 
                               reqId === 'test_request_id';
        
        // Log the detection
        logger.debug('Auth', 'Callback parameter validation', {
          hasCode: !!code,
          hasState: !!state,
          hasRequestId: !!reqId,
          isTestCode,
          isTestState,
          isTestRequestId
        });
        
        // Check if we have any stored auth data at all
        const hasStoredState = await SecureStore.getItemAsync('square_auth_state');
        const hasStoredRequestId = await SecureStore.getItemAsync('square_auth_request_id');
        
        // If storage is empty or contains test values, user likely direct-navigated 
        // to this screen without initiating a proper Square auth flow
        const isMissingStoredData = !hasStoredState || !hasStoredRequestId;
        
        // Early exit - either test data or missing stored data should go to profile
        if (isTestCode || isTestState || isTestRequestId || isMissingStoredData) {
          logger.info('Auth', 'Invalid auth data - redirecting to profile', {
            isTestCode,
            isTestState,
            isTestRequestId,
            isMissingStoredData
          });
          
          console.log('AUTH SUCCESS - Invalid auth data detected:', {
            isTestCode,
            isTestState,
            isTestRequestId,
            isMissingStoredData,
            codePresent: !!code,
            statePresent: !!state
          });
          
          setStatus('No valid auth data');
          setError('Missing or invalid authentication data');
          
          // Redirect to profile after a short delay to allow logging
          setTimeout(() => {
            requestAnimationFrame(() => {
              router.replace('/profile');
            });
          }, 1000);
          return;
        }
        
        setStatus('Processing authentication...');
        console.log('AUTH SUCCESS - URL search params:', {
          code: code.substring(0, 5) + '...',
          state: state.substring(0, 5) + '...',
          request_id: params.request_id
        });
        
        // Get the stored state for comparison
        const storedState = await SecureStore.getItemAsync('square_auth_state');
        const storedRequestId = await SecureStore.getItemAsync('square_auth_request_id');
        const storedCodeVerifier = await SecureStore.getItemAsync('square_auth_code_verifier');
        
        console.log('AUTH SUCCESS - Stored values:', {
          storedState: storedState ? storedState.substring(0, 5) + '...' : null,
          storedRequestId,
          storedCodeVerifier: storedCodeVerifier ? storedCodeVerifier.substring(0, 5) + '...' : null,
          storedStateLength: storedState?.length,
          storedRequestIdLength: storedRequestId?.length,
          storedCodeVerifierLength: storedCodeVerifier?.length
        });
        
        // Extract request_id from state parameter if it's in the combined format
        let requestId = params.request_id as string;
        if (!requestId && state && state.includes(':')) {
          const [_, extractedRequestId] = state.split(':');
          requestId = extractedRequestId;
          console.log('AUTH SUCCESS - Extracted request_id from state:', requestId);
        }
        
        // If we still have no valid data, redirect to profile
        if (!code || !state) {
          console.error('AUTH SUCCESS - Missing required parameters:', { code: !!code, state: !!state });
          setStatus('Missing required parameters');
          setError('Missing required authentication parameters');
          
          setTimeout(() => {
            requestAnimationFrame(() => {
              router.replace('/profile');
            });
          }, 2000);
          return;
        }
        
        // Validate state matches, but if we don't have a stored state, continue anyway
        // This prevents getting stuck during development when stored state is cleared
        if (storedState && state !== storedState) {
          console.error('AUTH SUCCESS - State validation failed:', {
            received: state.substring(0, 5) + '...',
            stored: storedState.substring(0, 5) + '...',
            match: state === storedState,
            receivedLength: state.length,
            storedLength: storedState.length
          });
          
          setStatus('State validation failed');
          setError('Invalid authentication state');
          
          // Instead of throwing, just redirect to profile with error
          setTimeout(() => {
            requestAnimationFrame(() => {
              router.replace({
                pathname: '/profile',
                params: { error: 'Invalid authentication state' }
              });
            });
          }, 2000);
          return;
        }
        
        // Create URL params
        const urlParams = new URLSearchParams();
        urlParams.append('code', code);
        urlParams.append('state', state);
        if (requestId) {
          urlParams.append('request_id', requestId);
        }
        
        // Reconstruct the callback URL
        const callbackUrl = `joylabs://auth/success?${urlParams.toString()}`;
        console.log('AUTH SUCCESS - Reconstructed callback URL:', callbackUrl);
        
        // Process the callback with a timeout to prevent hanging
        console.log('AUTH SUCCESS - Calling processCallback...');
        setStatus('Exchanging authorization code...');
        
        // Set a timeout to redirect to profile regardless of callback success
        const timeoutId = setTimeout(() => {
          console.log('AUTH SUCCESS - Callback timed out, redirecting to profile');
          setStatus('Authentication timeout');
          setError('Authentication process timed out');
          
          requestAnimationFrame(() => {
            router.replace('/profile');
          });
        }, 30000); // 30 second timeout (increased from 5s)
        
        try {
          // Log environment variables and device info
          console.log('AUTH SUCCESS - Environment:', {
            platform: Platform.OS,
            platformVersion: Platform.Version,
            isDev: false,
            hasSecureStore: !!SecureStore,
            timestamp: new Date().toISOString()
          });
          
          console.log('AUTH SUCCESS - Processing callback with code verifier present:', !!storedCodeVerifier);
          const result = await processCallback(callbackUrl);
          clearTimeout(timeoutId); // Clear timeout if callback succeeded
          
          console.log('AUTH SUCCESS - processCallback completed successfully:', result);
          setStatus('Authentication successful');
          
          // Add a small delay before redirecting to ensure logs are processed
          setTimeout(() => {
            requestAnimationFrame(() => {
              router.replace('/profile');
            });
          }, 1000);
        } catch (error: any) {
          clearTimeout(timeoutId); // Clear timeout if callback errored
          const errorMessage = error?.message || 'Unknown error';
          console.error(`AUTH SUCCESS - Error during processCallback: ${errorMessage}`, error);
          setStatus('Authentication failed');
          setError(errorMessage);
          
          // Add a small delay before redirecting
          setTimeout(() => {
            throw error; // Let the outer catch handle it
          }, 2000);
        }
      } catch (error: any) {
        const errorMessage = error?.message || 'Unknown error';
        console.error(`AUTH SUCCESS - Error processing callback: ${errorMessage}`, error);
        setStatus('Authentication failed');
        setError(errorMessage);
        
        // Redirect to profile with error state after a small delay
        setTimeout(() => {
          requestAnimationFrame(() => {
            router.replace({
              pathname: '/profile',
              params: { error: 'Failed to process authentication' }
            });
          });
        }, 2000);
      }
    };
    
    // Add a fallback timeout to prevent users from getting stuck on this screen
    const navigationTimeout = setTimeout(() => {
      console.log('AUTH SUCCESS - Navigation timeout reached, forcing redirect to profile');
      setStatus('Timeout - redirecting to profile');
      
      requestAnimationFrame(() => {
        router.replace('/profile');
      });
    }, 60000); // 60 second global timeout (increased from 10s)
    
    handleCallback().finally(() => {
      clearTimeout(navigationTimeout);
    });
    
    // Clear the timeout when component unmounts
    return () => {
      clearTimeout(navigationTimeout);
    };
  }, [isReady, params, router, processCallback]);
  
  return (
    <View style={styles.container}>
      <ActivityIndicator size="large" color="#000" />
      <Text style={styles.text}>{status}</Text>
      {error && <Text style={styles.errorText}>{error}</Text>}
      <Text style={styles.subText}>Please wait</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#fff',
    paddingHorizontal: 20,
  },
  text: {
    marginTop: 20,
    fontSize: 18,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  errorText: {
    marginTop: 10,
    fontSize: 16,
    color: '#E53935',
    textAlign: 'center',
  },
  subText: {
    marginTop: 8,
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
}); 