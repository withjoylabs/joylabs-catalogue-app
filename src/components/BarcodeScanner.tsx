import React, { useRef, useCallback, useEffect } from 'react';
import { TextInput, StyleSheet, ScrollView } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useBarcodeScanner } from '../hooks/useBarcodeScanner';
import logger from '../utils/logger';

interface BarcodeScannerProps {
  onScan: (barcode: string) => void;
  onError: (error: string) => void;
  enabled?: boolean;
  minLength?: number;
  maxLength?: number;
  timeout?: number;
  style?: any;
  debugVisible?: boolean;
}

const TAG = '[BarcodeScanner]';

export const BarcodeScanner: React.FC<BarcodeScannerProps> = React.memo(({
  onScan,
  onError,
  enabled = true,
  minLength = 1,
  maxLength = 100,
  timeout = 300,
  style,
  debugVisible = false
}) => {
  const firstInputRef = useRef<TextInput>(null);
  const secondInputRef = useRef<TextInput>(null);
  const focusIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Initialize barcode scanner hook
  const { 
    isListening, 
    processBarcodeInput
  } = useBarcodeScanner({
    onScan,
    onError,
    enabled,
    minLength,
    maxLength,
    timeout
  });

  // Focus management for first input
  const focusFirstInput = useCallback(() => {
    if (enabled && firstInputRef.current) {
      firstInputRef.current.focus();
    }
  }, [enabled]);

  const startFocusMaintenance = useCallback(() => {
    if (focusIntervalRef.current) {
      clearInterval(focusIntervalRef.current);
    }
    
    focusIntervalRef.current = setInterval(() => {
      if (enabled && firstInputRef.current && !firstInputRef.current.isFocused()) {
        firstInputRef.current.focus();
      }
    }, 2000);
  }, [enabled]);

  const stopFocusMaintenance = useCallback(() => {
    if (focusIntervalRef.current) {
      clearInterval(focusIntervalRef.current);
      focusIntervalRef.current = null;
    }
  }, []);

  // Focus effect for screen navigation
  useFocusEffect(
    useCallback(() => {
      if (enabled) {
        setTimeout(() => {
          focusFirstInput();
        }, 100);
        startFocusMaintenance();
      }

      return () => {
        stopFocusMaintenance();
      };
    }, [enabled, focusFirstInput, startFocusMaintenance, stopFocusMaintenance])
  );

  // Handle changes to enabled
  useEffect(() => {
    if (enabled) {
      focusFirstInput();
      startFocusMaintenance();
    } else {
      stopFocusMaintenance();
    }
  }, [enabled, focusFirstInput, startFocusMaintenance, stopFocusMaintenance]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopFocusMaintenance();
    };
  }, [stopFocusMaintenance]);

  // Scanner status tracking (silent for performance)

  if (!enabled) {
    return null;
  }

  // ScrollView with keyboardShouldPersistTaps to suppress iOS keyboard
  return (
    <ScrollView 
      keyboardShouldPersistTaps="always"
      style={styles.scannerContainer}
      showsVerticalScrollIndicator={false}
      showsHorizontalScrollIndicator={false}
      pointerEvents="none"
    >
      {/* First TextInput - Receives HID scanner input */}
      <TextInput
        ref={firstInputRef}
        style={[
          styles.hiddenInput,
          debugVisible && styles.debugVisibleFirst,
          style
        ]}
        autoFocus={true}
        editable={true}
        // iOS keyboard suppression
        showSoftInputOnFocus={false}
        contextMenuHidden={true}
        spellCheck={false}
        autoCorrect={false}
        autoCapitalize="none"
        keyboardType="default"
        onFocus={() => {
          // Ensure second input is cleared when first input gains focus
          if (secondInputRef.current) {
            secondInputRef.current.clear();
            secondInputRef.current.setNativeProps({ text: '' });
          }
        }}
        onBlur={() => {
          if (enabled) {
            setTimeout(() => {
              if (enabled && firstInputRef.current && !firstInputRef.current.isFocused()) {
                firstInputRef.current.focus();
              }
            }, 100);
          }
        }}
        onChangeText={(text) => {
          // Silent safety check - if text gets too long, clear it to prevent concatenation issues
          if (text.length > maxLength) {
            if (firstInputRef.current) {
              firstInputRef.current.clear();
            }
          }
        }}
        onSubmitEditing={(event) => {
          // Upon Enter key from barcode scanner, transfer complete string to second input
          const completeBarcode = event.nativeEvent.text.trim();
          
          if (completeBarcode.length > 0 && secondInputRef.current && processBarcodeInput) {
            // Step 1: Clear first input immediately
            if (firstInputRef.current) {
              firstInputRef.current.clear();
            }
            
            // Step 2: Set second input with the barcode
            secondInputRef.current.setNativeProps({ text: completeBarcode });
            
            // Step 3: Process the barcode
            processBarcodeInput(completeBarcode);
            
            // Step 4: Clear second input immediately after processing
            setTimeout(() => {
              if (secondInputRef.current) {
                secondInputRef.current.clear();
                secondInputRef.current.setNativeProps({ text: '' });
              }
            }, 50);
          }
          
          // Refocus first input for next scan
          setTimeout(() => {
            focusFirstInput();
          }, 100);
        }}
        onKeyPress={(event) => {
          // Silent Enter key detection - no logging needed for performance
        }}
        blurOnSubmit={false}
        placeholder=""
      />

      {/* Second TextInput - Holds the transferred barcode */}
      <TextInput
        ref={secondInputRef}
        style={[
          styles.hiddenInput,
          debugVisible && styles.debugVisibleSecond,
          style
        ]}
        editable={false}
        placeholder=""
      />
    </ScrollView>
  );
});

const styles = StyleSheet.create({
  hiddenInput: {
    height: 0,
    opacity: 0,
    position: 'absolute'
  },
  debugVisibleFirst: {
    position: 'absolute',
    top: 10,
    left: 10,
    width: 200,
    height: 40,
    opacity: 1,
    backgroundColor: 'red',
    borderWidth: 2,
    borderColor: 'blue',
    color: 'white',
    fontSize: 12,
    textAlign: 'center',
    textAlignVertical: 'center'
  },
  debugVisibleSecond: {
    position: 'absolute',
    top: 60,
    left: 10,
    width: 200,
    height: 40,
    opacity: 1,
    backgroundColor: 'green',
    borderWidth: 2,
    borderColor: 'yellow',
    color: 'white',
    fontSize: 12,
    textAlign: 'center',
    textAlignVertical: 'center'
  },
  scannerContainer: {
    position: 'absolute',
    top: -1000, // Move far off-screen instead of using height: 0, width: 0
    left: -1000,
    height: 1,
    width: 1,
    overflow: 'hidden',
    zIndex: -1 // Ensure it's behind everything else
  }
});

export default BarcodeScanner;