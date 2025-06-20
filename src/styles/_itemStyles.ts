import { StyleSheet, Platform } from 'react-native';
import { lightTheme } from '../../src/themes';

// Define interface for the styles
interface ItemStyles {
  container: any;
  modalBackground: any;
  modalOverlay: any;
  modalContentContainer: any;
  modalSafeArea: any;
  modalHeader: any;
  modalContent: any;
  grabberContainer: any;
  safeContent: any;
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
  inputWrapper: any;
  clearButton: any;
  textArea: any;
  priceInputContainer: any;
  currencySymbol: any;
  priceInput: any;
  helperText: any;
  selectorButton: any;
  selectorText: any;
  placeholderText: any;
  checkboxContainer: any;
  checkboxIcon: any;
  checkboxLabel: any;
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
  
  // Inline Location Picker
  inlineLocationListContainer: any;
  inlineLocationListItem: any;
  inlineLocationListItemText: any;
  
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

  // Fixed Footer Styles
  footerContainer: any;
  footerButton: any;
  footerButtonClose: any;
  footerButtonPrint: any;
  footerButtonSave: any;
  footerButtonSaveAndPrint: any;
  footerButtonIcon: any;
  footerButtonText: any;

  // Styles for Menu integration in footer
  footerMenuWrapper: any;
  footerButtonVisuals: any;

  // === Styles for Print Options Popover Modal ===
  printOptionsCenteredView: any;
  printOptionsModalView: any;
  printOptionsModalTitle: any;
  printOptionVariationBlock: any;
  printOptionVariationName: any;
  printOptionItem: any;
  printOptionItemIndent: any;
  printOptionText: any;
  printOptionDetailText: any;
  // === End Styles for Print Options Popover Modal ===

  // === Category Modal Styles (copied from _indexStyles for consistency) ===
  categoryModalContainer: any;
  categoryModalContent: any;
  categoryModalTitle: any;
  categoryModalSearchInput: any;
  categoryModalSearchInputWrapper: any;
  categoryModalItem: any;
  categoryModalItemText: any;
  categoryModalItemTextSelected: any;
  categoryModalEmpty: any;
  categoryModalEmptyText: any;
  categoryModalFooter: any;
  categoryModalButton: any;
  categoryModalClearButton: any;
  categoryModalCloseButton: any;
  categoryModalButtonText: any;
  categoryModalClearButtonText: any;
  categoryModalListContainer: any;

  grabber: any;

  modalTitle: any;

  teamDataSection: any;
  teamDataTitle: any;
  checkboxRow: any;
  logContainer: any;
  logItem: any;
  logText: any;
  logMeta: any;

  // History Auth Prompt Styles
  historyAuthPrompt: any;
  historyAuthPromptTitle: any;
  historyAuthPromptText: any;

  // Category Advanced Mode Styles
  categoryHeaderContainer: any;
  advancedToggle: any;
  advancedToggleText: any;
  categorySubtext: any;
}

