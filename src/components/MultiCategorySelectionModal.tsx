import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  FlatList,
  TextInput,
  TouchableWithoutFeedback,
  Pressable,
  Platform,
  KeyboardAvoidingView,
  Alert,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import logger from '../utils/logger';

interface CategoryItem {
  id: string;
  name: string;
}

interface MultiCategorySelectionModalProps {
  visible: boolean;
  onClose: () => void;
  availableCategories: CategoryItem[];
  selectedCategories: Array<{ id: string; name?: string; ordinal?: number }>;
  reportingCategoryId?: string;
  onSave: (selectedCategories: Array<{ id: string; ordinal?: number }>, reportingCategoryId: string) => void;
}

const MultiCategorySelectionModal: React.FC<MultiCategorySelectionModalProps> = ({
  visible,
  onClose,
  availableCategories,
  selectedCategories,
  reportingCategoryId,
  onSave,
}) => {
  const [localSelectedCategories, setLocalSelectedCategories] = useState<Set<string>>(new Set());
  const [localReportingCategoryId, setLocalReportingCategoryId] = useState<string>('');
  const [searchTerm, setSearchTerm] = useState('');
  const [validationError, setValidationError] = useState<string>('');
  const [isInitialized, setIsInitialized] = useState<boolean>(false);

  // Use ref to track reporting category for stable callbacks
  const reportingCategoryRef = useRef<string>('');

  // Initialize local state when modal opens - with async loading to prevent blocking
  useEffect(() => {
    if (visible) {
      setIsInitialized(false);
      // Use setTimeout to prevent blocking the main thread during initialization
      const initTimer = setTimeout(() => {
        const selectedIds = new Set<string>(selectedCategories.map(cat => cat.id));
        setLocalSelectedCategories(selectedIds);
        setLocalReportingCategoryId(reportingCategoryId || '');
        reportingCategoryRef.current = reportingCategoryId || ''; // Keep ref in sync
        setSearchTerm('');
        setValidationError('');
        setIsInitialized(true);
      }, 0);
      
      return () => clearTimeout(initTimer);
    } else {
      setIsInitialized(false);
    }
  }, [visible, selectedCategories, reportingCategoryId]);

  // Filter categories based on search term - optimized with early return
  const filteredCategories = useMemo(() => {
    if (!availableCategories?.length) return [];
    if (!searchTerm.trim()) return availableCategories;
    const lowerSearchTerm = searchTerm.toLowerCase().trim();
    return availableCategories.filter(category =>
      category.name?.toLowerCase().includes(lowerSearchTerm)
    );
  }, [availableCategories, searchTerm]);

  const handleReportingCategoryPress = useCallback((categoryId: string) => {
    setLocalReportingCategoryId(categoryId);
    reportingCategoryRef.current = categoryId; // Keep ref in sync
    // Automatically add to subcategories if not already selected
    setLocalSelectedCategories(prev => {
      if (prev.has(categoryId)) return prev;
      return new Set([...prev, categoryId]);
    });
    setValidationError('');
  }, []);

  const handleSubcategoryPress = useCallback((categoryId: string) => {
    setLocalSelectedCategories(prev => {
      const newSet = new Set(prev);
      if (newSet.has(categoryId)) {
        // Check if this is the reporting category (use ref for stable callback)
        if (categoryId === reportingCategoryRef.current) {
          setValidationError('Cannot unselect the reporting category');
          return prev;
        }
        newSet.delete(categoryId);
      } else {
        newSet.add(categoryId);
      }
      return newSet;
    });
    setValidationError('');
  }, []); // No dependencies - fully stable callback

  const handleSave = useCallback(() => {
    // Validation
    if (!localReportingCategoryId) {
      setValidationError('Please select a reporting category');
      return;
    }

    if (localSelectedCategories.size === 0) {
      setValidationError('Please select at least one category');
      return;
    }

    // Ensure reporting category is in selected categories
    const finalSelectedCategories = new Set(localSelectedCategories);
    finalSelectedCategories.add(localReportingCategoryId);

    // Convert to array with ordinals
    const categoriesArray = Array.from(finalSelectedCategories).map((id, index) => ({
      id,
      ordinal: index + 1,
    }));

    onSave(categoriesArray, localReportingCategoryId);
    onClose();
  }, [localReportingCategoryId, localSelectedCategories, onSave, onClose]);

  const handleCancel = useCallback(() => {
    onClose();
  }, [onClose]);

  // Optimized category row component with minimal re-renders
  const CategoryRow = React.memo(({ item, isReporting, isSelected, onReportingPress, onSubcategoryPress }: {
    item: CategoryItem;
    isReporting: boolean;
    isSelected: boolean;
    onReportingPress: (id: string) => void;
    onSubcategoryPress: (id: string) => void;
  }) => (
    <View style={styles.tableRow}>
      {/* Category Name */}
      <View style={[styles.tableCell, styles.categoryNameColumn]}>
        <Text style={styles.categoryName} numberOfLines={2}>
          {item.name}
        </Text>
      </View>

      {/* Reporting Category Radio Button */}
      <View style={[styles.tableCell, styles.reportingColumn]}>
        <TouchableOpacity
          style={styles.radioButton}
          onPress={() => onReportingPress(item.id)}
          activeOpacity={0.7}
          hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
        >
          <View style={[styles.radioOuter, isReporting && styles.radioOuterSelected]}>
            {isReporting && <View style={styles.radioInner} />}
          </View>
        </TouchableOpacity>
      </View>

      {/* Subcategory Checkbox */}
      <View style={[styles.tableCell, styles.subcategoryColumn]}>
        <TouchableOpacity
          style={styles.checkbox}
          onPress={() => onSubcategoryPress(item.id)}
          activeOpacity={0.7}
          hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
        >
          <View style={[styles.checkboxOuter, isSelected && styles.checkboxOuterSelected]}>
            {isSelected && <Ionicons name="checkmark" size={14} color="white" />}
          </View>
        </TouchableOpacity>
      </View>
    </View>
  ));

  const renderCategoryRow = useCallback(({ item }: { item: CategoryItem }) => {
    const isReporting = item.id === localReportingCategoryId;
    const isSelected = localSelectedCategories.has(item.id);

    return (
      <CategoryRow
        item={item}
        isReporting={isReporting}
        isSelected={isSelected}
        onReportingPress={handleReportingCategoryPress}
        onSubcategoryPress={handleSubcategoryPress}
      />
    );
  }, [localSelectedCategories, localReportingCategoryId, handleReportingCategoryPress, handleSubcategoryPress]);

  // Render table header - memoized
  const renderHeader = useCallback(() => (
    <View style={styles.tableHeader}>
      <View style={[styles.tableHeaderCell, styles.categoryNameColumn]}>
        <Text style={[styles.tableHeaderText, { textAlign: 'left' }]}>Category Name</Text>
      </View>
      <View style={[styles.tableHeaderCell, styles.reportingColumn]}>
        <Text style={styles.tableHeaderText}>Reporting</Text>
      </View>
      <View style={[styles.tableHeaderCell, styles.subcategoryColumn]}>
        <Text style={styles.tableHeaderText}>Subcategory</Text>
      </View>
    </View>
  ), []);

  // Memoized empty component
  const renderEmptyComponent = useCallback(() => (
    <View style={styles.emptyState}>
      <Text style={styles.emptyText}>
        {searchTerm ? `No categories match "${searchTerm}"` : 'No categories available'}
      </Text>
    </View>
  ), [searchTerm]);

  // Memoized selected categories summary to prevent re-renders
  const selectedCategoriesSummary = useMemo(() => {
    if (!localReportingCategoryId && localSelectedCategories.size === 0) return null;
    
    const reportingCategory = availableCategories.find(cat => cat.id === localReportingCategoryId);
    const subcategoryIds = Array.from(localSelectedCategories).filter(id => id !== localReportingCategoryId);
    
    return {
      reportingCategory,
      subcategoryIds,
      subcategories: subcategoryIds.map(id => availableCategories.find(cat => cat.id === id)).filter(Boolean)
    };
  }, [localReportingCategoryId, localSelectedCategories, availableCategories]);

  return (
    <Modal
      animationType="fade"
      transparent={true}
      visible={visible}
      onRequestClose={handleCancel}
    >
      <TouchableWithoutFeedback onPress={handleCancel}>
        <View style={styles.modalContainer}>
          <KeyboardAvoidingView 
            behavior={Platform.OS === "ios" ? "padding" : "height"} 
            style={styles.keyboardAvoidingView}
            keyboardVerticalOffset={Platform.OS === "ios" ? 0 : 20}
          >
            <TouchableWithoutFeedback onPress={() => {}}>
              <View style={styles.modalContent}>
                {/* Title and Description */}
                <Text style={styles.modalTitle}>Select Categories</Text>
                <Text style={styles.modalDescription}>
                  Choose one reporting category and any additional subcategories.
                </Text>

                {/* Selected Categories Summary - Optimized horizontal layout */}
                {selectedCategoriesSummary && (
                  <View style={styles.selectedSummaryContainer}>
                    <View style={styles.selectedSummaryRow}>
                      {/* Reporting Category */}
                      {selectedCategoriesSummary.reportingCategory && (
                        <>
                          <Text style={styles.selectedSummaryLabel}>Reporting: </Text>
                          <View style={styles.reportingCategoryChip}>
                            <Text style={styles.reportingCategoryChipText}>
                              {selectedCategoriesSummary.reportingCategory.name}
                            </Text>
                          </View>
                        </>
                      )}
                      
                      {/* Subcategories - show all as individual chips */}
                      {selectedCategoriesSummary.subcategoryIds.length > 0 && (
                        <>
                          <Text style={styles.selectedSummaryLabel}>Sub: </Text>
                          {selectedCategoriesSummary.subcategories.map(category => (
                            <View key={category!.id} style={styles.subcategoryCategoryChip}>
                              <Text style={styles.subcategoryCategoryChipText}>
                                {category!.name}
                              </Text>
                            </View>
                          ))}
                        </>
                      )}
                    </View>
                  </View>
                )}

                {/* Validation Error */}
                {validationError && (
                  <View style={styles.validationError}>
                    <Text style={styles.validationErrorText}>{validationError}</Text>
                  </View>
                )}

                {/* Search Input */}
                <View style={styles.searchContainer}>
                  <TextInput
                    style={styles.searchInput}
                    placeholder="Search categories..."
                    placeholderTextColor="#999"
                    value={searchTerm}
                    onChangeText={setSearchTerm}
                    autoCapitalize="none"
                    autoCorrect={false}
                  />
                </View>

                {/* Category Table */}
                <View style={styles.tableContainer}>
                  {renderHeader()}
                  {!isInitialized ? (
                    <View style={styles.loadingContainer}>
                      <ActivityIndicator size="large" color={lightTheme.colors.primary} />
                      <Text style={styles.loadingText}>Loading categories...</Text>
                    </View>
                  ) : (
                    <FlatList
                      style={styles.tableList}
                      data={filteredCategories}
                      keyExtractor={(item) => item.id}
                      renderItem={renderCategoryRow}
                      ListEmptyComponent={renderEmptyComponent}
                      // Optimized performance settings like the main category modal
                      keyboardShouldPersistTaps="handled"
                      removeClippedSubviews={true}
                      maxToRenderPerBatch={20}
                      windowSize={10}
                      initialNumToRender={15}
                      updateCellsBatchingPeriod={50}
                      getItemLayout={(data, index) => ({
                        length: 44, // Fixed compact height for performance
                        offset: 44 * index,
                        index,
                      })}
                      scrollEventThrottle={1}
                      showsVerticalScrollIndicator={true}
                    />
                  )}
                </View>

                {/* Footer Buttons */}
                <View style={styles.buttonContainer}>
                  <TouchableOpacity 
                    style={[styles.button, styles.cancelButton]} 
                    onPress={handleCancel}
                  >
                    <Text style={styles.cancelButtonText}>Cancel</Text>
                  </TouchableOpacity>
                  <TouchableOpacity 
                    style={[styles.button, styles.saveButton, !localReportingCategoryId && styles.saveButtonDisabled]} 
                    onPress={handleSave}
                    disabled={!localReportingCategoryId}
                  >
                    <Text style={[styles.saveButtonText, !localReportingCategoryId && styles.saveButtonTextDisabled]}>
                      Save
                    </Text>
                  </TouchableOpacity>
                </View>
              </View>
            </TouchableWithoutFeedback>
          </KeyboardAvoidingView>
        </View>
      </TouchableWithoutFeedback>
    </Modal>
  );
};

