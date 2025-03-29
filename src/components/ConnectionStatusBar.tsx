import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

interface ConnectionStatusBarProps {
  connected: boolean;
  message: string;
}

const ConnectionStatusBar: React.FC<ConnectionStatusBarProps> = ({
  connected,
  message
}) => {
  return (
    <View style={styles.container}>
      <Text style={styles.statusText}>
        {message}
      </Text>
      <View style={[
        styles.statusIndicator, 
        { backgroundColor: connected ? '#4CD964' : '#FF3B30' }
      ]}>
        <Text style={styles.statusIndicatorText}>
          {connected ? 'OK' : 'X'}
        </Text>
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

export default ConnectionStatusBar; 