import React, { useState, useEffect, useRef } from 'react';
import { 
  View, 
  Text, 
  StyleSheet, 
  TextInput, 
  TouchableOpacity, 
  ScrollView, 
  Image, 
  Alert, 
  Switch,
  Platform,
  Keyboard
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { CatalogueItem } from '../../src/types';
import DropDownPicker from 'react-native-dropdown-picker';

// Sample categories for dropdown
const CATEGORIES = [
  { label: 'Beverages', value: 'Beverages' },
  { label: 'Snacks', value: 'Snacks' },
  { label: 'Groceries', value: 'Groceries' },
  { label: 'Household', value: 'Household' },
  { label: 'Drinks', value: 'Drinks' },
  { label: 'Electronics', value: 'Electronics' },
  { label: 'Health & Beauty', value: 'Health & Beauty' },
  { label: 'Office Supplies', value: 'Office Supplies' },
];

// Mock item for testing
const EMPTY_ITEM: CatalogueItem = {
  id: '',
  name: '',
  gtin: '',
  sku: '',
  reporting_category: '',
  price: null,
  tax: false,
  crv: false,
  description: ''
};

export default function ItemDetails() {
  const router = useRouter();
  const { id } = useLocalSearchParams();
  const isNewItem = id === 'new';
  const priceInputRef = useRef<TextInput>(null);
  const scrollViewRef = useRef<ScrollView>(null);
  const descriptionRef = useRef<TextInput>(null);
  
  // State for form fields
  const [item, setItem] = useState<CatalogueItem>(EMPTY_ITEM);
  const [hasChanges, setHasChanges] = useState(false);
  const [open, setOpen] = useState(false); // For dropdown
  const [showConfirmation, setShowConfirmation] = useState(false);
  const [priceText, setPriceText] = useState<string>('');
  
  // Tax states
  const [toggleAllTaxes, setToggleAllTaxes] = useState(false);
  const [southBayTax, setSouthBayTax] = useState(false);
  const [torranceTax, setTorranceTax] = useState(false);
  
  // Modifiers states
  const [crv5, setCrv5] = useState(false);
  const [crv10, setCrv10] = useState(false);
  
  useEffect(() => {
    // If we're editing an existing item, fetch its data
    if (!isNewItem && id) {
      // This would normally fetch from API or local storage
      // For now, just use mock data if available
      const mockItem: CatalogueItem = {
        id: id as string,
        name: 'Example Item 1',
        gtin: '78432786234',
        sku: 'ASBD123',
        reporting_category: 'Drinks',
        price: 14.99,
        tax: true,
        crv: 5,
        description: ''
      };
      
      setItem(mockItem);
      if (mockItem.price) {
        setPriceText(mockItem.price.toFixed(2));
      }
      
      // Set corresponding tax states
      setToggleAllTaxes(mockItem.tax === true);
      setSouthBayTax(mockItem.tax === true);
      setTorranceTax(mockItem.tax === true);
      
      // Set CRV modifiers
      if (mockItem.crv === 5) {
        setCrv5(true);
      } else if (mockItem.crv === 10) {
        setCrv10(true);
      }
    }
  }, [id, isNewItem]);
  
  // Listen for save events from the bottom tab bar
  useEffect(() => {
    const handleSaveEvent = () => {
      handleSave();
    };
    
    // For React Native we need a different approach since document is not available
    // This is a simplified example - in a real app, you'd use a state management 
    // library or context to communicate between components
    if (Platform.OS === 'web') {
      document.addEventListener('item:save', handleSaveEvent);
      return () => {
        document.removeEventListener('item:save', handleSaveEvent);
      };
    }
    
    // For native, we'll rely on the direct save button press
    return () => {};
  }, []);
  
  // Handlers for updating form values
  const updateItem = (key: keyof CatalogueItem, value: any) => {
    setItem(prev => ({ ...prev, [key]: value }));
    setHasChanges(true);
  };
  
  const handleToggleAllTaxes = (value: boolean) => {
    setToggleAllTaxes(value);
    setSouthBayTax(value);
    setTorranceTax(value);
    updateItem('tax', value);
  };
  
  const handleCrv = (type: 'crv5' | 'crv10', value: boolean) => {
    if (type === 'crv5') {
      setCrv5(value);
      if (value) {
        setCrv10(false);
        updateItem('crv', 5);
      } else if (!crv10) {
        updateItem('crv', false);
      }
    } else {
      setCrv10(value);
      if (value) {
        setCrv5(false);
        updateItem('crv', 10);
      } else if (!crv5) {
        updateItem('crv', false);
      }
    }
  };
  
  const handleCancel = () => {
    if (hasChanges && !isEmpty(item)) {
      setShowConfirmation(true);
    } else {
      router.back();
    }
  };
  
  const handleConfirmCancel = () => {
    setShowConfirmation(false);
    router.back();
  };
  
  const handleSave = () => {
    console.log('Saving item:', item);
    // Here you would save to API or local storage
    router.back();
  };
  
  // Simplified price input handling
  const handlePriceChange = (value: string) => {
    setPriceText(value);
    const numericValue = parseFloat(value);
    if (!isNaN(numericValue)) {
      updateItem('price', numericValue);
    } else {
      updateItem('price', null);
    }
  };
  
  // Handle description field focus to scroll view
  const handleDescriptionFocus = () => {
    // Close dropdown if open
    setOpen(false);
    
    // Scroll to the description area with better positioning
    setTimeout(() => {
      if (scrollViewRef.current) {
        // Scroll down somewhat but not too far
        scrollViewRef.current.scrollTo({ y: 350, animated: true });
      }
    }, 300);
  };
  
  // Handle general input focus (for closing dropdown)
  const handleInputFocus = () => {
    setOpen(false);
  };
  
  // Check if all fields are empty to determine if confirmation is needed
  const isEmpty = (item: CatalogueItem): boolean => {
    return (
      !item.name &&
      !item.gtin &&
      !item.sku &&
      !item.reporting_category &&
      (!item.price || item.price === 0) &&
      !item.tax &&
      !item.crv &&
      !item.description
    );
  };
  
  // Format price for display
  const formattedPrice = item.price ? `$${item.price.toFixed(2)}` : '$0.00';
  
  // Updated logic: show tax if any tax option is selected
  const showTax = southBayTax || torranceTax;
  const showCrv = item.crv !== false;
  const crvText = typeof item.crv === 'number' ? `+CRV${item.crv}` : '';
  
  return (
    <View style={styles.container}>
      <StatusBar style="auto" />
      
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Item Details</Text>
        <TouchableOpacity 
          style={styles.deleteButton}
          onPress={() => Alert.alert('Delete', 'Are you sure you want to delete this item?')}
        >
          <Text style={styles.deleteButtonText}>Delete</Text>
        </TouchableOpacity>
      </View>
      
      {/* Use View instead of ScrollView for outer container */}
      <View style={styles.contentContainer}>
        {/* Preview section */}
        <View style={styles.previewContainer}>
          <View style={styles.previewInfo}>
            <Text style={styles.previewName}>{item.name || 'Enter Item Name'}</Text>
            <View style={styles.previewPriceContainer}>
              <Text style={styles.previewPrice}>{formattedPrice}</Text>
              <View style={styles.previewTags}>
                {showTax && <Text style={styles.previewTag}>+TAX</Text>}
                {showCrv && <Text style={styles.previewTag}>{crvText}</Text>}
              </View>
            </View>
          </View>
          
          <TouchableOpacity style={styles.imageContainer}>
            {/* Placeholder image area */}
            <View style={styles.imagePlaceholder}>
              <Ionicons name="image-outline" size={40} color="#888" />
              <Text style={styles.imagePlaceholderText}>Tap to add image</Text>
            </View>
          </TouchableOpacity>
        </View>
        
        {/* Scrollable container for form */}
        <ScrollView 
          ref={scrollViewRef}
          style={styles.scrollView}
          contentContainerStyle={styles.scrollViewContent}
          keyboardShouldPersistTaps="handled"
        >
          {/* Form section */}
          <View style={styles.formContainer}>
            {/* GTIN / SKU row */}
            <View style={styles.formRow}>
              <View style={styles.formColumn}>
                <Text style={styles.label}>GTIN</Text>
                <TextInput
                  style={styles.input}
                  value={item.gtin}
                  onChangeText={(value) => updateItem('gtin', value)}
                  onFocus={handleInputFocus}
                  placeholder="Enter GTIN"
                  keyboardType="numeric"
                />
              </View>
              
              <View style={styles.formColumn}>
                <Text style={styles.label}>SKU</Text>
                <TextInput
                  style={styles.input}
                  value={item.sku}
                  onChangeText={(value) => updateItem('sku', value)}
                  onFocus={handleInputFocus}
                  placeholder="Enter SKU"
                />
              </View>
            </View>
            
            {/* Item Name */}
            <Text style={styles.label}>Item Name</Text>
            <TextInput
              style={[styles.input, styles.marginBottom16]}
              value={item.name}
              onChangeText={(value) => updateItem('name', value)}
              onFocus={handleInputFocus}
              placeholder="Enter item name"
            />
            
            {/* Price / Category row */}
            <View style={styles.formRow}>
              <View style={styles.formColumn}>
                <Text style={styles.label}>Selling Price</Text>
                <View style={styles.priceInputContainer}>
                  <Text style={styles.dollarSign}>$</Text>
                  <TextInput
                    ref={priceInputRef}
                    style={styles.priceInput}
                    value={priceText}
                    onChangeText={handlePriceChange}
                    placeholder="0.00"
                    keyboardType="decimal-pad"
                    textAlign="right"
                  />
                </View>
              </View>
              
              <View style={styles.formColumn}>
                <Text style={styles.label}>Category</Text>
                <DropDownPicker
                  open={open}
                  value={item.reporting_category || ''}
                  items={CATEGORIES}
                  setOpen={setOpen}
                  setValue={(val) => {
                    // Handle both function and direct value
                    if (typeof val === 'function') {
                      const newVal = val(item.reporting_category || '');
                      updateItem('reporting_category', newVal);
                    } else {
                      updateItem('reporting_category', val);
                    }
                  }}
                  style={styles.dropdown}
                  dropDownContainerStyle={styles.dropdownContainer}
                  placeholderStyle={styles.dropdownPlaceholder}
                  placeholder="Select category"
                  zIndex={1000}
                  listMode="SCROLLVIEW"
                />
              </View>
            </View>
            
            {/* Taxes & Modifiers section */}
            <View style={styles.formRow}>
              <View style={styles.formColumn}>
                <Text style={styles.label}>Taxes</Text>
                <View style={styles.checkboxContainer}>
                  <View style={styles.checkboxRow}>
                    <TouchableOpacity
                      style={styles.checkbox}
                      onPress={() => handleToggleAllTaxes(!toggleAllTaxes)}
                    >
                      {toggleAllTaxes && <Ionicons name="checkmark" size={20} color="#000" />}
                    </TouchableOpacity>
                    <Text style={styles.checkboxLabel}>Toggle All</Text>
                  </View>
                  
                  <View style={styles.checkboxRow}>
                    <TouchableOpacity
                      style={styles.checkbox}
                      onPress={() => {
                        const newValue = !southBayTax;
                        setSouthBayTax(newValue);
                        // Update the main tax flag if any tax is selected
                        updateItem('tax', newValue || torranceTax);
                      }}
                    >
                      {southBayTax && <Ionicons name="checkmark" size={20} color="#000" />}
                    </TouchableOpacity>
                    <Text style={styles.checkboxLabel}>SOUTH BAY (9.5%)</Text>
                  </View>
                  
                  <View style={styles.checkboxRow}>
                    <TouchableOpacity
                      style={styles.checkbox}
                      onPress={() => {
                        const newValue = !torranceTax;
                        setTorranceTax(newValue);
                        // Update the main tax flag if any tax is selected
                        updateItem('tax', southBayTax || newValue);
                      }}
                    >
                      {torranceTax && <Ionicons name="checkmark" size={20} color="#000" />}
                    </TouchableOpacity>
                    <Text style={styles.checkboxLabel}>TORRANCE (10%)</Text>
                  </View>
                </View>
              </View>
              
              <View style={styles.formColumn}>
                <Text style={styles.label}>Modifiers</Text>
                <View style={styles.checkboxContainer}>
                  <View style={styles.checkboxRow}>
                    <TouchableOpacity
                      style={styles.checkbox}
                      onPress={() => handleCrv('crv5', !crv5)}
                    >
                      {crv5 && <Ionicons name="checkmark" size={20} color="#000" />}
                    </TouchableOpacity>
                    <Text style={styles.checkboxLabel}>CRV5</Text>
                  </View>
                  
                  <View style={styles.checkboxRow}>
                    <TouchableOpacity
                      style={styles.checkbox}
                      onPress={() => handleCrv('crv10', !crv10)}
                    >
                      {crv10 && <Ionicons name="checkmark" size={20} color="#000" />}
                    </TouchableOpacity>
                    <Text style={styles.checkboxLabel}>CRV10</Text>
                  </View>
                </View>
              </View>
            </View>
            
            {/* Description */}
            <Text style={styles.label} id="description-label">Description</Text>
            <TextInput
              ref={descriptionRef}
              style={[styles.input, styles.multilineInput]}
              value={item.description}
              onChangeText={(value) => updateItem('description', value)}
              onFocus={handleDescriptionFocus}
              placeholder="Enter item description"
              multiline
              numberOfLines={4}
            />
            
            {/* Add extra padding at the bottom to account for the tab bar and floating buttons */}
            <View style={styles.bottomPadding} />
          </View>
        </ScrollView>
      </View>
      
      {/* Floating Action Buttons Container */}
      <View style={styles.floatingButtonsContainer}>
        <TouchableOpacity 
          style={[styles.actionButton, styles.cancelButton]}
          onPress={handleCancel}
        >
          <Ionicons name="close" size={24} color="#fff" />
          <Text style={styles.actionButtonText}>
            {showConfirmation ? 'Confirm?' : 'Cancel'}
          </Text>
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={[styles.actionButton, styles.printButton]}
          onPress={() => console.log('Print functionality to be implemented')}
        >
          <Ionicons name="print" size={24} color="#fff" />
          <Text style={styles.actionButtonText}>Print</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  contentContainer: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 60,
    paddingBottom: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: 'bold',
  },
  deleteButton: {
    backgroundColor: '#ff3b30',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 25,
  },
  deleteButtonText: {
    color: '#fff',
    fontWeight: 'bold',
  },
  scrollView: {
    flex: 1,
  },
  scrollViewContent: {
    paddingBottom: 200, // Extra padding to ensure content is visible above bottom tab and floating buttons
  },
  previewContainer: {
    flexDirection: 'row',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  previewInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  previewName: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  previewPriceContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
  },
  previewPrice: {
    fontSize: 38,
    fontWeight: 'bold',
    marginRight: 10,
  },
  previewTags: {
    marginBottom: 8,
  },
  previewTag: {
    fontSize: 12, // Smaller tag text
    color: '#666',
  },
  imageContainer: {
    width: 140,
    height: 140,
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: 8,
    overflow: 'hidden',
  },
  imagePlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: '#f0f0f0',
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: 8,
  },
  imagePlaceholderText: {
    marginTop: 8,
    color: '#888',
    fontSize: 12,
    textAlign: 'center',
  },
  formContainer: {
    padding: 16,
  },
  formRow: {
    flexDirection: 'row',
    marginBottom: 16,
  },
  formColumn: {
    flex: 1,
    marginRight: 10,
  },
  label: {
    fontSize: 16,
    marginBottom: 8,
    fontWeight: '500',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
  },
  marginBottom16: {
    marginBottom: 16,
  },
  multilineInput: {
    minHeight: 120,
    textAlignVertical: 'top',
    marginBottom: 16,
  },
  priceInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    marginBottom: 16,
  },
  dollarSign: {
    paddingLeft: 12,
    fontSize: 16,
  },
  priceInput: {
    flex: 1,
    padding: 12,
    fontSize: 16,
  },
  dropdown: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    marginBottom: 16,
  },
  dropdownContainer: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
  },
  dropdownPlaceholder: {
    color: '#999',
  },
  checkboxContainer: {
    marginBottom: 16,
  },
  checkboxRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  checkbox: {
    width: 24,
    height: 24,
    borderWidth: 1,
    borderColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  checkboxLabel: {
    fontSize: 16,
  },
  floatingButtonsContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: '#eee',
    backgroundColor: '#fff',
    elevation: 5,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    zIndex: 1000,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
  },
  cancelButton: {
    backgroundColor: '#ff3b30',
  },
  printButton: {
    backgroundColor: '#007aff',
  },
  actionButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
    marginLeft: 8,
  },
  bottomPadding: {
    height: 100, // Extra padding to ensure content is visible above floating buttons and tab bar
  }
}); 