import React from 'react';
import { View, StyleSheet } from 'react-native';
import SystemModalTest from '../src/components/SystemModalTest';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function ModalTestScreen() {
  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <SystemModalTest />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
}); 