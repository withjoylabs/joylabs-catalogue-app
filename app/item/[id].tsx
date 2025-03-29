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
import { useCategories } from '../../src/hooks';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { ConvertedItem, ConvertedCategory } from '../../src/types/api';
import { lightTheme } from '../../src/themes';

// Empty item template for new items
const EMPTY_ITEM: ConvertedItem = {
  id: '',
  name: '',
  sku: '',
  price: undefined,
  description: '',
  categoryId: '',
  category: '',
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
  const { 
    categories, 
    getCategoryById,
    dropdownItems
  } = useCategories();
  
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
  
  // Category selection modal state
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [categorySearch, setCategorySearch] = useState('');
  const [filteredCategories, setFilteredCategories] = useState<ConvertedCategory[]>([]);
  
  // Confirmation modal state
  const [showCancelModal, setShowCancelModal] = useState(false);
  
  // Fetch the item data on component mount
  useEffect(() => {
    const fetchItemData = async () => {
      setIsLoading(true);
      setError(null);
      
      try {
        if (isNewItem) {
          setItem(EMPTY_ITEM);
          setOriginalItem(null);
        } else if (id) {
          const fetchedItem = await getProductById(id as string);
          if (fetchedItem) {
            setItem(fetchedItem);
            setOriginalItem(fetchedItem);
          } else {
            setError('Item not found');
            setItem(EMPTY_ITEM);
          }
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load item');
        console.error('Error fetching item:', err);
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchItemData();
  }, [id, getProductById, isNewItem]);
  
  // Filter categories when search text changes
  useEffect(() => {
    if (categories) {
      if (!categorySearch) {
        setFilteredCategories(categories);
      } else {
        const searchLower = categorySearch.toLowerCase();
        const filtered = categories.filter(
          category => category.name.toLowerCase().includes(searchLower)
        );
        setFilteredCategories(filtered);
      }
    }
  }, [categories, categorySearch]);
  
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
        !!item.categoryId
      );
      return;
    }
    
    // For existing items, compare with original values
    const hasChanged = 
      originalItem?.name !== item.name ||
      originalItem?.sku !== item.sku ||
      originalItem?.price !== item.price ||
      originalItem?.description !== item.description ||
      originalItem?.categoryId !== item.categoryId;
      
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
      !item.categoryId
    );
  };
  
  // Get the current category name
  const selectedCategoryName = useMemo(() => {
    if (!item.categoryId) return '';
    const category = getCategoryById(item.categoryId);
    return category ? category.name : '';
  }, [item.categoryId, getCategoryById]);
  
  // Handle selecting a category
  const handleSelectCategory = (category: ConvertedCategory) => {
    updateItem('categoryId', category.id);
    updateItem('category', category.name);
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
      
      if (isNewItem) {
        savedItem = await createProduct(item);
        Alert.alert('Success', 'Item created successfully');
      } else {
        savedItem = await updateProduct(item);
        Alert.alert('Success', 'Item updated successfully');
      }
      
      if (savedItem) {
        setItem(savedItem);
        setOriginalItem(savedItem);
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
  
  // Track selected category in modal
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>('');
  
  // Update selected category when item changes
  useEffect(() => {
    setSelectedCategoryId(item.categoryId || '');
  }, [item.categoryId]);
  
  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <StatusBar style="dark" />
        <ActivityIndicator size="large" color={lightTheme.colors.primary} />
        <Text style={styles.loadingText}>Loading item...</Text>
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
      
      <ScrollView style={styles.content}>
        {/* QR Code Button (only for existing items that have been saved) */}
        {!isNewItem && item.id && (
          <TouchableOpacity 
            style={styles.qrCodeButton}
            onPress={() => Alert.alert('QR Code', 'QR code generation will be implemented in a future update.')}
          >
            <Ionicons name="qr-code-outline" size={24} color={lightTheme.colors.primary} />
            <Text style={styles.qrCodeButtonText}>Generate QR Code</Text>
          </TouchableOpacity>
        )}
        
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
        
        {/* Item Category */}
        <View style={styles.fieldContainer}>
          <Text style={styles.label}>Category</Text>
          <TouchableOpacity 
            style={styles.categorySelector}
            onPress={() => setShowCategoryModal(true)}
          >
            <Text style={selectedCategoryName ? styles.categoryText : styles.placeholderText}>
              {selectedCategoryName || 'Select a category (optional)'}
            </Text>
            <Ionicons name="chevron-down" size={20} color="#888" />
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
        <View style={styles.modalContainer}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Category</Text>
              <TouchableOpacity
                onPress={() => setShowCategoryModal(false)}
                style={styles.closeButton}
              >
                <Ionicons name="close" size={24} color="#333" />
              </TouchableOpacity>
            </View>
            
            <TextInput
              style={styles.searchInput}
              value={categorySearch}
              onChangeText={setCategorySearch}
              placeholder="Search categories"
              placeholderTextColor="#999"
              clearButtonMode="while-editing"
            />
            
            <FlatList
              data={filteredCategories}
              keyExtractor={(item) => item.id}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={[
                    styles.categoryItem,
                    item.id === selectedCategoryId && styles.selectedCategoryItem
                  ]}
                  onPress={() => handleSelectCategory(item)}
                >
                  <View style={[styles.categoryColor, { backgroundColor: item.color || '#ddd' }]} />
                  {highlightMatchingText(item.name, categorySearch)}
                  {item.id === selectedCategoryId && (
                    <Ionicons name="checkmark" size={20} color={lightTheme.colors.primary} />
                  )}
                </TouchableOpacity>
              )}
              ListEmptyComponent={() => (
                <View style={styles.emptyList}>
                  <Text style={styles.emptyListText}>
                    {categories.length === 0
                      ? 'No categories available. Create categories in the profile section.'
                      : 'No matching categories found.'}
                  </Text>
                </View>
              )}
            />
          </View>
        </View>
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
  placeholderText: {
    fontSize: 16,
    color: '#999',
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
}); 