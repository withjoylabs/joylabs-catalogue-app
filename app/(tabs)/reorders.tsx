import React, { useState, useEffect, useMemo, useCallback } from 'react';
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
} from 'react-native';
import { Stack, useRouter, useFocusEffect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import Swipeable from 'react-native-gesture-handler/Swipeable';
import { useCatalogItems } from '../../src/hooks/useCatalogItems';
import { useBarcodeScanner } from '../../src/hooks/useBarcodeScanner';
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

const client = generateClient();

// Types for reorder functionality - use the service type
type ReorderItem = ServiceReorderItem;

interface QuantityModalProps {
  visible: boolean;
  item: ConvertedItem | null;
  onSubmit: (quantity: number) => void;
  onCancel: () => void;
  onDelete: () => void;
}

interface ItemSelectionModalProps {
  visible: boolean;
  items: ConvertedItem[];
  onSelect: (item: ConvertedItem) => void;
  onCancel: () => void;
}

type FilterType = 'completed' | 'incomplete' | 'category' | 'vendor' | 'sortConfig';

const TAG = '[ReordersScreen]';

// Quantity Modal Component
const QuantityModal: React.FC<QuantityModalProps> = ({ visible, item, onSubmit, onCancel, onDelete }) => {
  const [quantity, setQuantity] = useState('1');

  // Auto-submit if another scan comes in while modal is open
  useEffect(() => {
    if (!visible) {
      setQuantity('1'); // Reset quantity when modal closes
    }
  }, [visible]);

  const handleKeypadPress = (value: string) => {
    if (value === 'backspace') {
      setQuantity(prev => prev.length > 1 ? prev.slice(0, -1) : '0');
    } else if (value === 'clear') {
      setQuantity('0');
    } else {
      setQuantity(prev => {
        const newValue = prev === '0' ? value : prev + value;
        return parseInt(newValue) > 999 ? prev : newValue;
      });
    }
  };

  const handleSubmit = () => {
    const qty = parseInt(quantity) || 1;
    onSubmit(qty);
    setQuantity('1');
  };

  const keypadButtons = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['clear', '0', 'backspace']
  ];

  return (
    <Modal visible={visible} transparent animationType="fade">
      <View style={reorderStyles.modalOverlay}>
        <View style={reorderStyles.modalContainer}>
          <View style={reorderStyles.modalHeader}>
            <Text style={reorderStyles.modalTitle}>Enter Quantity</Text>
            <Text style={reorderStyles.modalItemName} numberOfLines={2}>
              {item?.name || 'Unknown Item'}
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
                        (button === 'clear' || button === 'backspace') && reorderStyles.keypadButtonSpecial
                      ]}
                      onPress={() => handleKeypadPress(button)}
                    >
                      {button === 'backspace' ? (
                        <Ionicons name="backspace-outline" size={20} color="#fff" />
                      ) : button === 'clear' ? (
                        <Text style={reorderStyles.keypadButtonSpecialText}>CLR</Text>
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
              style={[reorderStyles.modalButton, reorderStyles.modalButtonDanger]}
              onPress={onDelete}
            >
              <Text style={[reorderStyles.modalButtonText, reorderStyles.modalButtonTextDanger]}>
                Delete Scan
              </Text>
            </TouchableOpacity>
            
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
    <Modal visible={visible} transparent animationType="fade">
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
    <ScrollView style={{ maxHeight: 150 }} showsVerticalScrollIndicator={false}>
      <TouchableOpacity
        style={[reorderStyles.dropdownItem, { paddingVertical: 10 }]}
        onPress={() => onSelect(null)}
      >
        <Text style={[
          reorderStyles.dropdownItemText,
          !selectedValue && reorderStyles.dropdownItemTextSelected
        ]}>
          All {placeholder}
        </Text>
      </TouchableOpacity>
      {items.length === 0 ? (
        <View style={[reorderStyles.dropdownItem, { paddingVertical: 10 }]}>
          <Text style={[reorderStyles.dropdownItemText, { fontStyle: 'italic', opacity: 0.6 }]}>
            No {placeholder.toLowerCase()} available
          </Text>
        </View>
      ) : (
        items.map((item, index) => (
          <TouchableOpacity
            key={`${item.name}-${index}`}
            style={[reorderStyles.dropdownItem, { paddingVertical: 10 }]}
            onPress={() => onSelect(item.name)}
          >
            <Text style={[
              reorderStyles.dropdownItemText,
              selectedValue === item.name && reorderStyles.dropdownItemTextSelected
            ]}>
              {item.name} ({item.count})
            </Text>
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
  const [currentScannedItem, setCurrentScannedItem] = useState<ConvertedItem | null>(null);
  const [multipleItems, setMultipleItems] = useState<ConvertedItem[]>([]);
  const [scannerActive, setScannerActive] = useState(true);
  
  // State for filters and sorting
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [selectedVendor, setSelectedVendor] = useState<string | null>(null);
  const [showCategoryDropdown, setShowCategoryDropdown] = useState(false);
  const [showVendorDropdown, setShowVendorDropdown] = useState(false);
  const [sortState, setSortState] = useState<{
    chronological: 'off' | 'desc' | 'asc';
    alphabetical: 'off' | 'desc' | 'asc';
  }>({
    chronological: 'off',
    alphabetical: 'off'
  });

  // Get authenticated user information
  const { user } = useAuthenticator((context) => [context.user]);

  const { performSearch, isSearching, searchError } = useCatalogItems();
  
  // Handle barcode scan from the scanner
  const handleBarcodeScan = useCallback((barcode: string) => {
    logger.info(TAG, `Barcode scanned: ${barcode}`);
    
    // If quantity modal is open, auto-submit current item with qty 1 and process new scan
    if (showQuantityModal && currentScannedItem) {
      logger.info(TAG, 'Auto-submitting current item with qty 1 due to new scan');
      
      reorderService.addItem(currentScannedItem, 1);
      setShowQuantityModal(false);
      setCurrentScannedItem(null);
    }
    
    // Find items with matching barcode
    const matchingItems = catalogItems.filter((item: ConvertedItem) => 
      item.barcode === barcode
    );

    if (matchingItems.length === 0) {
      // No item found
      Alert.alert(
        'Item Not Found',
        'No item found with this barcode. Please create the item in the main scan page first.',
        [{ text: 'OK' }]
      );
      return;
    }

    if (matchingItems.length === 1) {
      // Single item found
      setCurrentScannedItem(matchingItems[0]);
      setShowQuantityModal(true);
    } else {
      // Multiple items found
      setMultipleItems(matchingItems);
      setShowSelectionModal(true);
    }
  }, [catalogItems, showQuantityModal, currentScannedItem, reorderItems.length]);

  // Initialize barcode scanner
  const { 
    isListening, 
    isKeyEventAvailable
  } = useBarcodeScanner({
    onScan: handleBarcodeScan,
    enabled: scannerActive,
    minLength: 4,
    maxLength: 50,
    timeout: 100
  });

  // Test function for manual barcode input (for testing when scanner isn't available)
  const testBarcodeScan = useCallback(() => {
    // For testing - simulate scanning a barcode
    const testBarcodes = ['123456789', '987654321', '555666777'];
    const randomBarcode = testBarcodes[Math.floor(Math.random() * testBarcodes.length)];
    handleBarcodeScan(randomBarcode);
  }, [handleBarcodeScan]);

  // Set up reorder service listener and cleanup
  useEffect(() => {
    const unsubscribe = reorderService.addListener(setReorderItems);
    
    return () => {
      unsubscribe();
      // Cleanup subscriptions when component unmounts
      reorderService.cleanup();
    };
  }, []);

  // Log scanner status (removed annoying alert)
  useEffect(() => {
    if (scannerActive && !isKeyEventAvailable) {
      logger.info(TAG, 'Scanner module not available, test mode enabled');
    }
  }, [scannerActive, isKeyEventAvailable]);

  // Handle quantity submission
  const handleQuantitySubmit = useCallback(async (quantity: number) => {
    if (!currentScannedItem) return;

    try {
      // Use the enhanced team data fetching from reorder service
      const teamData = await reorderService.fetchTeamData(currentScannedItem.id);
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      
      reorderService.addItem(currentScannedItem, quantity, teamData, userName);
      setShowQuantityModal(false);
      setCurrentScannedItem(null);

      logger.info(TAG, `Added reorder item: ${currentScannedItem.name} x${quantity}`);
    } catch (error) {
      logger.error(TAG, 'Error adding reorder item', { error });
      // Still add the item without team data
      const userName = user?.signInDetails?.loginId?.split('@')[0] || 'Unknown User';
      reorderService.addItem(currentScannedItem, quantity, undefined, userName);
      setShowQuantityModal(false);
      setCurrentScannedItem(null);
    }
  }, [currentScannedItem, user]);

  // Handle item selection from multiple items
  const handleItemSelection = useCallback((item: ConvertedItem) => {
    setCurrentScannedItem(item);
    setShowSelectionModal(false);
    setShowQuantityModal(true);
  }, []);

  // Handle item deletion
  const handleDeleteItem = async (itemId: string) => {
    try {
      await reorderService.removeItem(itemId);
    } catch (error) {
      console.error('Error deleting item:', error);
    }
  };

  // Generate dynamic filter data with counts
  const filterData = useMemo(() => {
    const incompleteItems = reorderItems.filter(item => !item.completed);
    

    
    // Category counts with better handling
    const categoryMap = new Map<string, number>();
    incompleteItems.forEach(item => {
      let category = item.item.category;
      
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
        item.item.category === selectedCategory
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
        const comparison = (a.item.name || '').localeCompare(b.item.name || '');
        return sortState.alphabetical === 'asc' ? comparison : -comparison;
      });
    } else if (sortState.chronological !== 'off') {
      filtered = [...filtered].sort((a, b) => {
        const comparison = new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime();
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
    if (filter === 'category' || filter === 'vendor') {
      // Special handling for dropdown filters
      if (filter === 'category') {
        setShowCategoryDropdown(!showCategoryDropdown);
        setShowVendorDropdown(false);
      } else {
        setShowVendorDropdown(!showVendorDropdown);
        setShowCategoryDropdown(false);
      }
    } else if (filter === 'sortConfig') {
      // TODO: Handle sort config button
    } else {
      // Toggle filter on/off
      setCurrentFilter(currentFilter === filter ? null : filter);
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
          item.completed && reorderStyles.reorderItemCompleted
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

          {/* Item content - not tappable */}
          <View style={reorderStyles.itemContent}>
            <View style={reorderStyles.itemHeader}>
              <View style={reorderStyles.itemNameContainer}>
                <Text style={[
                  reorderStyles.itemName,
                  item.completed && reorderStyles.itemNameCompleted
                ]} numberOfLines={1}>
                  {item.item.name}
                </Text>
                <Text style={reorderStyles.compactDetails}>
                  UPC: {item.item.barcode || 'N/A'}{item.item.sku ? ` • SKU: ${item.item.sku}` : ''} • Cat: {item.item.category || 'N/A'} • Price: ${item.item.price?.toFixed(2) || 'Variable'}{item.teamData?.vendorCost ? ` • Cost: $${item.teamData.vendorCost.toFixed(2)}` : ' • Cost: N/A'}{item.teamData?.vendor ? ` • Vendor: ${item.teamData.vendor}` : ' • Vendor: N/A'}{item.teamData?.discontinued ? ' • DISCONTINUED' : ''}
                </Text>
              </View>
              <View style={reorderStyles.qtyContainer}>
                <Text style={reorderStyles.qtyLabel}>Qty</Text>
                <Text style={reorderStyles.qtyNumber}>{item.quantity}</Text>
              </View>
            </View>

            <View style={reorderStyles.timestampContainer}>
              <Text style={reorderStyles.timestamp}>
                {item.timestamp.toLocaleDateString()} {item.timestamp.toLocaleTimeString()}
              </Text>
              <Text style={reorderStyles.addedBy}>
                By: {item.addedBy || 'Unknown User'}
              </Text>
            </View>
          </View>
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
        {isListening && isKeyEventAvailable
          ? 'Scanner is active and ready! Start scanning items to add them to your reorder list.'
          : isListening && !isKeyEventAvailable
          ? 'Scanner is in test mode. Use the test button in the header or add items from the main search page.'
          : 'Scanner is disabled. Tap the scanner icon in the header to enable it.'
        }
      </Text>
    </View>
  );

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
          headerRight: () => (
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              {!isKeyEventAvailable && (
                <TouchableOpacity 
                  onPress={testBarcodeScan}
                  style={{ marginRight: 16 }}
                >
                  <Ionicons name="flask-outline" size={24} color="#FF6B35" />
                </TouchableOpacity>
              )}
              <TouchableOpacity onPress={() => setScannerActive(!scannerActive)}>
                <Ionicons 
                  name={scannerActive ? "scan" : "scan-outline"} 
                  size={24} 
                  color={scannerActive && isKeyEventAvailable ? "#007AFF" : "#666"} 
                />
              </TouchableOpacity>
            </View>
          ),
        }}
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
            paddingHorizontal: 16,
          }}
          style={{ marginBottom: 8 }}
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
      {(showCategoryDropdown || showVendorDropdown) && (
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
          }}
        />
      )}

      {showCategoryDropdown && (
        <View style={{
          position: 'absolute',
          top: 220, // Below the header section
          left: 16,
          right: 16,
          backgroundColor: '#fff',
          borderRadius: 8,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 2 },
          shadowOpacity: 0.15,
          shadowRadius: 4,
          elevation: 8,
          zIndex: 1000,
          maxHeight: 200,
        }}>
          <View style={{ padding: 12, borderBottomWidth: 1, borderBottomColor: '#f0f0f0' }}>
            <Text style={{ fontSize: 14, fontWeight: '600', color: '#333' }}>
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
          top: 220, // Below the header section
          left: 16,
          right: 16,
          backgroundColor: '#fff',
          borderRadius: 8,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 2 },
          shadowOpacity: 0.15,
          shadowRadius: 4,
          elevation: 8,
          zIndex: 1000,
          maxHeight: 200,
        }}>
          <View style={{ padding: 12, borderBottomWidth: 1, borderBottomColor: '#f0f0f0' }}>
            <Text style={{ fontSize: 14, fontWeight: '600', color: '#333' }}>
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

      {/* Reorder List */}
      <TouchableOpacity 
        style={reorderStyles.listContainer}
        activeOpacity={1}
        onPress={() => {
          // Close dropdowns when tapping on the list area
          setShowCategoryDropdown(false);
          setShowVendorDropdown(false);
        }}
      >
        {filteredAndSortedItems.length === 0 ? (
          renderEmptyState()
        ) : (
          <FlatList
            data={filteredAndSortedItems}
            renderItem={renderReorderItem}
            keyExtractor={(item) => item.id}
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingBottom: 20 }}
          />
        )}
      </TouchableOpacity>

      {/* Modals */}
      <QuantityModal
        visible={showQuantityModal}
        item={currentScannedItem}
        onSubmit={handleQuantitySubmit}
        onCancel={() => {
          setShowQuantityModal(false);
          setCurrentScannedItem(null);
        }}
        onDelete={() => {
          setShowQuantityModal(false);
          setCurrentScannedItem(null);
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
    </SafeAreaView>
  );
} 