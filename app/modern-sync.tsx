import React from 'react';
import { View, Text, StyleSheet, ScrollView, SafeAreaView } from 'react-native';
import { Stack } from 'expo-router';
import ModernCatalogSyncStatus from '../src/components/ModernCatalogSyncStatus';
import { StatusBar } from 'expo-status-bar';

export default function ModernSyncScreen() {
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="dark" />
      <Stack.Screen options={{ 
        title: 'Modern SQLite Sync',
        headerShown: true,
      }} />
      
      <ScrollView style={styles.scrollView}>
        <View style={styles.header}>
          <Text style={styles.headerText}>Modern Catalog Sync</Text>
          <Text style={styles.headerDescription}>
            This page demonstrates the new SQLite implementation using the latest Expo SQLite APIs
          </Text>
        </View>
        
        <View style={styles.content}>
          <ModernCatalogSyncStatus />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    padding: 16,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  headerText: {
    fontSize: 22,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  headerDescription: {
    fontSize: 14,
    color: '#666',
    lineHeight: 20,
  },
  content: {
    padding: 16,
  },
}); 