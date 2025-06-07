import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { ScanHistoryItem } from '../types'; // Import ScanHistoryItem
import { ConvertedItem, CatalogCategoryData } from '../types/api'; // Import ConvertedItem and CatalogCategoryData
import logger from '../utils/logger'; // Import logger

// Product type definition
/*
export interface Product {
  id: string;
  name: string;
  description?: string;
  price: number;
  sku?: string;
  barcode?: string;
  stockQuantity?: number;
  isActive: boolean;
  category?: string;
  images: string[];
  lastScanned?: Date;
  createdAt: string;
  updatedAt: string;
}
*/

// Category type definition
export interface Category {
  id: string;
  name: string;
  description?: string;
  color: string;
  icon?: string;
  isActive: boolean;
  parentCategory?: string;
  createdAt: string;
  updatedAt: string;
}

// Main application state
interface AppState {
  // Products state
  products: ConvertedItem[];
  selectedProduct: ConvertedItem | null;
  isProductsLoading: boolean;
  productError: string | null;
  
  // Categories state
  categories: Category[];
  selectedCategory: Category | null;
  isCategoriesLoading: boolean;
  categoryError: string | null;
  
  // Search state
  searchQuery: string;
  sortBy: 'name' | 'price' | 'date' | 'category';
  sortOrder: 'asc' | 'desc';
  
  // Scan History state
  scanHistory: ScanHistoryItem[];
  adminScanHistory: ScanHistoryItem[]; // Full history for admin
  
  // Auto-search settings
  autoSearchOnEnter: boolean;
  autoSearchOnTab: boolean;
  itemSaveTriggeredAt: number | null;
  
  // Square Connection State
  isSquareConnected: boolean;
  
  // Label LIVE HTTP Settings
  labelLiveHost: string | null;
  labelLivePort: string | null;
  labelLivePrinter: string | null;
  labelLiveWindow: string | null;
  labelLiveFieldMap: {
    itemName: string | null;
    variationName: string | null;
    variationPrice: string | null;
    barcode: string | null;
  } | null;
  
  // Success Notification State
  showSuccessNotification: boolean;
  setShowSuccessNotification: (show: boolean) => void;
  successMessage: string;
  setSuccessMessage: (message: string) => void;
  
  // Recently updated item state
  lastUpdatedItem: ConvertedItem | null;
  setLastUpdatedItem: (item: ConvertedItem | null) => void;
  
  // Actions
  setProducts: (products: ConvertedItem[]) => void;
  setSelectedProduct: (product: ConvertedItem | null) => void;
  setProductsLoading: (isLoading: boolean) => void;
  setProductError: (error: string | null) => void;
  
  setCategories: (categories: Category[]) => void;
  setSelectedCategory: (category: Category | null) => void;
  setCategoriesLoading: (isLoading: boolean) => void;
  setCategoryError: (error: string | null) => void;
  
  setSearchQuery: (query: string) => void;
  setSortBy: (sortBy: 'name' | 'price' | 'date' | 'category') => void;
  setSortOrder: (sortOrder: 'asc' | 'desc') => void;
  
  // Scan History actions
  addScanHistoryItem: (item: ScanHistoryItem) => void;
  removeScanHistoryItem: (scanId: string) => void; // New action to remove items
  clearScanHistory: () => void;
  
  // Auto-search toggles
  toggleAutoSearchOnEnter: () => void;
  toggleAutoSearchOnTab: () => void;
  triggerItemSave: () => void;
  
  // Square Connection Action
  setSquareConnected: (isConnected: boolean) => void;

  // Label LIVE Actions
  setLabelLiveHost: (host: string) => void;
  setLabelLivePort: (port: string) => void;
  setLabelLivePrinter: (printer: string) => void;
  setLabelLiveWindow: (window: string) => void;
  setLabelLiveFieldMap: (map: AppState['labelLiveFieldMap']) => void;
  
  refreshProducts: () => Promise<void>;
  loadMoreProducts: () => Promise<void>;

  itemModalJustClosed: boolean;
  setItemModalJustClosed: (wasClosed: boolean) => void;
}

// Add the same helper function
const generateIdempotencyKey = () => {
  return `joylabs-${Date.now()}-${Math.random().toString(36).substring(2, 15)}`;
};

