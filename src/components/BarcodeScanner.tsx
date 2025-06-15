import React, { useRef, useCallback, useEffect } from 'react';
import { TextInput, StyleSheet } from 'react-native';
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
  debugVisible?: boolean; // For debugging - makes the hidden input visible
}

const TAG = '[BarcodeScanner]';

export const BarcodeScanner: React.FC<BarcodeScannerProps> = ({
  onScan,
  onError,
  enabled = true,
  minLength = 8,
  maxLength = 50,
  timeout = 1000,
  style,
  debugVisible = false
}) => {
  const scannerInputRef = useRef<TextInput>(null);

  // Initialize barcode scanner hook
  const { 
    isListening, 
    isKeyEventAvailable,
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
    logger.info(TAG, `Scanner status - isListening: ${isListening}, isKeyEventAvailable: ${isKeyEventAvailable}, enabled: ${enabled}`);
  }, [isListening, isKeyEventAvailable, enabled]);

  // Focus management when screen becomes active
  useFocusEffect(
    useCallback(() => {
      if (!enabled) {
        logger.info(TAG, 'Scanner disabled - skipping focus setup');
        return;
      }

      logger.info(TAG, 'Screen focused - setting up scanner focus');
      
      // Focus the scanner input when screen becomes active
      const focusTimer = setTimeout(() => {
        if (scannerInputRef.current) {
          scannerInputRef.current.focus();
          logger.info(TAG, 'Scanner input focused via useFocusEffect');
        }
      }, 100);

      // Set up interval to maintain focus
      const focusInterval = setInterval(() => {
        if (scannerInputRef.current && !scannerInputRef.current.isFocused()) {
          scannerInputRef.current.focus();
          logger.info(TAG, 'Scanner input refocused via interval');
        }
      }, 2000);

      return () => {
        clearTimeout(focusTimer);
        clearInterval(focusInterval);
        logger.info(TAG, 'Screen unfocused - cleaning up scanner focus');
      };
    }, [enabled])
  );

  // Method to manually refocus (useful after modal dismissals)
  const refocus = useCallback(() => {
    if (enabled && scannerInputRef.current) {
      setTimeout(() => {
        scannerInputRef.current?.focus();
        logger.info(TAG, 'Scanner manually refocused');
      }, 100);
    }
  }, [enabled]);

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
      autoFocus={true}
      showSoftInputOnFocus={false}
      keyboardType="default"
      editable={true}
      onFocus={() => {
        logger.info(TAG, 'Scanner TextInput focused');
      }}
      onBlur={() => {
        logger.warn(TAG, 'Scanner TextInput lost focus - attempting to refocus');
        setTimeout(() => {
          scannerInputRef.current?.focus();
        }, 100);
      }}
      onChangeText={(text) => {
        // Just log the input - don't store in state to avoid race conditions
        logger.info(TAG, `onChangeText: "${text}" (${text.length} chars)`);
      }}
      onSubmitEditing={(event) => {
        // Get value directly from the event to avoid race conditions
        const text = event.nativeEvent.text.trim();
        logger.info(TAG, `onSubmitEditing (Enter pressed): "${text}" (${text.length} chars)`);
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
      placeholder="Scan here"
    />
  );
};

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

    // Initialize barcode scanner hook
    const { 
      isListening, 
      isKeyEventAvailable,
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
      logger.info(TAG, `Scanner status - isListening: ${isListening}, isKeyEventAvailable: ${isKeyEventAvailable}, enabled: ${props.enabled}`);
    }, [isListening, isKeyEventAvailable, props.enabled]);

    // Focus management when screen becomes active
    useFocusEffect(
      useCallback(() => {
        if (props.enabled === false) {
          logger.info(TAG, 'Scanner disabled - skipping focus setup');
          return;
        }

        logger.info(TAG, 'Screen focused - setting up scanner focus');
        
        // Focus the scanner input when screen becomes active
        const focusTimer = setTimeout(() => {
          if (scannerInputRef.current) {
            scannerInputRef.current.focus();
            logger.info(TAG, 'Scanner input focused via useFocusEffect');
          }
        }, 100);

        // Set up interval to maintain focus
        const focusInterval = setInterval(() => {
          if (scannerInputRef.current && !scannerInputRef.current.isFocused()) {
            scannerInputRef.current.focus();
            logger.info(TAG, 'Scanner input refocused via interval');
          }
        }, 2000);

        return () => {
          clearTimeout(focusTimer);
          clearInterval(focusInterval);
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
          setTimeout(() => {
            scannerInputRef.current?.focus();
            logger.info(TAG, 'Scanner manually refocused via ref');
          }, 100);
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
        autoFocus={true}
        showSoftInputOnFocus={false}
        keyboardType="default"
        editable={true}
        onFocus={() => {
          logger.info(TAG, 'Scanner TextInput focused');
        }}
        onBlur={() => {
          logger.warn(TAG, 'Scanner TextInput lost focus - attempting to refocus');
          setTimeout(() => {
            scannerInputRef.current?.focus();
          }, 100);
        }}
        onChangeText={(text) => {
          // Just log the input - don't store in state to avoid race conditions
          logger.info(TAG, `onChangeText: "${text}" (${text.length} chars)`);
        }}
        onSubmitEditing={(event) => {
          // Get value directly from the event to avoid race conditions
          const text = event.nativeEvent.text.trim();
          logger.info(TAG, `onSubmitEditing (Enter pressed): "${text}" (${text.length} chars)`);
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
        placeholder="Scan here"
      />
    );
  }
);

const styles = StyleSheet.create({
  hiddenInput: {
    position: 'absolute',
    top: 10,
    left: 10,
    width: 50,
    height: 30,
    opacity: 0.1,
    backgroundColor: 'transparent',
    borderWidth: 0,
    color: 'transparent'
  },
  debugVisible: {
    opacity: 1,
    backgroundColor: 'red',
    borderWidth: 1,
    borderColor: 'blue',
    color: 'black'
  }
});

export default BarcodeScanner; 