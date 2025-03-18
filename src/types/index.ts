// Define common types for the application

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
  price: number;
  tax?: boolean;
  crv?: boolean | number; // Container Recycling Value
  timestamp?: string;
}

export interface ScanHistoryItem extends CatalogueItem {
  scanId: string;
  scanTime: string;
} 