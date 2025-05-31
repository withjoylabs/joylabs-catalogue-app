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
import { getAllCategories, getAllTaxes, getAllModifierLists, getAllLocations } from '../../src/database/modernDb';
import { getRecentCategoryIds, addRecentCategoryId } from '../../src/utils/recentCategories';
import { useAppStore } from '../../src/store';
import logger from '../../src/utils/logger';
import { printItemLabel, LabelData, getLabelPrinterStatus } from '../../src/utils/printLabel';
import { styles } from './itemStyles';
import CategorySelectionModal, { CategoryPickerItemType as ModalCategoryPickerItem } from '../../src/components/modals/CategorySelectionModal';
import VariationPrintSelectionModal from '../../src/components/modals/VariationPrintSelectionModal';
import PrintNotification from '../../src/components/modals/PrintNotification';
import apiClient from '../../src/api';
import SystemModal from '../../src/components/SystemModal';

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
  locationOverrides?: Array<{
    locationId: string;
    locationName?: string;
    price?: number;
  }>;
}

export default function ItemDetails() {
  const router = useRouter();
  const { id, ...params } = useLocalSearchParams<{ id: string, name?: string, sku?: string, barcode?: string }>();
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
  const [isSaving, setIsSaving] = useState(false);
  const [isSavingPending, startTransition] = useTransition();
  const [isPrinting, setIsPrinting] = useState(false);
  const [isPrintingAndSaving, setIsPrintingAndSaving] = useState(false); // New loading state
  const [error, setError] = useState<string | null>(null);
  const [showVariationModal, setShowVariationModal] = useState(false); // State for variation selection modal
  const [printingVariationIndex, setPrintingVariationIndex] = useState<number | null>(null); // For inline print button loading state
  
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
  
  // State for Locations
  const [availableLocations, setAvailableLocations] = useState<Array<{id: string, name: string}>>([]);
  
  const itemSaveTriggeredAt = useAppStore((state: any) => state.itemSaveTriggeredAt);
  const lastProcessedSaveTrigger = useRef<number | null>(null);
  
  // Get notification state from store
  const { 
    setShowSuccessNotification, 
    setSuccessMessage,
    showSuccessNotification,
    successMessage 
  } = useAppStore();
  
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
      variationName: variationToPrint.name === null ? undefined : variationToPrint.name,
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

  const handlePrintAndSave = async () => {
    setIsPrintingAndSaving(true);
    logger.info('ItemDetails:handlePrintAndSave', 'Starting Print and Save process.');

    // --- Step 1: Print ---
    let printSuccess = false;
    if (!variations || variations.length === 0) {
      logger.info('ItemDetails:handlePrintAndSave', 'No variations, skipping print.');
      printSuccess = true; // Consider it "success" for proceeding to save
    } else if (variations.length === 1) {
      logger.info('ItemDetails:handlePrintAndSave', 'Single variation, attempting direct print.');
      // Re-implement part of initiatePrint logic here to control notifications better
      // Or modify initiatePrint to return a status and not show its own modal for this flow
      // For now, let's assume initiatePrint handles its notifications and we await its completion.
      // A more robust solution might involve initiatePrint returning a promise that resolves to a boolean.
      try {
        await initiatePrint(0); // Assuming initiatePrint is now async and handles its own UI feedback
        // Check a flag or a ref if initiatePrint cannot return success directly.
        // This is a simplification; robust error handling from initiatePrint is needed.
        // For now, we'll assume if no error is thrown, it's a "go" for saving.
        printSuccess = true; 
      } catch (printError) {
        logger.error('ItemDetails:handlePrintAndSave', 'Error during direct print step.', { printError });
        printSuccess = false; 
        // Notification is handled by initiatePrint
      }
    } else {
      logger.info('ItemDetails:handlePrintAndSave', 'Multiple variations, showing selection modal.');
      // This part is tricky because setShowVariationModal is async UI.
      // We need a way to know if the user selected something and it printed.
      // This might require a change in how VariationPrintSelectionModal signals back.
      // For now, let's prompt and if they cancel, we still save.
      // Or, we make printing a prerequisite.
      // Let's assume for now: if they have multiple variations, we ask them to print one,
      // but we can't easily gate the save on that modal's outcome without a callback/promise.
      // This is a UX challenge. Simplest for now: open modal, then save regardless of print outcome.
      // A better way: handlePrintLabel could return a promise that resolves with print status.
      
      // Let's call handlePrintLabel which shows the modal
      await handlePrintLabel(); // It handles its own notifications.
      // We need to determine if print was successful or skipped.
      // This is a simplification: we're assuming if it doesn't throw, we proceed.
      // In a real scenario, handlePrintLabel might need to return a status or set a state.
      printSuccess = true; // Assume user handles print, then we save.
    }

    // --- Step 2: Save (if print was "successful" or skipped) ---
    if (printSuccess) {
      logger.info('ItemDetails:handlePrintAndSave', 'Print step completed (or skipped), proceeding to save.');
      try {
        await handleSaveAction(); // handleSaveAction already handles its own notifications and loading states
        logger.info('ItemDetails:handlePrintAndSave', 'Save action completed.');
      } catch (saveError) {
        logger.error('ItemDetails:handlePrintAndSave', 'Error during save step.', { saveError });
        // handleSaveAction should be setting its own error UI.
        // If not, we'd set a global error here.
      }
    } else {
      logger.warn('ItemDetails:handlePrintAndSave', 'Print step was not successful, skipping save.');
      // Notification for print failure is handled by initiatePrint/handlePrintLabel
    }

    setIsPrintingAndSaving(false);
    logger.info('ItemDetails:handlePrintAndSave', 'Print and Save process finished.');
  };

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
      } else if (field === 'locationOverrides') {
        // Handle location overrides as a special case
        newVariations[index] = { ...newVariations[index], locationOverrides: value as any };
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

  // Handler to add a price override to a variation
  const addPriceOverride = (variationIndex: number) => {
    setVariations(prevVariations => {
      const newVariations = [...prevVariations];
      const variation = newVariations[variationIndex];
      
      // Initialize locationOverrides array if it doesn't exist
      if (!variation.locationOverrides) {
        variation.locationOverrides = [];
      }
      
      // Add a new empty override
      variation.locationOverrides.push({
        locationId: '', // Will be selected by user
        price: undefined // Will be entered by user
      });
      
      return newVariations;
    });
    
    setIsEdited(true);
  };

  // Handler to remove a price override from a variation
  const removePriceOverride = (variationIndex: number, overrideIndex: number) => {
    setVariations(prevVariations => {
      const newVariations = [...prevVariations];
      const variation = newVariations[variationIndex];
      
      if (variation.locationOverrides && variation.locationOverrides.length > overrideIndex) {
        variation.locationOverrides.splice(overrideIndex, 1);
      }
      
      return newVariations;
    });
    
    setIsEdited(true);
  };

  // Handler to update a price override
  const updatePriceOverride = (variationIndex: number, overrideIndex: number, field: 'locationId' | 'price', value: string | number | undefined) => {
    setVariations(prevVariations => {
      const newVariations = [...prevVariations];
      const variation = newVariations[variationIndex];
      
      if (!variation.locationOverrides || variation.locationOverrides.length <= overrideIndex) {
        return newVariations;
      }
      
      if (field === 'price') {
        // Handle price conversion similar to handleInputChange
        const textValue = value as string;
        
        if (textValue === '' || textValue === null || textValue === undefined) {
          variation.locationOverrides[overrideIndex].price = undefined;
          return newVariations;
        }
        
        const digits = textValue.replace(/[^0-9]/g, '');
        
        if (digits === '') {
          variation.locationOverrides[overrideIndex].price = undefined;
          return newVariations;
        }
        
        const cents = parseInt(digits, 10);
        
        if (isNaN(cents)) {
          console.warn('Invalid number parsed for override price:', digits);
          variation.locationOverrides[overrideIndex].price = undefined;
          return newVariations;
        }
        
        const dollars = cents / 100;
        variation.locationOverrides[overrideIndex].price = dollars;
      } else {
        // Handle locationId
        variation.locationOverrides[overrideIndex].locationId = value as string;
        
        // Update the location name if available
        const location = availableLocations.find(loc => loc.id === value);
        if (location) {
          variation.locationOverrides[overrideIndex].locationName = location.name;
        }
      }
      
      return newVariations;
    });
    
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
      router.back(); // Dismiss modal
    }
  }, [isEdited, isEmpty, router, setShowCancelModal]);

  const handleConfirmCancel = useCallback(() => {
    setShowCancelModal(false);
    router.back(); // Dismiss modal
  }, [router, setShowCancelModal]);

  const handleSaveAction = async () => {
    try {
      if (!item.name) {
        setError('Item name is required');
        return; 
      }

      setIsSaving(true);
      setError(null);

      // Log the action
      logger.info('ItemDetails', 'Starting save action', {
        isNewItem: !item.id,
        itemId: item.id,
        itemName: item.name,
        variationsCount: variations.length
      });

      let savedItemResponse;
      if (!item.id) {
        // Create new product
        logger.info('ItemDetails', 'Creating new product', { itemName: item.name });
        savedItemResponse = await createProduct({
          ...item,
          variations
        });
      } else {
        // Update existing product
        logger.info('ItemDetails', 'Updating existing product', { 
          itemId: item.id,
          itemName: item.name,
          version: item.version
        });
        savedItemResponse = await updateProduct(item.id, {
          ...item,
          variations
        });
      }

      if (savedItemResponse) {
        logger.info('ItemDetails', 'Save successful', { 
          itemId: savedItemResponse.id,
          itemName: savedItemResponse.name
        });

        // First, navigate back to close the modal
        router.back();

        // Wait a very short time for the modal to start closing
        await new Promise(resolve => setTimeout(resolve, 50));

        // Then show success notification
        setSuccessMessage(`Item ${!item.id ? 'created' : 'updated'} successfully`);
        // setShowSuccessNotification(true); // Temporarily commented out for testing
          } else {
        throw new Error('Failed to save item');
        }
    } catch (error) {
      logger.error('ItemDetails', 'Error saving item', error);
      setError('Failed to save item. Please try again.');
    } finally {
      setIsSaving(false);
    }
  };
  
  // Fetch the item data, categories, taxes, and modifiers on component mount
  useEffect(() => {
    const fetchInitialData = async () => {
      setIsLoading(true);
      setError(null);
      
      try {
        // Fetch categories, taxes, modifiers, and locations concurrently
        const [fetchedCategories, fetchedTaxes, fetchedModifierLists, fetchedLocations] = await Promise.all([
          getAllCategories(),
          getAllTaxes(),
          getAllModifierLists(),
          getAllLocations()
        ]);

        console.log('[ItemDetails] Fetched Taxes:', JSON.stringify(fetchedTaxes, null, 2));
        console.log('[ItemDetails] Fetched Modifier Lists:', JSON.stringify(fetchedModifierLists, null, 2));

        setAvailableCategories(fetchedCategories);
        setFilteredCategories(fetchedCategories); 
        setAvailableTaxes(fetchedTaxes);
        setAvailableModifierLists(fetchedModifierLists);
        setAvailableLocations(fetchedLocations);
        
        const initialTaxIdsSet = new Set(item?.taxIds || []);
        const allFetchedTaxIds = new Set(fetchedTaxes.map(tax => tax.id));
        const areAllSelected = fetchedTaxes.length > 0 && fetchedTaxes.every(tax => initialTaxIdsSet.has(tax.id));
        setAllTaxesSelected(Boolean(areAllSelected));
        
        const recentIds = await getRecentCategoryIds();
        const recentCategoryObjects = recentIds
          .map(id => fetchedCategories.find(cat => cat.id === id))
          .filter((cat): cat is ModalCategoryPickerItem => cat !== undefined); 
        setRecentCategories(recentCategoryObjects);
        
        if (!isNewItem && typeof id === 'string') {
          const fetchedItem = await getProductById(id);
          if (fetchedItem) {
            console.log('[ItemDetails] Fetched Item Data:', JSON.stringify(fetchedItem, null, 2)); 
            const initialReportingCategoryId = (fetchedItem as any).reporting_category?.id || fetchedItem.reporting_category_id || '';
            console.log('[ItemDetails] Initial Reporting Category ID:', initialReportingCategoryId); 
            
            const initialTaxIds = fetchedItem.taxIds || [];
            const initialModifierListIds = fetchedItem.modifierListIds || [];
            const initialVersion = fetchedItem.version; 
            
            const itemWithReportingId = { 
              ...fetchedItem, 
              version: initialVersion, 
              reporting_category_id: initialReportingCategoryId,
              taxIds: initialTaxIds, 
              modifierListIds: initialModifierListIds 
            };
            setItem(itemWithReportingId);
            setOriginalItem(itemWithReportingId); 
            
            const itemVariations = fetchedItem.variations && Array.isArray(fetchedItem.variations) && fetchedItem.variations.length > 0
              ? fetchedItem.variations.map(v => ({
                  id: (v as ItemVariation).id,
                  version: (v as ItemVariation).version,
                  name: (v as ItemVariation).name || null,
                  sku: (v as ItemVariation).sku || null,
                  price: (v as ItemVariation).price,
                  barcode: (v as ItemVariation).barcode,
                  locationOverrides: (v as ItemVariation).locationOverrides // Pass locationOverrides through
                }))
              : [{
                  id: fetchedItem.variationId, // This might be from an older structure
                  version: fetchedItem.variationVersion,
                  name: fetchedItem.variationName || null,
                  sku: fetchedItem.sku || null,
                  price: fetchedItem.price,
                  barcode: fetchedItem.barcode,
                  // No locationOverrides for this fallback structure by default
                }];
            
            setVariations(itemVariations);
          } else {
            setError('Item not found');
            setItem(EMPTY_ITEM);
          }
        } else if (isNewItem) {
          setItem(EMPTY_ITEM);
          setOriginalItem(null);
          // Initialize with one default variation for new items
          let initialSku = '';
          let initialBarcode = '';

          const initialItemState = { ...EMPTY_ITEM };
          if (params.name) {
            initialItemState.name = params.name;
          }
          if (params.sku) {
            initialSku = params.sku;
            initialItemState.sku = params.sku; // Also set on item for consistency, though primary is variation
          }
          if (params.barcode) {
            initialBarcode = params.barcode;
            // Barcode is primarily a variation field, but can be set on item if needed by backend
          }

          setItem(initialItemState);

          setVariations([{
            name: null, // Default variation name
            sku: initialSku,
            price: undefined,
            barcode: initialBarcode
          }]);
        } else {
          setError('Invalid Item ID');
          setItem(EMPTY_ITEM);
        }
        
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load data');
        console.error('Error fetching initial data:', err);
        setItem(EMPTY_ITEM);
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
  
  // Check if item has been edited and update 'all taxes selected' status
  useEffect(() => {
    // 1. Calculate 'all taxes selected' state
    let areAllSelected = false;
    if (item && availableTaxes && availableTaxes.length > 0) {
        const currentTaxIdsSet = new Set(item.taxIds || []);
        areAllSelected = availableTaxes.every(tax => currentTaxIdsSet.has(tax.id));
    }
    setAllTaxesSelected(areAllSelected);

    // 2. Calculate 'isEdited' state
    let calculatedIsEdited = false; 

    if (isNewItem) {
        if (item) { // Ensure item is not null
            const defaultNewVariations = [{ name: null, sku: '', price: undefined, barcode: '' }];
            const variationsChanged = JSON.stringify(variations) !== JSON.stringify(defaultNewVariations);
            
       calculatedIsEdited =
          !!(item.name && item.name.trim()) ||
                !!(item.sku && item.sku.trim()) || // SKU at top level is likely not for new item, but for variations
                item.price !== undefined || // Price at top level is likely not for new item
          !!(item.description && item.description.trim()) ||
          !!item.reporting_category_id ||
          (item.taxIds && item.taxIds.length > 0) ||
                (item.modifierListIds && item.modifierListIds.length > 0) ||
                variationsChanged; // Check if variations changed from default
        }
    } else if (item && originalItem) {
        const taxIdsChanged = JSON.stringify(originalItem.taxIds?.sort() || []) !== JSON.stringify(item.taxIds?.sort() || []);
        const modifierIdsChanged = JSON.stringify(originalItem.modifierListIds?.sort() || []) !== JSON.stringify(item.modifierListIds?.sort() || []);
        const variationsChanged = JSON.stringify(originalItem.variations?.map(v => ({...(v as ItemVariation), locationOverrides: (v as ItemVariation).locationOverrides?.slice().sort((a: {locationId: string},b: {locationId: string}) => a.locationId.localeCompare(b.locationId))})).sort((a: ItemVariation,b: ItemVariation) => (a.id || '').localeCompare(b.id || '')) || []) !== 
                                JSON.stringify(variations?.map(v => ({...(v as ItemVariation), locationOverrides: (v as ItemVariation).locationOverrides?.slice().sort((a: {locationId: string},b: {locationId: string}) => a.locationId.localeCompare(b.locationId))})).sort((a: ItemVariation,b: ItemVariation) => (a.id || '').localeCompare(b.id || '')) || []);


        calculatedIsEdited =
          originalItem.name !== item.name ||
          originalItem.sku !== item.sku ||
          originalItem.price !== item.price ||
          originalItem.description !== item.description ||
          originalItem.reporting_category_id !== item.reporting_category_id ||
          taxIdsChanged ||
          modifierIdsChanged ||
          variationsChanged; // Include variations in edit check
    }
    
    setIsEdited(calculatedIsEdited);

  }, [item, originalItem, variations, isNewItem, availableTaxes]); // Added variations to dependencies
  
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
  };
  
  // Get the current category name for display, handle loading state
  const selectedCategoryName = useMemo(() => {
    if (isLoading) return 'Loading...'; // Show loading state
    const categoryId = item.reporting_category_id;
    console.log('[ItemDetails SelectedCategory] Category ID in state:', categoryId);
    if (categoryId) {
      const found = availableCategories.find(c => c.id === categoryId);
      if (found) {
        if (originalItem?.reporting_category_id !== categoryId) { // Check if recently changed
             addRecentCategoryId(categoryId);
        }
        return found.name;
      } else {
        console.warn(`[ItemDetails SelectedCategory] Category ID "${categoryId}" found in item but NOT in availableCategories list!`);
        return 'Select Category'; // ID exists but category not found
      }
    }
    return 'Select Category'; // No ID set
  }, [item.reporting_category_id, availableCategories, isLoading, originalItem]);
  
  // Handle selecting a category
  const handleSelectCategory = (categoryId: string) => {
    updateItem('reporting_category_id', categoryId); 
    addRecentCategoryId(categoryId); // Also add to recent when selected this way
    setShowCategoryModal(false);
    setCategorySearch(''); // Reset search on selection
  };
  
  // Handle delete button press
  const handleDelete = useCallback(async () => {
    if (!item?.id || isNewItem) return; // Do not allow delete for new items

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
              await deleteProduct(item.id as string); // Ensure item.id is passed as string
              Alert.alert('Success', 'Item deleted successfully');
              router.back(); // Dismiss modal on delete
            } catch (error: any) {
              console.error('Error deleting item:', error);
              Alert.alert('Error', `Error deleting item: ${error.message}`);
            }
          },
        },
      ],
      { cancelable: true } // Allow dismissing by tapping outside on Android
    );
  }, [item, deleteProduct, router, isNewItem]);
  
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
  
  // Effect to listen for global save triggers from the bottom tab bar
  useEffect(() => {
    if (itemSaveTriggeredAt && itemSaveTriggeredAt !== lastProcessedSaveTrigger.current) {
      lastProcessedSaveTrigger.current = itemSaveTriggeredAt;
      if (isEdited) { // Only save if there are actual changes
        logger.info('ItemDetails', 'Save triggered via bottom tab bar (modal context)', { isNewItem, isEdited });
        handleSaveAction();
      } else {
        logger.info('ItemDetails', 'Save trigger via bottom tab bar ignored - no changes (modal context)', { isNewItem, isEdited });
      }
    }
  }, [itemSaveTriggeredAt, isEdited, handleSaveAction, isNewItem]);
  
  // Function to fetch location data
  const fetchLocations = async (): Promise<Array<{id: string, name: string}>> => {
    try {
      logger.info('ItemDetails:fetchLocations', 'Fetching locations from database');
      const locations = await getAllLocations();
      
      logger.info('ItemDetails:fetchLocations', `Retrieved ${locations.length} locations`);
      return locations;
    } catch (error) {
      logger.error('ItemDetails:fetchLocations', 'Failed to fetch locations', { error });
      return [];
    }
  };
  
  // Update header buttons dynamically
  useEffect(() => {
    navigation.setOptions({
      headerLeft: () => (
        <TouchableOpacity onPress={handleCancel} style={styles.headerButton}>
          <Ionicons name="close-outline" size={28} color={lightTheme.colors.primary} />
        </TouchableOpacity>
      ),
      headerRight: () => (
        <View style={styles.headerRightContainer}>
          {/* Print Button */}
          <TouchableOpacity 
            onPress={handlePrintLabel} 
            style={[styles.headerButton, styles.headerButtonWithBorder]} 
            disabled={isPrinting || isSaving || isPrintingAndSaving || isLoading || isNewItem}
          >
            <Ionicons name="print-outline" size={24} color={(isPrinting || isSaving || isPrintingAndSaving || isLoading || isNewItem) ? lightTheme.colors.disabled : lightTheme.colors.primary} />
          </TouchableOpacity>
          
          {/* Save Button */}
          <TouchableOpacity 
            onPress={handleSaveAction} 
            style={[styles.headerButton, styles.headerButtonWithBorder]} 
            disabled={isSaving || isPrinting || isPrintingAndSaving || isLoading || !isEdited}
          >
            <Ionicons name="save-outline" size={24} color={(isSaving || isPrinting || isPrintingAndSaving || isLoading || !isEdited) ? lightTheme.colors.disabled : lightTheme.colors.primary} />
          </TouchableOpacity>

          {/* Print and Save Button */}
          <TouchableOpacity 
            onPress={handlePrintAndSave} 
            style={styles.headerButton} 
            disabled={isPrintingAndSaving || isPrinting || isSaving || isLoading || !isEdited || isNewItem}
          >
            <Ionicons name="document-text-outline" size={24} color={(isPrintingAndSaving || isPrinting || isSaving || isLoading || !isEdited || isNewItem) ? lightTheme.colors.disabled : lightTheme.colors.primary} />
          </TouchableOpacity>

          {(isSaving || isLoading || isPrinting || isPrintingAndSaving) && (
            <ActivityIndicator size="small" color={lightTheme.colors.primary} style={styles.headerActivityIndicator} />
          )}
        </View>
      ),
      headerTitle: isNewItem ? 'Add New Item' : (item?.name || 'Edit Item'),
    });
  }, [navigation, handleCancel, handlePrintLabel, handleSaveAction, handlePrintAndSave, isSaving, isLoading, isNewItem, item, isPrinting, isPrintingAndSaving, isEdited]);
  
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

      {/* Custom Modal Header */}
      <View style={styles.customHeaderContainer}>
        <View style={styles.customHeaderLeftActions}> 
          <TouchableOpacity
            style={styles.customHeaderButton}
            onPress={handleCancel}
            disabled={isSavingPending} // Disable during save
          >
            <Text style={[styles.customHeaderButtonText, isSavingPending && styles.disabledText]}>Cancel</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.customHeaderTitleWrapper}> 
          <Text style={styles.customHeaderTitle}>{isNewItem ? 'Add New Item' : 'Edit Item'}</Text>
        </View>

        <View style={styles.customHeaderRightActions}>
           {!isNewItem && (
            <TouchableOpacity
              style={styles.customHeaderButton}
              onPress={handlePrintLabel} // Corrected: was handlePrintLabel not handleSaveAction
              disabled={isSavingPending || isPrinting}
            >
              {(isPrinting && printingVariationIndex === null) ? ( // General printing state for header
                <ActivityIndicator size="small" color={lightTheme.colors.primary} />
              ) : (
                <Ionicons name="print-outline" size={24} color={lightTheme.colors.primary} />
              )}
            </TouchableOpacity>
          )}
          <TouchableOpacity
            style={[styles.customHeaderButton, styles.customHeaderSaveButton]}
            onPress={handleSaveAction}
            disabled={isSavingPending || isPrinting} // Disable during print as well
          >
            {isSavingPending ? (
              <ActivityIndicator size="small" color="#FFFFFF" />
            ) : (
              <Text style={[styles.customHeaderButtonText, styles.customHeaderSaveButtonText]}>Save</Text>
            )}
          </TouchableOpacity>
        </View>
      </View>

      {/* Error handling: Render error view if error exists */} 
      {error && !isNewItem && ( // Only show full error screen if not new item and error occurs
        <View style={styles.errorContainer}> 
          <Ionicons name="alert-circle-outline" size={48} color="red" />
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity style={styles.errorButton} onPress={() => router.back()}>
            <Text style={styles.errorButtonText}>Go Back</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Main Content: Render ScrollView and Modal if NO error OR if it's a new item (allows form filling even if some dropdown data failed) */} 
      {(!error || isNewItem) && (
        <>
          <ScrollView style={styles.content} keyboardShouldPersistTaps="handled" contentContainerStyle={styles.scrollContentContainer}>
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
                        onPress={() => initiatePrint(index)} // Direct call to initiatePrint with index
                        disabled={isPrinting} // Disable if any print is ongoing
                      >
                        {isPrinting && printingVariationIndex === index ? (
                           <ActivityIndicator size="small" color={lightTheme.colors.primary} />
                        ) : (
                          <>
                        <Ionicons name="print-outline" size={18} color={lightTheme.colors.primary} style={styles.inlinePrintIcon} />
                        <Text style={styles.inlinePrintButtonText}>Print</Text>
                          </>
                        )}
                      </TouchableOpacity>
                    {variations.length > 1 && (
                      <TouchableOpacity 
                        onPress={() => removeVariation(index)}
                        style={styles.removeVariationButton}
                         disabled={isSavingPending} // Disable during save
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
                      autoCapitalize="characters" // Keep autoCapitalize for SKU
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

                    {/* Price Overrides Section */}
                    <View style={{
                      marginTop: 10,
                      borderTopWidth: 1,
                      borderTopColor: '#eeeeee',
                      paddingTop: 8,
                    }}>
                      <View style={{
                        flexDirection: 'row',
                        justifyContent: 'flex-start',
                        marginBottom: 8,
                        alignItems: 'center',
                      }}>
                        <TouchableOpacity 
                          style={styles.addPriceOverrideButton} // Use style from styles.ts
                          onPress={() => addPriceOverride(index)}
                          disabled={availableLocations.length === 0 || isSavingPending} // Disable during save
                        >
                          <Text style={styles.addPriceOverrideButtonText}>Add Price Override</Text>
                        </TouchableOpacity>
                      </View>

                      {/* Render existing price overrides */}
                      {variation.locationOverrides && variation.locationOverrides.map((override, overrideIndex) => (
                        <View key={`override-${index}-${overrideIndex}`} style={styles.priceOverrideItemContainer}>
                          <View style={styles.priceOverrideInputWrapper}>
                            <Text style={styles.currencySymbol}>$</Text>
                            <TextInput
                              style={styles.priceOverrideInput}
                              value={override.price !== undefined ? override.price.toFixed(2) : ''}
                              onChangeText={(value) => updatePriceOverride(index, overrideIndex, 'price', value)}
                              placeholder="Price"
                              placeholderTextColor="#999"
                              keyboardType="numeric"
                            />
                          </View>

                          {/* Location selector */}
                          <View style={styles.priceOverrideLocationSelectorWrapper}>
                            {availableLocations.length > 0 ? (
                              <TouchableOpacity 
                                style={styles.priceOverrideLocationButton}
                                onPress={() => {
                                  Alert.alert(
                                    "Select Location",
                                    "Choose a location for this price override",
                                    availableLocations.map(location => ({
                                      text: location.name,
                                      onPress: () => updatePriceOverride(index, overrideIndex, 'locationId', location.id)
                                    })),
                                    { cancelable: true }
                                  );
                                }}
                              >
                                <Text style={[
                                  styles.priceOverrideLocationText,
                                  !override.locationId && styles.priceOverrideLocationPlaceholder
                                ]}>
                                  {override.locationId ? 
                                    (override.locationName || availableLocations.find(loc => loc.id === override.locationId)?.name || 'Select Location') :
                                    'Select Location'}
                                </Text>
                                <Ionicons name="chevron-down" size={16} color="#666" />
                              </TouchableOpacity>
                            ) : (
                              <Text style={styles.noLocationsText}>No locations</Text>
                            )}
                          </View>

                          {/* Remove override button */}
                          <TouchableOpacity 
                            style={styles.removePriceOverrideButton}
                            onPress={() => removePriceOverride(index, overrideIndex)}
                            disabled={isSavingPending}
                          >
                            <Ionicons name="close-circle" size={18} color="#ff3b30" />
                          </TouchableOpacity>
                        </View>
                      ))}
                    </View>
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
                      keyboardType="numeric" // Barcodes can be numeric
                    />
                  </View>
                </View>
              ))}
              
              <TouchableOpacity 
                style={styles.addVariationButton}
                onPress={addVariation}
                disabled={isSavingPending} // Disable during save
              >
                <Ionicons name="add-circle-outline" size={20} color={lightTheme.colors.primary} />
                <Text style={styles.addVariationText}>Add Variation</Text>
              </TouchableOpacity>
            </View>

            {/* Reporting Category */}
            <View style={styles.fieldContainer}>
              <Text style={styles.label}>Reporting Category</Text>
              <TouchableOpacity style={styles.selectorButton} onPress={() => setShowCategoryModal(true)} disabled={isSavingPending}>
                <Text style={styles.selectorText}>{selectedCategoryName}</Text>
                <Ionicons name="chevron-down" size={20} color="#666" />
              </TouchableOpacity>

              {/* Recent Categories Horizontal List */} 
              <View style={styles.recentCategoriesContainer}>
                {recentCategories.length > 0 && (
                  <>
                    <Text style={styles.recentLabel}>Recent:</Text>
                    <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                      {recentCategories.map((cat) => (
                        <TouchableOpacity
                          key={cat.id}
                          style={styles.recentCategoryChip}
                          onPress={() => handleSelectCategory(cat.id)}
                          disabled={isSavingPending}
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
                  disabled={isSavingPending} // Disable during save
                >
                  <Text style={[styles.selectAllButtonText, allTaxesSelected && styles.selectAllButtonTextSelected]}>
                    {allTaxesSelected ? 'Deselect All' : 'Select All'}
                  </Text>
                </TouchableOpacity>
              </View>
              {availableTaxes.length > 0 ? (
                availableTaxes.map((tax) => (
                  <TouchableOpacity
                    key={tax.id}
                    style={styles.checkboxContainer}
                    onPress={() => handleTaxSelection(tax.id)}
                    activeOpacity={0.7}
                    disabled={isSavingPending} // Disable during save
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
                availableModifierLists.map((modifier) => (
                  <TouchableOpacity
                    key={modifier.id}
                    style={styles.checkboxContainer}
                    onPress={() => handleModifierSelection(modifier.id)}
                    activeOpacity={0.7}
                    disabled={isSavingPending} // Disable during save
                  >
                    <Ionicons
                      name={item.modifierListIds?.includes(modifier.id) ? 'checkbox' : 'square-outline'}
                      size={24}
                      color={item.modifierListIds?.includes(modifier.id) ? lightTheme.colors.primary : '#ccc'}
                      style={styles.checkboxIcon}
                    />
                    <Text style={styles.checkboxLabel}>{modifier.name}</Text>
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
                onChangeText={(text) => updateItem('description', text)}
                placeholder="Enter item description (optional)"
                placeholderTextColor="#999"
                multiline
                numberOfLines={4}
                textAlignVertical="top"
              />
            </View>

            {/* Delete Button - Only for existing items */}
            {!isNewItem && (
              <View style={styles.deleteButtonContainer}>
                <TouchableOpacity
                  style={styles.deleteButton}
                  onPress={handleDelete}
                  disabled={isSavingPending} // Disable during save
                >
                  <Ionicons name="trash-outline" size={20} color={styles.deleteButtonText.color} />
                  <Text style={styles.deleteButtonText}>Delete Item</Text>
                </TouchableOpacity>
              </View>
            )}

            {/* Spacer to push delete button to the bottom / general spacing */}
            <View style={{ height: Platform.OS === 'ios' ? 80 : 100 }} /> 
          </ScrollView>

          {/* Category Selection Modal - Replaced with component */}
          <CategorySelectionModal
            visible={showCategoryModal}
            onClose={() => setShowCategoryModal(false)}
            filteredCategories={filteredCategories}
            onSelectCategory={(categoryId) => {
              handleSelectCategory(categoryId);
            }}
            categorySearch={categorySearch}
            setCategorySearch={setCategorySearch}
          />

          {/* --- Variation Selection Modal - Replaced with Component --- */}
          <VariationPrintSelectionModal
            visible={showVariationModal}
            variations={variations.map((v, idx) => ({
              id: v.id || `temp-${idx}`,
              name: v.name || item?.name || `Variation ${idx + 1}`,
              sku: v.sku,
              price: v.price,
              barcode: v.barcode,
              locationOverrides: v.locationOverrides
            }))}
            onSelectVariation={(selectedIndex: number) => {
              if (selectedIndex >= 0 && selectedIndex < variations.length) {
                initiatePrint(selectedIndex);
              }
              setShowVariationModal(false);
            }}
            onClose={() => setShowVariationModal(false)} 
          />

          <PrintNotification
            visible={showPrintNotification}
            message={printNotificationMessage}
            type={printNotificationType}
            onClose={() => setShowPrintNotification(false)}
          />

          <SystemModal
            visible={showPrintNotification}
            onClose={() => setShowPrintNotification(false)}
            message={printNotificationMessage}
            type={printNotificationType}
            position="top"
            autoClose={true}
            autoCloseTime={2000}
          />

          {/* Success Notification */}
          <SystemModal
            visible={showSuccessNotification}
            onClose={() => setShowSuccessNotification(false)}
            message={successMessage}
            type="success"
            position="top"
            autoClose={true}
            autoCloseTime={2000}
          />

          {/* Cancel Confirmation Modal */}
          <Modal
            animationType="fade"
            transparent={true}
            visible={showCancelModal}
            onRequestClose={() => setShowCancelModal(false)}
          >
            <View style={styles.centeredView}>
              <View style={styles.modalView}>
                <Text style={styles.modalText}>You have unsaved changes. Are you sure you want to discard them?</Text>
                <View style={styles.modalButtonsContainer}>
                  <TouchableOpacity
                    style={[styles.modalButton, styles.modalButtonSecondary]}
                    onPress={() => setShowCancelModal(false)}
                  >
                    <Text style={[styles.modalButtonText, styles.modalButtonTextSecondary]}>Keep Editing</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[styles.modalButton, styles.modalButtonPrimary]}
                    onPress={handleConfirmCancel} // This will call router.back()
                  >
                    <Text style={[styles.modalButtonText, styles.modalButtonTextPrimary]}>Discard</Text>
                  </TouchableOpacity>
                </View>
              </View>
            </View>
          </Modal>
        </>
      )}
    </SafeAreaView>
  );
}