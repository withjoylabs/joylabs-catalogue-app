import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { ScanHistoryItem } from '../types';
import { lightTheme } from '../themes';

interface CatalogueItemCardProps {
  item: ScanHistoryItem;
  index: number;
  onPress: (item: ScanHistoryItem) => void;
}

const CatalogueItemCard: React.FC<CatalogueItemCardProps> = ({ 
  item, 
  index,
  onPress 
}) => {
  // Format the price safely, handling null/undefined
  const formattedPrice = typeof item.price === 'number' 
    ? `$${item.price.toFixed(2)}` 
    : '$--.--'; // Display placeholder if price is not a valid number
  
  // Remove unused additionalInfo array
  // const additionalInfo = [];
  /* Remove access to non-existent properties
  if (item.tax) additionalInfo.push('+ TAX');
  if (item.crv) {
    if (typeof item.crv === 'number') {
      additionalInfo.push(`+ CRV${item.crv}`);
    } else {
      additionalInfo.push('+ CRV');
    }
  }
  */

  return (
    <TouchableOpacity 
      style={styles.container}
      onPress={() => onPress(item)}
    >
      <View style={styles.content}>
        <View style={styles.leftSection}>
          <Text style={styles.indexNumber}>{index}</Text>
        </View>
        
        <View style={styles.middleSection}>
          <Text 
            style={styles.itemName}
            numberOfLines={2}
            ellipsizeMode="tail"
          >
            {item.name}
          </Text>
          
          <View style={styles.itemDetails}>
            {/* Remove properties not on ScanHistoryItem */} 
            {/* <Text style={styles.detailText}>{item.reporting_category || 'None'}</Text> */}
            {/* <Text style={styles.detailText}>GTIN: {item.gtin || 'None'}</Text> */}
            {/* Display SKU if available */} 
            {item.sku && <Text style={styles.detailText}>SKU: {item.sku}</Text>}
            {/* Display Barcode/UPC if available */} 
            {item.barcode && <Text style={styles.detailText}>UPC: {item.barcode}</Text>}
          </View>
          
          {item.scanTime && (
            <Text style={styles.timeText}>{new Date(item.scanTime).toLocaleString()}</Text>
          )}
        </View>
        
        <View style={styles.rightSection}>
          <Text style={styles.priceText}>{formattedPrice}</Text>
          
          {/* Display Tax info if available */}
          {item.taxIds && item.taxIds.length > 0 && (
            <Text style={styles.additionalInfoText}>
              +Tax ({item.taxIds.length})
            </Text>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    width: '100%',
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  content: {
    flexDirection: 'row',
    paddingVertical: 14,
    paddingHorizontal: 10,
  },
  leftSection: {
    width: 30,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  indexNumber: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#888',
  },
  middleSection: {
    flex: 1,
    justifyContent: 'center',
  },
  itemName: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  itemDetails: {
    marginBottom: 4,
  },
  detailText: {
    fontSize: 13,
    color: '#666',
  },
  timeText: {
    fontSize: 12,
    color: '#888',
  },
  rightSection: {
    minWidth: 100,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  priceText: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  additionalInfoText: {
    fontSize: 12,
    color: '#666',
  },
});

export default CatalogueItemCard; 