const styles = StyleSheet.create({
  modalContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    padding: 20,
  },
  keyboardAvoidingView: {
    width: '100%',
    maxWidth: 600,
    height: '90%',
    justifyContent: 'center',
  },
  modalContent: {
    backgroundColor: 'white',
    borderRadius: 12,
    padding: 16,
    width: '100%',
    height: '100%',
    maxHeight: 700,
    flexDirection: 'column',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 4,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  modalDescription: {
    fontSize: 13,
    color: '#666',
    textAlign: 'center',
    marginBottom: 12,
    lineHeight: 18,
  },
  searchContainer: {
    marginBottom: 12,
  },
  searchInput: {
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    fontSize: 15,
    backgroundColor: 'white',
  },
  tableContainer: {
    flex: 1,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    backgroundColor: 'white',
    overflow: 'hidden',
    marginBottom: 12,
  },
  tableHeader: {
    flexDirection: 'row',
    backgroundColor: '#f8f9fa',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
    alignItems: 'center',
  },
  tableHeaderCell: {
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  tableHeaderText: {
    fontSize: 14,
    fontWeight: '600',
    color: lightTheme.colors.text,
    textAlign: 'center',
  },
  categoryNameColumn: {
    flex: 4,
    alignItems: 'flex-start',
  },
  reportingColumn: {
    flex: 1.5,
    alignItems: 'center',
  },
  subcategoryColumn: {
    flex: 1.5,
    alignItems: 'center',
  },
  tableList: {
    flex: 1,
    backgroundColor: 'white',
  },
  tableRow: {
    flexDirection: 'row',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
    alignItems: 'center',
    minHeight: 44,
    backgroundColor: 'white',
  },
  tableCell: {
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  categoryName: {
    fontSize: 15,
    color: lightTheme.colors.text,
    lineHeight: 20,
    textAlign: 'left',
  },
  radioButton: {
    padding: 4,
    alignItems: 'center',
    justifyContent: 'center',
    width: 44,
    height: 44,
    borderRadius: 22,
  },
  radioOuter: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#ddd',
    backgroundColor: 'white',
    justifyContent: 'center',
    alignItems: 'center',
  },
  radioOuterSelected: {
    borderColor: lightTheme.colors.primary,
  },
  radioInner: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: lightTheme.colors.primary,
  },
  checkbox: {
    padding: 4,
    alignItems: 'center',
    justifyContent: 'center',
    width: 44,
    height: 44,
    borderRadius: 8,
  },
  checkboxOuter: {
    width: 24,
    height: 24,
    borderRadius: 4,
    borderWidth: 2,
    borderColor: '#ddd',
    backgroundColor: 'white',
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkboxOuterSelected: {
    borderColor: lightTheme.colors.primary,
    backgroundColor: lightTheme.colors.primary,
  },
  buttonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: '#f0f0f0',
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginHorizontal: 4,
  },
  cancelButton: {
    backgroundColor: '#f8f9fa',
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
  },
  cancelButtonText: {
    color: lightTheme.colors.text,
    fontSize: 16,
    fontWeight: '500',
  },
  saveButton: {
    backgroundColor: lightTheme.colors.primary,
  },
  saveButtonDisabled: {
    backgroundColor: '#ddd',
  },
  saveButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  saveButtonTextDisabled: {
    color: '#999',
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
  },
  validationError: {
    backgroundColor: '#fff5f5',
    borderWidth: 1,
    borderColor: '#fed7d7',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
  },
  validationErrorText: {
    color: '#c53030',
    fontSize: 14,
    textAlign: 'center',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  selectedSummaryContainer: {
    marginBottom: 10,
  },
  selectedSummaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  selectedSummaryLabel: {
    fontSize: 14,
    fontWeight: '600',
    marginRight: 8,
    color: lightTheme.colors.text,
  },
  reportingCategoryChip: {
    padding: 4,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    borderRadius: 8,
    marginRight: 12,
  },
  reportingCategoryChipText: {
    fontSize: 14,
    color: lightTheme.colors.text,
  },
  subcategoryCategoryChip: {
    padding: 4,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    borderRadius: 8,
    marginRight: 4,
  },
  subcategoryCategoryChipText: {
    fontSize: 14,
    color: lightTheme.colors.text,
  },
});

export default MultiCategorySelectionModal; 