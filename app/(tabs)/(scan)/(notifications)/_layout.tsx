import React from 'react';
import { TouchableOpacity, Platform } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

// Custom back button component for the notifications screen
const NotificationsBackButton = () => {
  const router = useRouter();
  return (
    <TouchableOpacity
      onPress={() => {
        router.back();
      }}
      style={{ marginLeft: Platform.OS === 'ios' ? 10 : 0, padding: 5 }}
    >
      <Ionicons name="arrow-back" size={24} color="black" />
    </TouchableOpacity>
  );
};

export default function NotificationsLayout() {
  return (
    <Stack>
      <Stack.Screen
        name="index"
        options={{
          title: 'Notifications',
          headerLeft: () => <NotificationsBackButton />,
        }}
      />
    </Stack>
  );
}
