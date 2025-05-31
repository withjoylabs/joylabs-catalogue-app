import { StyleSheet, Platform } from 'react-native';
import { lightTheme } from '../../src/themes';

// Define interface for the styles
interface ItemStyles {
  container: any;
  content: any;
  scrollContentContainer: any;
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
  headerButton: any; // General header button, if used elsewhere
  headerButtonText: any; // General header button text
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
  
  // Custom Modal Header Styles
  customHeaderContainer: any;
  customHeaderLeftActions: any;
  customHeaderTitleWrapper: any;
  customHeaderTitle: any;
  customHeaderButton: any; // Specifically for modal header buttons
  customHeaderButtonText: any; // Specifically for modal header button text
  customHeaderRightActions: any;
  customHeaderSaveButton: any;
  customHeaderSaveButtonText: any;
  customHeaderTitleContainer: any;
  customHeaderSubtitle: any;

  // Price Overrides Styles
  priceOverridesContainer: any;
  priceOverrideHeader: any;
  addPriceOverrideButton: any;
  addPriceOverrideButtonText: any;
  priceOverrideItemContainer: any;
  priceOverrideInputWrapper: any;
  priceOverrideInput: any;
  priceOverrideLocationSelectorWrapper: any;
  priceOverrideLocationButton: any;
  priceOverrideLocationText: any;
  priceOverrideLocationPlaceholder: any;
  noLocationsText: any;
  removePriceOverrideButton: any;
  
  // Legacy/Unused (can be removed if definitely not needed)
  locationSelectorContainer: any; 
  locationSelector: any;
  locationSelectorText: any;
  removeOverrideButton: any; 
  priceOverrideRow: any;

  // Delete Button Container
  deleteButtonContainer: any;

