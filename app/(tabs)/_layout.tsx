import React, { useState, useEffect } from 'react';
import { Platform, View, TouchableOpacity, Text, StyleSheet } from 'react-native';
import { Tabs, useRouter, usePathname } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAppStore } from '../../src/store';
import logger from '../../src/utils/logger';
import { reorderService } from '../../src/services/reorderService';
import { imageCacheService } from '../../src/services/imageCacheService';
import '../../src/utils/debugImageCache'; // Initialize debug utilities

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
  // Badge styles
  badgeContainer: {
    position: 'relative',
  },
  badge: {
    position: 'absolute',
    top: -6,
    right: -6,
    backgroundColor: '#FF3B30',
    borderRadius: 10,
    minWidth: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#fff',
  },
  badgeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
});

function CustomFabButton() {
  const router = useRouter();
  const pathname = usePathname();
  const isItemDetails = pathname.startsWith('/item/');
  const isReordersPage = pathname === '/reorders';
  const triggerItemSave = useAppStore((state) => state.triggerItemSave);
  const triggerAddCustomItem = useAppStore((state) => state.triggerAddCustomItem);

  const handlePress = () => {
    if (isItemDetails) {
      logger.info('CustomFabButton', 'Save action triggered', { pathname });
      triggerItemSave();
    } else if (isReordersPage) {
      logger.info('CustomFabButton', 'Add custom item action triggered', { pathname });
      triggerAddCustomItem();
    } else {
      logger.info('CustomFabButton', 'Add action triggered, navigating to /item/new', { pathname });
      router.push('/item/new');
    }
  };

  // Determine icon based on current page
  const getIcon = () => {
    if (isItemDetails) return "checkmark";
    if (isReordersPage) return "add-outline"; // Different icon for reorders
    return "add";
  };

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
      <TouchableOpacity 
        style={[fabStyles.fabButton, isItemDetails && fabStyles.saveButton]} 
        onPress={handlePress}
      >
        <Ionicons name={getIcon()} size={28} color="#fff" />
      </TouchableOpacity>
    </View>
  );
}

function ReorderIconWithBadge({ color, focused }: { color: string; focused: boolean }) {
  const [reorderCount, setReorderCount] = useState(0);
  
  useEffect(() => {
    // Count only incomplete items for the badge
    const updateCount = (items: any[]) => {
      const incompleteCount = items.filter(item => item.status === 'incomplete').length;
      setReorderCount(incompleteCount);
    };

    // Set initial count asynchronously
    const initializeCount = async () => {
      const items = await reorderService.getItems();
      updateCount(items);
    };
    initializeCount();

    const unsubscribe = reorderService.addListener(updateCount);
    return unsubscribe;
  }, []);

  return (
    <View style={fabStyles.badgeContainer}>
      <Ionicons name={focused ? 'receipt-outline' : 'receipt-outline'} size={24} color={color} />
      {reorderCount > 0 && (
        <View style={fabStyles.badge}>
          <Text style={fabStyles.badgeText}>{reorderCount > 99 ? '99+' : reorderCount}</Text>
        </View>
      )}
    </View>
  );
}

export default function MainTabsLayout() {
  // Initialize image cache service on app startup
  useEffect(() => {
    imageCacheService.initialize().catch(error => {
      logger.error('MainTabsLayout', 'Failed to initialize image cache', error);
    });
  }, []);

  return (
    <Tabs
      initialRouteName="(scan)"
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
        name="(scan)"
        options={{
          title: 'Scan',
          headerShown: false,
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
            <ReorderIconWithBadge color={color} focused={focused} />
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