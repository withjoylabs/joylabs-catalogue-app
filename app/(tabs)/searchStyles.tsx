import { StyleSheet, Platform } from 'react-native';
import { lightTheme } from '../../src/themes';

export const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  mainContent: {
    flex: 1,
    marginBottom: 10,
  },
  resultsContainer: {
    flexGrow: 1,
    paddingHorizontal: 16,
  },
  searchBarContainer: {
    backgroundColor: '#f2f2f2',
    paddingHorizontal: 16,
    paddingVertical: 9,
    paddingBottom: 2,
    height: 70,
    borderTopWidth: 1,
    borderTopColor: '#e1e1e1',
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
  searchInputWrapper: {
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
  },
  searchIcon: {
    marginRight: 8,
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
  resultItem: {
    flexDirection: 'row',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
    alignItems: 'center',
  },
  resultIconContainer: {
    width: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
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
    marginTop:100,
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
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: '#f9f9f9',
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  filterButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    backgroundColor: '#eee',
    marginRight: 8,
  },
  filterButtonActive: {
    backgroundColor: lightTheme.colors.primary,
  },
  filterButtonText: {
    fontSize: 13,
    color: '#666',
  },
  filterButtonTextActive: {
    color: '#fff',
  },
  filterBadgesContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingVertical: 8,
  },
  filterBadge: {
    backgroundColor: lightTheme.colors.secondary + '20', // 20% opacity
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    marginRight: 6,
    marginBottom: 6,
  },
  filterBadgeText: {
    fontSize: 12,
    color: lightTheme.colors.secondary,
    fontWeight: '500',
  },
}); 