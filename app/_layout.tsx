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
  Linking 
} from 'react-native';
import { SplashScreen } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import BottomTabBar from '../src/components/BottomTabBar';
import * as ExpoLinking from 'expo-linking';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import * as Device from 'expo-device';
import { ApiProvider } from '../src/providers/ApiProvider';
import logger from '../src/utils/logger';
import { DatabaseProvider } from '../src/components/DatabaseProvider';
// Import the font file if needed, assuming Ionicons is the primary one
// If you have other custom fonts, add them here and to useFonts below
// import IoniconsFont from '@expo/vector-icons/build/vendor/react-native-vector-icons/Fonts/Ionicons.ttf'; // Example path, might vary

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
  
  // ** Restore useFonts hook **
  // Load required fonts. Add other fonts to this object if needed.
  const [fontsLoaded, fontError] = useFonts({
    // Make sure the key matches the font family name if used in styles
    'Ionicons': require('@expo/vector-icons/build/vendor/react-native-vector-icons/Fonts/Ionicons.ttf'),
    // Add other fonts like this:
    // 'SpaceMono-Regular': require('../assets/fonts/SpaceMono-Regular.ttf'),
  });
  
  // Log application start with device information
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
  
  // ** Update splash screen hiding logic **
  useEffect(() => {
    const startTime = Date.now();
    if (fontsLoaded || fontError) {
      console.log('APP - Fonts loaded or error occurred, hiding splash screen after', Date.now() - startTime, 'ms');
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded, fontError]);
  
  useEffect(() => {
    // Update the active tab based on the current route
    if (pathname === '/profile') {
      setActiveTab('profile');
    } else if (pathname === '/' || pathname.startsWith('/item/')) {
      setActiveTab('scan');
    }
    
    // Log navigation
    logger.debug('Navigation', `Navigated to: ${pathname}`);
  }, [pathname]);

  // Function to check if we should show the tab bar
  const shouldShowTabBar = () => {
    return pathname === '/' || 
           pathname === '/profile' ||
           pathname.startsWith('/item/');
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

  // ** Update font error logging **
  useEffect(() => {
    if (fontError) {
      // Log the actual error from useFonts
      console.error('ROOT LAYOUT - Error loading fonts:', fontError);
      logger.error('App', 'Font loading failed', { error: fontError });
      // Optionally show an alert or fallback UI
      // Alert.alert('Font Error', 'Failed to load essential fonts. The app might look strange.');
    } else if (fontsLoaded) {
      console.log('ROOT LAYOUT - Fonts loaded successfully');
    }
  }, [fontsLoaded, fontError]); // Depend on the actual state variables from useFonts

  // ** Update loading indicator logic **
  if (!fontsLoaded && !fontError) { // Show loading only if fonts are not loaded AND there's no error yet
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator size="large" color="#000" />
        <Text style={{ marginTop: 20 }}>Loading application...</Text>
      </View>
    );
  }

  return (
    <DatabaseProvider>
      <ApiProvider>
        <SafeAreaProvider>
          <View style={{ flex: 1 }}>
            <Stack
              initialRouteName="index"
              screenOptions={{
                headerShown: false,
                contentStyle: { backgroundColor: '#fff' },
                animation: Platform.OS === 'android' ? 'fade_from_bottom' : 'default',
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
                  headerShown: false,
                  animation: 'slide_from_right',
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
          </View>
        </SafeAreaProvider>
      </ApiProvider>
    </DatabaseProvider>
  );
} 