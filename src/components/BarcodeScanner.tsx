import React, { useRef, useCallback, useEffect } from 'react';
import { TextInput, StyleSheet, Platform } from 'react-native';
import { useFocusEffect } from 'expo-router';
import Constants from 'expo-constants';
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
  debugVisible?: boolean; // For debugging - makes the hidden input visible
}

const TAG = '[BarcodeScanner]';

// Environment detection for future custom UITextField implementation
const isEASBuild = Constants.executionEnvironment === 'standalone';
const isExpoGo = Constants.executionEnvironment === 'storeClient';
const canUseCustomUITextField = Platform.OS === 'ios' && isEASBuild;

logger.info(TAG, `Environment: EAS=${isEASBuild}, ExpoGo=${isExpoGo}, CustomUITextField=${canUseCustomUITextField}`);

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
  const scannerInputRef = useRef<TextInput>(null);
  const isReadyRef = useRef<boolean>(false);

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

  // Log scanner status for debugging
  useEffect(() => {
    logger.info(TAG, `Scanner status - isListening: ${isListening}, enabled: ${enabled}`);
  }, [isListening, enabled]);

  // Focus management when screen becomes active - ensure TextInput is fully ready
  useFocusEffect(
    useCallback(() => {
      if (!enabled) {
        logger.info(TAG, 'Scanner disabled - skipping focus setup');
        return;
      }

      logger.info(TAG, 'Screen focused - setting up scanner focus');
      
      // Give more time for TextInput to be fully mounted and ready
      const focusTimer = setTimeout(() => {
        if (scannerInputRef.current) {
          scannerInputRef.current.focus();
          logger.info(TAG, 'Scanner input focused via useFocusEffect');
          
          // Additional time to ensure focus is fully established
          setTimeout(() => {
            isReadyRef.current = true;
            logger.info(TAG, 'Scanner fully ready for input');
          }, 100);
        }
      }, 500); // Increased from 200ms to 500ms

      return () => {
        clearTimeout(focusTimer);
        logger.info(TAG, 'Screen unfocused - cleaning up scanner focus');
      };
    }, [enabled])
  );

  if (!enabled) {
    return null;
  }

  return (
          <TextInput
        ref={scannerInputRef}
        style={[
          styles.hiddenInput,
          debugVisible && styles.debugVisible,
          style
        ]}
        autoFocus={false}
        editable={true}
        contextMenuHidden={true}
      onFocus={() => {
        logger.info(TAG, 'Scanner TextInput focused - ready to receive barcode input');
      }}
      onBlur={() => {
        logger.info(TAG, 'Scanner TextInput lost focus');
        // Only refocus if the component is still enabled and mounted
        // Use a longer delay to avoid interfering with modals
        setTimeout(() => {
          if (scannerInputRef.current && enabled) {
            // Check if the input is still mounted and component is visible
            try {
              const isFocused = scannerInputRef.current.isFocused();
              if (!isFocused) {
                scannerInputRef.current.focus();
                logger.info(TAG, 'Scanner gently refocused after blur');
              }
            } catch (error) {
              // Input might be unmounted, ignore
              logger.info(TAG, 'Scanner refocus skipped - input unmounted');
            }
          }
        }, enabled ? 800 : 1500); // Shorter delay when enabled, longer when disabled for modals
      }}
      onChangeText={(text) => {
        // This is the uncontrolled TextInput - just log, don't interfere
        logger.info(TAG, `Uncontrolled TextInput onChangeText: "${text}" (${text.length} chars)`);
      }}
      onSubmitEditing={(event) => {
        // Get the complete text directly from the uncontrolled TextInput
        const text = event.nativeEvent.text.trim();
        
        logger.info(TAG, `Uncontrolled TextInput onSubmitEditing: "${text}" (${text.length} chars)`);
        if (text.length > 0 && processBarcodeInput) {
          processBarcodeInput(text);
        }
        // Clear the input for next scan
        if (scannerInputRef.current) {
          scannerInputRef.current.clear();
        }
      }}
      onKeyPress={(event) => {
        // Log key presses to see when Enter is pressed
        if (event.nativeEvent.key === 'Enter') {
          logger.info(TAG, 'Enter key detected!');
        } else {
          logger.info(TAG, `Key: "${event.nativeEvent.key}"`);
        }
      }}
      blurOnSubmit={false}
      placeholder="Scan barcode or search items..."
    />
  );
});

// Create a ref type for external access
export interface BarcodeScannerRef {
  focus: () => void;
  blur: () => void;
  clear: () => void;
  isFocused: () => boolean;
  refocus: () => void;
}

