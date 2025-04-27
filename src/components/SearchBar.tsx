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
  // Directly use props for value and onChangeText
  
  // Handle input change directly
  const handleInputChange = (newInput: string) => {
    // Call parent's handler immediately
    onChangeText(newInput);
  };
  
  // Handle special keys like Tab or Enter (if needed, but simplified)
  const handleKeyPress = (e: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
    // Basic Enter key handling (if autoSearchOnEnter is true)
    if (e.nativeEvent.key === 'Enter' && autoSearchOnEnter && onSubmit) {
      onSubmit();
    }
    // Basic Tab key handling (if autoSearchOnTab is true)
    if (e.nativeEvent.key === 'Tab' && autoSearchOnTab && onSubmit) {
      // @ts-ignore - preventDefault may not exist in React Native, but some scanners send it
      if (e.preventDefault) e.preventDefault();
      
      // Introduce a tiny delay to allow state update for the last character
      const submitTimeout = setTimeout(() => {
          if (onSubmit) { // Check onSubmit still exists in case of quick unmounts
              onSubmit(); 
          }
      }, 50); // 50ms delay - adjust if needed
      
      // Cleanup timeout if component unmounts quickly
      // (Optional but good practice)
      // This requires useEffect for cleanup, slightly more complex. 
      // Let's keep it simple for now, the chance of unmount in 50ms is low.
    }
  };
  
  // Handle pressing the GO button or submitting from keyboard
  const handleSubmit = () => {
    if (onSubmit) {
      onSubmit();
    }
  };
  
  // Clear the input field
  const handleClear = () => {
    onChangeText(''); // Clear parent state directly
    if (onClear) {
      onClear();
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.searchContainer}>
        <Ionicons name="search" size={24} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={ref} // Use the forwarded ref directly
          style={styles.input}
          value={value} // Use value directly from props
          onChangeText={handleInputChange} // Use simplified handler
          placeholder={placeholder}
          placeholderTextColor="#999"
          onSubmitEditing={handleSubmit} // Call simplified submit handler
          returnKeyType="search"
          clearButtonMode="never" // Keep this to avoid duplicate X
          onKeyPress={handleKeyPress} // Keep key press handling
          blurOnSubmit={false}
          keyboardType="default"
        />
        {value.length > 0 && ( // Check value directly from props
          <TouchableOpacity onPress={handleClear} style={styles.clearButton}>
            <Ionicons name="close-circle" size={18} color="#aaa" />
          </TouchableOpacity>
        )}
      </View>
      
      <TouchableOpacity 
        style={styles.goButton}
        onPress={handleSubmit} // Call simplified submit handler
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