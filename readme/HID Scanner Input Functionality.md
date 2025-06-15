# HID Scanner Input Functionality

## Overview

This document provides a comprehensive guide to implementing hardware barcode scanner functionality in React Native using HID (Human Interface Device) input. Hardware barcode scanners typically connect via Bluetooth and act as keyboard input devices, sending complete barcode data followed by an Enter key press.

## Table of Contents

1. [Background & Problem](#background--problem)
2. [Technical Architecture](#technical-architecture)
3. [Implementation Details](#implementation-details)
4. [Database Search Integration](#database-search-integration)
5. [Error Handling & User Feedback](#error-handling--user-feedback)
6. [Testing & Debugging](#testing--debugging)
7. [Common Issues & Solutions](#common-issues--solutions)
8. [Future Improvements](#future-improvements)

## Background & Problem

### Initial Challenge
Hardware barcode scanners are Bluetooth HID devices that act like keyboards. When scanning a barcode, they:
1. Send each character of the barcode individually as key presses
2. Send an Enter key press at the end
3. All input happens very quickly (within ~100-200ms)

### Failed Approaches
1. **react-native-keyevent**: Doesn't work with Expo SDK 53+ and requires Objective-C (not Swift)
2. **Complex buffer accumulation**: Trying to capture character-by-character input led to race conditions
3. **Controlled TextInput**: React state updates couldn't keep up with rapid scanner input

### Successful Solution
Use an **uncontrolled TextInput** that captures the complete barcode string in `onSubmitEditing` when the Enter key is pressed. This has been implemented as a **reusable BarcodeScanner component** that encapsulates all the logic.

## Technical Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    HID Scanner Flow                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Hardware Scanner (Bluetooth HID)                        │
│    ├── Sends barcode digits as key presses                 │
│    └── Sends Enter key at end                              │
│                                                             │
│ 2. BarcodeScanner Component                                 │
│    ├── Hidden TextInput (Uncontrolled)                     │
│    ├── Automatic focus management                          │
│    ├── Triggers onSubmitEditing on Enter                   │
│    └── Exposes refocus/control methods via ref             │
│                                                             │
│ 3. Barcode Scanner Hook (useBarcodeScanner)                │
│    ├── Validates GTIN format (8/12/13/14 digits)          │
│    ├── Handles debouncing/timeout                          │
│    └── Calls success/error callbacks                       │
│                                                             │
│ 4. Database Search Integration                              │
│    ├── Uses performSearch() with barcode-only filters      │
│    ├── Searches complete SQLite database                   │
│    └── Returns SearchResultItem[] results                  │
│                                                             │
│ 5. UI Feedback & Actions                                    │
│    ├── Audio/haptic feedback                               │
│    ├── Modal dialogs for quantity/selection                │
│    └── Error handling with dismissible modals              │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. BarcodeScanner Component

The core of the solution is a reusable `BarcodeScanner` component that encapsulates all scanner functionality:

#### Basic Usage
```typescript
import { BarcodeScanner } from '../components/BarcodeScanner';

// Basic implementation
<BarcodeScanner
  onScan={handleBarcodeScan}
  onError={handleScanError}
  enabled={true}
  minLength={8}
  maxLength={50}
  timeout={1000}
/>
```

#### Advanced Usage with Ref
```typescript
import { BarcodeScannerWithRef, BarcodeScannerRef } from '../components/BarcodeScanner';

const scannerRef = useRef<BarcodeScannerRef>(null);

<BarcodeScannerWithRef
  ref={scannerRef}
  onScan={handleBarcodeScan}
  onError={handleScanError}
  enabled={true}
  debugVisible={false}  // Set to true for debugging
/>

// Later in code - manually refocus after modal dismissal
scannerRef.current?.refocus();
```

#### Component Props
```typescript
interface BarcodeScannerProps {
  onScan: (barcode: string) => void;           // Callback for successful scans
  onError: (error: string) => void;            // Callback for scan errors
  enabled?: boolean;                           // Enable/disable scanner
  minLength?: number;                          // Minimum barcode length
  maxLength?: number;                          // Maximum barcode length
  timeout?: number;                            // Scanner timeout in ms
  style?: any;                                 // Custom styling
  debugVisible?: boolean;                      // Make hidden input visible for debugging
}
```

#### Ref Methods (BarcodeScannerWithRef)
```typescript
interface BarcodeScannerRef {
  focus: () => void;        // Manually focus the scanner
  blur: () => void;         // Blur the scanner
  clear: () => void;        // Clear the input
  isFocused: () => boolean; // Check if scanner is focused
  refocus: () => void;      // Manually refocus after modal dismissals
}
```

### 2. Focus Management

The `BarcodeScanner` component automatically handles focus management:

- **Automatic focus** when screen becomes active
- **Focus maintenance** with interval checks every 2 seconds
- **Refocus on blur** when focus is lost unexpectedly  
- **Manual refocus** methods for post-modal interactions
- **Cleanup** when screen becomes inactive

#### Manual Focus Control (Advanced)
```typescript
// Using the ref version for manual control
const scannerRef = useRef<BarcodeScannerRef>(null);

// After modal dismissal, refocus the scanner
const handleModalDismiss = () => {
  setShowModal(false);
  // Refocus scanner after modal closes
  scannerRef.current?.refocus();
};

// Check scanner focus state
const isScannerReady = scannerRef.current?.isFocused() ?? false;
```

### 3. Barcode Scanner Hook

The `useBarcodeScanner` hook handles validation and processing:

```typescript
// src/hooks/useBarcodeScanner.ts
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
    
    // Prevent processing too quickly after last successful scan
    if (currentTime - lastScanTime.current < timeout) {
      logger.info(TAG, 'Ignoring input - too soon after last scan');
      return false;
    }
    
    logger.info(TAG, `Processing barcode input: "${trimmedInput}" (${trimmedInput.length} chars)`);
    
    if (isValidGTIN(trimmedInput)) {
      logger.info(TAG, `Valid GTIN-${trimmedInput.length} detected: ${trimmedInput}`);
      onScan(trimmedInput);
      lastScanTime.current = currentTime;
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
    isKeyEventAvailable: true,
    processBarcodeInput,
  };
};
```

## Database Search Integration

### Critical Issue: Data Source Consistency

**Problem**: The original implementation used in-memory store filtering which only searched items currently loaded in memory:

```typescript
// WRONG: Only searches limited in-memory data
const matchingItems = catalogItems.filter((item: ConvertedItem) => 
  item.barcode === barcode
);
```

**Solution**: Use the same database search mechanism as the main screen:

```typescript
// CORRECT: Searches complete local database
const handleBarcodeScan = useCallback(async (barcode: string) => {
  try {
    const searchFilters = {
      name: false,
      sku: false,
      barcode: true, // Only search by barcode
      category: false
    };
    
    const matchingItems = await performSearch(barcode, searchFilters);
    
    if (matchingItems.length === 0) {
      // Handle no results
      playErrorSound();
      setErrorMessage(`No item found with barcode: ${barcode}`);
      setShowErrorModal(true);
      return;
    }
    
    // Handle success cases...
  } catch (error) {
    // Handle search errors
  }
}, [performSearch, ...]);
```

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Data Search Flow                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Barcode Input                                            │
│    └── "801243270508"                                      │
│                                                             │
│ 2. Search Filters                                           │
│    ├── name: false                                         │
│    ├── sku: false                                          │
│    ├── barcode: true  ← Only search by barcode             │
│    └── category: false                                     │
│                                                             │
│ 3. performSearch() Function                                 │
│    ├── Queries local SQLite database                       │
│    ├── Uses searchCatalogItems() from modernDb             │
│    └── Returns SearchResultItem[]                          │
│                                                             │
│ 4. Type Conversion                                          │
│    ├── SearchResultItem → ConvertedItem                    │
│    ├── Maintains all required fields                       │
│    └── Compatible with reorder service                     │
│                                                             │
│ 5. Business Logic                                           │
│    ├── Single item: Show quantity modal                    │
│    ├── Multiple items: Show selection modal                │
│    └── No items: Show error modal                          │
└─────────────────────────────────────────────────────────────┘
```

### Type Conversion

When using `performSearch()`, results come back as `SearchResultItem[]` but the reorder service expects `ConvertedItem[]`:

```typescript
// Convert SearchResultItem to ConvertedItem
const convertedItem: ConvertedItem = {
  id: matchingItems[0].id,
  name: matchingItems[0].name || '',
  sku: matchingItems[0].sku,
  barcode: matchingItems[0].barcode,
  price: matchingItems[0].price,
  category: matchingItems[0].category,
  categoryId: matchingItems[0].categoryId,
  reporting_category_id: matchingItems[0].categoryId || matchingItems[0].reporting_category_id,
  description: matchingItems[0].description,
  isActive: true,
  images: [],
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
};
```

## Error Handling & User Feedback

### Audio/Haptic Feedback

```typescript
// Success feedback
const playSuccessSound = useCallback(() => {
  console.log('🔊 SUCCESS - Item found!');
  logger.info(TAG, 'Playing success feedback');
  // Single short vibration for success
  Vibration.vibrate(100);
}, []);

// Error feedback  
const playErrorSound = useCallback(() => {
  console.log('🔊 ERROR - Scan failed!');  
  logger.info(TAG, 'Playing error feedback');
  // Double vibration pattern for error
  Vibration.vibrate([0, 200, 100, 200]);
}, []);
```

### Modal Management

Handle multiple modal states and auto-dismissal:

```typescript
// If error modal is open, dismiss it with any new scan and refocus scanner
if (showErrorModal) {
  setShowErrorModal(false);
  setErrorMessage('');
  // Refocus the scanner input after modal dismissal
  setTimeout(() => {
    scannerInputRef.current?.focus();
  }, 100);
}

// If quantity modal is open, auto-submit current item with qty 1 and process new scan
if (showQuantityModal && currentScannedItem) {
  logger.info(TAG, 'Auto-submitting current item with qty 1 due to new scan');
  
  try {
    await reorderService.addItem(currentScannedItem, 1);
  } catch (error) {
    logger.error(TAG, 'Error auto-submitting current item', { error });
  }
  setShowQuantityModal(false);
  setCurrentScannedItem(null);
}
```

## Testing & Debugging

### Debug Logging

Comprehensive logging helps troubleshoot scanner issues:

```typescript
// Key press logging
onKeyPress={(event) => {
  if (event.nativeEvent.key === 'Enter') {
    logger.info(TAG, 'Enter key detected!');
  } else {
    logger.info(TAG, `Key: "${event.nativeEvent.key}"`);
  }
}}

// Input change logging
onChangeText={(text) => {
  logger.info(TAG, `onChangeText: "${text}" (${text.length} chars)`);
}}

// Submit logging
onSubmitEditing={(event) => {
  const text = event.nativeEvent.text.trim();
  logger.info(TAG, `onSubmitEditing (Enter pressed): "${text}" (${text.length} chars)`);
}}
```

### Visual Debug Aids

Use the `debugVisible` prop to make the hidden TextInput visible during development:

```typescript
// Make scanner visible for debugging
<BarcodeScanner
  onScan={handleBarcodeScan}
  onError={handleScanError}
  enabled={true}
  debugVisible={true}  // Makes the hidden input visible
/>

// Or with custom styling
<BarcodeScanner
  onScan={handleBarcodeScan}
  onError={handleScanError}
  enabled={true}
  debugVisible={true}
  style={{ 
    backgroundColor: 'yellow',  // Custom debug styling
    borderColor: 'red',
    borderWidth: 2
  }}
/>
```

### Common Test Cases

1. **Valid GTIN-8**: `12345678`
2. **Valid GTIN-12**: `123456789012`
3. **Valid GTIN-13**: `1234567890123`
4. **Valid GTIN-14**: `12345678901234`
5. **Invalid (letters)**: `ABC123DEF456`
6. **Invalid (wrong length)**: `123456789`
7. **Rapid scanning**: Multiple scans within 1 second
8. **Focus loss**: Test modal interactions

## Common Issues & Solutions

### Issue 1: Scanner Input Not Detected

**Symptoms**: No logging in `onChangeText` or `onSubmitEditing`

**Solutions**:
1. Check TextInput focus state
2. Verify `autoFocus={true}` is set
3. Ensure focus management interval is running
4. Check if another input has stolen focus

### Issue 2: Race Conditions with React State

**Symptoms**: `onSubmitEditing` gets old/empty values

**Solutions**:
1. Use uncontrolled TextInput (no `value` prop)
2. Get value from `event.nativeEvent.text` directly
3. Avoid storing scanner input in React state

### Issue 3: Items Not Found Despite Existing

**Symptoms**: Valid barcodes return "No item found"

**Solutions**:
1. Use `performSearch()` instead of in-memory filtering
2. Verify database contains the items
3. Check search filters are correct
4. Ensure barcode field matches exactly

### Issue 4: Focus Loss After Modal Interactions

**Symptoms**: Scanner stops working after modals

**Solutions**:
1. Use `BarcodeScannerWithRef` and call `refocus()` after modal dismissal
2. Use `setTimeout` to delay refocus in custom implementations
3. Component handles `onBlur` events automatically

### Issue 5: Multiple Rapid Scans

**Symptoms**: Scanner processes same barcode multiple times

**Solutions**:
1. Implement timeout-based debouncing
2. Track `lastScanTime` to prevent rapid repeats
3. Clear TextInput after each successful scan

## Future Improvements

### 1. Enhanced Audio Feedback

```typescript
// Use expo-av for actual sound files
import { Audio } from 'expo-av';

const playSuccessSound = async () => {
  const { sound } = await Audio.Sound.createAsync(
    require('../assets/sounds/success.mp3')
  );
  await sound.playAsync();
};
```

### 2. Barcode Format Detection

```typescript
const detectBarcodeFormat = (barcode: string) => {
  if (/^\d{8}$/.test(barcode)) return 'EAN-8';
  if (/^\d{12}$/.test(barcode)) return 'UPC-A';
  if (/^\d{13}$/.test(barcode)) return 'EAN-13';
  if (/^\d{14}$/.test(barcode)) return 'ITF-14';
  return 'Unknown';
};
```

### 3. Scanner Configuration

```typescript
interface ScannerConfig {
  enabledFormats: string[];
  autoSubmitDelay: number;
  enableHapticFeedback: boolean;
  enableAudioFeedback: boolean;
  debugMode: boolean;
}
```

### 4. Multiple Scanner Support

```typescript
// Support for different scanner types/configurations
const scannerProfiles = {
  honeywell: { timeout: 500, enterKey: true },
  zebra: { timeout: 300, enterKey: true },
  generic: { timeout: 1000, enterKey: true }
};
```

## Conclusion

This implementation provides a robust, production-ready solution for hardware barcode scanner integration in React Native. The key insights are:

1. **Use uncontrolled TextInput** to avoid React state race conditions
2. **Search the complete database** rather than in-memory store
3. **Maintain focus aggressively** to ensure scanner input is captured
4. **Provide immediate feedback** for both success and error cases
5. **Handle edge cases** like rapid scanning and modal interactions
6. **Encapsulate complexity** in reusable components for maintainability

The solution is scalable and can be extended for different scanner types, barcode formats, and business requirements.

### Component Benefits

The new `BarcodeScanner` component provides:

- **Reusability**: Use across multiple screens without code duplication
- **Maintainability**: Centralized scanner logic for easier updates
- **Flexibility**: Both basic and advanced (ref-based) usage patterns
- **Debugging**: Built-in debug mode for development
- **Focus Management**: Automatic handling of complex focus scenarios
- **Type Safety**: Full TypeScript support with proper interfaces
 