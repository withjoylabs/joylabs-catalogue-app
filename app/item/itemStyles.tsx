import { StyleSheet } from 'react-native';
import { lightTheme } from '../../src/themes';

// Define interface for the styles
interface ItemStyles {
  container: any;
  content: any;
  fieldContainer: any;
  loadingContainer: any;
  loadingText: any;
  errorContainer: any;
  errorText: any;
  errorButton: any;
  errorButtonText: any;
  label: any;
  subLabel: any;
  sectionHeaderText: any;
  input: any;
  textArea: any;
  priceInputContainer: any;
  currencySymbol: any;
  priceInput: any;
  helperText: any;
  uploadButton: any;
  uploadButtonText: any;
  selectorButton: any;
  selectorText: any;
  placeholderText: any;
  checkboxContainer: any;
  checkboxIcon: any;
  checkboxLabel: any;
  headerButton: any;
  headerButtonText: any;
  disabledText: any;
  bottomButtonsContainer: any;
  deleteButton: any;
  deleteButtonText: any;
  recentCategoriesContainer: any;
  recentLabel: any;
  recentCategoryChip: any;
  recentCategoryChipText: any;
  variationContainer: any;
  variationHeader: any;
  variationTitle: any;
  variationHeaderButtons: any;
  inlinePrintButton: any;
  inlinePrintIcon: any;
  inlinePrintButtonText: any;
  removeVariationButton: any;
  addVariationButton: any;
  addVariationText: any;
  sectionHeader: any;
  selectAllButton: any;
  selectAllButtonSelected: any;
  selectAllButtonText: any;
  selectAllButtonTextSelected: any;
  noItemsText: any;
  highlightedText: any;
  priceOverridesContainer: any;
  priceOverrideHeader: any;
  addPriceOverrideButton: any;
  addPriceOverrideButtonText: any;
  priceOverrideRow: any;
  priceOverrideInputContainer: any;
  priceOverrideInput: any;
  locationSelectorContainer: any;
  locationSelector: any;
  locationSelectorText: any;
  noLocationsText: any;
  removeOverrideButton: any;
}