// Export the styles with type safety
export const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  modalBackground: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
  },
  modalContentContainer: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    marginTop: 60,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: -2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 10,
  },
  modalSafeArea: {
    flex: 1,
  },
  modalHeader: {
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5E7',
  },
  modalContent: {
    backgroundColor: lightTheme.colors.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderTopWidth: 2,
    borderTopColor: '#D1D1D6',
    maxHeight: '90%',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: -2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 5,
  },
  grabberContainer: {
    alignItems: 'center',
    paddingVertical: 8,
  },
  safeContent: {
    flex: 1,
  },
  grabber: {
    width: 40,
    height: 5,
    borderRadius: 2.5,
    backgroundColor: '#D1D1D6',
    marginTop: 3,
    marginBottom: 3,
  },
  content: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
    padding: 16,
  },
  scrollContentContainer: {
    paddingBottom: 60, // Default, will be adjusted if footer is taller
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
  teamDataSection: {
    marginTop: 24,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
  },
  teamDataTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: lightTheme.colors.primary,
    marginBottom: 16,
    textAlign: 'center',
  },
  checkboxRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  logContainer: {
    marginTop: 16,
  },
  logItem: {
    backgroundColor: '#f9f9f9',
    borderRadius: 5,
    padding: 10,
    marginBottom: 8,
    borderLeftWidth: 3,
    borderLeftColor: lightTheme.colors.primary,
  },
  logText: {
    fontSize: 14,
    color: '#333',
  },
  logMeta: {
    fontSize: 12,
    color: '#777',
    marginTop: 4,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    backgroundColor: 'white',
  },
  input: {
    flex: 1,
    padding: 12,
    fontSize: 16,
  },
  clearButton: {
    padding: 8,
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
  selectorButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    padding: 12,
    backgroundColor: 'white',
    color: 'white',
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
    paddingVertical: 8,
    paddingHorizontal: 14,
    marginRight: 8,
    justifyContent: 'center',
    alignItems: 'center',
    height: 36,
  },
  recentCategoryChipText: {
    fontSize: 14,
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
    paddingVertical: 8,
    paddingHorizontal: 12,
    marginRight: 8,
    backgroundColor: '#EFEFEF',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#DDD',
  },
  inlinePrintIcon: {
    marginRight: 6,
  },
  inlinePrintButtonText: {
    fontSize: 15,
    fontWeight: '500',
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
    padding: 12,
    fontSize: 16,
  },
  priceOverrideLocationSelectorWrapper: { 
    flex: 1.2, 
    marginRight: 8,
    zIndex: 1,
  },
  priceOverrideLocationButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 5,
    paddingVertical: 12, 
    paddingHorizontal: 8,
    backgroundColor: 'white',
  },
  priceOverrideLocationText: {
    fontSize: 16,
    color: '#333',
  },
  priceOverrideLocationPlaceholder: {
    color: '#999',
    fontSize: 16,
  },
  noLocationsText: { 
    fontSize: 16,
    color: '#888',
    fontStyle: 'italic',
    paddingVertical: 10, 
  },
  removePriceOverrideButton: {
    padding: 5, 
  },
  
  // Inline Location Picker
  inlineLocationListContainer: {
    position: 'absolute',
    top: '100%',
    left: 0,
    right: 0,
    marginTop: 4,
    borderWidth: 1,
    borderColor: '#DDD',
    borderRadius: 8,
    backgroundColor: 'white',
    maxHeight: 180, // Restrict height for scrolling
    zIndex: 10, // Ensure it's on top of other elements
  },
  inlineLocationListItem: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#EEE',
  },
  inlineLocationListItemText: {
    fontSize: 16,
    color: '#333',
  },
  
  // Delete Button Container
  deleteButtonContainer: {
    marginTop: 20, // Added margin for spacing before a potential fixed footer
    marginBottom: 20, // Ensure space if this is the last scrollable item
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
    color: lightTheme.colors.text,
  },

  // Fixed Footer Styles
  footerContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 10,
    backgroundColor: lightTheme.colors.background,
    borderTopWidth: 1,
    borderTopColor: lightTheme.colors.border,
    // Position fixed at the bottom - handled by placing it outside ScrollView
  },
  footerButton: {
    flex: 1, // Distribute space among buttons
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 6,
    paddingHorizontal: 5,
    borderRadius: 5,
    marginHorizontal: 4, // Add some horizontal spacing between buttons
  },
  footerButtonClose: {
    // specific styles for close if needed
  },
  footerButtonPrint: {
    // specific styles for print if needed
  },
  footerButtonSave: {
    // specific styles for save if needed
  },
  footerButtonSaveAndPrint: {
    // specific styles for save & print if needed
  },
  footerButtonIcon: {
    marginBottom: 4,
  },
  footerButtonText: {
    fontSize: 12,
    fontWeight: '500',
    textAlign: 'center',
    color: lightTheme.colors.text, // Default text color
  },

  // Styles for Menu integration in footer
  footerMenuWrapper: {
    flex: 1,
    marginHorizontal: 4, // Matches footerButton margin
  },
  footerButtonVisuals: { // For the content inside MenuTrigger, making it look like a button
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 6,   // from footerButton
    paddingHorizontal: 5, // from footerButton
    borderRadius: 5,      // from footerButton
    // IMPORTANT: No flex: 1 here
  },

  // === Styles for Print Options Popover Modal ===
  printOptionsCenteredView: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.4)',
  },
  printOptionsModalView: {
    margin: 20,
    backgroundColor: lightTheme.colors.card, // Use theme color
    borderRadius: 12,
    padding: 20,
    alignItems: 'stretch',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
    width: '90%',
    maxHeight: '80%',
  },
  printOptionsModalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 15,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  printOptionVariationBlock: {
    marginBottom: 10,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
    paddingBottom: 10,
  },
  printOptionVariationName: { // For variation name when it has overrides
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 8,
  },
  printOptionItem: {
    paddingVertical: 12,
    paddingHorizontal: 8,
    backgroundColor: '#f0f0f0', // Fallback for backgroundOffset, ensure good contrast with modal bg
    borderRadius: 6,
    marginBottom: 5,
  },
  printOptionItemIndent: { // For location overrides, indented
    paddingVertical: 10,
    paddingHorizontal: 8,
    marginLeft: 15, 
    backgroundColor: '#f0f0f0', // Fallback for backgroundOffset
    borderRadius: 6,
    marginBottom: 5,
  },
  printOptionText: {
    fontSize: 15,
    fontWeight: '500',
    color: lightTheme.colors.primary, 
  },
  printOptionDetailText: {
    fontSize: 13,
    color: '#888',
    marginLeft: 10,
  },
  // === End Styles for Print Options Popover Modal ===

  // === Category Modal Styles (copied from _indexStyles for consistency) ===
  categoryModalContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
  },
  categoryModalContent: {
    width: '90%',
    maxWidth: 500,
    backgroundColor: 'white',
    borderRadius: 14,
    padding: 20,
    height: '75%',
    maxHeight: 600,
  },
  categoryModalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  categoryModalSearchInputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 44,
    borderColor: lightTheme.colors.border,
    borderWidth: 1,
    borderRadius: 8,
    backgroundColor: lightTheme.colors.background,
    marginBottom: 10,
  },
  categoryModalSearchInput: {
    flex: 1,
    paddingHorizontal: 12,
    fontSize: 16,
    color: lightTheme.colors.text,
  },
  categoryModalItem: {
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  categoryModalItemText: {
    fontSize: 16,
  },
  categoryModalItemTextSelected: {
    fontWeight: 'bold',
    color: lightTheme.colors.primary,
  },
  categoryModalEmpty: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  categoryModalEmptyText: {
    color: '#666',
  },
  categoryModalFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingTop: 10,
    marginTop: 10,
    borderTopWidth: 1,
    borderTopColor: lightTheme.colors.border,
  },
  categoryModalButton: {
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    flex: 1,
    alignItems: 'center',
  },
  categoryModalClearButton: {
    backgroundColor: '#e9ecef',
    marginRight: 10,
  },
  categoryModalCloseButton: {
    backgroundColor: lightTheme.colors.primary,
  },
  categoryModalButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: 'white',
  },
  categoryModalClearButtonText: {
    color: lightTheme.colors.text,
  },
  categoryModalListContainer: {
    flex: 1,
  },

  modalTitle: {
    fontSize: 20,
    fontWeight: '600',
    textAlign: 'center',
    marginBottom: 16,
  },

  // History Auth Prompt Styles
  historyAuthPrompt: {
    backgroundColor: '#f8f9fa',
    borderRadius: 8,
    padding: 16,
    marginVertical: 8,
    borderWidth: 1,
    borderColor: '#dee2e6',
    alignItems: 'center',
  },
  historyAuthPromptTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    marginBottom: 8,
    textAlign: 'center',
  },
  historyAuthPromptText: {
    fontSize: 14,
    color: '#6c757d',
    textAlign: 'center',
    lineHeight: 20,
  },

  // Category Advanced Mode Styles
  categoryHeaderContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  advancedToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    backgroundColor: lightTheme.colors.primary + '15',
  },
  advancedToggleText: {
    fontSize: 12,
    color: lightTheme.colors.primary,
    fontWeight: '500',
    marginRight: 4,
  },
  categorySubtext: {
    fontSize: 12,
    color: '#666',
    fontStyle: 'italic',
    marginTop: 4,
  },
}) as unknown as ItemStyles; // Ensures stricter type checking by TypeScript
