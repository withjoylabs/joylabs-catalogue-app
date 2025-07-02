import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useAuthenticator } from '@aws-amplify/ui-react-native';

interface ConnectionStatusBarProps {
  connected: boolean;
  message?: string; // Made optional since we're making it compact
  compact?: boolean; // Add compact mode
}

const ConnectionStatusBar: React.FC<ConnectionStatusBarProps> = ({
  connected,
  message,
  compact = false
}) => {
  const { user } = useAuthenticator((context) => [context.user]);
  // CRITICAL FIX: Use multiple authentication indicators for better reliability
  const isAuthenticated = !!(
    user?.signInDetails?.loginId ||
    user?.userId ||
    user?.username
  );

  if (compact) {
    // Compact horizontal layout for header
    return (
      <View style={styles.compactContainer}>
        {/* Square Status Badge */}
        <View style={[
          styles.compactBadge, 
          { backgroundColor: connected ? '#4CD964' : '#FF3B30' }
        ]}>
          <Text style={styles.compactBadgeText}>SQ</Text>
        </View>
        
        {/* Auth Status Badge */}
        <View style={[
          styles.compactBadge, 
          { backgroundColor: isAuthenticated ? '#4CD964' : '#FF8C00' }
        ]}>
          <Text style={styles.compactBadgeText}>AU</Text>
        </View>
      </View>
    );
  }

  // Original layout for other uses
  return (
    <View style={styles.container}>
      <Text style={styles.statusText}>
        {message}
      </Text>
      <View style={styles.statusContainer}>
        {/* Square Connection Status */}
        <View style={styles.statusGroup}>
          <Text style={styles.statusLabel}>Square</Text>
      <View style={[
        styles.statusIndicator, 
        { backgroundColor: connected ? '#4CD964' : '#FF3B30' }
      ]}>
        <Text style={styles.statusIndicatorText}>
          {connected ? 'OK' : 'X'}
        </Text>
          </View>
        </View>
        
        {/* App Authentication Status */}
        <View style={styles.statusGroup}>
          <Text style={styles.statusLabel}>Auth</Text>
          <View style={[
            styles.statusIndicator, 
            { backgroundColor: isAuthenticated ? '#4CD964' : '#FF8C00' }
          ]}>
            <Text style={styles.statusIndicatorText}>
              {isAuthenticated ? 'OK' : '?'}
            </Text>
          </View>
        </View>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e1e1e1',
  },
  statusText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  statusGroup: {
    alignItems: 'center',
    gap: 4,
  },
  statusLabel: {
    fontSize: 12,
    fontWeight: '500',
    color: '#666',
  },
  statusIndicator: {
    width: 36,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusIndicatorText: {
    color: 'white',
    fontWeight: 'bold',
    fontSize: 12,
  },
  // Compact mode styles
  compactContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  compactBadge: {
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  compactBadgeText: {
    color: 'white',
    fontWeight: 'bold',
    fontSize: 10,
  },
});

export default React.memo(ConnectionStatusBar); 