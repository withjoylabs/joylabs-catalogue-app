import { Alert } from 'react-native';
import * as Print from 'expo-print';
import { shareAsync } from 'expo-sharing';
import logger from './logger';
import { ConvertedItem } from '../types/api';
import { useAppStore } from '../store';

// Default values for Label LIVE (fallbacks)
const DEFAULT_LABEL_LIVE_HOST = '192.168.254.133'; 
const DEFAULT_LABEL_LIVE_PORT = '11180'; 
const DEFAULT_LABEL_LIVE_PRINTER = 'System-ZQ511';
const DEFAULT_LABEL_LIVE_WINDOW = 'hide';
const DEFAULT_FIELD_MAP = {
  itemName: 'ITEM_NAME',
  variationName: 'VARIATION_NAME',
  variationPrice: 'PRICE',
  barcode: 'GTIN',
};

// Define the type for the label data
export interface LabelData {
  itemId?: string;
  itemName: string;
  variationId?: string;
  variationName?: string;
  price?: number;
  sku?: string | null;
  barcode?: string | null;
}

// Function to check if the printer is available
export const getLabelPrinterStatus = async (): Promise<boolean> => {
  try {
    // Get printer settings from store
    const state = useAppStore.getState();
    const host = state.labelLiveHost ?? DEFAULT_LABEL_LIVE_HOST;
    const port = state.labelLivePort ?? DEFAULT_LABEL_LIVE_PORT;
    
    // Simple check - ping the print server to see if it's available
    const response = await fetch(`http://${host}:${port}/api/v1/status`, {
      method: 'GET',
    });
    
    if (response.ok) {
      logger.info('LabelPrinter', 'Print server is available');
      return true;
    } else {
      logger.warn('LabelPrinter', 'Print server returned an error status', { status: response.status });
      return false;
    }
  } catch (error) {
    logger.error('LabelPrinter', 'Could not connect to print server', { error });
    return false;
  }
};

// Function to format price for display
const formatPrice = (price?: number): string => {
  if (price === undefined || price === null) return '';
  return price.toFixed(2);
};

/**
 * Generates the HTML content for the item label.
 * TODO: Enhance this with actual label layout and data.
 */
const generateLabelHtml = (item: ConvertedItem): string => {
  // Basic placeholder HTML
  return `
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no" />
        <style>
          body { font-family: sans-serif; text-align: center; }
          h1 { font-size: 18px; margin-bottom: 5px; }
          p { font-size: 14px; margin: 2px 0; }
        </style>
      </head>
      <body>
        <h1>${item.name || 'Item Name'}</h1>
        <p>Price: ${item.price !== undefined ? `$${item.price.toFixed(2)}` : 'Variable'}</p>
        <p>SKU: ${item.sku || 'N/A'}</p>
        ${item.barcode ? `<p>UPC: ${item.barcode}</p>` : ''}
        <p>ID: ${item.id}</p> 
      </body>
    </html>
  `;
};

// Main function to print a label
export const printItemLabel = async (labelData: LabelData): Promise<boolean> => {
  try {
    logger.info('PrintLabel', 'Printing label', { labelData });
  
    // Get settings from Zustand store
    const state = useAppStore.getState();
    const host = state.labelLiveHost ?? DEFAULT_LABEL_LIVE_HOST;
    const port = state.labelLivePort ?? DEFAULT_LABEL_LIVE_PORT;
    const printer = state.labelLivePrinter ?? DEFAULT_LABEL_LIVE_PRINTER;
    const windowParam = state.labelLiveWindow ?? DEFAULT_LABEL_LIVE_WINDOW;
    
    // Get field mapping from store, fall back to defaults if not set
    const fieldMap = { 
      ...DEFAULT_FIELD_MAP, 
      ...(state.labelLiveFieldMap || {})
    };
  
    // Create variables object using the field mapping
    const variables: Record<string, string> = {};
    
    // Map each data field according to the configured mapping
    if (fieldMap.itemName && labelData.itemName) {
      variables[fieldMap.itemName] = labelData.itemName;
    }
    
    if (fieldMap.variationName && labelData.variationName) {
      variables[fieldMap.variationName] = labelData.variationName;
    }
    
    if (fieldMap.variationPrice && labelData.price !== undefined) {
      variables[fieldMap.variationPrice] = formatPrice(labelData.price);
    }
    
    if (fieldMap.barcode && labelData.barcode) {
      variables[fieldMap.barcode] = labelData.barcode;
    }
    
    // Add empty values for any expected fields that aren't set
    ['ORIGPRICE', 'QTYFOR', 'QTYPRICE'].forEach(field => {
      if (!variables[field]) {
        variables[field] = '';
      }
    });
    
    // Convert variables object to the format needed in the query string
    const variablesString = encodeURIComponent(JSON.stringify(variables));

    // Construct the full URL with query parameters
    const url = `http://${host}:${port}/api/v1/print?design=joy-tags-aio&variables=${variablesString}&printer=${printer}&window=${windowParam}&copies=1`;
    
    logger.info('PrintLabel', 'Sending print request', { url });

    // Make the HTTP request
    const response = await fetch(url, {
      method: 'GET',
    });
    
    if (response.ok) {
      logger.info('PrintLabel', 'Print request successful');
      return true;
    } else {
      const errorText = await response.text();
      logger.warn('PrintLabel', 'Print request failed', { 
        status: response.status, 
        statusText: response.statusText,
        errorText 
      });
      return false;
    }
  } catch (error) {
    logger.error('PrintLabel', 'Error sending print request', { error });
    return false;
  }
}; 