// Create store using zustand with persistence for scanHistory
export const useAppStore = create<AppState>()(
  persist(
    (set, get) => ({
      // Initial products state
      products: [],
      selectedProduct: null,
      isProductsLoading: false,
      productError: null,
      
      // Initial categories state
      categories: [],
      selectedCategory: null,
      isCategoriesLoading: false,
      categoryError: null,
      
      // Initial search/sort state
      searchQuery: '',
      sortBy: 'name',
      sortOrder: 'asc',
      
      // Initial scan history state
      scanHistory: [],
      adminScanHistory: [], // Initialize admin scan history
      
      // Auto-search defaults and toggles
      autoSearchOnEnter: true,
      autoSearchOnTab: false,
      itemSaveTriggeredAt: null,

      // Initial Square Connection state
      isSquareConnected: false,

      // Initial Label LIVE state
      labelLiveHost: null,
      labelLivePort: null,
      labelLivePrinter: null,
      labelLiveWindow: null,
      labelLiveFieldMap: null,
      
      // Success Notification State
      showSuccessNotification: false,
      setShowSuccessNotification: (show: boolean) => set({ showSuccessNotification: show }),
      successMessage: '',
      setSuccessMessage: (message: string) => set({ successMessage: message }),
      
      // Recently updated item
      lastUpdatedItem: null,
      setLastUpdatedItem: (item: ConvertedItem | null) => {
        set({ lastUpdatedItem: item });
      },
      
      // Products actions
      setProducts: (products: ConvertedItem[]) => set({ products }),
      setSelectedProduct: (selectedProduct: ConvertedItem | null) => set({ selectedProduct }),
      setProductsLoading: (isProductsLoading: boolean) => set({ isProductsLoading }),
      setProductError: (productError: string | null) => set({ productError }),
      
      // Categories actions
      setCategories: (categories: Category[]) => set({ categories }),
      setSelectedCategory: (selectedCategory: Category | null) => set({ selectedCategory }),
      setCategoriesLoading: (isCategoriesLoading: boolean) => set({ isCategoriesLoading }),
      setCategoryError: (categoryError: string | null) => set({ categoryError }),
      
      // Search/sort actions
      setSearchQuery: (searchQuery: string) => set({ searchQuery }),
      setSortBy: (sortBy: 'name' | 'price' | 'date' | 'category') => set({ sortBy }),
      setSortOrder: (sortOrder: 'asc' | 'desc') => set({ sortOrder }),
      
      // Scan History actions
      addScanHistoryItem: (item: ScanHistoryItem) => {
        set((state) => {
          // Prevent duplicates based on scanId, keep latest
          const existingIndex = state.scanHistory.findIndex(histItem => histItem.id === item.id); // Check by item ID
          let newHistory = [...state.scanHistory];
          if (existingIndex > -1) {
            // Remove the old entry if it exists
            newHistory.splice(existingIndex, 1);
          }
          // Add the new item to the beginning and limit history size (e.g., 100 items)
          newHistory = [item, ...newHistory].slice(0, 100);
          
          // Also update admin scan history
          const existingAdminIndex = state.adminScanHistory.findIndex(histItem => histItem.id === item.id);
          let newAdminHistory = [...state.adminScanHistory];
          if (existingAdminIndex > -1) {
            newAdminHistory.splice(existingAdminIndex, 1);
          }
          newAdminHistory = [item, ...newAdminHistory].slice(0, 500); // Allow more items in admin history
          
          return { 
            scanHistory: newHistory,
            adminScanHistory: newAdminHistory
          };
        });
      },
      
      // Remove item from visible history but keep in admin history
      removeScanHistoryItem: (scanId: string) => {
        set((state) => {
          const newHistory = state.scanHistory.filter(item => item.scanId !== scanId);
          return { scanHistory: newHistory };
        });
      },
      
      clearScanHistory: () => set({ scanHistory: [] }),
      
      // Auto-search toggles
      toggleAutoSearchOnEnter: () => set((state) => ({ autoSearchOnEnter: !state.autoSearchOnEnter })),
      toggleAutoSearchOnTab: () => set((state) => ({ autoSearchOnTab: !state.autoSearchOnTab })),
      triggerItemSave: () => set({ itemSaveTriggeredAt: Date.now() }),
      
      // Square Connection action implementation
      setSquareConnected: (isSquareConnected: boolean) => set({ isSquareConnected }),

      // Label LIVE action implementations
      setLabelLiveHost: (labelLiveHost: string) => set({ labelLiveHost }),
      setLabelLivePort: (labelLivePort: string) => set({ labelLivePort }),
      setLabelLivePrinter: (labelLivePrinter: string) => set({ labelLivePrinter }),
      setLabelLiveWindow: (labelLiveWindow: string) => set({ labelLiveWindow }),
      setLabelLiveFieldMap: (labelLiveFieldMap: AppState['labelLiveFieldMap']) => set({ labelLiveFieldMap }),

      // Add placeholders for missing actions
      refreshProducts: async () => { console.warn('refreshProducts not implemented in store'); },
      loadMoreProducts: async () => { console.warn('loadMoreProducts not implemented in store'); },
      
      itemModalJustClosed: false,
      setItemModalJustClosed: (wasClosed: boolean) => set({ itemModalJustClosed: wasClosed }),
      
      // ... rest of the store implementation ...
    }),
    {
      name: 'app-storage', // AsyncStorage key
      storage: createJSONStorage(() => AsyncStorage),
      // Only persist a subset of the state
      partialize: (state) =>
        Object.fromEntries(
          Object.entries(state).filter(([key]) =>
            [
              'scanHistory',
              'adminScanHistory',
              'autoSearchOnEnter',
              'autoSearchOnTab',
              'labelLiveHost',
              'labelLivePort',
              'labelLivePrinter',
              'labelLiveWindow',
              'labelLiveFieldMap',
              'showSuccessNotification',
              'successMessage',
              'itemModalJustClosed',
              // 'lastUpdatedItem' should NOT be persisted
            ].includes(key)
          )
        ),
    }
  )
);
