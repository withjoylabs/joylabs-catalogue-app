import React, { useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import { Authenticator, useAuthenticator } from '@aws-amplify/ui-react-native';
import { useRouter } from 'expo-router';
import { Stack } from 'expo-router';

const LoginScreen = () => {
  const router = useRouter();
  const { route } = useAuthenticator();

  useEffect(() => {
    if (route === 'authenticated') {
      // Wait for the next render cycle to ensure the router is ready
      setTimeout(() => {
        if (router.canGoBack()) {
          router.back();
        }
      }, 0);
    }
  }, [route, router]);

  return (
    <View style={styles.container}>
      <Stack.Screen
        options={{
          headerTitle: 'Sign In or Create Account',
          headerBackTitle: 'Back',
        }}
      />
      <Authenticator />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'white', // Or your theme's background color
  },
});

export default LoginScreen; 