import React, { useState, useEffect, useRef, useMemo, useCallback, useTransition, useOptimistic } from 'react';
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
import { printItemLabel, LabelData, getLabelPrinterStatus } from '../../src/utils/printLabel'; // Import the print functions
import { styles } from './itemStyles';
import CategorySelectionModal, { CategoryPickerItemType as ModalCategoryPickerItem } from '../../src/components/modals/CategorySelectionModal'; // Added import
import VariationPrintSelectionModal from '../../src/components/modals/VariationPrintSelectionModal'; // Added import
import PrintNotification from '../../src/components/modals/PrintNotification'; // Import the new component

// Define type for category used in the picker
// type CategoryPickerItem = { id: string; name: string }; // Now using ModalCategoryPickerItem or ensure consistency

// Define type for Tax and Modifier List Pickers
type TaxPickerItem = { id: string; name: string; percentage: string | null };
type ModifierListPickerItem = { id: string; name: string }; // Used for both CRV and others

// Empty item template for new items
const EMPTY_ITEM: ConvertedItem = {
  id: '',
  name: '',
  variationName: null,
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
  createdAt: new Date().toISOString(),
  variations: [] // Initialize empty variations array
};

// Define a type for variations
export interface ItemVariation {
  id?: string;
  version?: number;
  name: string | null;
  sku: string | null;
  price?: number;
  barcode?: string;
}

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
  const [optimisticItem, setOptimisticItem] = useOptimistic(item, 
    (currentItem: ConvertedItem, updatedValues: Partial<ConvertedItem>) => ({ ...currentItem, ...updatedValues })
  );
  const [isEdited, setIsEdited] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSavingPending, startTransition] = useTransition();
  const [isPrinting, setIsPrinting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showVariationModal, setShowVariationModal] = useState(false); // State for variation selection modal
  
  // State for print notification
  const [showPrintNotification, setShowPrintNotification] = useState(false);
  const [printNotificationMessage, setPrintNotificationMessage] = useState('');
  const [printNotificationType, setPrintNotificationType] = useState<'success' | 'error'>('success');
  
  // State for variations
  const [variations, setVariations] = useState<ItemVariation[]>([{
    name: null,
    sku: '',
    price: undefined,
    barcode: ''
  }]);
  const [optimisticVariations, setOptimisticVariations] = useOptimistic(variations, 
    (currentVariations: ItemVariation[], newVariations: ItemVariation[]) => newVariations
  );
  
  // State for category list and modal
  const [availableCategories, setAvailableCategories] = useState<ModalCategoryPickerItem[]>([]);
  const [filteredCategories, setFilteredCategories] = useState<ModalCategoryPickerItem[]>([]);
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [categorySearch, setCategorySearch] = useState('');
  
  // Confirmation modal state
  const [showCancelModal, setShowCancelModal] = useState(false);
  
  // State for recent categories
  const [recentCategories, setRecentCategories] = useState<ModalCategoryPickerItem[]>([]);
  
  // State for Taxes
  const [availableTaxes, setAvailableTaxes] = useState<TaxPickerItem[]>([]);
  const [showTaxModal, setShowTaxModal] = useState(false);
  const [allTaxesSelected, setAllTaxesSelected] = useState(false);

  // State for Modifiers
  const [availableModifierLists, setAvailableModifierLists] = useState<ModifierListPickerItem[]>([]);
  
  const itemSaveTriggeredAt = useAppStore((state) => state.itemSaveTriggeredAt);
  const lastProcessedSaveTrigger = useRef<number | null>(null);
  
  // --- Printing Logic --- 

  // Helper function to construct LabelData and call the print utility
  const initiatePrint = useCallback(async (variationIndex: number) => {
    if (!item || !variations || variationIndex < 0 || variationIndex >= variations.length) {
      logger.warn('ItemDetails:initiatePrint', 'Invalid data for printing', { itemId: item?.id, variationIndex });
      setPrintNotificationMessage('Could not get variation data for printing.');
      setPrintNotificationType('error');
      setShowPrintNotification(true);
      setTimeout(() => setShowPrintNotification(false), 3000);
      return;
    }

    const variationToPrint = variations[variationIndex];

    const labelData: LabelData = {
      itemId: item.id,
      itemName: item.name || 'Item Name',
      variationId: variationToPrint.id,
      variationName: variationToPrint.name || 'Regular',
      price: variationToPrint.price,
      sku: variationToPrint.sku,
      barcode: variationToPrint.barcode,
    };

    logger.info('ItemDetails:initiatePrint', 'Initiating print for variation', { 
      itemId: item.id, 
      variationIndex, 
      variationId: variationToPrint.id
    });
    
    try {
      setIsPrinting(true); 
      const success = await printItemLabel(labelData);
      if (success) {
        setPrintNotificationMessage(`Label for "${variationToPrint.name || item.name || 'Item'}" sent to printer.`);
        setPrintNotificationType('success');
      } else {
        setPrintNotificationMessage('Print failed. Check printer connection.');
        setPrintNotificationType('error');
      }
    } catch (error) {
      logger.error('ItemDetails:initiatePrint', 'Error during print', { error });
      setPrintNotificationMessage('An unexpected error occurred during print.');
      setPrintNotificationType('error');
    } finally {
      setIsPrinting(false);
      setShowPrintNotification(true);
      setTimeout(() => setShowPrintNotification(false), 3000);
    }

  }, [item, variations, setIsPrinting, setPrintNotificationMessage, setPrintNotificationType, setShowPrintNotification]);

  // Updated header print button handler
  const handlePrintLabel = useCallback(async () => {
    if (!variations || variations.length === 0) {
      Alert.alert('Error', 'No variations available to print.');
      return;
    }
    if (variations.length === 1) {
      logger.info('ItemDetails:handlePrintLabel', 'Single variation found, printing directly.');
      initiatePrint(0);
    } else {
      logger.info('ItemDetails:handlePrintLabel', 'Multiple variations found, showing modal.');
      setShowVariationModal(true);
    }
  }, [variations, initiatePrint, setShowVariationModal]);

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

  // Handler for variation input changes
  const handleVariationChange = (index: number, field: keyof ItemVariation, value: string | number | undefined) => {
    setVariations(prevVariations => {
      const newVariations = [...prevVariations];
      
      if (field === 'price') {
        // Handle price conversion similar to handleInputChange
        const textValue = value as string;
        
        if (textValue === '' || textValue === null || textValue === undefined) {
          newVariations[index] = { ...newVariations[index], price: undefined };
          return newVariations;
        }
        
        const digits = textValue.replace(/[^0-9]/g, '');
        
        if (digits === '') {
          newVariations[index] = { ...newVariations[index], price: undefined };
          return newVariations;
        }
        
        const cents = parseInt(digits, 10);
        
        if (isNaN(cents)) {
          console.warn('Invalid number parsed for variation price:', digits);
          newVariations[index] = { ...newVariations[index], price: undefined };
          return newVariations;
        }
        
        const dollars = cents / 100;
        newVariations[index] = { ...newVariations[index], price: dollars };
      } else {
        // Handle other fields
        newVariations[index] = { ...newVariations[index], [field]: value };
      }
      
      return newVariations;
    });
    
    // Mark as edited
    setIsEdited(true);
  };

  // Handler to add a new variation
  const addVariation = () => {
    setVariations(prev => [...prev, {
      name: null,
      sku: '',
      price: undefined,
      barcode: ''
    }]);
    setIsEdited(true);
  };

  // Handler to remove a variation
  const removeVariation = (index: number) => {
    // Don't allow removing the last variation
    if (variations.length <= 1) {
      return;
    }

    setVariations(prev => prev.filter((_, i) => i !== index));
    setIsEdited(true);
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
      !(item.name && item.name.trim()) && 
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

  const handleSaveAction = useCallback(async () => {
    logger.info('ItemDetails:handleSaveAction', 'Save process initiated', { isNewItem, itemId: item.id });
    Keyboard.dismiss();

    const currentItemForOptimisticUpdate = { ...item }; 
    const currentVariationsForOptimisticUpdate = variations.map(v => ({...v})); 

    // setOptimisticItem(currentItemForOptimisticUpdate); // Moved inside startTransition
    // setOptimisticVariations(currentVariationsForOptimisticUpdate); // Moved inside startTransition

    startTransition(async () => {
      // Set optimistic state inside the transition
      setOptimisticItem(currentItemForOptimisticUpdate); 
      setOptimisticVariations(currentVariationsForOptimisticUpdate);

      logger.info('ItemDetails:handleSaveAction', 'Save transition started');
      setError(null);

      if (!(item.name && item.name.trim())) { // Ensure item.name is not null/empty before trimming
        Alert.alert('Error', 'Item name is required.');
        logger.warn('ItemDetails:handleSaveAction', 'Save aborted: Item name missing');
        return; 
      }

      const basePayload = {
        ...item, 
        name: item.name || null, 
        description: item.description || null, 
        sku: item.sku || null, 
        abbreviation: item.abbreviation || null, 
        reporting_category_id: item.reporting_category_id || null, 
        variations: variations.map(v => ({ 
          id: v.id,
          version: v.version,
          name: v.name as (string | null), // Explicit cast to help linter
          price: v.price, 
          sku: v.sku as (string | null), // Explicit cast
          barcode: v.barcode || null, 
        })),
        taxIds: item.taxIds || [],
        modifierListIds: item.modifierListIds || [],
        isActive: typeof item.isActive === 'boolean' ? item.isActive : true, 
      };

      let submissionPayload: any = { ...basePayload };
      delete submissionPayload.category; 
      delete submissionPayload.categoryId; 
      delete submissionPayload.variationName; 
      
      if (isNewItem) {
        delete submissionPayload.id;
        // `version` is optional in ConvertedItem and not needed for new Square items.
        // It will be assigned by Square upon creation.
        delete submissionPayload.version; 
      } else {
        // For updates, ensure id and version are definitely present and correct.
        if (!originalItem?.id || typeof item.version !== 'number') {
          logger.error('ItemDetails:handleSaveAction', 'Missing id or version for update', { originalItem, itemVersion: item.version });
          throw new Error('Cannot update item: missing ID or version.');
        }
        submissionPayload.id = originalItem.id; 
        submissionPayload.version = item.version;
      }

      try {
        let savedItemResponse: ConvertedItem | null | undefined; 

        if (isNewItem) {
          logger.info('ItemDetails:handleSaveAction', 'Creating new product with payload:', submissionPayload);
          savedItemResponse = await createProduct(submissionPayload); // createProduct takes `any`
        } else { 
          // submissionPayload here should now have a definite id and version from the block above.
          logger.info('ItemDetails:handleSaveAction', `Updating product ID ${submissionPayload.id} with payload:`, submissionPayload);
          savedItemResponse = await updateProduct(submissionPayload.id, submissionPayload as ConvertedItem);
        } 

        if (savedItemResponse) {
          const finalSavedItem: ConvertedItem = savedItemResponse; 
          logger.info('ItemDetails:handleSaveAction', 'Product saved successfully to backend', { savedItemId: finalSavedItem.id });
          setItem(finalSavedItem); 
          setOriginalItem(finalSavedItem); 
          setVariations(finalSavedItem.variations || []); 
          setIsEdited(false);
          
          Alert.alert('Success', `Item ${item.name || 'Selected Item'} ${isNewItem ? 'created' : 'updated'} successfully.`);
          if (navigation.canGoBack()) {
            navigation.goBack();
          } else {
            router.replace('/');
          }
        } else {
          logger.error('ItemDetails:handleSaveAction', 'Save operation completed but no saved item data was returned.');
          setError('Save operation failed: No item data returned. Please try again.');
          Alert.alert('Save Error', 'Save operation failed to return item data. The item may not have been saved correctly.');
        }
      } catch (e: any) {
        const errorMessage = e.message || 'An unexpected error occurred during save.';
        logger.error('ItemDetails:handleSaveAction', 'Error saving product during transition:', { error: errorMessage, details: e });
        setError(errorMessage);
        Alert.alert('Save Error', errorMessage);
        // If an error occurs, React automatically reverts optimistic updates tied to this transition.
        // You might want to explicitly reset 'item' to 'originalItem' here if the optimistic state was very different
        // and you don't want the user to see it anymore.
        // Example: if (originalItem) setItem(originalItem);
      }
    });
    logger.info('ItemDetails:handleSaveAction', 'Save process function call ended (transition may still be pending)');
  }, [
    item, 
    variations, 
    isNewItem, 
    id, // original id from params for update target
    originalItem, // for version and id for update
    createProduct, 
    updateProduct, 
    setOptimisticItem, // Added
    setOptimisticVariations, // Added
    startTransition, // Added
    setError, 
    setItem, 
    setOriginalItem, 
    setIsEdited, 
    navigation, // Added router from previous dependencies
    router
  ]);
  
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
          .filter((cat): cat is ModalCategoryPickerItem => cat !== undefined); // Remove undefined if ID not found
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
            
            // Initialize variations from the fetched item
            // If no variations exist, create a default one
            const itemVariations = fetchedItem.variations && Array.isArray(fetchedItem.variations) && fetchedItem.variations.length > 0
              ? fetchedItem.variations.map(v => ({
                  id: v.id,
                  version: v.version,
                  name: v.name || null,
                  sku: v.sku || null,
                  price: v.price,
                  barcode: v.barcode
                }))
              : [{
                  id: fetchedItem.variationId,
                  version: fetchedItem.variationVersion,
                  name: fetchedItem.variationName || null,
                  sku: fetchedItem.sku || null,
                  price: fetchedItem.price,
                  barcode: fetchedItem.barcode
                }];
            
            setVariations(itemVariations);
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
          onPress={handleCancel}
          disabled={isSavingPending || isPrinting}
        >
          <Text style={[styles.headerButtonText, (isSavingPending || isPrinting) && styles.disabledText]}>
            Cancel
          </Text>
        </TouchableOpacity>
      ),
      headerRight: () => (
        <View /* style={styles.headerRightContainer} // Temporarily removed */ >
          {!isNewItem && (
            <TouchableOpacity
              style={styles.headerButton}
              onPress={handlePrintLabel}
              disabled={isSavingPending || isPrinting}
            >
              {(isSavingPending || isPrinting) ? (
                <ActivityIndicator size="small" color={lightTheme.colors.primary} />
              ) : (
                <Text style={[styles.headerButtonText, (isSavingPending || isPrinting) && styles.disabledText]}>
                  Print Label
                </Text>
              )}
            </TouchableOpacity>
          )}
          <TouchableOpacity
            style={[
              styles.headerButton,
              (isSavingPending || isPrinting) && styles.disabledText
            ]}
            onPress={handleSaveAction}
            disabled={isSavingPending || isPrinting}
          >
            {(isSavingPending) ? (
              <ActivityIndicator size="small" color={lightTheme.colors.primary} />
            ) : (
              <Text style={[styles.headerButtonText, /* styles.saveButtonText // Temporarily use headerButtonText if saveButtonText is missing */]}>Save</Text>
            )}
          </TouchableOpacity>
        </View>
      ),
    });
  }, [navigation, isNewItem, isSavingPending, isPrinting, handleCancel, handlePrintLabel, handleSaveAction]);
  
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
          !!(item.name && item.name.trim()) ||
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
      handleSaveAction();
      lastProcessedSaveTrigger.current = itemSaveTriggeredAt; // Mark this trigger as processed
    }
  }, [itemSaveTriggeredAt, handleSaveAction]);
  
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
                value={item.name || ''}
                onChangeText={value => handleInputChange('name', value)}
                placeholder="Enter item name"
                placeholderTextColor="#999"
              />
            </View>

            {/* Variations Section */}
            <View style={styles.fieldContainer}>
              <Text style={styles.sectionHeaderText}>Variations</Text>
              
              {variations.map((variation, index) => (
                <View key={`variation-${index}`} style={styles.variationContainer}>
                  <View style={styles.variationHeader}>
                    <Text style={styles.variationTitle}>Variation {index + 1}</Text>
                    <View style={styles.variationHeaderButtons}>
                      <TouchableOpacity
                        style={styles.inlinePrintButton}
                        onPress={() => initiatePrint(index)}
                      >
                        <Ionicons name="print-outline" size={18} color={lightTheme.colors.primary} style={styles.inlinePrintIcon} />
                        <Text style={styles.inlinePrintButtonText}>Print</Text>
                      </TouchableOpacity>
                    {variations.length > 1 && (
                      <TouchableOpacity 
                        onPress={() => removeVariation(index)}
                        style={styles.removeVariationButton}
                      >
                        <Ionicons name="close-circle" size={22} color="#ff3b30" />
                      </TouchableOpacity>
                    )}
                    </View>
                  </View>

                  {/* Variation Name */}
                  <View style={styles.fieldContainer}>
                    <Text style={styles.subLabel}>Variation Name</Text>
                    <TextInput
                      style={styles.input}
                      value={variation.name || ''}
                      onChangeText={(value) => handleVariationChange(index, 'name', value)}
                      placeholder="e.g., Regular, Large, Blue (optional)"
                      placeholderTextColor="#999"
                    />
                  </View>

                  {/* SKU */}
                  <View style={styles.fieldContainer}>
                    <Text style={styles.subLabel}>SKU</Text>
                    <TextInput
                      style={styles.input}
                      value={variation.sku || ''}
                      onChangeText={(value) => handleVariationChange(index, 'sku', value)}
                      placeholder="Enter SKU (optional)"
                      placeholderTextColor="#999"
                      autoCapitalize="characters"
                    />
                  </View>

                  {/* Price */}
                  <View style={styles.fieldContainer}>
                    <Text style={styles.subLabel}>Price</Text>
                    <View style={styles.priceInputContainer}>
                      <Text style={styles.currencySymbol}>$</Text>
                      <TextInput
                        style={styles.priceInput}
                        value={variation.price !== undefined ? variation.price.toFixed(2) : ''}
                        onChangeText={(value) => handleVariationChange(index, 'price', value)}
                        placeholder="Variable"
                        placeholderTextColor="#999"
                        keyboardType="numeric"
                      />
                    </View>
                    <Text style={styles.helperText}>Leave blank for variable pricing</Text> 
                  </View>
                  
                  {/* UPC/Barcode */}
                  <View style={styles.fieldContainer}>
                    <Text style={styles.subLabel}>UPC / Barcode</Text>
                    <TextInput
                      style={styles.input}
                      value={variation.barcode || ''}
                      onChangeText={(value) => handleVariationChange(index, 'barcode', value)}
                      placeholder="Enter UPC or scan barcode"
                      placeholderTextColor="#999"
                      keyboardType="numeric"
                    />
                  </View>
                </View>
              ))}
              
              <TouchableOpacity 
                style={styles.addVariationButton}
                onPress={addVariation}
              >
                <Ionicons name="add-circle-outline" size={20} color={lightTheme.colors.primary} />
                <Text style={styles.addVariationText}>Add Variation</Text>
              </TouchableOpacity>
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

          {/* Category Selection Modal - Replaced with component */}
          <CategorySelectionModal
            visible={showCategoryModal}
            onClose={() => setShowCategoryModal(false)}
            filteredCategories={filteredCategories}
            onSelectCategory={(categoryId) => {
              handleSelectCategory(categoryId); // This already calls setShowCategoryModal(false)
            }}
            categorySearch={categorySearch}
            setCategorySearch={setCategorySearch}
            // categories={availableCategories} // Pass availableCategories if needed by modal for its own filtering/display logic
          />

          {/* --- Variation Selection Modal - Replaced with Component --- */}
          <VariationPrintSelectionModal
            visible={showVariationModal}
            onClose={() => setShowVariationModal(false)}
            variations={variations} // Pass the actual variations state
            onSelectVariation={(index) => {
              initiatePrint(index); // initiatePrint already exists
              // setShowVariationModal(false); // Modal will close itself via its own onPress logic
            }}
          />

          {/* Print Notification Modal */}
          <PrintNotification
            visible={showPrintNotification}
            message={printNotificationMessage}
            type={printNotificationType}
            onClose={() => setShowPrintNotification(false)} // Allows manual close if ever needed by design
          />
        </>
      )}
    </SafeAreaView>
  );
}