import { useEffect, useState } from 'react';
import { getCurrentUser, fetchAuthSession } from 'aws-amplify/auth';
import logger from '../utils/logger';

interface AuthInitState {
  isLoading: boolean;
  isAuthenticated: boolean;
  error: string | null;
}

export const useAuthInit = (): AuthInitState => {
  const [state, setState] = useState<AuthInitState>({
    isLoading: true,
    isAuthenticated: false,
    error: null
  });

  useEffect(() => {
    const initializeAuth = async () => {
      try {
        logger.info('AuthInit', 'Checking existing authentication session...');
        
        // Check if user is currently authenticated
        const user = await getCurrentUser();
        
        if (user) {
          logger.info('AuthInit', 'User found, verifying session...');
          
          // Verify the session is still valid
          const session = await fetchAuthSession();
          
          if (session.tokens?.accessToken) {
            logger.info('AuthInit', 'Valid authentication session restored', {
              userId: user.userId,
              username: user.username
            });
            
            setState({
              isLoading: false,
              isAuthenticated: true,
              error: null
            });
          } else {
            logger.warn('AuthInit', 'No valid tokens found in session');
            setState({
              isLoading: false,
              isAuthenticated: false,
              error: null
            });
          }
        } else {
          logger.info('AuthInit', 'No authenticated user found');
          setState({
            isLoading: false,
            isAuthenticated: false,
            error: null
          });
        }
      } catch (error: any) {
        logger.info('AuthInit', 'No existing authentication session', { 
          error: error.message 
        });
        
        // This is expected when user is not authenticated
        setState({
          isLoading: false,
          isAuthenticated: false,
          error: null
        });
      }
    };

    initializeAuth();
  }, []);

  return state;
}; 