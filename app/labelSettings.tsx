import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TextInput, ScrollView, Keyboard, TouchableWithoutFeedback, TouchableOpacity, Platform } from 'react-native';
import { useAppStore } from '../src/store'; // Adjusted import path
import { lightTheme } from '../src/themes'; // Adjusted import path
import { Ionicons } from '@expo/vector-icons'; // Added Ionicons
import { useRouter } from 'expo-router'; // Added useRouter
import { StatusBar } from 'expo-status-bar'; // Added StatusBar

// Updated Constants for Label LIVE
const DEFAULT_LABEL_LIVE_HOST = '192.168.254.133'; 
const DEFAULT_LABEL_LIVE_PORT = '11180'; 
const DEFAULT_LABEL_LIVE_PRINTER = 'System-ZQ511';
const DEFAULT_LABEL_LIVE_WINDOW = 'hide';
const DEFAULT_FIELD_MAP = {
  itemName: 'ITEM_NAME',
  variationName: 'VARIATION_NAME',
  variationPrice: 'PRICE',
  barcode: 'GTIN',
};

export default function LabelSettingsScreen() {
  const router = useRouter(); // Get router instance

  // Select state values ONCE using new names
  const initialState = useAppStore.getState();
  const initialLabelLiveHost = initialState.labelLiveHost;
  const initialLabelLivePort = initialState.labelLivePort;
  const initialLabelLivePrinter = initialState.labelLivePrinter;
  const initialLabelLiveWindow = initialState.labelLiveWindow;
  const initialLabelLiveFieldMap = initialState.labelLiveFieldMap;

  // Select actions using new names
  const setLabelLiveHost = useAppStore((state) => state.setLabelLiveHost);
  const setLabelLivePort = useAppStore((state) => state.setLabelLivePort);
  const setLabelLivePrinter = useAppStore((state) => state.setLabelLivePrinter);
  const setLabelLiveWindow = useAppStore((state) => state.setLabelLiveWindow);
  const setLabelLiveFieldMap = useAppStore((state) => state.setLabelLiveFieldMap);

  // Local state for inputs, renamed
  const [localHost, setLocalHost] = useState(initialLabelLiveHost ?? DEFAULT_LABEL_LIVE_HOST);
  const [localPort, setLocalPort] = useState(initialLabelLivePort ?? DEFAULT_LABEL_LIVE_PORT);
  const [localPrinter, setLocalPrinter] = useState(initialLabelLivePrinter ?? DEFAULT_LABEL_LIVE_PRINTER);
  const [localWindow, setLocalWindow] = useState(initialLabelLiveWindow ?? DEFAULT_LABEL_LIVE_WINDOW);
  // Local state for field map - merge defaults with stored values
  const [localFieldMap, setLocalFieldMap] = useState({
    ...DEFAULT_FIELD_MAP,
    ...(initialLabelLiveFieldMap || {}),
  });

  // Handlers to update Zustand store when input loses focus (onBlur) - using new names
  const handleBlur = (field: keyof typeof localFieldMap) => {
    const currentState = useAppStore.getState();
    const zustandMap = { ...DEFAULT_FIELD_MAP, ...(currentState.labelLiveFieldMap || {}) };
    if (localFieldMap[field] !== zustandMap[field]) {
      // Create the new map object to save
      const newMapToSave = { ...zustandMap, [field]: localFieldMap[field] || null }; // Set null if empty
      setLabelLiveFieldMap(newMapToSave);
    }
  };

  const handleHostBlur = () => {
    const currentState = useAppStore.getState();
    const zustandHost = currentState.labelLiveHost ?? DEFAULT_LABEL_LIVE_HOST;
    if (localHost !== zustandHost) setLabelLiveHost(localHost);
  };

  const handlePortBlur = () => {
    const currentState = useAppStore.getState();
    const zustandPort = currentState.labelLivePort ?? DEFAULT_LABEL_LIVE_PORT;
    if (localPort !== zustandPort) setLabelLivePort(localPort);
  };

  const handlePrinterBlur = () => {
    const currentState = useAppStore.getState();
    const zustandPrinter = currentState.labelLivePrinter ?? DEFAULT_LABEL_LIVE_PRINTER;
    if (localPrinter !== zustandPrinter) setLabelLivePrinter(localPrinter);
  };

  const handleWindowBlur = () => {
    const currentState = useAppStore.getState();
    const zustandWindow = currentState.labelLiveWindow ?? DEFAULT_LABEL_LIVE_WINDOW;
    if (localWindow !== zustandWindow) setLabelLiveWindow(localWindow);
  };

  // Helper to update local field map state
  const updateLocalFieldMap = (field: keyof typeof localFieldMap, value: string) => {
    setLocalFieldMap(prev => ({ ...prev, [field]: value }));
  };

  return (
    <View style={styles.container}>
      <StatusBar style="dark" />
      {/* Custom Header Start */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="black" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Label Settings</Text>
        <View style={styles.headerActions}></View>
      </View>
      {/* Custom Header End */}
      
      {/* Content Area */}
      <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
        <ScrollView
          style={styles.contentScrollView}
          contentContainerStyle={styles.scrollContentContainer}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Label LIVE HTTP Configuration</Text>
            <Text style={styles.description}>
              Enter the Host IP address and Port for the Label LIVE HTTP service running on your network.
            </Text>

            <View style={styles.inputGroup}>
              <Text style={styles.label}>Label LIVE Host IP</Text>
              <TextInput
                style={styles.input}
                value={localHost}
                onChangeText={setLocalHost}
                onBlur={handleHostBlur}
                placeholder={DEFAULT_LABEL_LIVE_HOST}
                keyboardType="decimal-pad"
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>

            <View style={styles.inputGroup}>
              <Text style={styles.label}>Label LIVE Port</Text>
              <TextInput
                style={styles.input}
                value={localPort}
                onChangeText={setLocalPort}
                onBlur={handlePortBlur}
                placeholder={DEFAULT_LABEL_LIVE_PORT}
                keyboardType="number-pad"
              />
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Print Parameters</Text>
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Printer Name</Text>
              <TextInput
                style={styles.input}
                value={localPrinter}
                onChangeText={setLocalPrinter}
                onBlur={handlePrinterBlur}
                placeholder={DEFAULT_LABEL_LIVE_PRINTER}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Window Parameter ('show' or 'hide')</Text>
              <TextInput
                style={styles.input}
                value={localWindow}
                onChangeText={setLocalWindow}
                onBlur={handleWindowBlur}
                placeholder={DEFAULT_LABEL_LIVE_WINDOW}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Field Mapping</Text>
            <Text style={styles.description}>
              Map app data fields to Label LIVE variable names used in the 'variables' query parameter.
            </Text>

            <View style={styles.mappingGroup}>
              <Text style={styles.mappingLabel}>Item Name maps to:</Text>
              <TextInput
                style={styles.mappingInput}
                value={localFieldMap.itemName || ''}
                onChangeText={(val) => updateLocalFieldMap('itemName', val)}
                onBlur={() => handleBlur('itemName')}
                placeholder={DEFAULT_FIELD_MAP.itemName}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>

            <View style={styles.mappingGroup}>
              <Text style={styles.mappingLabel}>Variation Name maps to:</Text>
              <TextInput
                style={styles.mappingInput}
                value={localFieldMap.variationName || ''}
                onChangeText={(val) => updateLocalFieldMap('variationName', val)}
                onBlur={() => handleBlur('variationName')}
                placeholder={DEFAULT_FIELD_MAP.variationName}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
            
            <View style={styles.mappingGroup}>
              <Text style={styles.mappingLabel}>Variation Price maps to:</Text>
              <TextInput
                style={styles.mappingInput}
                value={localFieldMap.variationPrice || ''}
                onChangeText={(val) => updateLocalFieldMap('variationPrice', val)}
                onBlur={() => handleBlur('variationPrice')}
                placeholder={DEFAULT_FIELD_MAP.variationPrice}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
            
            <View style={styles.mappingGroup}>
              <Text style={styles.mappingLabel}>UPC/Barcode maps to:</Text>
              <TextInput
                style={styles.mappingInput}
                value={localFieldMap.barcode || ''}
                onChangeText={(val) => updateLocalFieldMap('barcode', val)}
                onBlur={() => handleBlur('barcode')}
                placeholder={DEFAULT_FIELD_MAP.barcode}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
          </View>

        </ScrollView>
      </TouchableWithoutFeedback>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: Platform.OS === 'ios' ? 60 : 40,
    paddingBottom: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 8,
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
    textAlign: 'center',
  },
  headerActions: {
    width: 40,
    height: 40,
  },
  contentScrollView: {
    flex: 1,
  },
  scrollContentContainer: {
    padding: 20,
  },
  section: {
    marginBottom: 30,
    backgroundColor: 'white',
    padding: 15,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
    color: lightTheme.colors.primary,
  },
  description: {
    fontSize: 14,
    color: '#666',
    marginBottom: 15,
    lineHeight: 20,
  },
  inputGroup: {
    marginBottom: 15,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: '#555',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
    backgroundColor: '#fff',
    color: lightTheme.colors.text,
  },
  mappingGroup: {
    marginBottom: 15,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  mappingLabel: {
    fontSize: 14,
    color: '#333',
    marginRight: 10,
    flexShrink: 1,
  },
  mappingInput: {
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 14,
    backgroundColor: '#f8f9fa',
    color: lightTheme.colors.text,
    flexGrow: 1,
    textAlign: 'right',
  },
}); 