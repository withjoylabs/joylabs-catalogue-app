import 'react-native-get-random-values';
import { useEffect, useState } from 'react';
import { Stack, SplashScreen, ErrorBoundary } from 'expo-router';
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

export default function RootLayout() {
  const [debugTapCount, setDebugTapCount] = useState(0);
  const [debugModeActive, setDebugModeActive] = useState(false);
  const colorScheme = useColorScheme();
  
  const paperTheme = colorScheme === 'dark' ? MD3DarkTheme : MD3LightTheme;
  const [loaded, fontError] = useFonts({ ...FontAwesome.font });
  
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

  if (!loaded && !fontError) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator size="large" color="#000" />
        <Text style={{ marginTop: 20 }}>Loading application...</Text>
      </View>
    );
  }

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <PaperProvider theme={paperTheme}>
        <DatabaseProvider>
          <ApiProvider>
            <SafeAreaProvider>
              <Stack
                screenOptions={{
                  animation: 'none',
                }}
              >
                <Stack.Screen
                  name="(tabs)"
                  options={{ headerShown: false }}
                />
                <Stack.Screen
                  name="item/[id]"
                  options={{
                    title: 'Item Details',
                    headerShown: true,
                    presentation: 'card',
                  }}
                />
                <Stack.Screen
                  name="auth/success"
                  options={{
                    title: 'Authentication',
                    headerShown: false,
                  }}
                />
                <Stack.Screen
                  name="debug"
                  options={{
                    title: 'Debug Logs',
                    headerShown: true,
                    presentation: 'modal',
                  }}
                />
                <Stack.Screen name="catalogue" options={{ title: 'Catalogue', headerShown: true }}/>
                <Stack.Screen name="modules" options={{ title: 'Modules', headerShown: true }}/>
                <Stack.Screen name="labelDesigner" options={{ title: 'Label Designer', headerShown: true}}/>
                <Stack.Screen name="labelSettings" options={{ title: 'Label Settings', headerShown: true}}/>
              </Stack>
              
              <TouchableOpacity 
                style={{ 
                  position: 'absolute', top: Platform.OS === 'ios' ? 40 : 10, right: 10, 
                  width: 40, height: 40, opacity: debugModeActive ? 0.8 : 0,
                  zIndex: 9999, justifyContent: 'center', alignItems: 'center',
                  backgroundColor: debugModeActive ? 'rgba(0,0,0,0.1)' : 'transparent',
                  borderRadius: 20
                }}
                onPress={handleDebugTap}
              >
                {debugModeActive && (
                  <Ionicons name="bug-outline" size={24} color="#E53935" />
                )}
              </TouchableOpacity>
              
              <StatusBar style="dark" />
            </SafeAreaProvider>
          </ApiProvider>
        </DatabaseProvider>
      </PaperProvider>
    </GestureHandlerRootView>
  );
}

export { ErrorBoundary };

export const unstable_settings = {
  initialRouteName: '(tabs)',
}; 