// Export the styles with type safety
export const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  content: {
    flex: 1,
    padding: 16,
  },
  fieldContainer: {
    marginBottom: 20,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: lightTheme.colors.primary,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  errorText: {
    marginTop: 10,
    fontSize: 16,
    color: 'red',
    textAlign: 'center',
    marginBottom: 20,
  },
  errorButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 5,
  },
  errorButtonText: {
    color: 'white',
    fontSize: 16,
  },
  label: {
    fontSize: 16,
    fontWeight: '500',
    marginBottom: 8,
    color: '#333',
  },
  subLabel: {
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 8,
    color: '#555',
  },
  sectionHeaderText: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    color: '#333',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    padding: 12,
    fontSize: 16,
    backgroundColor: 'white',
  },
  textArea: {
    height: 100,
    textAlignVertical: 'top',
  },
  priceInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    backgroundColor: 'white',
    paddingLeft: 10,
  },
  currencySymbol: {
    fontSize: 16,
    color: '#333',
  },
  priceInput: {
    flex: 1,
    padding: 12,
    fontSize: 16,
  },
  helperText: {
    fontSize: 12,
    color: '#777',
    marginTop: 4,
  },
  uploadButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: lightTheme.colors.primary,
    borderRadius: 5,
    padding: 10,
    marginTop: 10,
  },
  uploadButtonText: {
    color: lightTheme.colors.primary,
    fontSize: 16,
    marginLeft: 8,
  },
  
  selectorButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    padding: 12,
    backgroundColor: 'white',
  },
  selectorText: {
    fontSize: 16,
    color: '#333',
  },
  placeholderText: {
    color: '#999',
  },
  
  checkboxContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  checkboxIcon: {
    marginRight: 8,
  },
  checkboxLabel: {
    fontSize: 16,
    color: '#333',
  },
  
  headerButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  headerButtonText: {
    fontSize: 16,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  disabledText: {
    opacity: 0.5,
  },
  
  bottomButtonsContainer: {
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: '#eee',
    backgroundColor: 'white',
  },
  deleteButton: {
    backgroundColor: '#ff3b30',
    padding: 12,
    borderRadius: 5,
    alignItems: 'center',
    marginTop: 10,
  },
  deleteButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
  },
  
  // Category Selection styles
  recentCategoriesContainer: {
    marginTop: 10,
  },
  recentLabel: {
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 8,
    color: '#666',
  },
  recentCategoryChip: {
    backgroundColor: '#f0f0f0',
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginRight: 8,
    marginBottom: 8,
  },
  recentCategoryChipText: {
    fontSize: 14,
    color: '#333',
  },
  
  // Variation related styles
  variationContainer: {
    backgroundColor: '#f8f8f8',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#eee',
  },
  variationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  variationTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  variationHeaderButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  inlinePrintButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'transparent',
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 4,
    marginRight: 8,
  },
  inlinePrintIcon: {
    marginRight: 4,
  },
  inlinePrintButtonText: {
    fontSize: 14,
    color: lightTheme.colors.primary,
  },
  removeVariationButton: {
    padding: 4,
  },
  addVariationButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 4,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: lightTheme.colors.primary,
  },
  addVariationText: {
    fontSize: 14,
    color: lightTheme.colors.primary,
    marginLeft: 4,
  },
  
  // Section header styles
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  selectAllButton: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: lightTheme.colors.primary,
  },
  selectAllButtonSelected: {
    backgroundColor: lightTheme.colors.primary,
  },
  selectAllButtonText: {
    fontSize: 12,
    color: lightTheme.colors.primary,
  },
  selectAllButtonTextSelected: {
    color: 'white',
  },
  
  noItemsText: {
    fontSize: 14,
    fontStyle: 'italic',
    color: '#999',
    textAlign: 'center',
    padding: 12,
  },
  
  highlightedText: {
    backgroundColor: '#FFFF99',
    fontWeight: 'bold',
  },
  
  // Price Override styles - FIXED AND IMPROVED
  priceOverridesContainer: {
    marginTop: 16,
    marginBottom: 8,
    borderTopWidth: 1,
    borderTopColor: '#eeeeee',
    paddingTop: 12,
  },
  priceOverrideHeader: {
    flexDirection: 'row',
    justifyContent: 'flex-start',
    marginBottom: 12,
    alignItems: 'center',
  },
  addPriceOverrideButton: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#f0f8ff',
    borderWidth: 1,
    borderColor: lightTheme.colors.primary,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 1,
    elevation: 1,
  },
  addPriceOverrideButtonText: {
    color: lightTheme.colors.primary,
    fontSize: 14,
    fontWeight: '500',
  },
  priceOverrideRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
    backgroundColor: '#fafafa',
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 6,
    padding: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 1,
    elevation: 1,
  },
  priceOverrideInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    width: 100,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 4,
    backgroundColor: 'white',
    paddingHorizontal: 8,
    marginRight: 10,
    height: 40,
  },
  priceOverrideInput: {
    flex: 1,
    height: 38,
    paddingHorizontal: 4,
    fontSize: 14,
  },
  locationSelectorContainer: {
    flex: 1,
    height: 40,
  },
  locationSelector: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    backgroundColor: 'white',
    borderRadius: 4,
    paddingHorizontal: 10,
    paddingVertical: 0,
    height: 40,
  },
  locationSelectorText: {
    fontSize: 14,
    color: '#333',
  },
  noLocationsText: {
    fontSize: 14,
    color: '#999',
    fontStyle: 'italic',
    padding: 10,
  },
  removeOverrideButton: {
    padding: 8,
    marginLeft: 8,
    backgroundColor: '#fff5f5',
    borderRadius: 20,
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
}) as ItemStyles; 