import React from 'react';
import { Stack } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

export default function ScanLayout() {
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#fff' }} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <Stack>
        <Stack.Screen
          name="index"
          options={{
            headerShown: false, // Scan page handles its own header
          }}
        />
        <Stack.Screen
          name="(notifications)"
          options={{
            headerShown: false, // Let notifications handle its own header
          }}
        />
      </Stack>
    </SafeAreaView>
  );
}
