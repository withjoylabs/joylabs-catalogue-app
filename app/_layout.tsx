import { Stack } from 'expo-router';
import { useEffect } from 'react';
import { Platform } from 'react-native';
import * as SplashScreen from 'expo-splash-screen';

// Keep the splash screen visible while we initialize the app
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  useEffect(() => {
    // Hide the splash screen after our app is ready
    SplashScreen.hideAsync();
  }, []);

  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: 'white' },
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
          // Full screen modal on iOS for this screen
          ...(Platform.OS === 'ios' && {
            fullScreenGestureEnabled: true,
          }),
        }}
      />
    </Stack>
  );
} 