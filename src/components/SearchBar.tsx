import React, { forwardRef, useState, useRef, useEffect } from 'react';
import { View, TextInput, TouchableOpacity, StyleSheet, Text, NativeSyntheticEvent, TextInputKeyPressEventData, TextInputChangeEventData, TextInput as RNTextInput, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import logger from '../utils/logger'; // Assuming logger is correctly set up

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  onSubmit?: (submittedValue: string) => void;
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
  const scanEndTimeout = useRef<NodeJS.Timeout | null>(null);
  const latestInputValueRef = useRef<string>(value); // Ref to store the latest input value synchronously

  // Keep latestInputValueRef in sync if the prop value changes externally (e.g. parent clears it)
  useEffect(() => {
    latestInputValueRef.current = value;
  }, [value]);

  // Modified to handle event from onChange prop
  const handleInputChange = (event: NativeSyntheticEvent<TextInputChangeEventData>) => {
    const newInput = event.nativeEvent.text;
    latestInputValueRef.current = newInput; // Update ref synchronously
    
    if (!isScanning.current && newInput.length > 4 && /^\d*\w*\d*$/.test(newInput)) {
      isScanning.current = true;
    }
    if (newInput.length === 0) {
      isScanning.current = false;
    }
    onChangeText(newInput); // Call the parent's state updater (setSearch)
  };
  
  // Clears any pending scan-end timeout
  const clearPendingSubmit = () => {
    if (scanEndTimeout.current) {
      clearTimeout(scanEndTimeout.current);
      scanEndTimeout.current = null;
    }
  };

  // Handle special keys like Tab or Enter
  const handleKeyPress = (e: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
    const key = e.nativeEvent.key;
    // Conditional logging to see if this block is entered when flags are false
    if ((key === 'Enter' && autoSearchOnEnter) || (key === 'Tab' && autoSearchOnTab)) {
      logger.info('SearchBar::handleKeyPress', 'Enter/Tab auto-search condition met', { key, autoSearchOnEnter, autoSearchOnTab });
      if (e.preventDefault && key === 'Tab') e.preventDefault();
      clearPendingSubmit();
      
      // Capture the value from the SYNCHRONOUSLY updated ref
      const valueToSubmit = latestInputValueRef.current;
      
      logger.info('SearchBar::handleKeyPress', 'Scheduling timeout for Tab/Enter', { 
        key,
        valueCapturedFromRef: valueToSubmit 
      });

      scanEndTimeout.current = setTimeout(() => {
        logger.info('SearchBar::handleKeyPress', `Timeout fired for ${key}. Submitting.`, { 
          valueBeingSubmitted: valueToSubmit, // This value was from the ref at scheduling time
          originalKey: key 
        });

        if (onSubmit) {
          onSubmit(valueToSubmit); // Pass the value from the ref captured at scheduling
        }
        isScanning.current = false; 
      }, 50);
    } else if (key === 'Enter' || key === 'Tab') {
      // currentValue: value here refers to the value prop of the current render when this else branch is hit.
      logger.info('SearchBar::handleKeyPress', 'Enter/Tab pressed, but auto-search flags are false or condition not met', { key, autoSearchOnEnter, autoSearchOnTab, currentValueFromProp: value, currentValueFromRef: latestInputValueRef.current });
    }
  };
  
  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      clearPendingSubmit();
    };
  }, []);
  
  // This handleSubmit is for the search icon button
  const handleSubmitFromIcon = () => {
    clearPendingSubmit();
    // For icon press, the user has paused, so the prop `value` should be up-to-date.
    // Or, to be absolutely consistent, we could use latestInputValueRef.current here too.
    // Let's use latestInputValueRef for consistency for now.
    const valueToSubmit = latestInputValueRef.current;
    logger.info('SearchBar::handleSubmitFromIcon', 'Submitting due to icon press', { submittedValue: valueToSubmit });
    if (onSubmit) {
      onSubmit(valueToSubmit);
    }
    isScanning.current = false;
  };
  
  // Clear the input field
  const handleClear = () => {
    latestInputValueRef.current = ''; // Clear ref
    onChangeText('');
    isScanning.current = false;
    if (onClear) {
      onClear();
    }
    clearPendingSubmit(); // Also clear timeout if input is manually cleared
  };

  return (
    <View style={styles.container}>
      <View style={styles.searchContainer}>
        <Ionicons name="search" size={24} color="#888" style={styles.searchIcon} />
        <TextInput
          ref={ref}
          style={styles.input}
          value={value}
          onChange={handleInputChange}
          placeholder={placeholder}
          placeholderTextColor="#999"
          clearButtonMode="never"
          onKeyPress={handleKeyPress}
          blurOnSubmit={false}
          keyboardType="default"
          autoCapitalize="none"
          autoCorrect={false}
        />
        {value.length > 0 && (
          <TouchableOpacity onPress={handleClear} style={styles.clearButton}>
            <Ionicons name="close-circle" size={18} color="#aaa" />
          </TouchableOpacity>
        )}
        
        {value.length > 0 && (
          <TouchableOpacity onPress={handleSubmitFromIcon} style={styles.searchButton}>
            <Ionicons name="arrow-forward-circle" size={24} color={lightTheme.colors.primary} />
          </TouchableOpacity>
        )}
      </View>
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
  },
  searchButton: {
    padding: 4,
    marginLeft: 4,
  },
});

export default SearchBar; 