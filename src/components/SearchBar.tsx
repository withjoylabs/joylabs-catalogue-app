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
  // Track if we're currently handling a barcode scan
  const isScanning = useRef(false);
  const scanTimeout = useRef<NodeJS.Timeout | null>(null);

  // Handle input change directly
  const handleInputChange = (newInput: string) => {
    // If the input is numeric and longer than 8 digits, assume it's a barcode scan
    if (/^\d+$/.test(newInput) && newInput.length > 8) {
      isScanning.current = true;
    }
    onChangeText(newInput);
  };
  
  // Handle special keys like Tab or Enter
  const handleKeyPress = (e: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
    // Basic Enter key handling
    if (e.nativeEvent.key === 'Enter' && autoSearchOnEnter && onSubmit) {
      onSubmit();
    }
    
    // Tab key handling for barcode scanners
    if (e.nativeEvent.key === 'Tab' && autoSearchOnTab && onSubmit) {
      // @ts-ignore - preventDefault may not exist in React Native, but some scanners send it
      if (e.preventDefault) e.preventDefault();
      
      // Clear any existing timeout
      if (scanTimeout.current) {
        clearTimeout(scanTimeout.current);
      }
      
      // Set a timeout to allow the last character to be entered
      // Increased to 100ms to be more reliable with different scanners
      scanTimeout.current = setTimeout(() => {
        if (onSubmit && isScanning.current) {
          onSubmit();
          isScanning.current = false;
        }
      }, 100);
    }
  };
  
  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (scanTimeout.current) {
        clearTimeout(scanTimeout.current);
      }
    };
  }, []);
  
  // Handle pressing the GO button or submitting from keyboard
  const handleSubmit = () => {
    if (onSubmit) {
      onSubmit();
    }
  };
  
  // Clear the input field
  const handleClear = () => {
    onChangeText('');
    isScanning.current = false;
    if (onClear) {
      onClear();
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.searchContainer}>
        <Ionicons name="search" size={24} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={ref}
          style={styles.input}
          value={value}
          onChangeText={handleInputChange}
          placeholder={placeholder}
          placeholderTextColor="#999"
          onSubmitEditing={handleSubmit}
          returnKeyType="search"
          clearButtonMode="never"
          onKeyPress={handleKeyPress}
          blurOnSubmit={false}
          keyboardType="numeric" // Changed to numeric for better barcode scanning
          autoCapitalize="none"
          autoCorrect={false}
        />
        {value.length > 0 && (
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