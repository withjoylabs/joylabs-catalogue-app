import React from 'react';
import 'react-native-get-random-values';
import { useEffect, useState, useMemo, useCallback } from 'react';
import { Stack, SplashScreen, ErrorBoundary, useRouter } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { 
  Platform, 
  View, 
  TouchableOpacity, 
  Text, 
  Dimensions, 
  ActivityIndicator, 
  Linking,
  useColorScheme,
  LogBox,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import FontAwesome from '@expo/vector-icons/FontAwesome';
import * as ExpoLinking from 'expo-linking';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import { ApiProvider } from '../src/providers/ApiProvider';
import logger from '../src/utils/logger';
import { DatabaseProvider } from '../src/components/DatabaseProvider';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import type { NotificationBehavior } from 'expo-notifications';
import { CatalogSyncService } from '../src/database/catalogSync';
import { PaperProvider, MD3DarkTheme, MD3LightTheme } from 'react-native-paper';
import { useAppStore } from '../src/store';
import { ActionSheetProvider } from '@expo/react-native-action-sheet';
import { MenuProvider } from 'react-native-popup-menu';
import * as SystemUI from 'expo-system-ui';
import { lightTheme } from '../src/themes';
import GlobalSuccessModal from '../src/components/GlobalSuccessModal';
import { Amplify } from 'aws-amplify';
import { ConsoleLogger } from 'aws-amplify/utils';
import config from '../src/aws-exports';

Amplify.configure(config);
ConsoleLogger.LOG_LEVEL = 'DEBUG';

const BACKGROUND_NOTIFICATION_TASK = 'CATALOG_SYNC_TASK';

TaskManager.defineTask(BACKGROUND_NOTIFICATION_TASK, async ({ data, error, executionInfo }) => {
  const taskTag = '[TaskManager]';
  logger.info(taskTag, 'Background notification task started', { data, executionInfo });
  if (error) {
    logger.error(taskTag, 'Error in background task:', error);
    return;
  }
  const notification = (data as any)?.notification as Notifications.Notification | undefined;
  if (notification) {
    const notificationData = notification.request.content.data as { type?: string; [key: string]: any } | undefined;
    logger.info(taskTag, 'Received notification', { notificationData });
    if (notificationData?.type === 'catalog_updated') {
      logger.info(taskTag, 'Catalog update notification received. Triggering incremental sync.');
      try {
        const syncService = CatalogSyncService.getInstance();
        await syncService.runIncrementalSync();
        logger.info(taskTag, 'Incremental sync finished successfully (triggered by task).');
      } catch (syncError: any) {
        logger.error(taskTag, 'Error occurred during runIncrementalSync triggered by task:', { error: syncError.message, details: syncError });
      }
    } else {
      logger.warn(taskTag, 'Received notification of unknown type or missing data', { notificationData });
    }
  } else {
    logger.warn(taskTag, 'Task executed without notification data?', { data });
  }
  logger.info(taskTag, 'Background notification task finished');
});

const linking = {
  prefixes: ['joylabs://', 'https://app.joylabs.io'],
  config: {
    screens: {
      '(tabs)': {
    initialRouteName: 'index',
    screens: {
      index: '',
          search: 'search',
      labels: 'labels',
          profile: 'profile',
        }
      },
      'item/:id': 'item/:id',
      'auth/success': 'auth/success',
      debug: 'debug',
      labelDesigner: 'label-designer',
      labelSettings: 'label-settings',
      catalogue: 'catalogue',
      modules: 'modules',
    },
  },
};

SplashScreen.preventAutoHideAsync();

LogBox.ignoreLogs([
  'Warning: Encountered two children with the same key',
  'Key \" allthedata\" already exists in ' // specific key causing issues
]);

export default function RootLayout() {
  const [debugTapCount, setDebugTapCount] = useState(0);
  const [debugModeActive, setDebugModeActive] = useState(false);
  const [debugTapTimeout, setDebugTapTimeout] = useState<NodeJS.Timeout | null>(null);
  const [responseListenerSubscription, setResponseListenerSubscription] = useState<Notifications.Subscription | null>(null);

  const colorScheme = useColorScheme();
  
  const paperTheme = useMemo(() => {
    logger.info('RootLayout', 'Recalculating paperTheme', { colorScheme });
    return colorScheme === 'dark' ? MD3DarkTheme : MD3LightTheme;
  }, [colorScheme]);

  const [loaded, fontError] = useFonts({ ...FontAwesome.font });
  const [isAppReady, setIsAppReady] = useState(false);
  
  useEffect(() => {
    logger.info('RootLayout', 'Color scheme changed', { colorScheme });
  }, [colorScheme]);
    
  useEffect(() => {
    const startTime = Date.now();
    const { width, height } = Dimensions.get('window');
    logger.info('App', 'Application started', {
      version: '1.0.0',
      platform: Platform.OS,
      platformVersion: Platform.Version,
      deviceWidth: width,
      deviceHeight: height,
      deviceInfo: `${Platform.OS} ${Platform.Version}`,
      isDev: false,
      startupTime: startTime
    });
  }, []);
  
  useEffect(() => {
    if (loaded || fontError) {
      SplashScreen.hideAsync();
      setIsAppReady(true);
      logger.info('RootLayout', 'Fonts loaded, app marked as ready.');
    }
  }, [loaded, fontError]);

  const handleDebugTap = () => {
    const newCount = debugTapCount + 1;
    setDebugTapCount(newCount);
    if (newCount >= 7 && !debugModeActive) {
      setDebugModeActive(true);
      logger.info('App', 'Debug mode activated by user');
    }
    setTimeout(() => setDebugTapCount(0), 3000);
  };

  useEffect(() => {
    const subscription = Linking.addEventListener('url', (event) => {
    });
    const getInitialURL = async () => {
      try {
        const initialUrl = await Linking.getInitialURL();
        if (initialUrl) {
          if (initialUrl.includes('auth/success')) {
          }
        }
      } catch (err) {
        console.error('ROOT LAYOUT - Error getting initial URL:', err);
      }
    };
    getInitialURL();
    return () => {
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    if (fontError) {
      console.error('ROOT LAYOUT - Error loading fonts:', fontError);
      logger.error('App', 'Font loading failed', { error: fontError });
    }
  }, [fontError]);

  useEffect(() => {
    let isMounted = true;
    let responseListenerSubscription: Notifications.Subscription | null = null;
    logger.info('[Notifications]', 'Setting up notification handlers...');
    Notifications.setNotificationHandler({
      handleNotification: async (notification): Promise<NotificationBehavior> => {
        logger.info('[Notifications]', 'Notification received while app running/foregrounded', notification.request.content);
        return {
          shouldShowAlert: false, 
            shouldPlaySound: false,
            shouldSetBadge: false,
        } as NotificationBehavior;
      },
      handleSuccess: (notificationId) => {
        if (!isMounted) return;
        logger.info('[Notifications]', 'Notification handled successfully (foreground/running)', { notificationId });
      },
      handleError: (notificationId, err) => {
        if (!isMounted) return;
        logger.error('[Notifications]', 'Error handling notification (foreground/running)', { notificationId, error: err });
      },
    });
    responseListenerSubscription = Notifications.addNotificationResponseReceivedListener(response => {
      if (!isMounted) return;
      logger.info('[Notifications]', 'Notification response received', { response });
      const url = response.notification.request.content.data?.url as string | undefined;
      if (url) {
        logger.info('[Notifications]', `Attempting to navigate to URL from notification: ${url}`);
      }
    });
    logger.info('[Notifications]', 'Notification handlers set.');
    return () => {
      isMounted = false;
      if (responseListenerSubscription) {
        logger.info('[Notifications]', 'Removing notification response listener.');
        Notifications.removeNotificationSubscription(responseListenerSubscription);
      }
    };
  }, []);

  useEffect(() => {
    if (loaded || fontError) {
      SplashScreen.hideAsync();
    }
  }, [loaded, fontError]);

  useEffect(() => {
    // Set the background color for the navigation bar or other system UI elements
    SystemUI.setBackgroundColorAsync(lightTheme.colors.background).catch((err: any) => {
      console.warn('Failed to set system UI background color:', err);
    });
  }, []);

  if (!loaded && !fontError) {
    return null;
  }

  return (
    <MenuProvider>
      <GestureHandlerRootView style={{ flex: 1 }}>
        <PaperProvider theme={paperTheme}>
          <ApiProvider>
            <SafeAreaProvider>
              <ActionSheetProvider>
                <React.Fragment>
                  <DatabaseProvider>
                    {isAppReady ? (
                      <Stack
                        screenOptions={{
                          headerShown: false,
                          gestureEnabled: true,
                        }}
                      >
                        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
                        <Stack.Screen name="item/[id]" options={{ presentation: 'modal' }} />
                        <Stack.Screen name="auth/success" />
                        <Stack.Screen name="debug" />
                        <Stack.Screen name="labelDesigner" />
                        <Stack.Screen name="labelSettings" />
                        <Stack.Screen name="catalogue" />
                        <Stack.Screen name="modules" />
                      </Stack>
                    ) : (
                      <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: lightTheme.colors.background }}>
                        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
                      </View>
                    )}
                  </DatabaseProvider>
                  <GlobalSuccessModal />
                  <TouchableOpacity onPress={handleDebugTap} style={{ position: 'absolute', bottom: 0, left: 0, width: 50, height: 50, opacity: 0.05 }} />
                  {debugModeActive && (
                    <View style={{ position: 'absolute', bottom: 10, right: 10, padding: 10, backgroundColor: 'rgba(0,0,0,0.7)', borderRadius: 5 }}>
                      <Text style={{ color: 'white' }}>Debug Mode Active</Text>
                    </View>
                  )}
                </React.Fragment>
              </ActionSheetProvider>
            </SafeAreaProvider>
          </ApiProvider>
        </PaperProvider>
      </GestureHandlerRootView>
    </MenuProvider>
  );
}

export { ErrorBoundary };

export const unstable_settings = {
  initialRouteName: '(tabs)',
}; 