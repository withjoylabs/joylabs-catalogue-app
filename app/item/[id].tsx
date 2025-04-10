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
  ActivityIndicator
} from 'react-native';
import { useRouter, useLocalSearchParams, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
// import { useCategories } from '../../src/hooks'; // Commented out
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { ConvertedItem, ConvertedCategory } from '../../src/types/api';
import { lightTheme } from '../../src/themes';
import { getAllCategories } from '../../src/database/modernDb'; // Import the new function

// Define type for category used in the picker
type CategoryPickerItem = { id: string; name: string };

// Empty item template for new items
const EMPTY_ITEM: ConvertedItem = {
  id: '',
  name: '',
  sku: '',
  price: undefined,
  description: '',
  categoryId: '', // Keep for now, but focus on reporting_category_id
  reporting_category_id: '', // Add this field
  category: '', // Keep for display compatibility?
  isActive: true,
  images: [],
  updatedAt: new Date().toISOString(),
  createdAt: new Date().toISOString()
};

export default function ItemDetails() {
  const router = useRouter();
  const { id } = useLocalSearchParams();
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
  
  // Fetch the item data and categories on component mount
  useEffect(() => {
    const fetchInitialData = async () => {
      setIsLoading(true);
      setError(null);
      
      try {
        // Fetch categories first
        const fetchedCategories = await getAllCategories();
        setAvailableCategories(fetchedCategories);
        setFilteredCategories(fetchedCategories); // Initialize filtered list
        
        // Fetch item data if not a new item
        if (!isNewItem && typeof id === 'string') {
          const fetchedItem = await getProductById(id);
          if (fetchedItem) {
            // Ensure reporting_category_id is set from fetched data
            // Assuming fetchedItem might have reporting_category: { id: ... }
            const initialReportingCategoryId = fetchedItem.reporting_category?.id || fetchedItem.reporting_category_id || '';
            const itemWithReportingId = { 
              ...fetchedItem, 
              reporting_category_id: initialReportingCategoryId 
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
  
  // Check if item has been edited
  useEffect(() => {
    if (!originalItem && !isNewItem) {
      setIsEdited(false);
      return;
    }
    
    if (isNewItem) {
      // For new items, check if any required field has been filled
      setIsEdited(
        !!item.name.trim() || 
        !!(item.sku && item.sku.trim()) || 
        item.price !== undefined ||
        !!(item.description && item.description.trim()) ||
        !!item.reporting_category_id // Check reporting category ID
      );
      return;
    }
    
    // For existing items, compare with original values
    const hasChanged = 
      originalItem?.name !== item.name ||
      originalItem?.sku !== item.sku ||
      originalItem?.price !== item.price ||
      originalItem?.description !== item.description ||
      originalItem?.reporting_category_id !== item.reporting_category_id; // Check reporting category ID
      
    setIsEdited(hasChanged);
  }, [item, originalItem, isNewItem]);
  
  // Update a field in the item state
  const updateItem = (key: keyof ConvertedItem, value: any) => {
    setItem(prev => ({ ...prev, [key]: value }));
  };
  
  // Check if the item form is empty (for cancel confirmation)
  const isEmpty = (): boolean => {
    return (
      !item.name.trim() && 
      !(item.sku && item.sku.trim()) && 
      item.price === undefined &&
      !(item.description && item.description.trim()) &&
      !item.reporting_category_id // Check reporting category ID
    );
  };
  
  // Get the current category name for display
  const selectedCategoryName = useMemo(() => {
    if (!item.reporting_category_id) return 'Select Category';
    const category = availableCategories.find(cat => cat.id === item.reporting_category_id);
    return category ? category.name : 'Select Category'; // Fallback if ID doesn't match
  }, [item.reporting_category_id, availableCategories]);
  
  // Handle selecting a category
  const handleSelectCategory = (category: CategoryPickerItem) => {
    updateItem('reporting_category_id', category.id); // Store the ID
    setShowCategoryModal(false);
  };
  
  // Handle cancel button press
  const handleCancel = () => {
    if (isEdited && !isEmpty()) {
      setShowCancelModal(true);
    } else {
      router.back();
    }
  };
  
  // Handle confirm cancel
  const handleConfirmCancel = () => {
    setShowCancelModal(false);
    router.back();
  };
  
  // Handle save button press
  const handleSave = async () => {
    // Validate required fields
    if (!item.name.trim()) {
      Alert.alert('Error', 'Item name is required');
      return;
    }
    
    setIsSaving(true);
    setError(null);
    
    try {
      let savedItem;
      
      // Prepare the item payload for saving, ensuring reporting_category is formatted
      const itemPayload: any = { ...item };
      if (item.reporting_category_id) {
        itemPayload.reporting_category = { id: item.reporting_category_id };
      } else {
        // Ensure reporting_category is explicitly null or removed if not selected
        // Depending on API requirements, choose one:
        itemPayload.reporting_category = null; 
        // delete itemPayload.reporting_category;
      }
      // Remove the temporary reporting_category_id field before sending
      delete itemPayload.reporting_category_id;
      // Also remove the potentially stale category name field
      delete itemPayload.category;
      
      if (isNewItem) {
        savedItem = await createProduct(itemPayload);
        Alert.alert('Success', 'Item created successfully');
      } else {
        if (typeof id !== 'string') {
            throw new Error('Invalid item ID for update');
        }
        savedItem = await updateProduct(id, itemPayload); 
        Alert.alert('Success', 'Item updated successfully');
      }
      
      if (savedItem) {
        // Re-add reporting_category_id for local state consistency
        const savedItemWithReportingId = { 
           ...savedItem, 
           reporting_category_id: savedItem.reporting_category?.id || '' 
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
  };
  
  // Handle delete button press
  const handleDelete = () => {
    Alert.alert(
      'Delete Item',
      'Are you sure you want to delete this item? This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        { 
          text: 'Delete', 
          style: 'destructive',
          onPress: confirmDelete
        }
      ]
    );
  };
  
  // Handle delete confirmation
  const confirmDelete = async () => {
    if (!item.id || isNewItem) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      await deleteProduct(item.id);
      Alert.alert('Success', 'Item deleted successfully');
      router.back();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete item');
      Alert.alert('Error', 'Failed to delete item. Please try again.');
      console.error('Error deleting item:', err);
    } finally {
      setIsLoading(false);
    }
  };
  
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
  
  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <StatusBar style="dark" />
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
        <Text style={styles.loadingText}>Loading item data...</Text>
      </View>
    );
  }
  
  if (error && !isNewItem) {
    return (
      <View style={styles.errorContainer}>
        <StatusBar style="dark" />
        <Ionicons name="alert-circle-outline" size={48} color="red" />
        <Text style={styles.errorText}>{error}</Text>
        <TouchableOpacity style={styles.errorButton} onPress={() => router.back()}>
          <Text style={styles.errorButtonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }
  
  return (
    <View style={styles.container}>
      <StatusBar style="dark" />
      
      <Stack.Screen
        options={{
          title: isNewItem ? 'Add New Item' : 'Edit Item',
          headerShown: true,
          headerStyle: {
            backgroundColor: '#fff',
          },
          headerTitleStyle: {
            color: '#333',
            fontWeight: 'bold',
          },
          headerLeft: () => (
            <TouchableOpacity
              style={styles.headerButton}
              onPress={handleCancel}
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
              onPress={handleSave}
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
        }}
      />
      
      <ScrollView style={styles.content} keyboardShouldPersistTaps="handled">
        {/* QR Code Button (Removed) */}
        {/* {!isNewItem && item.id && (
          <TouchableOpacity 
            style={styles.qrCodeButton}
            onPress={() => Alert.alert('QR Code', 'QR code generation will be implemented in a future update.')}
          >
            <Ionicons name="qr-code-outline" size={24} color={lightTheme.colors.primary} />
            <Text style={styles.qrCodeButtonText}>Generate QR Code</Text>
          </TouchableOpacity>
        )} */}
        
        {/* Item Name */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>Item Name*</Text>
          <TextInput
            style={styles.input}
            value={item.name}
            onChangeText={(text) => updateItem('name', text)}
            placeholder="Enter item name"
            placeholderTextColor="#999"
          />
        </View>
        
        {/* Item SKU */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>SKU</Text>
          <TextInput
            style={styles.input}
            value={item.sku || ''}
            onChangeText={(text) => updateItem('sku', text)}
            placeholder="Enter SKU (optional)"
            placeholderTextColor="#999"
          />
        </View>
        
        {/* Item GTIN/UPC */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>GTIN / UPC</Text>
          <TextInput
            style={styles.input}
            value={item.barcode || ''}
            onChangeText={(text) => updateItem('barcode', text)}
            placeholder="Enter GTIN or UPC (optional)"
            placeholderTextColor="#999"
            keyboardType="numeric"
          />
        </View>
        
        {/* Item Price */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>Price</Text>
          <View style={styles.priceInputContainer}>
            <Text style={styles.currencySymbol}>$</Text>
            <TextInput
              style={styles.priceInput}
              value={item.price !== undefined ? item.price.toString() : ''}
              onChangeText={(text) => {
                const price = text === '' ? undefined : parseFloat(text);
                updateItem('price', price);
              }}
              placeholder="0.00"
              placeholderTextColor="#999"
              keyboardType="decimal-pad"
            />
          </View>
        </View>
        
        {/* Reporting Category */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>Reporting Category</Text>
          <TouchableOpacity 
            style={styles.categorySelector} 
            onPress={() => {
              setCategorySearch(''); // Clear search on open
              setFilteredCategories(availableCategories); // Reset filter on open
              setShowCategoryModal(true);
            }}
          >
            <Text style={styles.categoryText}>
              {selectedCategoryName}
            </Text>
            <Ionicons name="chevron-down" size={20} color={lightTheme.colors.text} />
          </TouchableOpacity>
        </View>
        
        {/* Item Description */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>Description</Text>
          <TextInput
            style={[styles.input, styles.textArea]}
            value={item.description || ''}
            onChangeText={(text) => updateItem('description', text)}
            placeholder="Enter item description (optional)"
            placeholderTextColor="#999"
            multiline
            textAlignVertical="top"
            numberOfLines={4}
          />
        </View>
        
        {/* Item Status */}
        <View style={styles.fieldContainer}>
          <View style={styles.switchRow}>
            <Text style={styles.label}>Active</Text>
            <TouchableOpacity 
              style={[styles.switchButton, item.isActive ? styles.switchButtonActive : styles.switchButtonInactive]} 
              onPress={() => updateItem('isActive', !item.isActive)}
            >
              <View style={[styles.switchThumb, item.isActive ? styles.switchThumbActive : styles.switchThumbInactive]} />
            </TouchableOpacity>
          </View>
          <Text style={styles.helperText}>
            {item.isActive ? 'Item is active and will appear in your catalogue' : 'Item is inactive and will be hidden'}
          </Text>
        </View>
        
        {/* Delete Button (only for existing items) */}
        {!isNewItem && (
          <TouchableOpacity 
            style={styles.deleteButton}
            onPress={handleDelete}
            disabled={isSaving}
          >
            <Ionicons name="trash-outline" size={20} color="white" />
            <Text style={styles.deleteButtonText}>Delete Item</Text>
          </TouchableOpacity>
        )}
        
        {/* Add spacing at the bottom */}
        <View style={{ height: 40 }} />
      </ScrollView>
      
      {/* Category Selection Modal */}
      <Modal
        visible={showCategoryModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowCategoryModal(false)}
      >
        <TouchableWithoutFeedback onPress={() => setShowCategoryModal(false)}>
          <View style={styles.modalOverlay}>
            <TouchableWithoutFeedback>
              <View style={styles.modalContent}>
                <Text style={styles.modalTitle}>Select Reporting Category</Text>
                <TextInput
                  style={styles.modalSearchInput}
                  placeholder="Search categories..."
                  value={categorySearch}
                  onChangeText={setCategorySearch}
                />
                <FlatList
                  data={filteredCategories}
                  keyExtractor={(cat) => cat.id}
                  renderItem={({ item: cat }) => (
                    <TouchableOpacity 
                      style={styles.modalItem} 
                      onPress={() => handleSelectCategory(cat)}
                    >
                      {highlightMatchingText(cat.name, categorySearch)}
                    </TouchableOpacity>
                  )}
                  ListEmptyComponent={<Text style={styles.modalEmptyText}>No categories found</Text>}
                  keyboardShouldPersistTaps="handled" // Keep keyboard open while scrolling/tapping
                />
                <TouchableOpacity style={styles.modalCloseButton} onPress={() => setShowCategoryModal(false)}>
                  <Text style={styles.modalCloseButtonText}>Close</Text>
                </TouchableOpacity>
              </View>
            </TouchableWithoutFeedback>
          </View>
        </TouchableWithoutFeedback>
      </Modal>
      
      {/* Cancel Confirmation Modal */}
      <Modal
        visible={showCancelModal}
        animationType="fade"
        transparent={true}
        onRequestClose={() => setShowCancelModal(false)}
      >
        <TouchableWithoutFeedback onPress={() => setShowCancelModal(false)}>
          <View style={styles.modalOverlay}>
            <TouchableWithoutFeedback>
              <View style={styles.confirmModalContent}>
                <Text style={styles.confirmModalTitle}>Discard Changes?</Text>
                <Text style={styles.confirmModalText}>
                  You have unsaved changes. Are you sure you want to discard them?
                </Text>
                <View style={styles.confirmModalButtons}>
                  <TouchableOpacity
                    style={[styles.confirmModalButton, styles.cancelButton]}
                    onPress={() => setShowCancelModal(false)}
                  >
                    <Text style={styles.cancelButtonText}>Keep Editing</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[styles.confirmModalButton, styles.discardButton]}
                    onPress={handleConfirmCancel}
                  >
                    <Text style={styles.discardButtonText}>Discard</Text>
                  </TouchableOpacity>
                </View>
              </View>
            </TouchableWithoutFeedback>
          </View>
        </TouchableWithoutFeedback>
      </Modal>
    </View>
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
  categorySelector: {
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
  categoryText: {
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
    backgroundColor: 'white',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: Dimensions.get('window').height * 0.8,
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
    padding: 20,
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
  modalOverlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
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
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    textAlign: 'center',
    color: '#333',
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
}); 