  // Modal Styles (for cancel confirmation)
  centeredView: any;
  modalView: any;
  modalText: any;
  modalButtonsContainer: any;
  modalButton: any;
  modalButtonPrimary: any;
  modalButtonSecondary: any;
  modalButtonText: any;
  modalButtonTextPrimary: any;
  modalButtonTextSecondary: any;
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
  scrollContentContainer: {
    paddingBottom: 100, 
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
    marginRight: 4,
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
  headerButton: { // General, if used elsewhere
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  headerButtonText: { // General, if used elsewhere
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#ff3b30',
    padding: 12,
    borderRadius: 5,
    marginTop: 10,
  },
  deleteButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
    marginLeft: 8,
  },
  recentCategoriesContainer: {
    marginTop: 10,
  },
  recentLabel: {
    fontSize: 13,
    color: '#555',
    marginBottom: 5,
  },
  recentCategoryChip: {
    backgroundColor: '#e9e9e9',
    borderRadius: 15,
    paddingVertical: 6,
    paddingHorizontal: 12,
    marginRight: 8,
  },
  recentCategoryChipText: {
    fontSize: 13,
    color: '#333',
  },
  variationContainer: {
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
    backgroundColor: '#f9f9f9',
  },
  variationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  variationTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#444',
  },
  variationHeaderButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  inlinePrintButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 4,
    paddingHorizontal: 8,
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
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderColor: lightTheme.colors.primary,
    borderStyle: 'dashed',
    borderRadius: 5,
    marginTop: 8,
  },
  addVariationText: {
    marginLeft: 8,
    fontSize: 16,
    color: lightTheme.colors.primary,
  },
  sectionHeader: { 
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8, 
  },
  selectAllButton: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 5,
    borderWidth: 1,
    borderColor: lightTheme.colors.primary,
  },
  selectAllButtonSelected: {
    backgroundColor: lightTheme.colors.primary,
  },
  selectAllButtonText: {
    fontSize: 13,
    color: lightTheme.colors.primary,
  },
  selectAllButtonTextSelected: {
    color: 'white',
  },
  noItemsText: {
    fontSize: 14,
    color: '#777',
    fontStyle: 'italic',
    textAlign: 'center',
    marginTop: 10,
  },
  highlightedText: {
    fontWeight: 'bold',
    backgroundColor: lightTheme.colors.secondary, 
    color: 'white',
  },
  
  // Custom Modal Header Styles
  customHeaderContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '100%',
    paddingHorizontal: 0,
    height: Platform.OS === 'ios' ? 44 : 56,
  },
  customHeaderLeftActions: {
    justifyContent: 'flex-start',
  },
  customHeaderTitleWrapper: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  customHeaderTitleContainer: {
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    flex: 1,
  },
  customHeaderTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: lightTheme.colors.text,
    textAlign: 'center',
  },
  customHeaderSubtitle: {
    fontSize: 12,
    color: lightTheme.colors.border,
    textAlign: 'center',
    marginTop: 2,
  },
  customHeaderButton: {
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  customHeaderButtonText: { 
    fontSize: 17,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  customHeaderRightActions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
  },
  customHeaderSaveButton: { 
    marginLeft: 10,
  },
  customHeaderSaveButtonText: { 
    fontWeight: '600',
    fontSize: 17,
    color: lightTheme.colors.primary, 
  },

  // Price Overrides Styles
  priceOverridesContainer: { 
    marginTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#eeeeee',
    paddingTop: 10,
  },
  priceOverrideHeader: { 
    fontSize: 14,
    fontWeight: '600',
    color: '#555',
    marginBottom: 8,
  },
  addPriceOverrideButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
    paddingHorizontal: 10,
    backgroundColor: lightTheme.colors.secondary, 
    borderRadius: 5,
    alignSelf: 'flex-start', 
  },
  addPriceOverrideButtonText: {
    fontSize: 14,
    color: 'white', 
    marginLeft: 4,
  },
  priceOverrideItemContainer: { 
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    paddingVertical: 4,
  },
  priceOverrideInputWrapper: { 
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    backgroundColor: 'white',
    paddingLeft: 8,
    flex: 1, 
    marginRight: 8,
  },
  priceOverrideInput: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 6,
    fontSize: 15,
  },
  priceOverrideLocationSelectorWrapper: { 
    flex: 1.2, 
    marginRight: 8,
  },
  priceOverrideLocationButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    paddingVertical: 10, 
    paddingHorizontal: 8,
    backgroundColor: 'white',
  },
  priceOverrideLocationText: {
    fontSize: 15,
    color: '#333',
  },
  priceOverrideLocationPlaceholder: {
    color: '#999',
  },
  noLocationsText: { 
    fontSize: 14,
    color: '#888',
    fontStyle: 'italic',
    paddingVertical: 10, 
  },
  removePriceOverrideButton: {
    padding: 5, 
  },
  
  // Legacy/Unused (can be removed if not needed after verification)
  locationSelectorContainer: {}, 
  locationSelector: {},
  locationSelectorText: {},
  removeOverrideButton: {}, 
  priceOverrideRow: {},

  // Delete Button Container
  deleteButtonContainer: { 
    marginTop: 20,
  },

  // Modal Styles (for cancel confirmation)
  centeredView: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.4)', 
  },
  modalView: {
    margin: 20,
    backgroundColor: 'white',
    borderRadius: 10,
    padding: 25,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
    width: '85%',
  },
  modalText: {
    marginBottom: 20,
    textAlign: 'center',
    fontSize: 17,
    lineHeight: 24,
  },
  modalButtonsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between', 
    width: '100%',
  },
  modalButton: {
    borderRadius: 5,
    paddingVertical: 12,
    paddingHorizontal: 10,
    elevation: 2,
    flex: 1, 
    marginHorizontal: 5, 
    alignItems: 'center', 
  },
  modalButtonPrimary: {
    backgroundColor: lightTheme.colors.primary,
  },
  modalButtonSecondary: {
    backgroundColor: '#e0e0e0', 
  },
  modalButtonText: {
    fontWeight: 'bold',
    textAlign: 'center',
    fontSize: 15,
  },
  modalButtonTextPrimary: {
    color: 'white',
  },
  modalButtonTextSecondary: {
    color: '#333', 
  },
}) as unknown as ItemStyles; // Ensures stricter type checking by TypeScript
