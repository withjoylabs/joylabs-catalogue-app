import React from 'react';
import { Platform, View, TouchableOpacity, Text, StyleSheet } from 'react-native';
import { Tabs, useRouter, usePathname } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAppStore } from '../../src/store';
import logger from '../../src/utils/logger';

// Styles for the custom FAB, extracted from original BottomTabBar.tsx logic
// Note: These were previously in app/_layout.tsx
const fabStyles = StyleSheet.create({
  fabContainer: {
    justifyContent: 'center',
    alignItems: 'center',
    width: 70,
    height: Platform.OS === 'ios' ? (80 - 15) : (60 -15),
  },
  fabButton: {
    width: 55,
    height: 55,
    borderRadius: 27.5,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 3,
    elevation: 3,
    position: 'absolute',
    bottom: Platform.OS === 'ios' ? 15 : 0,
    alignSelf: 'center',
  },
  saveButton: {
    backgroundColor: '#4CD964',
  },
});

function CustomFabButton() {
  const router = useRouter();
  const pathname = usePathname();
  const isItemDetails = pathname.startsWith('/item/');
  const triggerItemSave = useAppStore((state) => state.triggerItemSave);

  const handlePress = () => {
    if (isItemDetails) {
      logger.info('CustomFabButton', 'Save action triggered', { pathname });
      triggerItemSave();
    } else {
      logger.info('CustomFabButton', 'Add action triggered, navigating to /item/new', { pathname });
      router.push('/item/new');
    }
  };

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
      <TouchableOpacity 
        style={[fabStyles.fabButton, isItemDetails && fabStyles.saveButton]} 
        onPress={handlePress}
      >
        <Ionicons name={isItemDetails ? "checkmark" : "add"} size={28} color="#fff" />
      </TouchableOpacity>
    </View>
  );
}

export default function MainTabsLayout() {
  return (
    <Tabs
      initialRouteName="index"
      screenOptions={{
        headerShown: false, 
        tabBarActiveTintColor: '#007AFF',
        tabBarInactiveTintColor: '#8E8E93',
        tabBarStyle: {
          height: Platform.OS === 'ios' ? 80 : 60,
          paddingBottom: Platform.OS === 'ios' ? 20 : 0,
          paddingHorizontal: 10, 
          backgroundColor: '#fff',
          borderTopWidth: 1,
          borderTopColor: '#eee',
        },
        tabBarLabelStyle: {
          fontSize: 12,
          marginTop: 2,
        },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Scan',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'barcode' : 'barcode-outline'} size={24} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="reorders"
        options={{
          title: 'Reorders',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'receipt-outline' : 'receipt-outline'} size={24} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="__fab_dummy__" 
        options={{
          title: '',
          tabBarButton: () => <CustomFabButton />,
        }}
        listeners={{
          tabPress: (e) => {
            e.preventDefault(); 
          },
        }}
      />
      <Tabs.Screen
        name="labels"
        options={{
          title: 'Labels',
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'pricetag' : 'pricetag-outline'} size={24} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="(profile)"
        options={{
          title: 'Profile',
          headerShown: false, 
          tabBarIcon: ({ color, focused }) => (
            <Ionicons name={focused ? 'person' : 'person-outline'} size={24} color={color} />
          ),
        }}
      />
      <Tabs.Screen 
        name="scanHistory"
        options={{ href: null }}
      />
    </Tabs>
  );
} 