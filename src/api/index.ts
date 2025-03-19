import axios from 'axios';

// API Configuration
const API_URL = process.env.EXPO_PUBLIC_API_URL || 'http://localhost:5000/api';

// Create axios instance
const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Products API
export const productsApi = {
  getAll: async () => {
    const response = await api.get('/products');
    return response.data;
  },
  
  getById: async (id: string) => {
    const response = await api.get(`/products/${id}`);
    return response.data;
  },
  
  create: async (product: any) => {
    const response = await api.post('/products', product);
    return response.data;
  },
  
  update: async (id: string, product: any) => {
    const response = await api.put(`/products/${id}`, product);
    return response.data;
  },
  
  delete: async (id: string) => {
    const response = await api.delete(`/products/${id}`);
    return response.data;
  },

  search: async (query: string) => {
    const response = await api.get(`/products?search=${query}`);
    return response.data;
  },
};

// Categories API
export const categoriesApi = {
  getAll: async () => {
    // Mock response for development
    // In production, this would call the real API
    // const response = await api.get('/categories');
    // return response.data;
    
    // Simulate API delay
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Return mock data
    return [
      {
        id: 'cat_1',
        name: 'Beverages',
        description: 'Drinks and liquid refreshments',
        color: '#4CD964',
        icon: 'fast-food-outline',
        isActive: true,
        itemCount: 128,
        createdAt: '2023-01-15T10:30:00Z',
        updatedAt: '2023-01-15T10:30:00Z'
      },
      {
        id: 'cat_2',
        name: 'Clothing & Accessories',
        description: 'Apparel and fashion items',
        color: '#5AC8FA',
        icon: 'shirt-outline',
        isActive: true,
        itemCount: 95,
        createdAt: '2023-01-15T10:35:00Z',
        updatedAt: '2023-01-15T10:35:00Z'
      },
      {
        id: 'cat_3',
        name: 'Home & Kitchen',
        description: 'Household and kitchen items',
        color: '#FF9500',
        icon: 'home-outline',
        isActive: true,
        itemCount: 74,
        createdAt: '2023-01-15T10:40:00Z',
        updatedAt: '2023-01-15T10:40:00Z'
      },
      {
        id: 'cat_4',
        name: 'Sports & Outdoors',
        description: 'Sports equipment and outdoor gear',
        color: '#FF2D55',
        icon: 'fitness-outline',
        isActive: true,
        itemCount: 63,
        createdAt: '2023-01-15T10:45:00Z',
        updatedAt: '2023-01-15T10:45:00Z'
      },
      {
        id: 'cat_5',
        name: 'Electronics',
        description: 'Electronic devices and accessories',
        color: '#5856D6',
        icon: 'desktop-outline',
        isActive: true,
        itemCount: 52,
        createdAt: '2023-01-15T10:50:00Z',
        updatedAt: '2023-01-15T10:50:00Z'
      },
    ];
  },
  
  getById: async (id: string) => {
    const response = await api.get(`/categories/${id}`);
    return response.data;
  },
  
  create: async (category: any) => {
    const response = await api.post('/categories', category);
    return response.data;
  },
  
  update: async (id: string, category: any) => {
    const response = await api.put(`/categories/${id}`, category);
    return response.data;
  },
  
  delete: async (id: string) => {
    const response = await api.delete(`/categories/${id}`);
    return response.data;
  },
};

export default api;
