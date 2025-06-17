import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  StyleSheet,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  SafeAreaView,
  Image,
  Modal,
  Alert,
  ScrollView,
  Animated,
  RefreshControl,
  Vibration,
  Keyboard
} from 'react-native';
import { Stack, useRouter, useFocusEffect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import Swipeable from 'react-native-gesture-handler/Swipeable';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { BarcodeScanner, BarcodeScannerRef } from '../../src/components/BarcodeScanner';
import * as modernDb from '../../src/database/modernDb';
import { ConvertedItem } from '../../src/types/api';
import { lightTheme } from '../../src/themes';
import logger from '../../src/utils/logger';
import { styles } from '../../src/styles/_indexStyles'; // Use styles from index
import { reorderStyles } from '../../src/styles/_reorderStyles';
import { reorderService, ReorderItem as ServiceReorderItem } from '../../src/services/reorderService';
import { generateClient } from 'aws-amplify/api';
import * as queries from '../../src/graphql/queries';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useAppStore } from '../../src/store';

const client = generateClient();

// Types for reorder functionality - use the service type
type ReorderItem = ServiceReorderItem & {
  isCustom?: boolean;
  notes?: string;
};

// Add interface for custom item being edited
interface CustomItemEdit {
  id: string;
  itemName: string;
  itemCategory: string;
  vendor: string;
  quantity: number;
  notes: string;
}

interface QuantityModalProps {
  visible: boolean;
  item: ReorderItem | null;
  onSubmit: (quantity: number) => void;
  onCancel: () => void;
}

interface ItemSelectionModalProps {
  visible: boolean;
  items: ConvertedItem[];
  onSelect: (item: ConvertedItem) => void;
  onCancel: () => void;
}

type FilterType = 'completed' | 'incomplete' | 'category' | 'vendor' | 'sortConfig';

const TAG = '[ReordersScreen]';

// Quantity Modal Component - now for manual editing only
const QuantityModal: React.FC<QuantityModalProps & { quantity: string; setQuantity: (qty: string) => void }> = ({ 
  visible, 
  item, 
  onSubmit, 
  onCancel, 
  quantity, 
  setQuantity 
}) => {
  const [isFirstInput, setIsFirstInput] = useState(true);

  // Reset quantity when modal opens with current item quantity
  useEffect(() => {
    if (visible && item) {
      setQuantity(item.quantity.toString());
      setIsFirstInput(true); // Mark that the next input should overwrite
    }
  }, [visible, item, setQuantity]);

  const handleKeypadPress = (value: string) => {
    if (value === 'backspace') {
      setQuantity(quantity.length > 1 ? quantity.slice(0, -1) : '1');
      setIsFirstInput(false);
    } else if (value === 'reset') {
      setQuantity('1');
      setIsFirstInput(false);
    } else {
      // First digit after opening modal overwrites existing value, subsequent digits append
      const newValue = isFirstInput ? value : quantity + value;
      setQuantity(parseInt(newValue) > 999 ? quantity : newValue);
      setIsFirstInput(false);
    }
  };

  const handleSubmit = () => {
    const qty = parseInt(quantity);
    // Allow 0 for deletion, but default to 1 for invalid input
    const finalQty = isNaN(qty) ? 1 : qty;
    onSubmit(finalQty);
  };

  const keypadButtons = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['reset', '0', 'backspace']
  ];

  return (
    <Modal visible={visible} transparent animationType="none">
      <View style={reorderStyles.modalOverlay}>
        <View style={reorderStyles.modalContainer}>
          <View style={reorderStyles.modalHeader}>
            <Text style={reorderStyles.modalTitle}>Edit Quantity</Text>
            <Text style={reorderStyles.modalItemName} numberOfLines={2}>
              {item?.itemName || 'Unknown Item'}
            </Text>
          </View>

          <View style={reorderStyles.quantityContainer}>
            <Text style={reorderStyles.quantityDisplay}>{quantity}</Text>
            
            <View style={reorderStyles.keypadContainer}>
              {keypadButtons.map((row, rowIndex) => (
                <View key={rowIndex} style={reorderStyles.keypadRow}>
                  {row.map((button) => (
                    <TouchableOpacity
                      key={button}
                      style={[
                        reorderStyles.keypadButton,
                        (button === 'reset' || button === 'backspace') && reorderStyles.keypadButtonSpecial
                      ]}
                      onPress={() => handleKeypadPress(button)}
                    >
                      {button === 'backspace' ? (
                        <Ionicons name="backspace-outline" size={20} color="#fff" />
                      ) : button === 'reset' ? (
                        <Text style={reorderStyles.keypadButtonSpecialText}>Reset</Text>
                      ) : (
                        <Text style={reorderStyles.keypadButtonText}>{button}</Text>
                      )}
                    </TouchableOpacity>
                  ))}
                </View>
              ))}
            </View>
          </View>

          <View style={reorderStyles.modalActions}>
            <TouchableOpacity
              style={[reorderStyles.modalButton, reorderStyles.modalButtonSecondary]}
              onPress={onCancel}
            >
              <Text style={[reorderStyles.modalButtonText, reorderStyles.modalButtonTextSecondary]}>
                Cancel
              </Text>
            </TouchableOpacity>
            
            <TouchableOpacity
              style={[reorderStyles.modalButton, reorderStyles.modalButtonPrimary]}
              onPress={handleSubmit}
            >
              <Text style={[reorderStyles.modalButtonText, reorderStyles.modalButtonTextPrimary]}>
                Submit
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
};

