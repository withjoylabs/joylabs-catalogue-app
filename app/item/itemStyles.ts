import { StyleSheet } from 'react-native';
import { lightTheme } from '../../src/themes';

// Disable this file from being treated as a route
export const unstable_settings = {
  disableLayout: true,
}

// Export a default empty function to satisfy Expo Router requirements
export default function EmptyComponent() {
  return null;
}

export const styles = StyleSheet.create({
  // === Layout & Container Styles ===
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  content: {
    flex: 1,
    padding: 16,
  },
  fieldContainer: {
    marginBottom: 16,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },

  // === Typography Styles ===
  label: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#333',
  },
  subLabel: {
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 6,
    color: '#555',
  },
  helperText: {
    fontSize: 12,
    color: '#777',
    marginTop: 4,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#555',
  },
  errorText: {
    marginTop: 15,
    fontSize: 16,
    color: 'red',
    textAlign: 'center',
  },
  disabledText: {
    opacity: 0.5,
  },
  noItemsText: {
    fontSize: 14,
    color: '#777',
    fontStyle: 'italic',
    marginTop: 8,
  },
  sectionHeaderText: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    color: '#333',
  },
  modalItemText: {
    fontSize: 16,
    color: '#333',
  },
  modalItemSubText: {
    fontSize: 12,
    color: '#666',
    marginTop: 2,
  },
  highlightedText: {
    backgroundColor: 'rgba(0, 122, 255, 0.2)',
    color: '#007AFF',
  },
  
  // === Input Styles ===
  input: {
    height: 44,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
    backgroundColor: '#fff',
  },
  textArea: {
    height: 100,
    paddingTop: 10,
  },
  priceInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 44,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    backgroundColor: '#fff',
  },
  currencySymbol: {
    paddingHorizontal: 12,
    fontSize: 16,
    color: '#333',
  },
  priceInput: {
    flex: 1,
    height: '100%',
    fontSize: 16,
    paddingRight: 12,
  },
  searchInput: {
    height: 40,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
    backgroundColor: '#fff',
    marginBottom: 12,
  },
  
  // === Button Styles ===
  headerButton: {
    paddingHorizontal: 12,
  },
  headerButtonText: {
    fontSize: 16,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  saveButton: {
    color: lightTheme.colors.primary,
    fontWeight: '600',
  },
  errorButton: {
    marginTop: 20,
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: 8,
  },
  errorButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  closeButton: {
    marginTop: 12,
    backgroundColor: '#f2f2f2',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  closeButtonText: {
    color: '#333',
    fontSize: 16,
    fontWeight: '500',
  },
  selectorButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    height: 44,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    paddingHorizontal: 12,
    backgroundColor: '#fff',
  },
  selectorText: {
    fontSize: 16,
    color: '#333',
  },
  selectAllButton: {
    backgroundColor: '#f2f2f2',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 6,
    marginLeft: 'auto',
  },
  selectAllButtonSelected: {
    backgroundColor: 'rgba(0, 122, 255, 0.2)',
  },
  selectAllButtonText: {
    fontSize: 14,
    color: '#333',
  },
  selectAllButtonTextSelected: {
    color: lightTheme.colors.primary,
  },
  deleteButton: {
    backgroundColor: '#ff3b30',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginVertical: 16,
  },
  deleteButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  discardButton: {
    borderWidth: 1,
    borderColor: '#ff3b30',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginVertical: 8,
  },
  discardButtonText: {
    color: '#ff3b30',
    fontSize: 16,
    fontWeight: '600',
  },
  confirmButton: {
    backgroundColor: '#007AFF',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 16,
  },
  confirmButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  
  // === Modal Styles ===
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    width: '80%',
    maxHeight: '70%',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  variationModalContent: {
    width: '80%',
    maxHeight: '70%',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  confirmModalContent: {
    width: '80%',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 16,
    textAlign: 'center',
  },
  modalSeparator: {
    height: 1,
    backgroundColor: '#eee',
    marginVertical: 8,
  },
  modalItem: {
    paddingVertical: 12,
    paddingHorizontal: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#f2f2f2',
  },
  emptyListText: {
    padding: 20,
    textAlign: 'center',
    color: '#888',
  },
  
  // === Variation Styles ===
  variationContainer: {
    marginBottom: 16,
    padding: 12,
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 8,
    backgroundColor: '#f9f9f9',
  },
  variationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  variationHeaderButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  variationTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  removeVariationButton: {
    padding: 4,
    marginLeft: 8,
  },
  addVariationButton: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
    padding: 8,
  },
  addVariationText: {
    marginLeft: 6,
    fontSize: 16,
    color: lightTheme.colors.primary,
  },
  inlinePrintButton: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 6,
    backgroundColor: 'rgba(0, 122, 255, 0.1)',
    borderRadius: 6,
    alignSelf: 'flex-start',
  },
  inlinePrintIcon: {
    marginRight: 4,
  },
  inlinePrintButtonText: {
    color: lightTheme.colors.primary,
    fontSize: 13,
    fontWeight: '500',
  },
  
  // === Checkbox & Selection Styles ===
  checkboxContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
  },
  checkboxIcon: {
    marginRight: 8,
  },
  checkboxLabel: {
    fontSize: 16,
    color: '#333',
  },
  
  // === Recent Categories Styles ===
  recentCategoriesContainer: {
    marginTop: 8,
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
  },
  recentLabel: {
    fontSize: 14,
    color: '#666',
    marginRight: 8,
  },
  recentCategoryChip: {
    backgroundColor: '#f0f0f0',
    padding: 8,
    borderRadius: 20,
    marginRight: 8,
    marginBottom: 8,
  },
  recentCategoryChipText: {
    fontSize: 14,
    color: '#333',
  },
  
  // === Misc Styles ===
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 16,
    paddingTop: 0,
    backgroundColor: '#fff',
  },
  logo: {
    width: 100,
    height: 40,
    resizeMode: 'contain',
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  separator: {
    height: 1,
    backgroundColor: '#f2f2f2',
    marginVertical: 16,
  },
  imageContainer: {
    width: 100,
    height: 100,
    borderRadius: 8,
    backgroundColor: '#f2f2f2',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  itemImage: {
    width: '100%',
    height: '100%',
    borderRadius: 8,
  },
  placeholderText: {
    color: '#999',
    fontSize: 12,
  },
}); 