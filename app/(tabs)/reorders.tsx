import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  SafeAreaView,
  Image,
} from 'react-native';
import { Stack, useRouter, useFocusEffect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { ConvertedItem } from '../../src/types/api';
import { lightTheme } from '../../src/themes';
import logger from '../../src/utils/logger';
import { styles } from './_indexStyles'; // Use styles from index

export default function ReordersScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.container}>
      <Stack.Screen
        options={{
          headerShown: true,
          title: 'Reorders',
        }}
      />
      <View style={styles.container}>
        <Text>Reorders Screen</Text>
      </View>
    </SafeAreaView>
  );
} 