// Item Selection Modal Component
const ItemSelectionModal: React.FC<ItemSelectionModalProps> = ({ visible, items, onSelect, onCancel }) => {
  return (
    <Modal visible={visible} transparent animationType="none">
      <View style={reorderStyles.modalOverlay}>
        <View style={reorderStyles.modalContainer}>
          <View style={reorderStyles.modalHeader}>
            <Text style={reorderStyles.modalTitle}>Multiple Items Found</Text>
            <Text style={reorderStyles.modalItemName}>
              Select the item you want to reorder:
            </Text>
          </View>

          <ScrollView style={reorderStyles.selectionList}>
            {items.map((item, index) => (
              <TouchableOpacity
                key={item.id}
                style={[
                  reorderStyles.selectionItem,
                  index === items.length - 1 && reorderStyles.selectionItemLast
                ]}
                onPress={() => onSelect(item)}
              >
                <Text style={reorderStyles.selectionItemName}>{item.name}</Text>
                <Text style={reorderStyles.selectionItemDetails}>
                  {item.category} • ${item.price} • {item.barcode}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>

          <View style={reorderStyles.modalActions}>
            <TouchableOpacity
              style={[reorderStyles.modalButton, reorderStyles.modalButtonSecondary]}
              onPress={onCancel}
            >
              <Text style={[reorderStyles.modalButtonText, reorderStyles.modalButtonTextSecondary]}>
                Cancel
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
};

// Render dropdown for category/vendor filters
const renderDropdown = (
  items: Array<{ name: string; count: number }>,
  selectedValue: string | null,
  onSelect: (value: string | null) => void,
  placeholder: string
) => {
  return (
    <ScrollView style={{ maxHeight: 180 }} showsVerticalScrollIndicator={false}>
      <TouchableOpacity
        style={{
          paddingHorizontal: 20,
          paddingVertical: 14,
          borderBottomWidth: 1,
          borderBottomColor: '#f0f0f0',
          backgroundColor: !selectedValue ? '#f0f8ff' : 'transparent',
        }}
        onPress={() => onSelect(null)}
      >
        <Text style={{
          fontSize: 15,
          color: !selectedValue ? '#007AFF' : '#333',
          fontWeight: !selectedValue ? '600' : '400',
        }}>
          All {placeholder}
        </Text>
      </TouchableOpacity>
      {items.length === 0 ? (
        <View style={{
          paddingHorizontal: 20,
          paddingVertical: 20,
          alignItems: 'center',
        }}>
          <Text style={{
            fontSize: 14,
            color: '#999',
            fontStyle: 'italic',
          }}>
            No {placeholder.toLowerCase()} available
          </Text>
        </View>
      ) : (
        items.map((item, index) => (
          <TouchableOpacity
            key={`${item.name}-${index}`}
            style={{
              paddingHorizontal: 20,
              paddingVertical: 14,
              borderBottomWidth: index === items.length - 1 ? 0 : 1,
              borderBottomColor: '#f0f0f0',
              backgroundColor: selectedValue === item.name ? '#f0f8ff' : 'transparent',
              flexDirection: 'row',
              justifyContent: 'space-between',
              alignItems: 'center',
            }}
            onPress={() => onSelect(item.name)}
          >
            <Text style={{
              fontSize: 15,
              color: selectedValue === item.name ? '#007AFF' : '#333',
              fontWeight: selectedValue === item.name ? '600' : '400',
              flex: 1,
            }}>
              {item.name}
            </Text>
            <View style={{
              backgroundColor: selectedValue === item.name ? '#007AFF' : '#e0e0e0',
              paddingHorizontal: 8,
              paddingVertical: 4,
              borderRadius: 12,
              minWidth: 24,
              alignItems: 'center',
            }}>
              <Text style={{
                fontSize: 12,
                color: selectedValue === item.name ? '#fff' : '#666',
                fontWeight: '600',
              }}>
                {item.count}
              </Text>
            </View>
          </TouchableOpacity>
        ))
      )}
    </ScrollView>
  );
};

export default function ReordersScreen() {
  const router = useRouter();
  const { products: catalogItems, isProductsLoading: loading } = useCatalogItems();
  
  // State management
  const [reorderItems, setReorderItems] = useState<ReorderItem[]>([]);
  const [currentFilter, setCurrentFilter] = useState<FilterType | null>(null);
  const [showQuantityModal, setShowQuantityModal] = useState(false);
  const [showSelectionModal, setShowSelectionModal] = useState(false);
  const [currentEditingItem, setCurrentEditingItem] = useState<ReorderItem | null>(null);
  const [multipleItems, setMultipleItems] = useState<ConvertedItem[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showErrorModal, setShowErrorModal] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  
  // Quantity modal state - for manual editing only
  const [modalQuantity, setModalQuantity] = useState('1');
  
  // Custom item states
  const [showAddCustomItem, setShowAddCustomItem] = useState(false);
  const [editingCustomItem, setEditingCustomItem] = useState<string | null>(null);
  const [customItemEdit, setCustomItemEdit] = useState<CustomItemEdit | null>(null);
  
  // Sync status state
  const [syncStatus, setSyncStatus] = useState({ isOnline: false, pendingCount: 0, isAuthenticated: false });
  const [showSyncStatusPopover, setShowSyncStatusPopover] = useState(false);
  
  // State for filters and sorting
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [selectedVendor, setSelectedVendor] = useState<string | null>(null);
  const [showCategoryDropdown, setShowCategoryDropdown] = useState(false);
  const [showVendorDropdown, setShowVendorDropdown] = useState(false);
  const [showConfigDropdown, setShowConfigDropdown] = useState(false);
  const [sectionByCategory, setSectionByCategory] = useState(false);
  const [sectionByVendor, setSectionByVendor] = useState(false);
  const [sortState, setSortState] = useState<{
    chronological: 'off' | 'desc' | 'asc';
    alphabetical: 'off' | 'desc' | 'asc';
  }>({
    chronological: 'off',
    alphabetical: 'off'
  });

  // Get authenticated user information
  const { user } = useAuthenticator((context) => [context.user]);

  // Listen for add custom item trigger from tab bar
  const addCustomItemTriggeredAt = useAppStore((state) => state.addCustomItemTriggeredAt);
  const setCategories = useAppStore((state) => state.setCategories);
  const lastTriggeredAtRef = useRef<number | null>(null);

  // Load categories from local database into store so useCatalogItems can use them
  useEffect(() => {
    const loadCategories = async () => {
      try {
        const categoriesFromDb = await modernDb.getAllCategories();
        const formattedCategories = categoriesFromDb.map(cat => ({
          id: cat.id,
          name: cat.name,
          color: '#007AFF',
          isActive: true,
          createdAt: '',
          updatedAt: ''
        }));
        setCategories(formattedCategories);
        logger.info(TAG, `Loaded ${categoriesFromDb.length} categories into store for category name resolution`);
      } catch (error) {
        logger.error(TAG, 'Failed to load categories', { error });
      }
    };
    loadCategories();
  }, [setCategories]);
  
  useEffect(() => {
    if (addCustomItemTriggeredAt && addCustomItemTriggeredAt !== lastTriggeredAtRef.current) {
      lastTriggeredAtRef.current = addCustomItemTriggeredAt;
      handleAddCustomItem();
    }
  }, [addCustomItemTriggeredAt]);

  const { performSearch, isSearching, searchError } = useCatalogItems();

  // Scanner ref no longer needed for fluid scanning
  
  // Audio/Haptic feedback for scan results
  const playSuccessSound = useCallback(() => {
    console.log('🔊 SUCCESS - Item found!');
    logger.info(TAG, 'Playing success feedback');
    // Single short vibration for success
    Vibration.vibrate(100);
  }, []);

  const playErrorSound = useCallback(() => {
    console.log('🔊 ERROR - Scan failed!');  
    logger.info(TAG, 'Playing error feedback');
    // Double vibration pattern for error
    Vibration.vibrate([0, 200, 100, 200]);
  }, []);

  // Handle barcode scan - new fluid scanning logic
  const handleBarcodeScan = useCallback(async (barcode: string) => {
    logger.info(TAG, `🔍 FLUID SCAN: "${barcode}"`);
    
    // If error modal is open, dismiss it with any new scan
    if (showErrorModal) {
      setShowErrorModal(false);
      setErrorMessage('');
    }
    
    // Search for items with matching barcode
    try {
      const searchFilters = {
        name: false,
        sku: false,
        barcode: true, // Only search by barcode
        category: false
      };
      
      const matchingItems = await performSearch(barcode, searchFilters);

      if (matchingItems.length === 0) {
        // ERROR CASE: No item found in database - play error sound & show modal
        playErrorSound();
        setErrorMessage(`No item found with barcode: ${barcode}\n\nPlease create the item in the main scan page first.`);
        setShowErrorModal(true);
        return;
      }

      if (matchingItems.length === 1) {
        // Single item found - implement additive scanning logic
        const foundItem = matchingItems[0];
        
        // Convert SearchResultItem to ConvertedItem
        const convertedItem: ConvertedItem = {
          id: foundItem.id,
          name: foundItem.name || '',
          sku: foundItem.sku,
          barcode: foundItem.barcode,
          price: foundItem.price,
          category: foundItem.category,
          categoryId: foundItem.categoryId,
          reporting_category_id: foundItem.categoryId || foundItem.reporting_category_id,
          description: foundItem.description,
          isActive: true,
          images: [],
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        };
        
        // Check if item already exists in reorder list
        const existingItem = reorderItems.find(item => item.itemId === convertedItem.id);
        
        if (existingItem) {
          // ADDITIVE SCANNING: Increment existing item quantity by 1
          logger.info(TAG, `📈 ADDITIVE SCAN: ${convertedItem.name} (${existingItem.quantity} → ${existingItem.quantity + 1})`);
          
          try {
            let teamData: any = undefined;
            try {
              teamData = await reorderService.fetchTeamData(convertedItem.id);
            } catch (teamDataError) {
              logger.warn(TAG, 'Failed to fetch team data, proceeding without it', { teamDataError });
            }
            
            const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
            const newQuantity = existingItem.quantity + 1;
            
            // Use overwrite mode with incremented quantity
            const success = await reorderService.addItem(convertedItem, newQuantity, teamData, userName, true);
            
            if (success) {
              playSuccessSound();
              logger.info(TAG, `✅ Incremented item: ${convertedItem.name} to qty ${newQuantity}`);
            } else {
              throw new Error('Failed to increment item');
            }
          } catch (error) {
            logger.error(TAG, 'Error incrementing item', { error });
            playErrorSound();
            setErrorMessage('Failed to increment item quantity. Please try again.');
            setShowErrorModal(true);
          }
        } else {
          // NEW ITEM: Add with default quantity of 1
          logger.info(TAG, `🆕 NEW ITEM SCAN: ${convertedItem.name} (qty: 1)`);
          
          try {
            let teamData: any = undefined;
            try {
              teamData = await reorderService.fetchTeamData(convertedItem.id);
            } catch (teamDataError) {
              logger.warn(TAG, 'Failed to fetch team data, proceeding without it', { teamDataError });
            }
            
            const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
            
            const success = await reorderService.addItem(convertedItem, 1, teamData, userName, true);
            
            if (success) {
              playSuccessSound();
              logger.info(TAG, `✅ Added new item: ${convertedItem.name} (qty: 1)`);
            } else {
              throw new Error('Failed to add new item');
            }
          } catch (error) {
            logger.error(TAG, 'Error adding new item', { error });
            playErrorSound();
            setErrorMessage('Failed to add item to reorder list. Please try again.');
            setShowErrorModal(true);
          }
        }
      } else {
        // Multiple items found - show selection modal
        const convertedItems: ConvertedItem[] = matchingItems.map(item => ({
          id: item.id,
          name: item.name || '',
          sku: item.sku,
          barcode: item.barcode,
          price: item.price,
          category: item.category,
          categoryId: item.categoryId,
          reporting_category_id: item.categoryId || item.reporting_category_id,
          description: item.description,
          isActive: true,
          images: [],
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        }));
        
        setMultipleItems(convertedItems);
        setShowSelectionModal(true);
      }
    } catch (error) {
      logger.error(TAG, 'Error searching for barcode', { barcode, error });
      playErrorSound();
      setErrorMessage(`Search failed for barcode: ${barcode}\n\nPlease try again.`);
      setShowErrorModal(true);
    }
  }, [performSearch, showErrorModal, playSuccessSound, playErrorSound, reorderItems, user]);

  // Handle scan errors (ERROR CASE 2: Invalid GTIN format - play error sound & show modal)
  const handleScanError = useCallback((error: string) => {
    logger.warn(TAG, `Scan error: ${error}`);
    playErrorSound();
    setErrorMessage(`Scan failed: ${error}`);
    setShowErrorModal(true);
  }, [playErrorSound]);

  // Handle manual quantity edit submission
  const handleQuantitySubmit = useCallback(async (quantity: number) => {
    if (!currentEditingItem) return;

    // Handle quantity 0 as deletion
    if (quantity === 0) {
      logger.info(TAG, `Quantity 0 specified - deleting item: ${currentEditingItem.itemName}`);
      
      try {
        await reorderService.removeItem(currentEditingItem.id);
        playSuccessSound();
        logger.info(TAG, `Deleted reorder item: ${currentEditingItem.itemName}`);
      } catch (error) {
        logger.error(TAG, 'Error deleting item', { error });
        playErrorSound();
        setErrorMessage('Failed to delete item from reorder list');
        setShowErrorModal(true);
      }
      
              setShowQuantityModal(false);
        setCurrentEditingItem(null);
        setModalQuantity('1');
      return;
    }

    try {
      // For manual editing, we need to convert the ReorderItem back to ConvertedItem format
      const convertedItem: ConvertedItem = {
        id: currentEditingItem.itemId,
        name: currentEditingItem.itemName,
        sku: '', // ReorderItem doesn't store SKU
        barcode: currentEditingItem.itemBarcode || '',
        price: currentEditingItem.itemPrice || 0,
        category: currentEditingItem.itemCategory || '',
        categoryId: '', // ReorderItem doesn't store categoryId
        reporting_category_id: '', // ReorderItem doesn't store reporting_category_id
        description: '', // ReorderItem doesn't store description
        isActive: true,
        images: [],
        createdAt: currentEditingItem.createdAt,
        updatedAt: currentEditingItem.updatedAt,
      };
      
      let teamData: any = currentEditingItem.teamData;
      if (!teamData) {
        try {
          teamData = await reorderService.fetchTeamData(currentEditingItem.itemId);
        } catch (teamDataError) {
          logger.warn(TAG, 'Failed to fetch team data, proceeding without it', { teamDataError });
        }
      }
      
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      
      const success = await reorderService.addItem(convertedItem, quantity, teamData, userName, true);
      
      if (success) {
        playSuccessSound();
        setShowQuantityModal(false);
        setCurrentEditingItem(null);
        logger.info(TAG, `Updated reorder item: ${currentEditingItem.itemName} to qty ${quantity}`);
        
        // Check sync status to inform user if saved locally
        const syncStatus = reorderService.getSyncStatus();
        if (!syncStatus.isAuthenticated || !syncStatus.isOnline) {
          logger.info(TAG, 'Item updated locally - will sync when connected');
        }
      } else {
        playErrorSound();
        setErrorMessage('Failed to update item quantity. Please try again.');
        setShowErrorModal(true);
      }
    } catch (error) {
      logger.error(TAG, 'Error updating reorder item', { error });
      playErrorSound();
      setErrorMessage('Failed to update item quantity. The change has been saved locally and will sync when you\'re connected.');
      setShowErrorModal(true);
      setShowQuantityModal(false);
      setCurrentEditingItem(null);
    }
      }, [currentEditingItem, user, playSuccessSound, playErrorSound]);

  // Handle item selection from multiple items - implement additive logic
  const handleItemSelection = useCallback(async (item: ConvertedItem) => {
    setShowSelectionModal(false);
    setMultipleItems([]);
    
    // Implement the same additive logic as single item scan
    const existingItem = reorderItems.find(reorderItem => reorderItem.itemId === item.id);
    
    if (existingItem) {
      // ADDITIVE SCANNING: Increment existing item quantity by 1
      logger.info(TAG, `📈 ADDITIVE SELECTION: ${item.name} (${existingItem.quantity} → ${existingItem.quantity + 1})`);
      
      try {
        let teamData: any = undefined;
        try {
          teamData = await reorderService.fetchTeamData(item.id);
        } catch (teamDataError) {
          logger.warn(TAG, 'Failed to fetch team data, proceeding without it', { teamDataError });
        }
        
        const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
        const newQuantity = existingItem.quantity + 1;
        
        const success = await reorderService.addItem(item, newQuantity, teamData, userName, true);
        
        if (success) {
          playSuccessSound();
          logger.info(TAG, `✅ Incremented selected item: ${item.name} to qty ${newQuantity}`);
        } else {
          throw new Error('Failed to increment selected item');
        }
      } catch (error) {
        logger.error(TAG, 'Error incrementing selected item', { error });
        playErrorSound();
        setErrorMessage('Failed to increment item quantity. Please try again.');
        setShowErrorModal(true);
      }
    } else {
      // NEW ITEM: Add with default quantity of 1
      logger.info(TAG, `🆕 NEW ITEM SELECTION: ${item.name} (qty: 1)`);
      
      try {
        let teamData: any = undefined;
        try {
          teamData = await reorderService.fetchTeamData(item.id);
        } catch (teamDataError) {
          logger.warn(TAG, 'Failed to fetch team data, proceeding without it', { teamDataError });
        }
        
        const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
        
        const success = await reorderService.addItem(item, 1, teamData, userName, true);
        
        if (success) {
          playSuccessSound();
          logger.info(TAG, `✅ Added selected item: ${item.name} (qty: 1)`);
        } else {
          throw new Error('Failed to add selected item');
        }
      } catch (error) {
        logger.error(TAG, 'Error adding selected item', { error });
        playErrorSound();
        setErrorMessage('Failed to add item to reorder list. Please try again.');
        setShowErrorModal(true);
      }
    }
  }, [reorderItems, user, playSuccessSound, playErrorSound]);

  // Handle item deletion
  const handleDeleteItem = async (itemId: string) => {
    try {
      await reorderService.removeItem(itemId);
    } catch (error) {
      console.error('Error deleting item:', error);
    }
  };

  // Handle manual refresh
  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      await reorderService.refresh();
      // Update sync status after refresh
      const status = reorderService.getSyncStatus();
      setSyncStatus(status);
      logger.info(TAG, 'Manual refresh completed');
    } catch (error) {
      logger.error(TAG, 'Manual refresh failed', { error });
    } finally {
      setIsRefreshing(false);
    }
  }, []);

  // Handle custom item creation
  const handleAddCustomItem = useCallback(() => {
    const newCustomItem: CustomItemEdit = {
      id: `custom-${Date.now()}`,
      itemName: '',
      itemCategory: '',
      vendor: '',
      quantity: 1,
      notes: ''
    };
    setCustomItemEdit(newCustomItem);
    setEditingCustomItem(newCustomItem.id);
    setShowAddCustomItem(true);
  }, []);

  // Handle custom item save
  const handleSaveCustomItem = useCallback(async () => {
    if (!customItemEdit || !customItemEdit.itemName.trim()) return;

    try {
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      
      const success = await reorderService.addCustomItem({
        itemName: customItemEdit.itemName.trim(),
        itemCategory: customItemEdit.itemCategory || 'Custom',
        quantity: customItemEdit.quantity,
        addedBy: userName,
        vendor: customItemEdit.vendor || undefined,
        notes: customItemEdit.notes || undefined
      });
      
      if (success) {
        // Reset states
        setShowAddCustomItem(false);
        setEditingCustomItem(null);
        setCustomItemEdit(null);
        
        logger.info(TAG, `Added custom item: ${customItemEdit.itemName}`);
      } else {
        Alert.alert('Error', 'Failed to add custom item');
      }
    } catch (error) {
      logger.error(TAG, 'Error adding custom item', { error });
      Alert.alert('Error', 'Failed to add custom item');
    }
  }, [customItemEdit, user]);

  // Handle custom item edit
  const handleEditCustomItem = useCallback((item: ReorderItem) => {
    if (!item.isCustom) return;
    
    const editItem: CustomItemEdit = {
      id: item.id,
      itemName: item.itemName,
      itemCategory: item.itemCategory || '',
      vendor: item.teamData?.vendor || '',
      quantity: item.quantity,
      notes: item.notes || ''
    };
    
    setCustomItemEdit(editItem);
    setEditingCustomItem(item.id);
  }, []);

  // Handle custom item cancel
  const handleCancelCustomItem = useCallback(() => {
    setShowAddCustomItem(false);
    setEditingCustomItem(null);
    setCustomItemEdit(null);
  }, []);

  // Monitor sync status
  useEffect(() => {
    const updateSyncStatus = () => {
      const status = reorderService.getSyncStatus();
      setSyncStatus(status);
    };
    
    // Update immediately
    updateSyncStatus();
    
    // Update every 5 seconds
    const interval = setInterval(updateSyncStatus, 5000);
    
    return () => clearInterval(interval);
  }, []);

  // Set up reorder service listener and cleanup
  useEffect(() => {
    const unsubscribe = reorderService.addListener(setReorderItems);
    
    return () => {
      unsubscribe();
      // Cleanup subscriptions when component unmounts
      reorderService.cleanup();
    };
  }, []);

  // Initialize service with user ID when user changes
  useEffect(() => {
    if (user?.signInDetails?.loginId) {
      const userId = user.signInDetails.loginId;
      reorderService.initialize(userId);
    }
  }, [user?.signInDetails?.loginId]);



  // Generate dynamic filter data with counts
  const filterData = useMemo(() => {
    const incompleteItems = reorderItems.filter(item => !item.completed);
    

    
    // Category counts with better handling
    const categoryMap = new Map<string, number>();
    incompleteItems.forEach(item => {
      let category = item.itemCategory;
      
      // Handle various undefined/null/empty cases
      if (!category || category.trim() === '' || category === 'N/A') {
        category = 'Uncategorized';
      }
      
      categoryMap.set(category, (categoryMap.get(category) || 0) + 1);
    });
    
    // Vendor counts with better handling
    const vendorMap = new Map<string, number>();
    incompleteItems.forEach(item => {
      let vendor = item.teamData?.vendor;
      
      // Handle various undefined/null/empty cases
      if (!vendor || vendor.trim() === '' || vendor === 'N/A' || vendor === 'Unknown Vendor') {
        vendor = 'No Vendor';
      }
      
      vendorMap.set(vendor, (vendorMap.get(vendor) || 0) + 1);
    });
    
    const categories = Array.from(categoryMap.entries())
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count);
      
    const vendors = Array.from(vendorMap.entries())
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count);
    

    
    return { categories, vendors };
  }, [reorderItems]);

  // Filter and sort items based on current filter
  const filteredAndSortedItems = useMemo(() => {
    let filtered = reorderItems;

    // Apply completion filter
    if (currentFilter === 'completed') {
      filtered = filtered.filter(item => item.completed);
    } else if (currentFilter === 'incomplete') {
      filtered = filtered.filter(item => !item.completed);
    }

    // Apply category filter
    if (selectedCategory) {
      filtered = filtered.filter(item => 
        item.itemCategory === selectedCategory
      );
    }

    // Apply vendor filter
    if (selectedVendor) {
      filtered = filtered.filter(item => 
        item.teamData?.vendor === selectedVendor
      );
    }

    // Apply sorting based on sortState
    if (sortState.alphabetical !== 'off') {
      filtered = [...filtered].sort((a, b) => {
        const comparison = (a.itemName || '').localeCompare(b.itemName || '');
        return sortState.alphabetical === 'asc' ? comparison : -comparison;
      });
    } else if (sortState.chronological !== 'off') {
      filtered = [...filtered].sort((a, b) => {
        const aTime = a.timestamp ? a.timestamp.getTime() : new Date(a.createdAt).getTime();
        const bTime = b.timestamp ? b.timestamp.getTime() : new Date(b.createdAt).getTime();
        const comparison = bTime - aTime;
        return sortState.chronological === 'desc' ? comparison : -comparison;
      });
    }

    return filtered;
  }, [reorderItems, currentFilter, selectedCategory, selectedVendor, sortState]);

  // Calculate stats
  const stats = useMemo(() => {
    const total = reorderItems.length;
    const completed = reorderItems.filter(item => item.completed).length;
    const incomplete = total - completed;
    const totalQuantity = reorderItems.reduce((sum, item) => sum + item.quantity, 0);

    return { total, completed, incomplete, totalQuantity };
  }, [reorderItems]);

  // Render sort button (3-state cycle)
  const renderSortButton = (sortType: 'chronological' | 'alphabetical', label: string, icon: string) => {
    const state = sortState[sortType];
    const isActive = state !== 'off';
    
    return (
      <TouchableOpacity
        style={[
          reorderStyles.filterButton,
          isActive && reorderStyles.filterButtonActive
        ]}
        onPress={() => handleSortClick(sortType)}
      >
        <Ionicons 
          name={icon as any} 
          size={16} 
          color={isActive ? '#fff' : '#333'} 
        />
        <Text style={[
          reorderStyles.filterButtonText,
          isActive && reorderStyles.filterButtonTextActive
        ]}>
          {label}{state === 'asc' ? ' ↑' : state === 'desc' ? ' ↓' : ''}
        </Text>
      </TouchableOpacity>
    );
  };

  // Render filter button
  const renderFilterButton = (filter: FilterType, label: string, icon: string) => {
    if (filter === 'category') {
      return (
        <TouchableOpacity
          style={[
            reorderStyles.filterButton,
            (selectedCategory || showCategoryDropdown) && reorderStyles.filterButtonActive
          ]}
          onPress={() => handleFilterClick(filter)}
        >
          <Ionicons 
            name={icon as any} 
            size={16} 
            color={(selectedCategory || showCategoryDropdown) ? '#fff' : '#333'} 
          />
          <Text style={[
            reorderStyles.filterButtonText,
            (selectedCategory || showCategoryDropdown) && reorderStyles.filterButtonTextActive
          ]}>
            {selectedCategory ? `${selectedCategory} (${filterData.categories.find(c => c.name === selectedCategory)?.count || 0})` : `Categories (${filterData.categories.length})`}
          </Text>
          <Ionicons 
            name={showCategoryDropdown ? "chevron-up" : "chevron-down"} 
            size={14} 
            color={(selectedCategory || showCategoryDropdown) ? '#fff' : '#333'} 
            style={{ marginLeft: 4 }}
          />
        </TouchableOpacity>
      );
    }

    if (filter === 'vendor') {
      return (
        <TouchableOpacity
          style={[
            reorderStyles.filterButton,
            (selectedVendor || showVendorDropdown) && reorderStyles.filterButtonActive
          ]}
          onPress={() => handleFilterClick(filter)}
        >
          <Ionicons 
            name={icon as any} 
            size={16} 
            color={(selectedVendor || showVendorDropdown) ? '#fff' : '#333'} 
          />
          <Text style={[
            reorderStyles.filterButtonText,
            (selectedVendor || showVendorDropdown) && reorderStyles.filterButtonTextActive
          ]}>
            {selectedVendor ? `${selectedVendor} (${filterData.vendors.find(v => v.name === selectedVendor)?.count || 0})` : `Vendors (${filterData.vendors.length})`}
          </Text>
          <Ionicons 
            name={showVendorDropdown ? "chevron-up" : "chevron-down"} 
            size={14} 
            color={(selectedVendor || showVendorDropdown) ? '#fff' : '#333'} 
            style={{ marginLeft: 4 }}
          />
        </TouchableOpacity>
      );
    }

    // Regular filter button (completed, incomplete, sortConfig)
    const isActive = currentFilter === filter;
    return (
      <TouchableOpacity
        style={[
          reorderStyles.filterButton,
          isActive && reorderStyles.filterButtonActive
        ]}
        onPress={() => handleFilterClick(filter)}
      >
        <Ionicons 
          name={icon as any} 
          size={16} 
          color={isActive ? '#fff' : '#333'} 
        />
        <Text style={[
          reorderStyles.filterButtonText,
          isActive && reorderStyles.filterButtonTextActive
        ]}>
          {label}
        </Text>
      </TouchableOpacity>
    );
  };

  // Handle sort button clicks (3-state cycle for chronological/alphabetical)
  const handleSortClick = (sortType: 'chronological' | 'alphabetical') => {
    setSortState(prev => {
      const currentState = prev[sortType];
      let newState: 'off' | 'desc' | 'asc';
      
      if (currentState === 'off') {
        newState = 'desc'; // First click: most recent/A-Z
      } else if (currentState === 'desc') {
        newState = 'asc'; // Second click: oldest/Z-A
      } else {
        newState = 'off'; // Third click: turn off
      }
      
      return {
        ...prev,
        [sortType]: newState,
        // Turn off the other sort when one is activated
        [sortType === 'chronological' ? 'alphabetical' : 'chronological']: newState === 'off' ? prev[sortType === 'chronological' ? 'alphabetical' : 'chronological'] : 'off'
      };
    });
  };

  // Handle filter button clicks (toggle on/off)
  const handleFilterClick = (filter: FilterType) => {
    // Close all dropdowns first
    setShowCategoryDropdown(false);
    setShowVendorDropdown(false);
    setShowConfigDropdown(false);
    setShowSyncStatusPopover(false);
    
    if (filter === 'completed') {
      setCurrentFilter(currentFilter === 'completed' ? null : 'completed');
    } else if (filter === 'incomplete') {
      setCurrentFilter(currentFilter === 'incomplete' ? null : 'incomplete');
    } else if (filter === 'category') {
      setShowCategoryDropdown(true);
    } else if (filter === 'vendor') {
      setShowVendorDropdown(true);
    } else if (filter === 'sortConfig') {
      setShowConfigDropdown(true);
    }
  };

  // Render reorder item
  const renderReorderItem = ({ item }: { item: ReorderItem }) => {
    return (
      <Swipeable
        friction={2}
        leftThreshold={120}
        rightThreshold={120}
        overshootLeft={false}
        overshootRight={false}
        renderRightActions={(progress, dragX) => {
          const opacity = progress.interpolate({
            inputRange: [0, 0.7, 0.8],
            outputRange: [1, 1, 0],
            extrapolate: 'clamp',
          });
          
          return (
            <View style={{
              flex: 1,
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'flex-end',
              paddingRight: 16,
            }}>
              <Animated.View style={[
                reorderStyles.deleteButton,
                { opacity }
              ]}>
                <TouchableOpacity
                  style={reorderStyles.deleteButtonInner}
                  onPress={() => handleDeleteItem(item.id)}
                >
                  <Ionicons name="trash-outline" size={24} color="#fff" />
                </TouchableOpacity>
              </Animated.View>
            </View>
          );
        }}
        onSwipeableRightOpen={() => {
          // Auto-delete on full swipe
          handleDeleteItem(item.id);
        }}
      >
        <View style={[
          reorderStyles.reorderItem,
          item.completed && reorderStyles.reorderItemCompleted,
          item.isCustom && { borderLeftWidth: 4, borderLeftColor: '#007AFF' }
        ]}>
          {/* Index number - tappable for completion toggle */}
          <TouchableOpacity
            style={[
              reorderStyles.indexContainer,
              item.completed && reorderStyles.indexContainerCompleted
            ]}
            onPress={() => reorderService.toggleCompletion(item.id)}
          >
            {item.completed ? (
              <Ionicons name="checkmark" size={18} color="#fff" />
            ) : (
              <Text style={reorderStyles.indexText}>{item.index}</Text>
            )}
          </TouchableOpacity>

          {/* Item content - tappable for quantity editing */}
          <TouchableOpacity 
            style={reorderStyles.itemContent}
            onPress={() => {
              if (item.isCustom) {
                handleEditCustomItem(item);
              } else {
                // Open quantity modal for manual editing
                setCurrentEditingItem(item);
                setShowQuantityModal(true);
              }
            }}
          >
            <View style={reorderStyles.itemHeader}>
              <View style={reorderStyles.itemNameContainer}>
                <Text style={[
                  reorderStyles.itemName,
                  item.completed && reorderStyles.itemNameCompleted
                ]} numberOfLines={1}>
                  {item.itemName}
                </Text>
                <View style={{ flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', marginTop: 2 }}>
                  {item.itemCategory && <Text style={reorderStyles.itemCategory}>{item.itemCategory}</Text>}
                  <Text style={reorderStyles.compactDetails}>
                    UPC: {item.itemBarcode || 'N/A'}{item.itemBarcode ? ` • SKU: N/A` : ''} • Price: ${item.itemPrice?.toFixed(2) || 'Variable'}{item.teamData?.vendorCost ? ` • Cost: $${item.teamData.vendorCost.toFixed(2)}` : ' • Cost: N/A'}{item.teamData?.vendor ? ` • Vendor: ${item.teamData.vendor}` : ' • Vendor: N/A'}{item.teamData?.discontinued ? ' • DISCONTINUED' : ''}
                  </Text>
                </View>
              </View>
              <View style={reorderStyles.qtyContainer}>
                <Text style={reorderStyles.qtyLabel}>Qty</Text>
                <Text style={reorderStyles.qtyNumber}>{item.quantity}</Text>
              </View>
            </View>

            <View style={reorderStyles.timestampContainer}>
              <Text style={reorderStyles.timestamp}>
                {(item.timestamp || new Date(item.createdAt)).toLocaleDateString()} {(item.timestamp || new Date(item.createdAt)).toLocaleTimeString()}
              </Text>
              <Text style={reorderStyles.addedBy}>
                By: {item.addedBy || 'Unknown User'}
              </Text>
            </View>
          </TouchableOpacity>
        </View>
      </Swipeable>
    );
  };

  // Render empty state
  const renderEmptyState = () => (
    <View style={reorderStyles.emptyContainer}>
      <Ionicons name="scan-outline" size={64} color="#ccc" style={reorderStyles.emptyIcon} />
      <Text style={reorderStyles.emptyTitle}>No Reorders Yet</Text>
      <Text style={reorderStyles.emptySubtitle}>
        Scanner is ready! Start scanning items to add them to your reorder list.
      </Text>
    </View>
  );

  // Create sectioned data for rendering
  const sectionedData = useMemo(() => {
    let baseData = filteredAndSortedItems;
    
    if (!sectionByCategory && !sectionByVendor) {
      // Add custom item entry at the top if it's being added
      if (showAddCustomItem) {
        return [{ type: 'customEntry' }, ...baseData];
      }
      return baseData;
    }

    const groupBy = sectionByVendor ? 'vendor' : 'category'; // Vendor takes precedence
    const sections: { [key: string]: ReorderItem[] } = {};

    baseData.forEach(item => {
      let key: string;
      if (groupBy === 'vendor') {
        key = item.teamData?.vendor || 'No Vendor';
      } else {
        key = item.itemCategory || 'Uncategorized';
      }
      
      if (!sections[key]) {
        sections[key] = [];
      }
      sections[key].push(item);
    });

    // Convert to flat array with section headers
    const flatData: (ReorderItem | { type: 'header'; title: string; count: number } | { type: 'customEntry' })[] = [];
    
    // Add custom item entry at the very top if it's being added
    if (showAddCustomItem) {
      flatData.push({ type: 'customEntry' });
    }
    
    Object.keys(sections)
      .sort()
      .forEach(sectionKey => {
        flatData.push({
          type: 'header',
          title: sectionKey,
          count: sections[sectionKey].length
        });
        flatData.push(...sections[sectionKey]);
      });

    return flatData;
  }, [filteredAndSortedItems, sectionByCategory, sectionByVendor, showAddCustomItem]);

  // Render section header
  const renderSectionHeader = (title: string, count: number) => (
    <View style={reorderStyles.sectionHeader}>
      <Text style={reorderStyles.sectionHeaderText}>
        {title}
        <Text style={reorderStyles.sectionHeaderCount}>({count})</Text>
      </Text>
    </View>
  );

  // Updated render item function to handle both items and headers
  const renderListItem = ({ item }: { item: any }) => {
    if (item.type === 'header') {
      return renderSectionHeader(item.title, item.count);
    }
    if (item.type === 'customEntry') {
      return renderCustomItemEntry();
    }
    return renderReorderItem({ item });
  };

  // Render custom item entry (inline at top of list)
  const renderCustomItemEntry = () => {
    if (!showAddCustomItem || !customItemEdit) return null;

    return (
      <View style={[reorderStyles.reorderItem, { borderColor: '#007AFF', borderWidth: 2 }]}>
        <View style={[reorderStyles.indexContainer, { backgroundColor: '#007AFF' }]}>
          <Ionicons name="add" size={18} color="#fff" />
        </View>

        <View style={reorderStyles.itemContent}>
          <View style={reorderStyles.itemHeader}>
            <View style={reorderStyles.itemNameContainer}>
              <TextInput
                style={[reorderStyles.itemName, { borderBottomWidth: 1, borderBottomColor: '#ddd', paddingBottom: 4 }]}
                value={customItemEdit.itemName}
                onChangeText={(text) => setCustomItemEdit(prev => prev ? { ...prev, itemName: text } : null)}
                placeholder="Enter item name..."
                autoFocus
                returnKeyType="next"
              />
              <View style={{ flexDirection: 'row', gap: 8, marginTop: 8 }}>
                <TextInput
                  style={[reorderStyles.compactDetails, { 
                    flex: 1, 
                    borderBottomWidth: 1, 
                    borderBottomColor: '#ddd', 
                    paddingBottom: 2,
                    fontSize: 12
                  }]}
                  value={customItemEdit.itemCategory}
                  onChangeText={(text) => setCustomItemEdit(prev => prev ? { ...prev, itemCategory: text } : null)}
                  placeholder="Category..."
                />
                <TextInput
                  style={[reorderStyles.compactDetails, { 
                    flex: 1, 
                    borderBottomWidth: 1, 
                    borderBottomColor: '#ddd', 
                    paddingBottom: 2,
                    fontSize: 12
                  }]}
                  value={customItemEdit.vendor}
                  onChangeText={(text) => setCustomItemEdit(prev => prev ? { ...prev, vendor: text } : null)}
                  placeholder="Vendor..."
                />
              </View>
            </View>
            <View style={reorderStyles.qtyContainer}>
              <Text style={reorderStyles.qtyLabel}>Qty</Text>
              <TextInput
                style={[reorderStyles.qtyNumber, { 
                  borderBottomWidth: 1, 
                  borderBottomColor: '#ddd', 
                  textAlign: 'center',
                  minWidth: 40
                }]}
                value={customItemEdit.quantity.toString()}
                onChangeText={(text) => {
                  const qty = parseInt(text) || 1;
                  setCustomItemEdit(prev => prev ? { ...prev, quantity: qty } : null);
                }}
                keyboardType="numeric"
              />
            </View>
          </View>

          <View style={[reorderStyles.timestampContainer, { flexDirection: 'row', justifyContent: 'space-between' }]}>
            <TouchableOpacity
              style={{ backgroundColor: '#ff3b30', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 6 }}
              onPress={handleCancelCustomItem}
            >
              <Text style={{ color: '#fff', fontSize: 12, fontWeight: '600' }}>Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={{ 
                backgroundColor: customItemEdit.itemName.trim() ? '#007AFF' : '#ccc', 
                paddingHorizontal: 12, 
                paddingVertical: 6, 
                borderRadius: 6 
              }}
              onPress={handleSaveCustomItem}
              disabled={!customItemEdit.itemName.trim()}
            >
              <Text style={{ color: '#fff', fontSize: 12, fontWeight: '600' }}>Save</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    );
  };

  // Get sync status explanation
  const getSyncStatusExplanation = () => {
    const { isAuthenticated, isOnline, pendingCount } = syncStatus;
    
    let title = '';
    let description = '';
    let color = '';
    
    if (isAuthenticated && isOnline && pendingCount === 0) {
      title = '✅ Fully Synced';
      description = 'You are signed in and all items are synced with the server. Changes will appear on all your devices in real-time.';
      color = '#4CD964';
    } else if (isAuthenticated && isOnline && pendingCount > 0) {
      title = '🔄 Syncing';
      description = `You are signed in but ${pendingCount} item${pendingCount > 1 ? 's' : ''} are waiting to sync. Tap refresh to sync now.`;
      color = '#FF9500';
    } else if (isAuthenticated && !isOnline) {
      title = '📱 Offline Mode';
      description = 'You are signed in but currently offline. Items are saved locally and will sync when connection is restored.';
      color = '#FF3B30';
    } else if (!isAuthenticated && isOnline) {
      title = '🔐 Not Signed In';
      description = 'You are not signed in. Items are saved locally on this device only. Sign in to sync across devices.';
      color = '#FF9500';
    } else {
      title = '📱 Local Only';
      description = 'You are not signed in and offline. Items are saved locally on this device only.';
      color = '#FF3B30';
    }
    
    return { title, description, color };
  };

  if (loading) {
    return (
      <SafeAreaView style={reorderStyles.container}>
        <Stack.Screen options={{ headerShown: true, title: 'Reorders' }} />
        <View style={reorderStyles.loadingContainer}>
          <ActivityIndicator size="large" color="#007AFF" />
          <Text style={reorderStyles.loadingText}>Loading catalog...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={reorderStyles.container}>
      <Stack.Screen
        options={{
          headerShown: true,
          title: 'Reorders',
          headerLeft: () => (
            <TouchableOpacity 
              style={{ flexDirection: 'row', alignItems: 'center', marginLeft: 8 }}
              onPress={() => setShowSyncStatusPopover(true)}
            >
              <Ionicons 
                name={syncStatus.isAuthenticated ? "person" : "person-outline"} 
                size={20} 
                color={syncStatus.isAuthenticated ? "#4CD964" : "#FF9500"} 
              />
              <Ionicons 
                name={syncStatus.isOnline ? "cloud" : "cloud-offline"} 
                size={20} 
                color={syncStatus.isOnline ? "#4CD964" : "#FF3B30"} 
                style={{ marginLeft: 4 }}
              />
              {syncStatus.pendingCount > 0 && (
                <View style={{
                  backgroundColor: '#FF9500',
                  borderRadius: 10,
                  minWidth: 20,
                  height: 20,
                  justifyContent: 'center',
                  alignItems: 'center',
                  marginLeft: 4
                }}>
                  <Text style={{ color: '#fff', fontSize: 12, fontWeight: 'bold' }}>
                    {syncStatus.pendingCount}
                  </Text>
                </View>
              )}
            </TouchableOpacity>
          ),
          headerRight: () => (
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <TouchableOpacity 
                onPress={handleAddCustomItem}
                style={{ marginRight: 16 }}
              >
                <Ionicons name="add" size={24} color="#007AFF" />
              </TouchableOpacity>
              <TouchableOpacity 
                onPress={handleRefresh}
                style={{ marginRight: 16 }}
                disabled={isRefreshing}
              >
                <Ionicons 
                  name={isRefreshing ? "sync" : "refresh"} 
                  size={24} 
                  color={isRefreshing ? "#999" : "#007AFF"} 
                />
              </TouchableOpacity>
              <View style={{ alignItems: 'center', marginRight: 8 }}>
                <Ionicons 
                  name="scan" 
                  size={24} 
                  color="#007AFF" 
                />
                <Text style={{ 
                  fontSize: 10, 
                  color: "#007AFF",
                  marginTop: 2
                }}>
                  Ready
                </Text>
              </View>
            </View>
          ),
        }}
      />

      {/* Barcode Scanner Component */}
      <BarcodeScanner
        onScan={handleBarcodeScan}
        onError={handleScanError}
        enabled={!showQuantityModal && !showSelectionModal && !showErrorModal && !showAddCustomItem}
        minLength={8}
        maxLength={50}
        timeout={150}
      />

      {/* Header with stats and filters */}
      <View style={reorderStyles.headerSection}>
        {/* Stats */}
        <View style={reorderStyles.statsContainer}>
          <View style={reorderStyles.statItem}>
            <Text style={reorderStyles.statNumber}>{stats.total}</Text>
            <Text style={reorderStyles.statLabel}>Total</Text>
          </View>
          <View style={reorderStyles.statItem}>
            <Text style={reorderStyles.statNumber}>{stats.completed}</Text>
            <Text style={reorderStyles.statLabel}>Completed</Text>
          </View>
          <View style={reorderStyles.statItem}>
            <Text style={reorderStyles.statNumber}>{stats.incomplete}</Text>
            <Text style={reorderStyles.statLabel}>Remaining</Text>
          </View>
          <View style={reorderStyles.statItem}>
            <Text style={reorderStyles.statNumber}>{stats.totalQuantity}</Text>
            <Text style={reorderStyles.statLabel}>Qty</Text>
          </View>
        </View>

        {/* Filter Row */}
        <ScrollView 
          horizontal 
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: 8,
          }}
          style={{ marginBottom: 8, paddingLeft: 16 }}
        >
          {renderFilterButton('sortConfig', '', 'options')}
          {renderFilterButton('incomplete', 'Incomplete', 'ellipse-outline')}
          {renderFilterButton('completed', 'Completed', 'checkmark-circle')}
          {renderSortButton('chronological', 'Recent', 'time')}
          {renderSortButton('alphabetical', 'A-Z', 'text')}
          {renderFilterButton('category', 'Categories', 'folder')}
          {renderFilterButton('vendor', 'Vendors', 'business')}
        </ScrollView>
      </View>

      {/* Inline Dropdown Overlays */}
      {(showCategoryDropdown || showVendorDropdown || showConfigDropdown) && (
        <TouchableOpacity
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'transparent',
            zIndex: 999,
          }}
          activeOpacity={1}
          onPress={() => {
            setShowCategoryDropdown(false);
            setShowVendorDropdown(false);
            setShowConfigDropdown(false);
          }}
        />
      )}

      {showCategoryDropdown && (
        <View style={{
          position: 'absolute',
          top: 120, // Closer to the filter buttons
          left: 16,
          right: 16,
          backgroundColor: '#fff',
          borderRadius: 12,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.25,
          shadowRadius: 8,
          elevation: 12,
          zIndex: 1000,
          maxHeight: 250,
          borderWidth: 1,
          borderColor: '#e0e0e0',
        }}>
          <View style={{ 
            padding: 16, 
            borderBottomWidth: 1, 
            borderBottomColor: '#f0f0f0',
            backgroundColor: '#f8f9fa',
            borderTopLeftRadius: 12,
            borderTopRightRadius: 12,
          }}>
            <Text style={{ 
              fontSize: 16, 
              fontWeight: '600', 
              color: '#333',
              textAlign: 'center'
            }}>
              Select Category
            </Text>
          </View>
          {renderDropdown(
            filterData.categories,
            selectedCategory,
            (value) => {
              setSelectedCategory(value);
              setShowCategoryDropdown(false);
            },
            'Categories'
          )}
        </View>
      )}

      {showVendorDropdown && (
        <View style={{
          position: 'absolute',
          top: 120, // Closer to the filter buttons
          left: 16,
          right: 16,
          backgroundColor: '#fff',
          borderRadius: 12,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.25,
          shadowRadius: 8,
          elevation: 12,
          zIndex: 1000,
          maxHeight: 250,
          borderWidth: 1,
          borderColor: '#e0e0e0',
        }}>
          <View style={{ 
            padding: 16, 
            borderBottomWidth: 1, 
            borderBottomColor: '#f0f0f0',
            backgroundColor: '#f8f9fa',
            borderTopLeftRadius: 12,
            borderTopRightRadius: 12,
          }}>
            <Text style={{ 
              fontSize: 16, 
              fontWeight: '600', 
              color: '#333',
              textAlign: 'center'
            }}>
              Select Vendor
            </Text>
          </View>
          {renderDropdown(
            filterData.vendors,
            selectedVendor,
            (value) => {
              setSelectedVendor(value);
              setShowVendorDropdown(false);
            },
            'Vendors'
          )}
        </View>
      )}

      {showConfigDropdown && (
        <View style={{
          position: 'absolute',
          top: 120,
          left: 16,
          right: 16,
          backgroundColor: '#fff',
          borderRadius: 12,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.25,
          shadowRadius: 8,
          elevation: 12,
          zIndex: 1000,
          borderWidth: 1,
          borderColor: '#e0e0e0',
        }}>
          <View style={{ 
            padding: 16, 
            borderBottomWidth: 1, 
            borderBottomColor: '#f0f0f0',
            backgroundColor: '#f8f9fa',
            borderTopLeftRadius: 12,
            borderTopRightRadius: 12,
          }}>
            <Text style={{ 
              fontSize: 16, 
              fontWeight: '600', 
              color: '#333',
              textAlign: 'center'
            }}>
              List Organization
            </Text>
          </View>
          
          <View style={{ padding: 16 }}>
            <TouchableOpacity
              style={{
                flexDirection: 'row',
                justifyContent: 'space-between',
                alignItems: 'center',
                paddingVertical: 12,
                borderBottomWidth: 1,
                borderBottomColor: '#f0f0f0',
              }}
              onPress={() => setSectionByCategory(!sectionByCategory)}
            >
              <Text style={{
                fontSize: 15,
                color: '#333',
                fontWeight: '400',
              }}>
                Group by Categories
              </Text>
              <View style={{
                width: 24,
                height: 24,
                borderRadius: 12,
                backgroundColor: sectionByCategory ? '#007AFF' : '#e0e0e0',
                justifyContent: 'center',
                alignItems: 'center',
              }}>
                {sectionByCategory && (
                  <Ionicons name="checkmark" size={16} color="#fff" />
                )}
              </View>
            </TouchableOpacity>
            
            <TouchableOpacity
              style={{
                flexDirection: 'row',
                justifyContent: 'space-between',
                alignItems: 'center',
                paddingVertical: 12,
              }}
              onPress={() => setSectionByVendor(!sectionByVendor)}
            >
              <Text style={{
                fontSize: 15,
                color: '#333',
                fontWeight: '400',
              }}>
                Group by Vendors
              </Text>
              <View style={{
                width: 24,
                height: 24,
                borderRadius: 12,
                backgroundColor: sectionByVendor ? '#007AFF' : '#e0e0e0',
                justifyContent: 'center',
                alignItems: 'center',
              }}>
                {sectionByVendor && (
                  <Ionicons name="checkmark" size={16} color="#fff" />
                )}
              </View>
            </TouchableOpacity>
            
            {sectionByVendor && sectionByCategory && (
              <Text style={{
                fontSize: 12,
                color: '#666',
                fontStyle: 'italic',
                marginTop: 8,
                textAlign: 'center',
              }}>
                Vendor grouping takes precedence when both are enabled
              </Text>
            )}
          </View>
        </View>
      )}

      {/* Reorder List */}
      <TouchableOpacity 
        style={reorderStyles.listContainer}
        activeOpacity={1}
        onPress={() => {
          // Close dropdowns when tapping on the list area
          setShowCategoryDropdown(false);
          setShowVendorDropdown(false);
          setShowConfigDropdown(false);
          setShowSyncStatusPopover(false);
        }}
      >
        {sectionedData.length === 0 ? (
          renderEmptyState()
        ) : (
          <FlatList
            data={sectionedData}
            renderItem={renderListItem}
            keyExtractor={(item) => {
              if ('type' in item) {
                if (item.type === 'header' && 'title' in item) {
                  return `header-${item.title}`;
                }
                if (item.type === 'customEntry') {
                  return 'custom-entry';
                }
              }
              return (item as ReorderItem).id;
            }}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingBottom: 20 }}
            refreshControl={
              <RefreshControl
                refreshing={isRefreshing}
                onRefresh={handleRefresh}
                tintColor="#007AFF"
                title="Pull to refresh"
                titleColor="#666"
              />
            }
          />
        )}
      </TouchableOpacity>

      {/* Modals */}
      <QuantityModal
        visible={showQuantityModal}
        item={currentEditingItem}
        quantity={modalQuantity}
        setQuantity={setModalQuantity}
        onSubmit={handleQuantitySubmit}
        onCancel={() => {
          setShowQuantityModal(false);
          setCurrentEditingItem(null);
          setModalQuantity('1'); // Reset quantity on cancel
        }}
      />

      <ItemSelectionModal
        visible={showSelectionModal}
        items={multipleItems}
        onSelect={handleItemSelection}
        onCancel={() => {
          setShowSelectionModal(false);
          setMultipleItems([]);
        }}
      />

      {/* Error Modal */}
      <Modal visible={showErrorModal} transparent animationType="fade">
            <TouchableOpacity 
          style={{
            flex: 1,
            backgroundColor: 'rgba(0,0,0,0.5)',
            justifyContent: 'center',
            alignItems: 'center',
            padding: 20,
          }}
          activeOpacity={1}
          onPress={() => {
            setShowErrorModal(false);
          }}
        >
          <View
            style={{
              backgroundColor: '#fff',
              borderRadius: 12,
              padding: 24,
              minWidth: 280,
              maxWidth: '90%',
              shadowColor: '#000',
              shadowOffset: { width: 0, height: 4 },
              shadowOpacity: 0.25,
              shadowRadius: 8,
              elevation: 8,
            }}
          >
            <View style={{ alignItems: 'center', marginBottom: 16 }}>
              <Ionicons name="alert-circle" size={48} color="#FF6B6B" />
              <Text style={{ fontSize: 18, fontWeight: 'bold', color: '#333', marginTop: 8 }}>
                Scan Failed
              </Text>
          </View>
            
            <Text style={{ 
              fontSize: 16, 
              color: '#666', 
              textAlign: 'center', 
              lineHeight: 24,
              marginBottom: 20
            }}>
              {errorMessage}
            </Text>
            
            <View style={{ alignItems: 'center' }}>
              <Text style={{ 
                fontSize: 14, 
                color: '#999', 
                textAlign: 'center',
                fontStyle: 'italic'
              }}>
                Scan another item to dismiss
              </Text>
      </View>
          </View>
        </TouchableOpacity>
      </Modal>

      {/* Sync Status Popover */}
      <Modal visible={showSyncStatusPopover} transparent animationType="fade">
        <TouchableOpacity 
          style={{
            flex: 1,
            backgroundColor: 'rgba(0,0,0,0.5)',
            justifyContent: 'center',
            alignItems: 'center',
            padding: 20
          }}
          activeOpacity={1}
          onPress={() => setShowSyncStatusPopover(false)}
        >
          <TouchableOpacity 
            style={{
              backgroundColor: '#fff',
              borderRadius: 16,
              padding: 24,
              maxWidth: 320,
              width: '100%',
              shadowColor: '#000',
              shadowOffset: { width: 0, height: 4 },
              shadowOpacity: 0.25,
              shadowRadius: 12,
              elevation: 8,
            }}
            activeOpacity={1}
            onPress={(e) => e.stopPropagation()}
          >
            <View style={{ alignItems: 'center', marginBottom: 16 }}>
              <Text style={{
                fontSize: 18,
                fontWeight: '600',
                color: getSyncStatusExplanation().color,
                textAlign: 'center'
              }}>
                {getSyncStatusExplanation().title}
              </Text>
            </View>
            
            <Text style={{
              fontSize: 15,
              color: '#333',
              lineHeight: 22,
              textAlign: 'center',
              marginBottom: 20
            }}>
              {getSyncStatusExplanation().description}
            </Text>
            
            <View style={{
              flexDirection: 'row',
              justifyContent: 'center',
              alignItems: 'center',
              marginBottom: 20,
              paddingVertical: 12,
              paddingHorizontal: 16,
              backgroundColor: '#f8f9fa',
              borderRadius: 8
            }}>
              <View style={{ alignItems: 'center', marginRight: 20 }}>
                <Ionicons 
                  name={syncStatus.isAuthenticated ? "person" : "person-outline"} 
                  size={24} 
                  color={syncStatus.isAuthenticated ? "#4CD964" : "#FF9500"} 
                />
                <Text style={{ fontSize: 12, color: '#666', marginTop: 4 }}>
                  {syncStatus.isAuthenticated ? 'Signed In' : 'Not Signed In'}
                </Text>
              </View>
              
              <View style={{ alignItems: 'center', marginRight: 20 }}>
                <Ionicons 
                  name={syncStatus.isOnline ? "cloud" : "cloud-offline"} 
                  size={24} 
                  color={syncStatus.isOnline ? "#4CD964" : "#FF3B30"} 
                />
                <Text style={{ fontSize: 12, color: '#666', marginTop: 4 }}>
                  {syncStatus.isOnline ? 'Online' : 'Offline'}
                </Text>
              </View>
              
              {syncStatus.pendingCount > 0 && (
                <View style={{ alignItems: 'center' }}>
                  <View style={{
                    backgroundColor: '#FF9500',
                    borderRadius: 12,
                    minWidth: 24,
                    height: 24,
                    justifyContent: 'center',
                    alignItems: 'center'
                  }}>
                    <Text style={{ color: '#fff', fontSize: 12, fontWeight: 'bold' }}>
                      {syncStatus.pendingCount}
                    </Text>
                  </View>
                  <Text style={{ fontSize: 12, color: '#666', marginTop: 4 }}>
                    Pending
                  </Text>
                </View>
              )}
            </View>
            
            <View style={{ flexDirection: 'row', gap: 12 }}>
              {syncStatus.pendingCount > 0 && (
                <TouchableOpacity
                  style={{
                    flex: 1,
                    backgroundColor: '#007AFF',
                    paddingVertical: 12,
                    paddingHorizontal: 16,
                    borderRadius: 8,
                    alignItems: 'center'
                  }}
                  onPress={() => {
                    setShowSyncStatusPopover(false);
                    handleRefresh();
                  }}
                >
                  <Text style={{ color: '#fff', fontSize: 16, fontWeight: '600' }}>
                    Sync Now
                  </Text>
                </TouchableOpacity>
              )}
              
              <TouchableOpacity
                style={{
                  flex: syncStatus.pendingCount > 0 ? 1 : 2,
                  backgroundColor: '#f0f0f0',
                  paddingVertical: 12,
                  paddingHorizontal: 16,
                  borderRadius: 8,
                  alignItems: 'center'
                }}
                onPress={() => setShowSyncStatusPopover(false)}
              >
                <Text style={{ color: '#333', fontSize: 16, fontWeight: '600' }}>
                  Close
                </Text>
              </TouchableOpacity>
            </View>
          </TouchableOpacity>
        </TouchableOpacity>
      </Modal>
    </SafeAreaView>
  );
} 