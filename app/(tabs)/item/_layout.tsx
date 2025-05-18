import { Stack } from 'expo-router';
import React from 'react';

export default function ItemLayout() {
  return (
    <Stack>
      <Stack.Screen
        name="[id]"
        options={{
          headerShown: true,
        }}
      />
    </Stack>
  );
} 