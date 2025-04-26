import 'react-native-get-random-values';
import { useEffect, useState } from 'react';
import { Stack, usePathname, useRouter } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { 
  Platform, 
  View, 
  TouchableOpacity, 
  Text, 
  Dimensions, 
  ActivityIndicator, 
  Linking,
  useColorScheme
} from 'react-native';
import { SplashScreen, ErrorBoundary } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import FontAwesome from '@expo/vector-icons/FontAwesome';
import BottomTabBar from '../src/components/BottomTabBar';
import * as ExpoLinking from 'expo-linking';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import * as Device from 'expo-device';
import { ApiProvider } from '../src/providers/ApiProvider';
import logger, { LogLevel } from '../src/utils/logger';
import { DatabaseProvider } from '../src/components/DatabaseProvider';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import { CatalogSyncService } from '../src/database/catalogSync'; // Adjust path if needed
import Constants from 'expo-constants';
import { PaperProvider } from 'react-native-paper';
import { MD3DarkTheme, MD3LightTheme } from 'react-native-paper';

const BACKGROUND_NOTIFICATION_TASK = 'CATALOG_SYNC_TASK';

TaskManager.defineTask(BACKGROUND_NOTIFICATION_TASK, async ({ data, error, executionInfo }) => {
  const taskTag = '[TaskManager]'; // Define a tag for logging
  logger.info(taskTag, 'Background notification task started', { data, executionInfo });

  if (error) {
    logger.error(taskTag, 'Error in background task:', error);
    return;
  }

  // Use optional chaining and type checking for safety
  const notification = (data as any)?.notification as Notifications.Notification | undefined;

  if (notification) {
    const notificationData = notification.request.content.data as { type?: string; [key: string]: any } | undefined;
    logger.info(taskTag, 'Received notification', { notificationData });

    // Check if it's our catalog update notification
    if (notificationData?.type === 'catalog_updated') {
      logger.info(taskTag, 'Catalog update notification received. Triggering incremental sync.');
      try {
        const syncService = CatalogSyncService.getInstance();
        await syncService.runIncrementalSync(); // Call the incremental sync method
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
  // According to expo-task-manager docs, you don't necessarily need to return anything
  // unless the task definition requires it (like BackgroundFetch). For notification handling,
  // completing the execution is sufficient.
});

// Configure linking
const linking = {
  prefixes: ['joylabs://', 'https://app.joylabs.io'],
  config: {
    initialRouteName: 'index',
    screens: {
      index: '',
      profile: 'profile',
      modules: 'modules',
      catalogue: 'catalogue',
      labels: 'labels',
      labelDesigner: 'labelDesigner',
      labelSettings: 'labelSettings',
      'item/[id]': 'item/:id',
      'auth/success': 'auth/success',
      debug: 'debug',
    },
  },
};

// Prevent the splash screen from auto-hiding before asset loading is complete
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const pathname = usePathname();
  const router = useRouter();
  const [activeTab, setActiveTab] = useState('scan');
  const [debugTapCount, setDebugTapCount] = useState(0);
  const [debugModeActive, setDebugModeActive] = useState(false);
  const colorScheme = useColorScheme();
  
  console.log('ROOT LAYOUT - Rendering with pathname:', pathname);
  
  const paperTheme = colorScheme === 'dark'
      ? MD3DarkTheme
      : MD3LightTheme;

  const [loaded, error] = useFonts({
    ...FontAwesome.font,
  });
  
  useEffect(() => {
    console.log('APP - Application starting at', new Date().toISOString());
    console.log('APP - Initial route:', pathname);
    
    const startTime = Date.now();
    const { width, height } = Dimensions.get('window');
    logger.info('App', 'Application started', {
      version: '1.0.0', // Update with your app version
      platform: Platform.OS,
      platformVersion: Platform.Version,
      deviceWidth: width,
      deviceHeight: height,
      deviceInfo: `${Platform.OS} ${Platform.Version}`,
      isDev: false, // Always false in production
      startupTime: startTime
    });
    
    // Hide the splash screen after our app is ready
    setTimeout(() => {
      console.log('APP - Hiding splash screen after', Date.now() - startTime, 'ms');
      SplashScreen.hideAsync();
    }, 500);
  }, [pathname]);
  
  useEffect(() => {
    const startTime = Date.now();
    if (loaded || error) {
      console.log('APP - Fonts loaded or error occurred, hiding splash screen after', Date.now() - startTime, 'ms');
      SplashScreen.hideAsync();
    }
  }, [loaded, error]);
  
  useEffect(() => {
    // Update the active tab based on the current route
    if (pathname === '/profile') {
      setActiveTab('profile');
    } else if (pathname === '/' || pathname.startsWith('/item/')) {
      setActiveTab('scan');
    } else if (pathname === '/labels' || pathname === '/labelSettings' || pathname === '/labelDesigner') {
      setActiveTab('labels');
    }
    
    // Log navigation
    logger.debug('Navigation', `Navigated to: ${pathname}`);
  }, [pathname]);

  // Function to check if we should show the tab bar
  const shouldShowTabBar = () => {
    return pathname === '/' || 
           pathname === '/profile' ||
           pathname === '/labels' ||
           pathname.startsWith('/item/'); // Restore showing tab bar on item screen
  };
  
  // Handle debug mode activation
  const handleDebugTap = () => {
    const newCount = debugTapCount + 1;
    setDebugTapCount(newCount);
    
    // Activate debug mode after 7 taps
    if (newCount >= 7 && !debugModeActive) {
      setDebugModeActive(true);
      logger.info('App', 'Debug mode activated by user');
    }
    
    // Reset count after 3 seconds
    setTimeout(() => {
      setDebugTapCount(0);
    }, 3000);
  };

  // Listen for deep links
  useEffect(() => {
    // Log when the root layout is mounted
    console.log('ROOT LAYOUT - Mounted');
    
    const subscription = Linking.addEventListener('url', (event) => {
      console.log('ROOT LAYOUT - Deep link received:', event.url);
      // Don't automatically process auth deep links on app load
      // They will be handled by the auth/success screen itself
    });
    
    // Check for initial URL (app opened via deep link)
    const getInitialURL = async () => {
      try {
        const initialUrl = await Linking.getInitialURL();
        if (initialUrl) {
          console.log('ROOT LAYOUT - App opened with initial URL:', initialUrl);
          if (initialUrl.includes('auth/success')) {
            console.log('ROOT LAYOUT - Auth callback deep link detected on startup, navigate to index instead');
            // Navigate to index first, letting the app properly initialize
            router.replace('/');
          }
        } else {
          console.log('ROOT LAYOUT - App opened normally without deep link');
        }
      } catch (error) {
        console.error('ROOT LAYOUT - Error getting initial URL:', error);
      }
    };
    
    getInitialURL();
    
    return () => {
      subscription.remove();
      console.log('ROOT LAYOUT - Unmounted');
    };
  }, []);

  useEffect(() => {
    if (error) {
      // Log the actual error from useFonts
      console.error('ROOT LAYOUT - Error loading fonts:', error);
      logger.error('App', 'Font loading failed', { error });
      // Optionally show an alert or fallback UI
      // Alert.alert('Font Error', 'Failed to load essential fonts. The app might look strange.');
    } else if (loaded) {
      console.log('ROOT LAYOUT - Fonts loaded successfully');
    }
  }, [loaded, error]); // Depend on the actual state variables from useFonts

  // Notification Handling and Permissions Setup
  useEffect(() => {
    let isMounted = true; // Flag to prevent state updates on unmounted component
    let responseListenerSubscription: Notifications.Subscription | null = null;

    logger.info('[Notifications]', 'Setting up notification handlers...');

    Notifications.setNotificationHandler({
      handleNotification: async (notification) => {
        logger.info('[Notifications]', 'Notification received while app running/foregrounded', notification.request.content);
        // Return behavior for foreground notifications
        return {
            shouldShowAlert: false, // Silent handling
            shouldPlaySound: false,
            shouldSetBadge: false,
        };
      },
      handleSuccess: (notificationId) => {
        if (!isMounted) return;
        logger.info('[Notifications]', 'Notification handled successfully (foreground/running)', { notificationId });
      },
      handleError: (notificationId, error) => {
        if (!isMounted) return;
        logger.error('[Notifications]', 'Error handling notification (foreground/running)', { notificationId, error });
      },
    });

    responseListenerSubscription = Notifications.addNotificationResponseReceivedListener(response => {
      if (!isMounted) return;
      logger.info('[Notifications]', 'Notification response received', { response });
      const url = response.notification.request.content.data?.url as string | undefined;
      if (url) {
        logger.info('[Notifications]', `Attempting to navigate to URL from notification: ${url}`);
        // Example: router.push(url);
      }
    });

    logger.info('[Notifications]', 'Notification handlers set.');

    // Example Trigger (Commented out - Place where appropriate, e.g., after login)
    // import { registerForPushNotificationsAsync } from '../services/notificationService'; // Import needed
    // registerForPushNotificationsAsync();

    // Cleanup function
    return () => {
      isMounted = false;
      if (responseListenerSubscription) {
        logger.info('[Notifications]', 'Removing notification response listener.');
        Notifications.removeNotificationSubscription(responseListenerSubscription);
      }
    };
  }, []); // Run setup once on mount

  if (!loaded && !error) {
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
              <View style={{ flex: 1 }}>
                <Stack
                  initialRouteName="index"
                  screenOptions={{
                    headerShown: false,
                    contentStyle: { backgroundColor: '#fff' },
                    animation: 'none',
                  }}
                >
                  <Stack.Screen
                    name="index"
                    options={{
                      title: 'Home',
                    }}
                  />
                  <Stack.Screen
                    name="modules"
                    options={{
                      title: 'Modules',
                    }}
                  />
                  <Stack.Screen
                    name="profile"
                    options={{
                      title: 'Profile',
                    }}
                  />
                  <Stack.Screen
                    name="catalogue"
                    options={{
                      title: 'Catalogue',
                      headerShown: false,
                      animation: 'slide_from_right',
                      presentation: 'card',
                      // Full screen gesture on iOS for this screen
                      ...(Platform.OS === 'ios' && {
                        fullScreenGestureEnabled: true,
                      }),
                    }}
                  />
                  <Stack.Screen
                    name="item/[id]"
                    options={{
                      title: 'Item Details',
                      headerShown: true,
                      animation: 'none',
                      presentation: 'card',
                    }}
                  />
                  <Stack.Screen
                    name="auth/success"
                    options={{
                      title: 'Authentication',
                      headerShown: false,
                      // This screen should only be accessed via deep linking, never as an initial route
                    }}
                  />
                  <Stack.Screen
                    name="debug"
                    options={{
                      title: 'Debug Logs',
                      headerShown: true,
                      animation: 'slide_from_bottom',
                      presentation: 'modal',
                    }}
                  />
                  <Stack.Screen
                    name="labels"
                    options={{
                      title: 'Labels',
                      headerShown: false,
                    }}
                  />
                  <Stack.Screen
                    name="labelDesigner"
                    options={{
                      title: 'Label Designer',
                      headerShown: false,
                    }}
                  />
                  <Stack.Screen
                    name="labelSettings"
                    options={{
                      title: 'Label Settings',
                      headerShown: false,
                    }}
                  />
                </Stack>
                
                {/* Debug mode indicator and trigger */}
                <TouchableOpacity 
                  style={{ 
                    position: 'absolute', 
                    top: Platform.OS === 'ios' ? 40 : 10, 
                    right: 10, 
                    width: 40, 
                    height: 40,
                    opacity: debugModeActive ? 0.8 : 0,
                    zIndex: 9999,
                    justifyContent: 'center',
                    alignItems: 'center',
                    backgroundColor: debugModeActive ? 'rgba(0,0,0,0.1)' : 'transparent',
                    borderRadius: 20
                  }}
                  onPress={handleDebugTap}
                >
                  {debugModeActive && (
                    <Ionicons name="bug-outline" size={24} color="#E53935" />
                  )}
                </TouchableOpacity>
                
                {/* Show the tab bar on appropriate screens */}
                {shouldShowTabBar() && (
                  <BottomTabBar activeTab={activeTab} />
                )}
                
                {/* Status bar */}
                <StatusBar style="dark" />
              </View>
            </SafeAreaProvider>
          </ApiProvider>
        </DatabaseProvider>
      </PaperProvider>
    </GestureHandlerRootView>
  );
}

export {
  // Catch any errors thrown by the Layout component.
  ErrorBoundary,
};

export const unstable_settings = {
  // Ensure that reloading keeps a back button present.
  initialRouteName: 'index',
}; 