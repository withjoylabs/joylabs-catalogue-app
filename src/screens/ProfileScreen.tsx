import React from 'react';
import { View, StyleSheet, ScrollView, Text, Button } from 'react-native';
import { useSquareAuth } from '../hooks/useSquareAuth';

const ProfileScreen = () => {
  const { testDeepLink, isConnected, connect, disconnect, merchantId, businessName } = useSquareAuth();

  return (
    <ScrollView style={styles.container}>
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Square Connection</Text>
        
        {isConnected ? (
          <View>
            <Text style={styles.infoText}>Connected to Square</Text>
            {merchantId && <Text style={styles.infoText}>Merchant ID: {merchantId}</Text>}
            {businessName && <Text style={styles.infoText}>Business: {businessName}</Text>}
            <Button 
              onPress={disconnect}
              title="Disconnect from Square"
              color="#cc0000"
            />
          </View>
        ) : (
          <Button 
            onPress={connect}
            title="Connect to Square"
            color="#00aacc"
          />
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Deep Link Testing</Text>
        <Text style={styles.infoText}>
          Click the button below to test deep linking functionality
        </Text>
        <Button 
          onPress={testDeepLink}
          title="Test Deep Link"
          color="#666666"
        />
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
  },
  section: {
    marginBottom: 24,
    padding: 16,
    backgroundColor: '#f8f8f8',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  infoText: {
    marginBottom: 12,
    fontSize: 14,
  }
});

export default ProfileScreen; 