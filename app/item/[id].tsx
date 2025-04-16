import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
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
  Keyboard,
  Modal,
  FlatList,
  TouchableWithoutFeedback,
  Dimensions,
  StatusBar as RNStatusBar,
  Animated,
  ActivityIndicator,
  SafeAreaView
} from 'react-native';
import { useRouter, useLocalSearchParams, Stack, useNavigation } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
// import { useCategories } from '../../src/hooks'; // Commented out
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { ConvertedItem, ConvertedCategory } from '../../src/types/api';
import { lightTheme } from '../../src/themes';
import { getAllCategories, getAllTaxes, getAllModifierLists } from '../../src/database/modernDb'; // Import the new function
import { getRecentCategoryIds, addRecentCategoryId } from '../../src/utils/recentCategories'; // Import recent category utils
import { useAppStore } from '../../src/store'; // Import Zustand store
import logger from '../../src/utils/logger'; // Import logger

// Define type for category used in the picker
type CategoryPickerItem = { id: string; name: string };

// Define type for Tax and Modifier List Pickers
type TaxPickerItem = { id: string; name: string; percentage: string | null };
type ModifierListPickerItem = { id: string; name: string }; // Used for both CRV and others

// Empty item template for new items
const EMPTY_ITEM: ConvertedItem = {
  id: '',
  name: '',
  variationName: 'Regular',
  sku: '',
  price: undefined,
  description: '',
  categoryId: '', // Keep for now, but focus on reporting_category_id
  reporting_category_id: '', // Add this field
  category: '', // Keep for display compatibility?
  isActive: true,
  images: [],
  taxIds: [], // Initialize taxIds
  modifierListIds: [], // Use an array for multiple modifier lists
  updatedAt: new Date().toISOString(),
  createdAt: new Date().toISOString()
};

