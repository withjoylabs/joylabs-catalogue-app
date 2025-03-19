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
    const response = await api.get('/categories');
    return response.data;
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
