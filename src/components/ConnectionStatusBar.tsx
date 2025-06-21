import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useAuthenticator } from '@aws-amplify/ui-react-native';

interface ConnectionStatusBarProps {
  connected: boolean;
  message: string;
}

const ConnectionStatusBar: React.FC<ConnectionStatusBarProps> = ({
  connected,
  message
}) => {
  const { user } = useAuthenticator((context) => [context.user]);
  const isAuthenticated = !!user?.signInDetails?.loginId;

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
});

export default React.memo(ConnectionStatusBar); 