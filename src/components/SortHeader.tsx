import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

interface SortHeaderProps {
  title: string;
  sortOrder: 'newest' | 'oldest' | 'name' | 'price';
  onSortChange: (sortOrder: 'newest' | 'oldest' | 'name' | 'price') => void;
}

const SortHeader: React.FC<SortHeaderProps> = ({
  title,
  sortOrder,
  onSortChange
}) => {
  const getSortLabel = () => {
    switch (sortOrder) {
      case 'newest': return 'Newest First';
      case 'oldest': return 'Oldest First';
      case 'name': return 'Name';
      case 'price': return 'Price';
      default: return 'Newest First';
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{title}</Text>
      
      <TouchableOpacity 
        style={styles.sortButton}
        onPress={() => {
          // Simple rotation through sort options
          const nextSort = 
            sortOrder === 'newest' ? 'oldest' :
            sortOrder === 'oldest' ? 'name' :
            sortOrder === 'name' ? 'price' : 'newest';
          onSortChange(nextSort);
        }}
      >
        <Text style={styles.sortText}>{getSortLabel()}</Text>
        <Ionicons name="chevron-down" size={16} color="#333" />
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#f8f8f8',
    borderBottomWidth: 1,
    borderBottomColor: '#e1e1e1',
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
  },
  sortButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sortText: {
    fontSize: 14,
    color: '#333',
    marginRight: 4,
  },
});

export default SortHeader; 