import React from 'react';
import { View, Button, Text, StyleSheet } from 'react-native';
import { useSquareAuth } from '../hooks/useSquareAuth';

const SquareDeepLinkTester = () => {
  const { testDeepLink, error } = useSquareAuth();

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Square Deep Link Tester</Text>
      <Button 
        onPress={testDeepLink}
        title="Test Deep Link"
        color="#666"
      />
      {error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorTitle}>Error:</Text>
          <Text style={styles.errorText}>{error.message}</Text>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 16,
    borderRadius: 8,
    backgroundColor: '#f0f0f0',
    marginVertical: 10,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  errorContainer: {
    marginTop: 10,
    padding: 8,
    backgroundColor: '#ffeeee',
    borderRadius: 4,
  },
  errorTitle: {
    fontWeight: 'bold',
    color: '#cc0000',
  },
  errorText: {
    color: '#cc0000',
  },
});

export default SquareDeepLinkTester; 