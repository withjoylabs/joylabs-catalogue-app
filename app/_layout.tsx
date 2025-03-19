import React, { useEffect, useState } from 'react';
import { Stack, usePathname } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { Platform, View } from 'react-native';
import { SplashScreen } from 'expo-router';
import BottomTabBar from '../src/components/BottomTabBar';

// Prevent the splash screen from auto-hiding before asset loading is complete
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const pathname = usePathname();
  const [activeTab, setActiveTab] = useState('scan');
  
  useEffect(() => {
    // Hide the splash screen after our app is ready
    SplashScreen.hideAsync();
  }, []);
  
  useEffect(() => {
    // Update the active tab based on the current route
    if (pathname === '/profile') {
      setActiveTab('profile');
    } else if (pathname === '/' || pathname.startsWith('/item/')) {
      setActiveTab('scan');
    }
  }, [pathname]);

  // Function to check if we should show the tab bar
  const shouldShowTabBar = () => {
    return pathname === '/' || 
           pathname === '/profile' ||
           pathname.startsWith('/item/');
  };

  return (
    <SafeAreaProvider>
      <View style={{ flex: 1 }}>
        <Stack
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
        </Stack>
        {/* Show the tab bar on appropriate screens */}
        {shouldShowTabBar() && (
          <BottomTabBar activeTab={activeTab} />
        )}
      </View>
    </SafeAreaProvider>
  );
} 