// Forward ref version for when parent needs direct access
export const BarcodeScannerWithRef = React.forwardRef<BarcodeScannerRef, BarcodeScannerProps>(
  (props, ref) => {
    const scannerInputRef = useRef<TextInput>(null);
    const isReadyRef = useRef<boolean>(false);

    // Initialize barcode scanner hook
    const { 
      isListening, 
      processBarcodeInput
    } = useBarcodeScanner({
      onScan: props.onScan,
      onError: props.onError,
      enabled: props.enabled,
      minLength: props.minLength,
      maxLength: props.maxLength,
      timeout: props.timeout
    });

    // Log scanner status for debugging
    useEffect(() => {
      logger.info(TAG, `Scanner status - isListening: ${isListening}, enabled: ${props.enabled}`);
    }, [isListening, props.enabled]);

    // Focus management when screen becomes active - ensure TextInput is fully ready
    useFocusEffect(
      useCallback(() => {
        if (props.enabled === false) {
          logger.info(TAG, 'Scanner disabled - skipping focus setup');
          return;
        }

        logger.info(TAG, 'Screen focused - setting up scanner focus');
        
        // Give more time for TextInput to be fully mounted and ready
        const focusTimer = setTimeout(() => {
          if (scannerInputRef.current) {
            scannerInputRef.current.focus();
            logger.info(TAG, 'Scanner input focused via useFocusEffect');
            
            // Additional time to ensure focus is fully established
            setTimeout(() => {
              isReadyRef.current = true;
              logger.info(TAG, 'Scanner fully ready for input');
            }, 100);
          }
        }, 500); // Increased from 200ms to 500ms

        return () => {
          clearTimeout(focusTimer);
          logger.info(TAG, 'Screen unfocused - cleaning up scanner focus');
        };
      }, [props.enabled])
    );

    // Expose methods via ref
    React.useImperativeHandle(ref, () => ({
      focus: () => scannerInputRef.current?.focus(),
      blur: () => scannerInputRef.current?.blur(),
      clear: () => scannerInputRef.current?.clear(),
      isFocused: () => scannerInputRef.current?.isFocused() || false,
      refocus: () => {
        if (props.enabled !== false && scannerInputRef.current) {
          scannerInputRef.current?.focus();
          logger.info(TAG, 'Scanner manually refocused via ref');
        }
      }
    }));

    if (props.enabled === false) {
      return null;
    }

    return (
      <TextInput
        ref={scannerInputRef}
        style={[
          styles.hiddenInput,
          props.debugVisible && styles.debugVisible,
          props.style
        ]}
        autoFocus={false}
        editable={true}
        contextMenuHidden={true}
      onFocus={() => {
        logger.info(TAG, 'Scanner TextInput focused - ready to receive barcode input');
      }}
      onBlur={() => {
        logger.info(TAG, 'Scanner TextInput lost focus');
        // Only refocus if the component is still enabled and mounted
        // Use a longer delay to avoid interfering with modals
        setTimeout(() => {
          if (scannerInputRef.current && props.enabled) {
            // Check if the input is still mounted and component is visible
            try {
              const isFocused = scannerInputRef.current.isFocused();
              if (!isFocused) {
                scannerInputRef.current.focus();
                logger.info(TAG, 'Scanner gently refocused after blur');
              }
            } catch (error) {
              // Input might be unmounted, ignore
              logger.info(TAG, 'Scanner refocus skipped - input unmounted');
            }
          }
        }, props.enabled ? 800 : 1500); // Shorter delay when enabled, longer when disabled for modals
      }}
      onChangeText={(text) => {
        // This is the uncontrolled TextInput - just log, don't interfere
        logger.info(TAG, `Uncontrolled TextInput onChangeText: "${text}" (${text.length} chars)`);
      }}
      onSubmitEditing={(event) => {
        // Get the complete text directly from the uncontrolled TextInput
        const text = event.nativeEvent.text.trim();
        
        logger.info(TAG, `Uncontrolled TextInput onSubmitEditing: "${text}" (${text.length} chars)`);
        if (text.length > 0 && processBarcodeInput) {
          processBarcodeInput(text);
        }
        // Clear the input for next scan
        if (scannerInputRef.current) {
          scannerInputRef.current.clear();
        }
      }}
      onKeyPress={(event) => {
        // Log key presses to see when Enter is pressed
        if (event.nativeEvent.key === 'Enter') {
          logger.info(TAG, 'Enter key detected!');
        } else {
          logger.info(TAG, `Key: "${event.nativeEvent.key}"`);
        }
      }}
      blurOnSubmit={false}
      placeholder="Scan barcode or search items..."
    />
  );
});

const styles = StyleSheet.create({
  hiddenInput: {
    height: 0,
    opacity: 0,
    position: 'absolute'
  },
  debugVisible: {
    position: 'absolute',
    top: 10,
    left: 10,
    width: 100,
    height: 40,
    opacity: 1,
    backgroundColor: 'red',
    borderWidth: 2,
    borderColor: 'blue',
    color: 'white',
    fontSize: 12,
    textAlign: 'center',
    textAlignVertical: 'center'
  }
});

export default BarcodeScanner; 