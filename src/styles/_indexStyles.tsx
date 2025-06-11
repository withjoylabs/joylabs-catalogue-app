import { StyleSheet, Platform } from 'react-native';
import { lightTheme } from '../../src/themes';

export const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  mainContent: {
    flex: 1,
    // Removed marginBottom: 10, as the SearchBar in index.tsx might have different spacing needs
  },
  resultsContainer: {
    flexGrow: 1,
  },
  // Uncommented and activated styles for the bottom search bar
  searchBarContainer: {
    backgroundColor: '#f2f2f2',
    paddingHorizontal: 16,
    paddingVertical: 9,
    borderTopWidth: 1,
    borderTopColor: '#e1e1e1',
    flexDirection: 'row',
    alignItems: 'center',
  },
  searchInputWrapper: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingHorizontal: 12,
    alignItems: 'center',
    height: 44,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 1,
    elevation: 1,
    bottom: 5,
  },
  searchIcon: {
    marginRight: 4,
  },
  searchInput: {
    flex: 1,
    height: 44,
    fontSize: 16,
    color: '#333',
  },
  clearButton: {
    padding: 4,
  },
  externalClearTextButton: {
    paddingVertical: 8,
    paddingHorizontal: 12,
    marginRight: 8,
    borderRadius: 8,
    backgroundColor: '#e9ecef',
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
    bottom: 5,
  },
  externalClearTextButtonDisabled: {
    backgroundColor: '#f8f9fa',
    opacity: 0.6,
  },
  externalClearButtonText: {
    fontSize: 14,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },
  externalClearButtonTextDisabled: {
    color: '#adb5bd',
  },
  // End of uncommented styles
  resultItem: {
    flexDirection: 'row',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  resultNumberContainer: {
    width: 10,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 4,
  },
  resultNumberText: {
    fontSize: 12,
    color: '#888',
    fontWeight: '500',
  },
  // resultIconContainer: { // Commented out as it's replaced by resultNumberContainer
  //   width: 40,
  //   alignItems: 'center',
  //   justifyContent: 'center',
  // },
  resultDetails: {
    flex: 1,
    paddingHorizontal: 8,
  },
  resultName: {
    fontSize: 16,
    fontWeight: '500',
    marginBottom: 4,
  },
  resultMeta: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
  },
  resultSku: {
    fontSize: 12,
    color: '#666',
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 6,
    marginBottom: 2,
  },
  resultCategory: {
    fontSize: 12,
    color: '#666',
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 6,
    marginBottom: 2,
  },
  resultBarcode: {
    fontSize: 12,
    color: '#666',
    marginRight: 6,
  },
  resultPrice: {
    minWidth: 80,
    alignItems: 'flex-end',
    flexDirection: 'row',
    justifyContent: 'flex-end',
  },
  priceText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    marginRight: 4,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'flex-start',
    alignItems: 'center',
    padding: 32,
    marginTop: 100, // Keep a top margin for the empty state when results are above
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '500',
    color: '#888',
    marginTop: 16,
    marginBottom: 8,
  },
  emptyText: {
    fontSize: 14,
    color: '#999',
    textAlign: 'center',
  },
  searchingText: {
    fontSize: 16,
    color: '#777',
    marginTop: 16,
  },
  filterContainer: {
    flexDirection: 'row',
    // Removed justifyContent: 'space-around', as it's now part of a flex item
    // Removed paddingVertical and paddingHorizontal, handled by inner/outer containers
    // Removed backgroundColor, borderBottomWidth, borderBottomColor
    alignItems: 'center', // Align filter buttons nicely in their group
  },
  filterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    backgroundColor: lightTheme.colors.background,
    marginRight: 6, // Space between filter buttons
  },
  filterButtonActive: {
    backgroundColor: lightTheme.colors.primary,
    borderColor: lightTheme.colors.primary,
  },
  filterButtonText: {
    fontSize: 13,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },
  filterButtonTextActive: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
  filterBadgesContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingVertical: 0,
    // No paddingHorizontal here, it's in resultsContainer
  },
  filterBadge: {
    backgroundColor: lightTheme.colors.secondary + '20', // 20% opacity
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    marginRight: 6,
    marginBottom: 4,
  },
  filterBadgeText: {
    fontSize: 13,
    color: lightTheme.colors.secondary,
    fontWeight: '500',
  },
  // Styles from original index.tsx for history button, loading overlay, etc. can be merged or added here if needed.
  // For now, keeping them separate in index.tsx or ensuring they don't conflict.
  historyButtonContainer: { // Copied from index.tsx for reference, ensure it's styled correctly in index.tsx
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  historyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
    backgroundColor: lightTheme.colors.background, 
    borderRadius: 8,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
  },
  historyButtonText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.primary,
  },
  // Added from original index.tsx StyleSheet
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 10, // Ensure it's above other content
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#555',
  },
  // New Styles for FilterAndSortControls and Sorting
  controlsContainer: {
    paddingBottom: Platform.OS === 'ios' ? 0 : 0, 
    backgroundColor: lightTheme.colors.background, 
    borderTopWidth: 1,
    borderTopColor: lightTheme.colors.border,
    paddingHorizontal: 10, // Add horizontal padding to the main controls container
  },
  filterAndSortInnerContainer: { // New style for row layout
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 6, // Vertical padding for the inner content
  },
  // Styles for the new sort cycle button
  sortCycleButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 10,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    backgroundColor: lightTheme.colors.background,
  },
  sortCycleButtonText: {
    fontSize: 13,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },
  // Styles for the new Category Filter Button
  categoryFilterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
    paddingHorizontal: 10,
    backgroundColor: '#e9ecef', // A light grey, adjust as needed
    borderRadius: 16,
    marginTop: 6, // Space above this button
    // Remove marginHorizontal if it's now part of a flex container
  },
  categoryFilterButtonText: {
    fontSize: 13,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },

  // NEW Styles for inline category filter button
  categoryFilterButtonInline: {
    flexDirection: 'row',
    alignItems: 'center',
  },

  // Styles for Category Modal
  categoryModalContainer: {
    flex: 1,
    justifyContent: 'flex-start',
    backgroundColor: 'rgba(0,0,0,0.5)',
    paddingTop: Platform.OS === 'ios' ? 60 : 40,
  },
  categoryModalContent: {
    backgroundColor: 'white',
    borderRadius: 20,
    padding: 20,
    marginHorizontal: 20,
    maxHeight: '85%',
    elevation: 5,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
  },
  categoryModalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 15,
    textAlign: 'center',
  },
  categoryModalItem: {
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  categoryModalItemText: {
    fontSize: 16,
  },
  categoryModalItemTextSelected: {
    color: lightTheme.colors.primary,
    fontWeight: '600',
  },
  categoryModalSearchInput: {
    height: 44,
    borderColor: lightTheme.colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
    marginBottom: 10, // Space above the footer buttons
    backgroundColor: '#f8f8f8',
  },
  categoryModalEmpty: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  categoryModalEmptyText: {
    fontSize: 14,
    color: '#888',
  },
  categoryModalFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 10, // Space above the footer
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  categoryModalButton: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: 8,
    alignItems: 'center',
    flex: 1, // Make buttons take equal width
  },
  categoryModalCloseButton: {
    backgroundColor: lightTheme.colors.primary,
    marginLeft: 5, // Space between clear and close
  },
  categoryModalClearButton: {
    backgroundColor: lightTheme.colors.secondary + '20', // Light secondary for clear
    marginRight: 5, // Space between clear and close
  },
  categoryModalButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '500',
  },
  categoryModalClearButtonText: {
    color: lightTheme.colors.secondary, // Darker text for the light clear button
  },
  // Styles for "Create New Item" buttons
  createItemButtonsContainer: {
    marginTop: 16,
    width: '100%',
    alignItems: 'center',
  },
  createItemButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 10,
    paddingHorizontal: 20,
    borderRadius: 8,
    marginBottom: 8,
    width: '80%', // Adjust width as needed
    alignItems: 'center',
  },
  createItemButtonText: {
    color: 'white',
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
  },
  // Styles for swipe-to-print action (LEFT swipe)
  swipePrintActionLeft: {
    justifyContent: 'center',
    alignItems: 'flex-start', // Align button to the left end of the swipe area
    // backgroundColor: 'pink', // For debugging reveal area
    // width: 100, // Define a fixed width for the action button container
  },
  swipePrintButtonContainer: {
    backgroundColor: lightTheme.colors.primary, 
    paddingHorizontal: 20,
    paddingVertical: 10, 
    justifyContent: 'center',
    alignItems: 'center',
    height: '100%', 
    flexDirection: 'row',
    // width: 100, // Ensure this matches the width used in animation if fixed
  },
  swipePrintActionText: {
    color: '#fff',
    fontWeight: '600',
    marginLeft: 8,
    fontSize: 14,
  },
}); 