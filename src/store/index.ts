import { create } from 'zustand';

// Product type definition
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
  products: Product[];
  selectedProduct: Product | null;
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
  
  // Actions
  setProducts: (products: Product[]) => void;
  setSelectedProduct: (product: Product | null) => void;
  setProductsLoading: (isLoading: boolean) => void;
  setProductError: (error: string | null) => void;
  
  setCategories: (categories: Category[]) => void;
  setSelectedCategory: (category: Category | null) => void;
  setCategoriesLoading: (isLoading: boolean) => void;
  setCategoryError: (error: string | null) => void;
  
  setSearchQuery: (query: string) => void;
  setSortBy: (sortBy: 'name' | 'price' | 'date' | 'category') => void;
  setSortOrder: (sortOrder: 'asc' | 'desc') => void;
}

// Create store using zustand
export const useAppStore = create<AppState>((set: any) => ({
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
  
  // Products actions
  setProducts: (products: Product[]) => set({ products }),
  setSelectedProduct: (selectedProduct: Product | null) => set({ selectedProduct }),
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
}));
