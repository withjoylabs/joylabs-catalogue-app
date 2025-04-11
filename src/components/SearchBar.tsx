import React, { forwardRef, useState, useRef, useEffect } from 'react';
import { View, TextInput, TouchableOpacity, StyleSheet, Text, NativeSyntheticEvent, TextInputKeyPressEventData, TextInput as RNTextInput, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  onSubmit?: () => void;
  onClear?: () => void;
  placeholder?: string;
  autoSearchOnEnter: boolean;
  autoSearchOnTab: boolean;
}

const SearchBar = forwardRef<RNTextInput, SearchBarProps>((
  {
    value,
    onChangeText,
    onSubmit,
    onClear,
    placeholder = 'Ready to Scan Item',
    autoSearchOnEnter,
    autoSearchOnTab,
  },
  ref
) => {
  // Capture input values
  const [accumulatedValue, setAccumulatedValue] = useState<string>(value || "");
  
  // Scanner buffering and timing management
  const isScanningRef = useRef<boolean>(false);
  const isInitializedRef = useRef<boolean>(false);
  const preInitBuffer = useRef<string[]>([]);
  const inputFieldRef = useRef<RNTextInput | null>(null);
  
  // For timeout management
  const scanCompleteTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const processScanTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  
  // Initialize immediately with pre-scan capture capabilities
  useEffect(() => {
    // Enable pre-initialization capture
    isInitializedRef.current = true;
    
    // Process any pre-init buffer content
    const bufferContent = preInitBuffer.current.join('');
    if (bufferContent) {
      // If we have buffered content, use it
      handleInputChange(bufferContent);
      preInitBuffer.current = [];
    }
    
    return () => {
      isInitializedRef.current = false;
      clearAllTimeouts();
    };
  }, []);
  
  // Handle incoming input
  const handleInputChange = (newInput: string) => {
    // Update UI immediately
    setAccumulatedValue(newInput);
    
    // Start/continue the scanning process
    isScanningRef.current = true;
    
    // Reset any existing scan completion timer
    if (scanCompleteTimeoutRef.current) {
      clearTimeout(scanCompleteTimeoutRef.current);
    }
    
    // Set new completion timer
    scanCompleteTimeoutRef.current = setTimeout(() => {
      // Scanning has completed, process the input
      processScan(newInput);
      scanCompleteTimeoutRef.current = null;
    }, 300);
  };
  
  // Process a completed scan
  const processScan = (scanText: string) => {
    if (!isScanningRef.current) return;
    
    isScanningRef.current = false;
    const trimmedScan = scanText.trim();
    
    // Update parent state
    if (onChangeText && trimmedScan !== value) {
      onChangeText(trimmedScan);
    }
    
    // Clean up any pending process timers
    if (processScanTimeoutRef.current) {
      clearTimeout(processScanTimeoutRef.current);
    }
    
    // Auto-submit if configured
    if (autoSearchOnEnter && onSubmit && trimmedScan.length > 0) {
      processScanTimeoutRef.current = setTimeout(() => {
        onSubmit();
        processScanTimeoutRef.current = null;
      }, 50);
    }
  };
  
  // Handle special keys like Tab
  const handleKeyPress = (e: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
    if (e.nativeEvent.key === 'Tab' && autoSearchOnTab && onSubmit) {
      // @ts-ignore - preventDefault may not exist in React Native, but some scanners send it
      if (e.preventDefault) e.preventDefault();
      
      // Immediately process the current scan when Tab is detected
      if (scanCompleteTimeoutRef.current) {
        clearTimeout(scanCompleteTimeoutRef.current);
        scanCompleteTimeoutRef.current = null;
      }
      
      processScan(accumulatedValue);
    }
  };
  
  // Handle pressing the GO button
  const handleSubmit = () => {
    if (scanCompleteTimeoutRef.current) {
      clearTimeout(scanCompleteTimeoutRef.current);
      scanCompleteTimeoutRef.current = null;
    }
    
    processScan(accumulatedValue);
    
    if (onSubmit) {
      onSubmit();
    }
  };
  
  // Clear the input field
  const handleClear = () => {
    setAccumulatedValue("");
    preInitBuffer.current = [];
    isScanningRef.current = false;
    clearAllTimeouts();
    
    if (onClear) {
      onClear();
    }
  };
  
  // Helper to clear all timeouts
  const clearAllTimeouts = () => {
    if (scanCompleteTimeoutRef.current) {
      clearTimeout(scanCompleteTimeoutRef.current);
      scanCompleteTimeoutRef.current = null;
    }
    if (processScanTimeoutRef.current) {
      clearTimeout(processScanTimeoutRef.current);
      processScanTimeoutRef.current = null;
    }
  };
  
  // Sync local value with parent when not scanning
  useEffect(() => {
    if (!isScanningRef.current && value !== accumulatedValue) {
      setAccumulatedValue(value || "");
    }
  }, [value]);
  
  // Clean up on unmount
  useEffect(() => {
    return clearAllTimeouts;
  }, []);

  // Save the ref for direct access if needed
  const setRefs = (input: RNTextInput | null) => {
    // Forward the ref to the parent
    if (typeof ref === 'function') {
      ref(input);
    } else if (ref) {
      ref.current = input;
    }
    
    // Also keep our local ref
    inputFieldRef.current = input;
  };

  return (
    <View style={styles.container}>
      <View style={styles.searchContainer}>
        <Ionicons name="search" size={24} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={setRefs}
          style={styles.input}
          value={accumulatedValue}
          onChangeText={handleInputChange}
          placeholder={placeholder}
          placeholderTextColor="#999"
          onSubmitEditing={handleSubmit}
          returnKeyType="search"
          clearButtonMode="never" // Fix duplicate X issue by disabling built-in clear button
          onKeyPress={handleKeyPress}
          blurOnSubmit={false}
          keyboardType="default" // Default keyboard better for scanner input
        />
        {accumulatedValue.length > 0 && (
          <TouchableOpacity onPress={handleClear} style={styles.clearButton}>
            <Ionicons name="close-circle" size={18} color="#aaa" />
          </TouchableOpacity>
        )}
      </View>
      
      <TouchableOpacity 
        style={styles.goButton}
        onPress={handleSubmit}
      >
        <Text style={styles.goButtonText}>GO</Text>
      </TouchableOpacity>
    </View>
  );
});

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingHorizontal: 15,
    paddingVertical: 10,
    alignItems: 'center',
  },
  searchContainer: {
    flexDirection: 'row',
    flex: 1,
    backgroundColor: 'white',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 20,
    alignItems: 'center',
    paddingHorizontal: 12,
    height: 46,
  },
  searchIcon: {
    marginRight: 8,
  },
  input: {
    flex: 1,
    fontSize: 16,
    height: 46,
    color: '#333',
  },
  clearButton: {
    padding: 4,
    zIndex: 10, // Ensure our custom clear button is on top
  },
  goButton: {
    backgroundColor: lightTheme.colors.primary,
    width: 50,
    height: 50,
    borderRadius: 25,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 10,
  },
  goButtonText: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
  },
});

export default SearchBar; 