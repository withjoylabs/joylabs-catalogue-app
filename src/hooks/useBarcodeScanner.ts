import { useEffect, useCallback, useRef } from 'react';
import { Platform } from 'react-native';
import logger from '../utils/logger';

// Safely import KeyEvent with error handling
let KeyEvent: any = null;
try {
  KeyEvent = require('react-native-keyevent');
} catch (error) {
  logger.warn('[BarcodeScanner]', 'react-native-keyevent not available:', error);
}

interface BarcodeScannerOptions {
  onScan: (barcode: string) => void;
  enabled?: boolean;
  minLength?: number;
  maxLength?: number;
  timeout?: number; // Time in ms to wait for complete barcode
}

const TAG = '[BarcodeScanner]';

export const useBarcodeScanner = ({
  onScan,
  enabled = true,
  minLength = 4,
  maxLength = 50,
  timeout = 100
}: BarcodeScannerOptions) => {
  const barcodeBuffer = useRef<string>('');
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastKeyTime = useRef<number>(0);
  const isKeyEventAvailable = useRef<boolean>(false);

  // Check if KeyEvent is available and properly initialized
  useEffect(() => {
    if (KeyEvent && typeof KeyEvent.onKeyDownListener === 'function') {
      isKeyEventAvailable.current = true;
      logger.info(TAG, 'KeyEvent module is available');
    } else {
      isKeyEventAvailable.current = false;
      logger.warn(TAG, 'KeyEvent module is not available - barcode scanning disabled');
    }
  }, []);

  const processBarcodeBuffer = useCallback(() => {
    const barcode = barcodeBuffer.current.trim();
    
    if (barcode.length >= minLength && barcode.length <= maxLength) {
      logger.info(TAG, `Barcode scanned: ${barcode}`);
      onScan(barcode);
    } else if (barcode.length > 0) {
      logger.warn(TAG, `Invalid barcode length: ${barcode} (${barcode.length} chars)`);
    }
    
    // Clear buffer
    barcodeBuffer.current = '';
  }, [onScan, minLength, maxLength]);

  const handleKeyEvent = useCallback((keyEvent: any) => {
    if (!enabled || !isKeyEventAvailable.current) return;

    const currentTime = Date.now();
    const { pressedKey, action } = keyEvent;

    // Only process key down events
    if (action !== 'keydown') return;

    // Clear timeout if it exists
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }

    // Check if this is likely a new barcode scan (significant time gap)
    if (currentTime - lastKeyTime.current > 500) {
      barcodeBuffer.current = '';
    }
    lastKeyTime.current = currentTime;

    // Handle special keys
    if (pressedKey === 'Enter' || pressedKey === 'Return') {
      // Barcode scanner typically sends Enter/Return at the end
      processBarcodeBuffer();
      return;
    }

    // Ignore modifier keys and other special keys
    const ignoredKeys = [
      'Shift', 'Control', 'Alt', 'Meta', 'CapsLock', 'Tab', 'Escape',
      'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Backspace', 'Delete'
    ];
    
    if (ignoredKeys.includes(pressedKey)) {
      return;
    }

    // Add character to buffer
    if (pressedKey && pressedKey.length === 1) {
      barcodeBuffer.current += pressedKey;
      
      // Set timeout to process buffer if no more keys come
      timeoutRef.current = setTimeout(() => {
        processBarcodeBuffer();
      }, timeout);
    }
  }, [enabled, processBarcodeBuffer, timeout]);

  useEffect(() => {
    if (!enabled || !isKeyEventAvailable.current) {
      logger.info(TAG, 'Scanner disabled or KeyEvent not available');
      return;
    }

    logger.info(TAG, 'Starting barcode scanner listener');

    try {
      // Add key event listener with error handling
      KeyEvent.onKeyDownListener(handleKeyEvent);
    } catch (error) {
      logger.error(TAG, 'Failed to start key event listener:', error);
      isKeyEventAvailable.current = false;
      return;
    }

    return () => {
      logger.info(TAG, 'Stopping barcode scanner listener');
      
      try {
        // Clean up with error handling
        if (KeyEvent && typeof KeyEvent.removeKeyDownListener === 'function') {
          KeyEvent.removeKeyDownListener();
        }
      } catch (error) {
        logger.warn(TAG, 'Error removing key event listener:', error);
      }
      
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
        timeoutRef.current = null;
      }
      
      barcodeBuffer.current = '';
    };
  }, [enabled, handleKeyEvent]);

  // Clean up on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return {
    isListening: enabled && isKeyEventAvailable.current,
    currentBuffer: barcodeBuffer.current,
    isKeyEventAvailable: isKeyEventAvailable.current
  };
}; 