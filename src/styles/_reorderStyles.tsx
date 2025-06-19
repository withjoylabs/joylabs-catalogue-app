import { StyleSheet, Dimensions } from 'react-native';

const { width, height } = Dimensions.get('window');

export const reorderStyles = StyleSheet.create({
  // Main container styles
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  
  // Header and filter section
  headerSection: {
    backgroundColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
    overflow: 'visible',
  },
  
  filterContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  
  filterButtonContainer: {
    position: 'relative',
    marginRight: 8,
    overflow: 'visible',
  },
  
  filterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f0f0f0',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  
  filterButtonActive: {
    backgroundColor: '#007AFF',
  },
  
  filterButtonText: {
    fontSize: 14,
    color: '#333',
    marginLeft: 4,
  },
  
  filterButtonTextActive: {
    color: '#fff',
  },
  
  // Stats section
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: 8,
    backgroundColor: '#f8f8f8',
    marginBottom: 12,
  },
  
  statItem: {
    alignItems: 'center',
  },
  
  statNumber: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#007AFF',
  },
  
  statLabel: {
    fontSize: 12,
    color: '#666',
    marginTop: 2,
  },
  
  // List styles
  listContainer: {
    flex: 1,
  },
  
  sectionHeader: {
    backgroundColor: '#f8f9fa',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
    marginTop: 8,
  },
  
  sectionHeaderText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  
  sectionHeaderCount: {
    fontSize: 12,
    fontWeight: '400',
    color: '#999',
    marginLeft: 8,
  },
  
  // Reorder item styles
  reorderItem: {
    backgroundColor: '#fff',
    marginHorizontal: 16,
    marginVertical: 4,
    borderRadius: 8,
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  
  reorderItemCompleted: {
    backgroundColor: '#f8f8f8',
    opacity: 0.7,
  },
  
  // Delete button for swipe action
  deleteButton: {
    backgroundColor: '#FF3B30',
    justifyContent: 'center',
    alignItems: 'center',
    width: 80,
    height: 60,
    borderRadius: 8,
  },
  
  deleteButtonInner: {
    flex: 1,
    width: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  
  indexContainer: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  
  indexContainerCompleted: {
    backgroundColor: '#4CAF50',
  },
  
  indexText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: 'bold',
  },
  
  indexTextCompleted: {
    textDecorationLine: 'line-through',
    color: '#999',
  },
  
  itemContent: {
    flex: 1,
  },
  
  itemHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 4,
  },
  
  itemName: {
    fontSize: 15,
    fontWeight: '600',
    color: '#333',
    flex: 1,
    marginRight: 8,
    lineHeight: 18,
  },
  
  itemNameCompleted: {
    textDecorationLine: 'line-through',
    color: '#999',
  },
  
  qtyBadge: {
    backgroundColor: '#FF6B35',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 12,
    minWidth: 24,
    alignItems: 'center',
  },
  
  qtyText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },


  
  itemDetails: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginBottom: 4,
  },
  
  detailItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 16,
    marginBottom: 2,
  },
  
  detailLabel: {
    fontSize: 12,
    color: '#666',
    marginRight: 4,
  },
  
  detailValue: {
    fontSize: 12,
    color: '#333',
    fontWeight: '500',
  },
  
  priceContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  
  priceItem: {
    alignItems: 'center',
  },
  
  priceLabel: {
    fontSize: 10,
    color: '#666',
  },
  
  priceValue: {
    fontSize: 12,
    fontWeight: '600',
    color: '#333',
  },
  
  wholesalePrice: {
    color: '#4CAF50',
  },
  
  timestamp: {
    fontSize: 10,
    color: '#999',
    marginTop: 4,
    textAlign: 'right',
  },
  
  // New styles for improved compact reorder item layout
  itemNameContainer: {
    flex: 1,
    marginRight: 12,
  },
  
  compactDetails: {
    fontSize: 11,
    color: '#666',
    marginTop: 2,
    lineHeight: 14,
  },
  
  // New meta styles matching index.tsx format
  itemMeta: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginTop: 4,
  },

  itemUpc: {
    fontSize: 12,
    color: '#666',
    marginRight: 6,
    marginBottom: 2,
  },

  itemCategory: {
    fontSize: 12,
    color: '#666',
    backgroundColor: '#f5f5f5',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 6,
    marginBottom: 2,
  },

  itemPrice: {
    fontSize: 12,
    color: '#666',
    marginRight: 6,
    marginBottom: 2,
  },

  itemCost: {
    fontSize: 12,
    color: '#666',
    marginRight: 6,
    marginBottom: 2,
  },

  itemVendor: {
    fontSize: 12,
    color: '#666',
    marginRight: 6,
    marginBottom: 2,
  },

  itemDiscontinued: {
    fontSize: 12,
    color: '#FF3B30',
    fontWeight: '600',
    marginRight: 6,
    marginBottom: 2,
  },
  
  qtyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 50,
    paddingHorizontal: 8,
  },
  
  qtyLabel: {
    fontSize: 10,
    fontWeight: '500',
    color: '#666',
    marginBottom: 2,
  },
  
  qtyNumber: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
    lineHeight: 28,
  },
  
  timestampContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 6,
    paddingTop: 6,
    borderTopWidth: 1,
    borderTopColor: '#f0f0f0',
  },
  
  addedBy: {
    fontSize: 10,
    color: '#999',
    fontStyle: 'italic',
  },
  
  // Legacy styles (keeping for compatibility)
  qtyBadgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  
  detailRow: {
    fontSize: 12,
    color: '#666',
    marginBottom: 2,
  },
  
  // Modal styles
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  
  modalContainer: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 24,
    width: width * 0.85,
    maxWidth: 400,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 8,
  },
  
  modalHeader: {
    alignItems: 'center',
    marginBottom: 20,
  },
  
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 8,
  },
  
  modalItemName: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
  },
  
  // Quantity input styles
  quantityContainer: {
    alignItems: 'center',
    marginBottom: 24,
  },
  
  quantityDisplay: {
    fontSize: 48,
    fontWeight: 'bold',
    color: '#007AFF',
    marginBottom: 16,
    minHeight: 60,
    textAlign: 'center',
  },
  
  keypadContainer: {
    width: '100%',
  },
  
  keypadRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  
  keypadButton: {
    width: '30%',
    height: 50,
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  
  keypadButtonText: {
    fontSize: 20,
    fontWeight: '600',
    color: '#333',
  },
  
  keypadButtonSpecial: {
    backgroundColor: '#FF6B35',
  },
  
  keypadButtonSpecialText: {
    color: '#fff',
  },
  
  // Modal action buttons
  modalActions: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  
  modalButton: {
    flex: 1,
    height: 44,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: 4,
  },
  
  modalButtonPrimary: {
    backgroundColor: '#007AFF',
  },
  
  modalButtonSecondary: {
    backgroundColor: '#f0f0f0',
  },
  
  modalButtonDanger: {
    backgroundColor: '#FF3B30',
  },
  
  modalButtonText: {
    fontSize: 16,
    fontWeight: '600',
  },
  
  modalButtonTextPrimary: {
    color: '#fff',
  },
  
  modalButtonTextSecondary: {
    color: '#333',
  },
  
  modalButtonTextDanger: {
    color: '#fff',
  },
  
  // Item selection modal (for multiple items with same barcode)
  selectionList: {
    maxHeight: 300,
    marginBottom: 20,
  },
  
  selectionItem: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  
  selectionItemLast: {
    borderBottomWidth: 0,
  },
  
  selectionItemName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  
  selectionItemDetails: {
    fontSize: 14,
    color: '#666',
  },
  
  // Empty state
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  
  emptyIcon: {
    marginBottom: 16,
  },
  
  emptyTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 8,
    textAlign: 'center',
  },
  
  emptySubtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    lineHeight: 22,
  },
  
  // Loading state
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  
  loadingText: {
    fontSize: 16,
    color: '#666',
    marginTop: 12,
  },
  
  // Dropdown styles
  dropdownContainer: {
    position: 'absolute',
    top: '100%',
    left: 0,
    right: 0,
    backgroundColor: '#fff',
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
    zIndex: 1000,
    maxHeight: 200,
  },
  
  dropdownList: {
    maxHeight: 200,
  },
  
  dropdownItem: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  
  dropdownItemText: {
    fontSize: 14,
    color: '#333',
  },
  
  dropdownItemTextSelected: {
    color: '#007AFF',
    fontWeight: '600',
  },
});
