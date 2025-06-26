import React, { useState, useEffect } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { lightTheme } from '../themes';
import NotificationService, { NotificationServiceState } from '../services/notificationService';

interface NotificationBellProps {
  size?: number;
  color?: string;
  showBadge?: boolean;
}

export default function NotificationBell({ 
  size = 24, 
  color = lightTheme.colors.text,
  showBadge = true 
}: NotificationBellProps) {
  const router = useRouter();
  const [state, setState] = useState<NotificationServiceState>(NotificationService.getState());

  // Subscribe to notification service updates
  useEffect(() => {
    const unsubscribe = NotificationService.subscribe(setState);
    return unsubscribe;
  }, []);

  const handlePress = () => {
    router.push('/(tabs)/(scan)/(notifications)');
  };

  return (
    <Pressable style={styles.container} onPress={handlePress}>
      <View style={styles.iconContainer}>
        <Ionicons 
          name={state.unreadCount > 0 ? "notifications" : "notifications-outline"} 
          size={size} 
          color={color} 
        />
        {showBadge && state.unreadCount > 0 && (
          <View style={styles.badge}>
            <Text style={styles.badgeText}>
              {state.unreadCount > 99 ? '99+' : state.unreadCount.toString()}
            </Text>
          </View>
        )}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 8,
  },
  iconContainer: {
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
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  badgeText: {
    color: '#FFFFFF',
    fontSize: 11,
    fontWeight: '600',
    textAlign: 'center',
  },
}); 