export default function ItemDetails() {
  const router = useRouter();
  const { id } = useLocalSearchParams();
  const navigation = useNavigation();
  const isNewItem = id === 'new';
  
  // Hooks for categories and items
  // const { // Commented out
  //   categories, // Commented out
  //   getCategoryById, // Commented out
  //   dropdownItems // Commented out
  // } = useCategories(); // Commented out
  
  const {
    getProductById,
    createProduct,
    updateProduct,
    deleteProduct,
    isProductsLoading,
    productError
  } = useCatalogItems();
  
  // State for the current item
  const [item, setItem] = useState<ConvertedItem>(EMPTY_ITEM);
  const [originalItem, setOriginalItem] = useState<ConvertedItem | null>(null);
  const [isEdited, setIsEdited] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  // State for category list and modal
  const [availableCategories, setAvailableCategories] = useState<CategoryPickerItem[]>([]);
  const [filteredCategories, setFilteredCategories] = useState<CategoryPickerItem[]>([]);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [categorySearch, setCategorySearch] = useState('');
  
  // Confirmation modal state
  const [showCancelModal, setShowCancelModal] = useState(false);
  
  // State for recent categories
  const [recentCategories, setRecentCategories] = useState<CategoryPickerItem[]>([]);
  
  // State for Taxes
  const [availableTaxes, setAvailableTaxes] = useState<TaxPickerItem[]>([]);
  const [showTaxModal, setShowTaxModal] = useState(false);
  const [allTaxesSelected, setAllTaxesSelected] = useState(false);

  // State for Modifiers
  const [availableModifierLists, setAvailableModifierLists] = useState<ModifierListPickerItem[]>([]);
  
  const itemSaveTriggeredAt = useAppStore((state) => state.itemSaveTriggeredAt);
  const lastProcessedSaveTrigger = useRef<number | null>(null);
  
  // Define handlers before they are used
  const handleInputChange = (key: keyof ConvertedItem, value: string | number | undefined) => {
    // Handle potential numeric conversion for price
    if (key === 'price') {
      const textValue = value as string; // Input value is text

      // If input is empty or explicitly cleared, treat as variable price
      if (textValue === '' || textValue === null || textValue === undefined) {
        updateItem('price', undefined);
        return;
      }

      // Keep only digits
      const digits = textValue.replace(/[^0-9]/g, '');

      // If no digits remain (e.g., input was just '.'), treat as variable
      if (digits === '') {
        updateItem('price', undefined);
        return;
      }

      // Parse digits as cents
      const cents = parseInt(digits, 10);

      // Handle potential parsing errors (though unlikely with digit filter)
      if (isNaN(cents)) {
        console.warn('Invalid number parsed for price:', digits);
        // Optionally reset to variable or keep previous state? Resetting for safety.
        updateItem('price', undefined); 
        return;
      }

      // Calculate price in dollars and update state
      const dollars = cents / 100;
      updateItem('price', dollars);
      
    } else {
      // Handle other fields normally (treat as strings)
      updateItem(key, value as string);
    }
  };

  const handleTaxSelection = (taxId: string) => {
    const currentIds = item.taxIds || [];
    const newIds = currentIds.includes(taxId)
      ? currentIds.filter(id => id !== taxId)
      : [...currentIds, taxId];
    updateItem('taxIds', newIds);
  };

  const handleModifierSelection = (modifierId: string) => {
    // Log before update
    console.log(`[Modifier Selection] Tapped ID: ${modifierId}`);
    console.log(`[Modifier Selection] Item state BEFORE updateItem call:`, JSON.stringify(item)); // Log state before calling updateItem

    // Directly pass the toggled modifierId to updateItem.
    // The logic to add/remove is handled within updateItem itself.
    updateItem('modifierListIds', modifierId);
  };
  
  // == Stable Handlers ==
  const isEmpty = useCallback((): boolean => {
    return (
      !item.name.trim() && 
      !(item.sku && item.sku.trim()) && 
      item.price === undefined &&
      !(item.description && item.description.trim()) &&
      !item.reporting_category_id
    );
  }, [item]); // Depends on item state

  const handleCancel = useCallback(() => {
    if (isEdited && !isEmpty()) {
      setShowCancelModal(true);
    } else {
      router.back();
    }
  }, [isEdited, isEmpty, router, setShowCancelModal]);

  const handleConfirmCancel = useCallback(() => {
    setShowCancelModal(false);
    router.back();
  }, [router, setShowCancelModal]);

  const handleSave = useCallback(async () => {
    if (!item.name.trim()) {
      Alert.alert('Error', 'Item name is required');
      return;
    }
    
    setIsSaving(true);
    setError(null);
    
    try {
      let savedItem;
      let itemPayload: any; // Declare payload variable

      if (isNewItem) {
        // Construct payload specifically for CREATE
        itemPayload = {
          name: item.name,
          abbreviation: item.abbreviation || null,
          variationName: item.variationName || 'Regular',
          sku: item.sku || null, // Ensure null if empty
          price: item.price, // Pass price (number or undefined)
          description: item.description || null, // Ensure null if empty
          isActive: item.isActive, // Typically true for new items
          images: item.images || [],
          barcode: item.barcode || null,         // Pass barcode
          taxIds: item.taxIds || [],             // Pass taxIds (camelCase)
          modifierListIds: item.modifierListIds || [], // Pass modifierListIds (camelCase)
          reporting_category_id: item.reporting_category_id || null,
          // Do NOT include id, version, category, categoryId, updatedAt, createdAt for CREATE
        };
        // Remove price if it's undefined (for variable pricing)
        if (itemPayload.price === undefined) {
          delete itemPayload.price;
        }
        
        savedItem = await createProduct(itemPayload); 
        Alert.alert('Success', 'Item created successfully');
      } else {
        // Construct payload for UPDATE (include version)
        itemPayload = { 
          ...item, // Start with current state (includes version)
          abbreviation: item.abbreviation || null,
          variationName: item.variationName || 'Regular',
          reporting_category_id: item.reporting_category_id || null // Ensure correct ID is present
        };
        
        // **FIXED: Explicitly remove potentially incorrect category object if spread from item**
        delete (itemPayload as any).reporting_category; 

        // Delete frontend-specific/derived fields before sending
        // delete itemPayload.reporting_category_id; // Don't delete the ID!
        delete itemPayload.category; 
        delete itemPayload.categoryId; 

        // Transform taxIds and modifierListIds
        itemPayload.tax_ids = item.taxIds || []; 
        itemPayload.modifier_list_info = (item.modifierListIds || []).map(id => ({
          modifier_list_id: id,
          enabled: true
        }));
        delete itemPayload.modifierListIds;
        
        // Remove price if it's undefined (for variable pricing)
        if (itemPayload.price === undefined) {
          delete itemPayload.price;
        }

        if (typeof id !== 'string') {
          throw new Error('Invalid item ID for update');
        }
        savedItem = await updateProduct(id, itemPayload); 
        Alert.alert('Success', 'Item updated successfully');
      }
      
      if (savedItem) {
        const reportingCategoryId = savedItem.reporting_category_id ?? '';
        const savedItemWithReportingId = { 
           ...savedItem, 
           reporting_category_id: reportingCategoryId 
         };
        setItem(savedItemWithReportingId);
        setOriginalItem(savedItemWithReportingId);
        setIsEdited(false);
      }
      
      router.back();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save item');
      Alert.alert('Error', 'Failed to save item. Please try again.');
      console.error('Error saving item:', err);
    } finally {
      setIsSaving(false);
    }
  }, [item, isNewItem, id, createProduct, updateProduct, setIsSaving, setError, setItem, setOriginalItem, setIsEdited, router]); // Extensive dependencies
  
  // Fetch the item data, categories, taxes, and modifiers on component mount
  useEffect(() => {
    const fetchInitialData = async () => {
      setIsLoading(true);
      setError(null);
      
      try {
        // Fetch categories, taxes, and modifiers concurrently
        const [fetchedCategories, fetchedTaxes, fetchedModifierLists] = await Promise.all([
          getAllCategories(),
          getAllTaxes(),
          getAllModifierLists()
        ]);

        setAvailableCategories(fetchedCategories);
        setFilteredCategories(fetchedCategories); // Initialize filtered category list
        setAvailableTaxes(fetchedTaxes);
        setAvailableModifierLists(fetchedModifierLists);

        // No need to filter for CRV here anymore, availableModifierLists holds all of them
        
        // Log available categories for debugging
        console.log('[ItemDetails] Available Categories:', JSON.stringify(fetchedCategories.map(c => ({id: c.id, name: c.name})), null, 2));
        
        // Check if all available taxes are initially selected in the item
        const initialTaxIdsSet = new Set(item?.taxIds || []);
        const allFetchedTaxIds = new Set(fetchedTaxes.map(tax => tax.id));
        const areAllSelected = fetchedTaxes.length > 0 && fetchedTaxes.every(tax => initialTaxIdsSet.has(tax.id));
        setAllTaxesSelected(Boolean(areAllSelected));
        
        // Fetch recent category IDs and map them to full category objects
        const recentIds = await getRecentCategoryIds();
        const recentCategoryObjects = recentIds
          .map(id => fetchedCategories.find(cat => cat.id === id))
          .filter((cat): cat is CategoryPickerItem => cat !== undefined); // Remove undefined if ID not found
        setRecentCategories(recentCategoryObjects);
        
        // Fetch item data if not a new item
        if (!isNewItem && typeof id === 'string') {
          const fetchedItem = await getProductById(id);
          if (fetchedItem) {
            // Ensure reporting_category_id is set from fetched data
            // Try to get it from reporting_category.id OR directly from reporting_category_id
            console.log('[ItemDetails] Fetched Item Data:', JSON.stringify(fetchedItem, null, 2)); // Log fetched item
            const initialReportingCategoryId = (fetchedItem as any).reporting_category?.id || fetchedItem.reporting_category_id || '';
            console.log('[ItemDetails] Initial Reporting Category ID:', initialReportingCategoryId); // Log extracted ID
            
            // Extract initial Tax IDs (assuming fetchedItem has taxIds)
            const initialTaxIds = fetchedItem.taxIds || [];
            
            // Extract initial Modifier List IDs
            // Assumes transformCatalogItemToItem sets modifierListIds based on modifier_list_info
            const initialModifierListIds = fetchedItem.modifierListIds || [];
            
            // Extract the version from the fetched item
            const initialVersion = fetchedItem.version; 
            
            const itemWithReportingId = { 
              ...fetchedItem, 
              version: initialVersion, // Ensure version is stored in state
              reporting_category_id: initialReportingCategoryId,
              taxIds: initialTaxIds, // Ensure taxIds are set in the state
              modifierListIds: initialModifierListIds // Ensure Modifier IDs are set
            };
            setItem(itemWithReportingId);
            setOriginalItem(itemWithReportingId); 
          } else {
            setError('Item not found');
            setItem(EMPTY_ITEM);
          }
        } else if (isNewItem) {
          setItem(EMPTY_ITEM);
          setOriginalItem(null);
        } else {
          setError('Invalid Item ID');
          setItem(EMPTY_ITEM);
        }
        
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load data');
        console.error('Error fetching initial data:', err);
        setItem(EMPTY_ITEM); // Reset item on error
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchInitialData();
  }, [id, getProductById, isNewItem]);
  
  // Effect to update header options dynamically
  useEffect(() => {
    navigation.setOptions({
      title: isNewItem ? 'Add New Item' : 'Edit Item',
      headerLeft: () => (
        <TouchableOpacity
          style={styles.headerButton}
          onPress={handleCancel} // Use the stable handler
          disabled={isSaving}
        >
          <Text style={[styles.headerButtonText, isSaving && styles.disabledText]}>
            Cancel
          </Text>
        </TouchableOpacity>
      ),
      headerRight: () => (
        <TouchableOpacity
          style={styles.headerButton}
          onPress={handleSave} // Use the stable handler
          disabled={!isEdited || isSaving}
        >
          {isSaving ? (
            <ActivityIndicator size="small" color={lightTheme.colors.primary} />
          ) : (
            <Text
              style={[
                styles.headerButtonText, 
                styles.saveButton,
                (!isEdited || isSaving) && styles.disabledText
              ]}
            >
              Save
            </Text>
          )}
        </TouchableOpacity>
      ),
    });
  }, [navigation, isNewItem, isEdited, isSaving, handleCancel, handleSave]);
  
  // Filter categories when search text changes
  useEffect(() => {
    if (!categorySearch) {
      setFilteredCategories(availableCategories);
    } else {
      const searchLower = categorySearch.toLowerCase();
      const filtered = availableCategories.filter(
        category => category.name.toLowerCase().includes(searchLower)
      );
      setFilteredCategories(filtered);
    }
  }, [availableCategories, categorySearch]);
  
  // Check if item has been edited and update 'all taxes selected' status
  useEffect(() => {
    // 1. Calculate 'all taxes selected' state
    let areAllSelected = false;
    // Ensure calculation only happens when necessary arrays are populated
    if (item && availableTaxes && availableTaxes.length > 0) {
        const currentTaxIdsSet = new Set(item.taxIds || []);
        // Check if every available tax ID is present in the item's tax IDs
        areAllSelected = availableTaxes.every(tax => currentTaxIdsSet.has(tax.id));
    }
    // Set the state - areAllSelected is guaranteed to be boolean here
    setAllTaxesSelected(areAllSelected);

    // 2. Calculate 'isEdited' state
    let calculatedIsEdited: boolean | undefined = undefined; // Start as undefined

    if (isNewItem && item) {
       // Check if any field has changed from the empty state for a new item
       calculatedIsEdited =
          !!item.name.trim() ||
          !!(item.sku && item.sku.trim()) ||
          item.price !== undefined ||
          !!(item.description && item.description.trim()) ||
          !!item.reporting_category_id ||
          (item.taxIds && item.taxIds.length > 0) ||
          (item.modifierListIds && item.modifierListIds.length > 0);
    } else if (item && originalItem) { // Only compare if both item and originalItem exist
        // Compare sorted arrays to ignore order differences
        const taxIdsChanged = JSON.stringify(originalItem.taxIds?.sort() || []) !== JSON.stringify(item.taxIds?.sort() || []);
        const modifierIdsChanged = JSON.stringify(originalItem.modifierListIds?.sort() || []) !== JSON.stringify(item.modifierListIds?.sort() || []);

        calculatedIsEdited =
          originalItem.name !== item.name ||
          originalItem.sku !== item.sku ||
          originalItem.price !== item.price ||
          originalItem.description !== item.description ||
          originalItem.reporting_category_id !== item.reporting_category_id ||
          taxIdsChanged ||
          modifierIdsChanged;
    }
    
     // Set the state - Use the calculated value, defaulting to false if undefined
    setIsEdited(calculatedIsEdited === undefined ? false : calculatedIsEdited);

  // Dependencies: Recalculate whenever the item, original item, or available taxes change
  }, [item, originalItem, isNewItem, availableTaxes]);
  
  // Update a field in the item state
  const updateItem = (key: keyof ConvertedItem, value: any) => {
    // Use functional update to ensure we work with the latest state
    // **Ensure variationName defaults to 'Regular' if cleared**
    if (key === 'variationName' && (value === '' || value === null || value === undefined)) {
      value = 'Regular';
    }
    setItem(prev => {
      let newState = { ...prev }; // Copy previous state

      // Special handling for modifierListIds array
      if (key === 'modifierListIds') {
        const modifierId = value; // 'value' is the single ID being toggled
        const currentIds = prev.modifierListIds || [];
        let newIds;
        if (currentIds.includes(modifierId)) {
          newIds = currentIds.filter(id => id !== modifierId); // Remove ID
        } else {
          newIds = [...currentIds, modifierId]; // Add ID
        }
        newState = { ...prev, modifierListIds: newIds };
      } else {
        // Handle other fields normally
        newState = { ...prev, [key]: value };
      }

      // Recalculate 'all taxes selected' state *after* the main state update logic
      // Only do this if taxIds was the key being updated
      if (key === 'taxIds') {
        let areAllSelected = false;
        const newTaxIds = newState.taxIds || []; // Use the updated tax IDs from newState
        // Ensure availableTaxes is populated before checking
        if (availableTaxes && availableTaxes.length > 0) {
           areAllSelected = availableTaxes.every(tax => newTaxIds.includes(tax.id));
        }
        // Set the dependent state - guaranteed boolean
        setAllTaxesSelected(areAllSelected);
      }

      return newState; // Return the fully updated state
    });
  };
  
  // Toggle all taxes selection
  const handleSelectAllTaxes = () => {
    const currentTaxIds = item.taxIds || [];
    let newTaxIds: string[];

    if (allTaxesSelected) {
      // If all are selected, deselect all
      newTaxIds = [];
    } else {
      // If not all are selected (or none), select all
      newTaxIds = availableTaxes.map(tax => tax.id);
    }
    updateItem('taxIds', newTaxIds);
    setAllTaxesSelected(!allTaxesSelected);
  };
  
  // Get the current category name for display, handle loading state
  const selectedCategoryName = useMemo(() => {
    if (isLoading) return 'Loading...'; // Show loading state
    const categoryId = item.reporting_category_id;
    console.log('[ItemDetails SelectedCategory] Category ID in state:', categoryId);
    if (categoryId) {
      const found = availableCategories.find(c => c.id === categoryId);
      if (found) {
        return found.name;
      } else {
        console.warn(`[ItemDetails SelectedCategory] Category ID "${categoryId}" found in item but NOT in availableCategories list!`);
        return 'Select Category'; // ID exists but category not found
      }
    }
    return 'Select Category'; // No ID set
  }, [item.reporting_category_id, availableCategories, isLoading]);
  
  // Handle selecting a category
  const handleSelectCategory = (categoryId: string) => {
    updateItem('reporting_category_id', categoryId); 
    setShowCategoryModal(false);
    setCategorySearch(''); // Reset search on selection
  };
  
  // Handle delete button press
  const handleDelete = useCallback(async () => {
    if (!item?.id) return;

    Alert.alert(
      'Delete Item',
      `Are you sure you want to delete "${item.name || 'this item'}"? This action cannot be undone.`,
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteProduct(item.id);
              Alert.alert('Success', 'Item deleted successfully');
              if (navigation.canGoBack()) {
                navigation.goBack();
              } else {
                // Fallback if cannot go back (e.g., deep link)
                router.push('/'); // Navigate to the root route
              }
            } catch (error: any) {
              console.error('Error deleting item:', error);
              Alert.alert('Error', `Error deleting item: ${error.message}`);
            }
          },
        },
      ],
      { cancelable: true } // Allow dismissing by tapping outside on Android
    );
  }, [item, deleteProduct, navigation, router]);
  
  // Render component for matching text in search results
  const highlightMatchingText = (text: string, query: string) => {
    if (!query) return <Text>{text}</Text>;
    
    const parts = text.split(new RegExp(`(${query})`, 'gi'));
    
    return (
      <Text>
        {parts.map((part, index) => 
          part.toLowerCase() === query.toLowerCase() ? (
            <Text key={index} style={styles.highlightedText}>{part}</Text>
          ) : (
            <Text key={index}>{part}</Text>
          )
        )}
      </Text>
    );
  };
  
  // Get the display name for a selected modifier list ID
  const getModifierListName = (modifierId: string): string => {
    return availableModifierLists.find(m => m.id === modifierId)?.name || 'Unknown Modifier';
  };
  
  // Effect to trigger save based on Zustand state
  useEffect(() => {
    if (itemSaveTriggeredAt && itemSaveTriggeredAt !== lastProcessedSaveTrigger.current) {
      logger.info('ItemScreen', 'Save triggered via Zustand state', { timestamp: itemSaveTriggeredAt });
      handleSave();
      lastProcessedSaveTrigger.current = itemSaveTriggeredAt; // Mark this trigger as processed
    }
  }, [itemSaveTriggeredAt, handleSave]);
  
  // If loading, show spinner
  if (isLoading) {
    return (
      <SafeAreaView style={styles.container}> 
        <StatusBar style="dark" />
        <View style={styles.loadingContainer}> 
          <ActivityIndicator size="large" color={lightTheme.colors.primary} />
          <Text style={styles.loadingText}>Loading item data...</Text>
        </View>
      </SafeAreaView>
    );
  }
  
  // If loading is done AND we can render content (Removed canRenderContent check)
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="dark" />

      {/* Error handling: Render error view if error exists */} 
      {error && !isNewItem && (
        <View style={styles.errorContainer}> 
          <Ionicons name="alert-circle-outline" size={48} color="red" />
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity style={styles.errorButton} onPress={() => router.back()}>
            <Text style={styles.errorButtonText}>Go Back</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Main Content: Render ScrollView and Modal if NO error */} 
      {!error && (
        <>
          <ScrollView style={styles.content} keyboardShouldPersistTaps="handled">
            {/* Item Name */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Item Name</Text>
              <TextInput
                style={styles.input}
                value={item.name}
                onChangeText={value => handleInputChange('name', value)}
                placeholder="Enter item name"
                placeholderTextColor="#999"
              />
            </View>

            {/* Variation Name */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Variation Name</Text>
              <TextInput
                style={styles.input}
                value={item.variationName || ''}
                onChangeText={value => handleInputChange('variationName', value || 'Regular')}
                placeholder="e.g., Regular, Large, Blue"
                placeholderTextColor="#999"
              />
            </View>

            {/* ADD SKU FIELD BACK */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>SKU</Text>
              <TextInput
                style={styles.input}
                value={item.sku || ''} // Bind to item.sku
                onChangeText={value => handleInputChange('sku', value)} // Use handleInputChange
                placeholder="Enter SKU (optional)"
                placeholderTextColor="#999"
                autoCapitalize="characters" // Suggest uppercase for SKU
              />
            </View>

            {/* ADD PRICE FIELD BACK */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Price</Text>
              <View style={styles.priceInputContainer}>
                <Text style={styles.currencySymbol}>$</Text>
                <TextInput
                  style={styles.priceInput}
                  value={item.price !== undefined ? item.price.toFixed(2) : ''} // Display formatted price or empty
                  onChangeText={value => handleInputChange('price', value)} // Use handleInputChange for custom logic
                  placeholder="Variable" // Updated placeholder
                  placeholderTextColor="#999"
                  keyboardType="numeric"
                />
              </View>
               <Text style={styles.helperText}>Leave blank for variable pricing</Text> 
            </View>

            {/* Reporting Category */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Reporting Category</Text>
              <TouchableOpacity style={styles.selectorButton} onPress={() => setShowCategoryModal(true)}>
                <Text style={styles.selectorText}>{selectedCategoryName}</Text>
                <Ionicons name="chevron-down" size={20} color="#666" />
              </TouchableOpacity>

              {/* Recent Categories Horizontal List */} 
              <View style={styles.recentCategoriesContainer}>
                {recentCategories.length > 0 && (
                  <>
                    <Text style={styles.recentLabel}>Recent:</Text>
                    <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                      {recentCategories.map(cat => (
                        <TouchableOpacity
                          key={cat.id}
                          style={styles.recentCategoryChip}
                          onPress={() => handleSelectCategory(cat.id)}
                        >
                          <Text style={styles.recentCategoryChipText}>{cat.name}</Text>
                        </TouchableOpacity>
                      ))}
                    </ScrollView>
                  </>
                )}
              </View>
            </View>
            
            {/* UPC/Barcode */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>UPC / Barcode</Text>
              <TextInput
                style={styles.input}
                value={item.barcode || ''}
                onChangeText={value => updateItem('barcode', value)}
                placeholder="Enter UPC or scan barcode"
                placeholderTextColor="#999"
                keyboardType="numeric" // Suggest numeric keyboard
              />
            </View>

            {/* Taxes */}
            <View style={styles.fieldContainer}>
              <View style={styles.sectionHeader}>
                <Text style={styles.label}>Taxes</Text>
                <TouchableOpacity 
                  style={[styles.selectAllButton, allTaxesSelected && styles.selectAllButtonSelected]}
                  onPress={handleSelectAllTaxes}
                >
                  <Text style={[styles.selectAllButtonText, allTaxesSelected && styles.selectAllButtonTextSelected]}>
                    {allTaxesSelected ? 'Deselect All' : 'Select All'}
                  </Text>
                </TouchableOpacity>
              </View>
              {availableTaxes.length > 0 ? (
                availableTaxes.map(tax => (
                  <TouchableOpacity
                    key={tax.id}
                    style={styles.checkboxContainer}
                    onPress={() => handleTaxSelection(tax.id)}
                    activeOpacity={0.7}
                  >
                    <Ionicons
                      name={item.taxIds?.includes(tax.id) ? 'checkbox' : 'square-outline'}
                      size={24}
                      color={item.taxIds?.includes(tax.id) ? lightTheme.colors.primary : '#ccc'}
                      style={styles.checkboxIcon}
                    />
                    <Text style={styles.checkboxLabel}>{tax.name} ({tax.percentage}%)</Text>
                  </TouchableOpacity>
                ))
              ) : (
                <Text style={styles.noItemsText}>No applicable taxes found.</Text>
              )}
            </View>

            {/* Modifiers */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Modifiers</Text>
              {availableModifierLists.length > 0 ? (
                availableModifierLists.map(modifier => (
                  <TouchableOpacity
                    key={modifier.id}
                    style={styles.checkboxContainer}
                    onPress={() => handleModifierSelection(modifier.id)} // Use direct ID toggle
                    activeOpacity={0.7}
                  >
                    <Ionicons
                      name={item.modifierListIds?.includes(modifier.id) ? 'checkbox' : 'square-outline'}
                      size={24}
                      color={item.modifierListIds?.includes(modifier.id) ? lightTheme.colors.primary : '#ccc'}
                      style={styles.checkboxIcon}
                    />
                    <Text style={styles.checkboxLabel}>{modifier.name}</Text>
                    {/* Optional: Add more info about the modifier list */}
                  </TouchableOpacity>
                ))
              ) : (
                <Text style={styles.noItemsText}>No modifier lists available.</Text>
              )}
              
              {/* Display Selected Modifiers (Optional but helpful for debugging) */}
              {item.modifierListIds && item.modifierListIds.length > 0 && (
                <View style={styles.selectedModifiersContainer}>
                  <Text style={styles.selectedModifiersLabel}>Selected:</Text>
                  {item.modifierListIds.map(id => (
                    <Text key={id} style={styles.selectedModifierItem}>
                      - {getModifierListName(id)} ({id})
                    </Text>
                  ))}
                </View>
              )}
            </View>

            {/* Description */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Description</Text>
              <TextInput
                style={[styles.input, styles.textArea]}
                value={item.description || ''}
                onChangeText={text => updateItem('description', text)} // Corrected onChangeText
                placeholder="Enter item description (optional)"
                placeholderTextColor="#999"
                multiline
                numberOfLines={4}
                textAlignVertical="top" // For Android alignment
              />
            </View>

            {/* Spacer to push delete button to the bottom */}
            <View style={{ height: 40 }} />
          </ScrollView>

          {/* Category Selection Modal */} 
          <Modal
            animationType="slide"
            transparent={true}
            visible={showCategoryModal}
            onRequestClose={() => setShowCategoryModal(false)}
          >
            <TouchableWithoutFeedback onPress={() => setShowCategoryModal(false)}>
              <View style={styles.modalOverlay}>
                <TouchableWithoutFeedback>
                  <View style={styles.modalContent}>
                    <Text style={styles.modalTitle}>Select Category</Text>
                    <TextInput
                      style={styles.searchInput}
                      placeholder="Search categories..."
                      value={categorySearch}
                      onChangeText={setCategorySearch}
                    />
                    <FlatList
                      data={filteredCategories}
                      keyExtractor={cat => cat.id}
                      renderItem={({ item: cat }) => (
                        <TouchableOpacity
                          style={styles.modalItem}
                          onPress={() => {
                            handleSelectCategory(cat.id);
                            setShowCategoryModal(false);
                          }}
                        >
                          <Text>{cat.name}</Text>
                        </TouchableOpacity>
                      )}
                      ListEmptyComponent={<Text style={styles.emptyListText}>No matching categories</Text>}
                    />
                    <TouchableOpacity
                      style={styles.closeButton}
                      onPress={() => setShowCategoryModal(false)}
                    >
                      <Text style={styles.closeButtonText}>Close</Text>
                    </TouchableOpacity>
                  </View>
                </TouchableWithoutFeedback>
              </View>
            </TouchableWithoutFeedback>
          </Modal>
        </>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: '#666',
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#fff',
    padding: 20,
  },
  errorText: {
    marginTop: 16,
    fontSize: 16,
    color: 'red',
    textAlign: 'center',
  },
  errorButton: {
    marginTop: 20,
    paddingVertical: 10,
    paddingHorizontal: 20,
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
  },
  errorButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
  },
  headerButton: {
    padding: 10,
  },
  headerButtonText: {
    fontSize: 16,
    color: lightTheme.colors.primary,
  },
  saveButton: {
    fontWeight: '600',
  },
  disabledText: {
    opacity: 0.5,
  },
  content: {
    flex: 1,
    padding: 16,
  },
  fieldContainer: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: '#555',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
    color: '#333',
    backgroundColor: '#fff',
  },
  textArea: {
    minHeight: 100,
    paddingTop: 12,
  },
  priceInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    backgroundColor: '#fff',
  },
  currencySymbol: {
    paddingLeft: 12,
    fontSize: 16,
    color: '#333',
  },
  priceInput: {
    flex: 1,
    paddingHorizontal: 8,
    paddingVertical: 10,
    fontSize: 16,
    color: '#333',
  },
  selectorButton: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: '#fff',
  },
  selectorText: {
    fontSize: 16,
    color: '#333',
  },
  switchRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  switchButton: {
    width: 51,
    height: 31,
    borderRadius: 25,
    padding: 5,
  },
  switchButtonActive: {
    backgroundColor: lightTheme.colors.primary,
  },
  switchButtonInactive: {
    backgroundColor: '#e0e0e0',
  },
  switchThumb: {
    width: 21,
    height: 21,
    borderRadius: 21,
    backgroundColor: 'white',
  },
  switchThumbActive: {
    transform: [{ translateX: 20 }],
  },
  switchThumbInactive: {
    transform: [{ translateX: 0 }],
  },
  helperText: {
    fontSize: 12,
    color: '#777',
    marginTop: 4,
  },
  deleteButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#d9534f',
    borderRadius: 8,
    paddingVertical: 12,
    marginTop: 20,
  },
  deleteButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
    marginLeft: 8,
  },
  modalContainer: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  modalContent: {
    width: '90%',
    maxWidth: 500,
    maxHeight: '80%',
    backgroundColor: 'white',
    borderRadius: 12,
    overflow: 'hidden',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    textAlign: 'center',
  },
  closeButton: {
    padding: 4,
  },
  searchInput: {
    margin: 16,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
    color: '#333',
    backgroundColor: '#f9f9f9',
  },
  categoryItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  selectedCategoryItem: {
    backgroundColor: '#f0f8ff',
  },
  categoryColor: {
    width: 16,
    height: 16,
    borderRadius: 8,
    marginRight: 12,
  },
  highlightedText: {
    backgroundColor: '#ffff99',
    fontWeight: '500',
  },
  emptyList: {
    padding: 20,
    alignItems: 'center',
  },
  emptyListText: {
    color: '#666',
    textAlign: 'center',
  },
  modalOverlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  confirmModalContent: {
    backgroundColor: 'white',
    borderRadius: 12,
    padding: 20,
    width: '85%',
    maxWidth: 400,
  },
  confirmModalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 12,
  },
  confirmModalText: {
    fontSize: 16,
    color: '#555',
    marginBottom: 20,
  },
  confirmModalButtons: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
  },
  confirmModalButton: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
    marginLeft: 12,
  },
  cancelButton: {
    backgroundColor: '#f0f0f0',
  },
  cancelButtonText: {
    color: '#333',
    fontWeight: '500',
  },
  discardButton: {
    backgroundColor: '#d9534f',
  },
  discardButtonText: {
    color: 'white',
    fontWeight: '500',
  },
  qrCodeButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
    paddingVertical: 12,
    marginBottom: 20,
  },
  qrCodeButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
    marginLeft: 8,
  },
  modalSearchInput: {
    margin: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    fontSize: 16,
  },
  modalItem: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  modalItemText: {
    fontSize: 16,
    color: '#333',
  },
  modalEmptyText: {
    padding: 20,
    textAlign: 'center',
    color: '#666',
  },
  modalCloseButton: {
    padding: 16,
    alignItems: 'center',
    backgroundColor: '#f0f0f0',
  },
  modalCloseButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.primary,
  },
  recentCategoriesContainer: {
    marginTop: 10,
  },
  recentLabel: {
    fontSize: 12,
    color: '#777',
    marginBottom: 5,
  },
  recentCategoryChip: {
    backgroundColor: '#e8f0fe', // Light blue background
    paddingVertical: 5,
    paddingHorizontal: 10,
    borderRadius: 15,
    marginRight: 8,
    borderWidth: 1,
    borderColor: '#c6d9f8', // Slightly darker blue border
  },
  recentCategoryChipText: {
    fontSize: 13,
    color: '#335b95', // Darker blue text
  },
  checkboxContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
  },
  checkboxLabel: {
    fontSize: 16,
    color: '#333',
    marginLeft: 8,
  },
  selectAllLabel: {
    fontWeight: 'bold',
  },
  checkboxGroup: {},
  // No minHeight or loadingInSection styles needed anymore
  rowContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginHorizontal: -4, // Adjust spacing between items if needed
  },
  rowItem: {
    flex: 1,
    marginHorizontal: 4, // Adjust spacing between items if needed
  },
  closeButtonText: { // Added for the modal close button
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.primary,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  selectAllButton: {
    padding: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
  },
  selectAllButtonSelected: {
    backgroundColor: lightTheme.colors.primary,
  },
  selectAllButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.primary,
  },
  selectAllButtonTextSelected: {
    color: 'white',
  },
  checkboxIcon: {
    marginRight: 8,
  },
  noItemsText: {
    color: '#777',
    marginTop: 4,
  },
  selectedModifiersContainer: {
    marginTop: 10,
  },
  selectedModifiersLabel: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#777',
  },
  selectedModifierItem: {
    color: '#333',
  },
}); 