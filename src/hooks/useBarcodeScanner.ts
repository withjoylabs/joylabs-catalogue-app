import { useEffect, useCallback, useRef } from 'react';
import { Platform } from 'react-native';
import logger from '../utils/logger';

interface BarcodeScannerOptions {
  onScan: (barcode: string) => void;
  onError?: (error: string) => void;
  enabled?: boolean;
  minLength?: number;
  maxLength?: number;
  timeout?: number;
}

const TAG = '[BarcodeScanner]';

export const useBarcodeScanner = ({
  onScan,
  onError,
  enabled = true,
  minLength = 8,
  maxLength = 50,
  timeout = 1000
}: BarcodeScannerOptions) => {
  const isListening = useRef<boolean>(enabled);
  const lastScanTime = useRef<number>(0);
  const lastScannedCode = useRef<string>('');

  useEffect(() => {
    isListening.current = enabled;
    if (enabled) {
      logger.info(TAG, 'Hardware barcode scanner enabled');
    } else {
      logger.info(TAG, 'Hardware barcode scanner disabled');
    }
  }, [enabled]);

  const isValidGTIN = useCallback((code: string): boolean => {
    // Must be all digits
    if (!/^\d+$/.test(code)) {
      return false;
    }
    
    // Must be exact GTIN lengths: 8, 12, 13, or 14 digits
    const validLengths = [8, 12, 13, 14];
    return validLengths.includes(code.length);
  }, []);

  const processBarcodeInput = useCallback((input: string) => {
    const currentTime = Date.now();
    const trimmedInput = input.trim();

    // Ignore empty input
    if (trimmedInput.length === 0) {
      return false;
    }
    
    logger.info(TAG, `Processing barcode input: "${trimmedInput}" (${trimmedInput.length} chars)`);
    
    if (isValidGTIN(trimmedInput)) {
      // Always allow valid scans - the timeout is only to prevent accidental double-processing
      // of the same physical scan action, not to prevent intentional rapid scanning
      if (currentTime - lastScanTime.current < timeout && lastScannedCode.current === trimmedInput) {
        // Only block if it's suspiciously fast (likely same physical scan)
        if (currentTime - lastScanTime.current < 100) { // 100ms threshold for same physical scan
          logger.info(TAG, `Suspected duplicate physical scan ignored - too fast (${currentTime - lastScanTime.current}ms)`);
          return false;
        }
    }

      logger.info(TAG, `Valid GTIN-${trimmedInput.length} detected: ${trimmedInput}`);
      onScan(trimmedInput);
      lastScanTime.current = currentTime;
      lastScannedCode.current = trimmedInput;
      return true;
    } else {
      const errorMsg = `Invalid GTIN format: ${trimmedInput} (${trimmedInput.length} chars, must be 8/12/13/14 digits)`;
      logger.warn(TAG, errorMsg);
      if (onError) {
        onError(errorMsg);
      }
      return false;
    }
  }, [onScan, onError, isValidGTIN, timeout]);

  return {
    isListening: enabled,
    processBarcodeInput,
  };
}; 