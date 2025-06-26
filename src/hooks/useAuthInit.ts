import { useEffect, useState } from 'react';
import { getCurrentUser, fetchAuthSession } from 'aws-amplify/auth';
import logger from '../utils/logger';
import { CatalogSyncService } from '../database/catalogSync';
import PushNotificationService from '../services/pushNotificationService';

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

            // Initialize push notifications after successful authentication
            try {
              logger.info('AuthInit', '📱 Initializing push notifications after authentication...');
              const pushService = PushNotificationService.getInstance();

              // Initialize push notifications (don't await to avoid blocking UI)
              pushService.initialize().then(() => {
                logger.info('AuthInit', '✅ Push notification initialization completed successfully');
              }).catch(error => {
                logger.error('AuthInit', '❌ Push notification initialization failed', { error });
              });

              // Set up notification listeners
              pushService.setupNotificationListeners();

              logger.info('AuthInit', '🔔 Push notification initialization started');
            } catch (pushError) {
              // Don't fail authentication if push notifications fail
              logger.error('AuthInit', '❌ Failed to initialize push notifications', { pushError });
            }

            // Only trigger catch-up sync if we have a specific reason to believe we missed webhook events
            // This prevents unnecessary API calls on every app startup
            try {
              logger.info('AuthInit', 'Checking if catch-up sync is needed after authentication...');
              const syncService = CatalogSyncService.getInstance();
              
              // Only run catch-up sync if we detect we actually missed webhook events
              // This uses intelligent detection rather than blindly syncing on every startup
              syncService.checkAndRunCatchUpSync().catch(error => {
                logger.error('AuthInit', 'Catch-up sync check failed during app startup', { error });
              });
              
              logger.info('AuthInit', 'Intelligent catch-up sync check initiated');
            } catch (syncError) {
              // Don't fail authentication if sync fails
              logger.error('AuthInit', 'Failed to initiate catch-up sync check', { syncError });
            }
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