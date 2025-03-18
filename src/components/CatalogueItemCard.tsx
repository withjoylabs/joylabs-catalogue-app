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
  // Format the price to have 2 decimal places
  const formattedPrice = `$${item.price.toFixed(2)}`;
  
  // Format the additional information sections
  const additionalInfo = [];
  if (item.tax) additionalInfo.push('+ TAX');
  if (item.crv) {
    if (typeof item.crv === 'number') {
      additionalInfo.push(`+ CRV${item.crv}`);
    } else {
      additionalInfo.push('+ CRV');
    }
  }

  return (
    <TouchableOpacity 
      style={styles.container}
      onPress={() => onPress(item)}
    >
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
          <Text style={styles.detailText}>{item.reporting_category || 'None'}</Text>
          <Text style={styles.detailText}>GTIN: {item.gtin || 'None'}</Text>
          <Text style={styles.detailText}>SKU: {item.sku || 'None'}</Text>
        </View>
        
        {item.scanTime && (
          <Text style={styles.timeText}>{item.scanTime}</Text>
        )}
      </View>
      
      <View style={styles.rightSection}>
        <Text style={styles.priceText}>{formattedPrice}</Text>
        
        {additionalInfo.map((info, i) => (
          <Text key={i} style={styles.additionalInfoText}>{info}</Text>
        ))}
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
    paddingVertical: 14,
    paddingHorizontal: 10,
    backgroundColor: '#fff',
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