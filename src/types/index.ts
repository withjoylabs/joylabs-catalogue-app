// Define common types for the application

import { ConvertedItem } from './api'; // Add import for ConvertedItem

export interface Module {
  id: string;
  name: string;
  description: string;
  route: string;
  icon?: string;
}

export interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
}

export interface AppTheme {
  colors: {
    primary: string;
    secondary: string;
    background: string;
    card: string;
    text: string;
    border: string;
    notification: string;
  };
  spacing: {
    xs: number;
    sm: number;
    md: number;
    lg: number;
    xl: number;
  };
  fontSizes: {
    small: number;
    medium: number;
    large: number;
    xlarge: number;
  };
}

export interface CatalogueItem {
  id: string;
  name: string;
  gtin?: string; // Global Trade Item Number
  sku?: string;
  reporting_category?: string; // Category field for Square API integration
  price: number | null;
  tax?: boolean;
  crv?: boolean | number; // Container Recycling Value
  timestamp?: string;
  description?: string; // Item description
}

export interface ScanHistoryItem extends ConvertedItem {
  scanId: string; // Unique ID for the scan event
  scanTime: string; // ISO string representation of the scan time
  // Properties from ConvertedItem are inherited
} 