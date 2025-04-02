import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter, usePathname } from 'expo-router';

type BottomTabBarProps = {
  activeTab: string;
};

export default function BottomTabBar({ activeTab }: BottomTabBarProps) {
  const router = useRouter();
  const pathname = usePathname();
  const isItemDetails = pathname.startsWith('/item/');
  
  // Handle save action when on item details page
  const handleSaveAction = () => {
    if (isItemDetails) {
      // This sends a message to the item details screen via global event
      // This is a workaround since we can't directly call the handleSave function
      // from another component
      const event = new CustomEvent('item:save');
      document.dispatchEvent(event);
    } else {
      router.push('/item/new');
    }
  };
  
  return (
    <View style={styles.container}>
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={() => router.push('/')}
      >
        <Ionicons 
          name={activeTab === 'scan' ? 'barcode' : 'barcode-outline'} 
          size={24} 
          color={activeTab === 'scan' ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, activeTab === 'scan' && styles.activeTabLabel]}>
          Scan
        </Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={() => router.push('/search')}
      >
        <Ionicons 
          name="search" 
          size={24} 
          color="#8E8E93" 
        />
        <Text style={styles.tabLabel}>Search</Text>
      </TouchableOpacity>
      
      {/* Floating action button - changes to a save button on item details screen */}
      <View style={styles.fabContainer}>
        <TouchableOpacity 
          style={[
            styles.fabButton,
            isItemDetails && styles.saveButton
          ]} 
          onPress={handleSaveAction}
        >
          <Ionicons 
            name={isItemDetails ? "checkmark" : "add"} 
            size={28} 
            color="#fff" 
          />
        </TouchableOpacity>
      </View>
      
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={() => router.push('/labels')}
      >
        <Ionicons 
          name="pricetag-outline" 
          size={24} 
          color="#8E8E93" 
        />
        <Text style={styles.tabLabel}>Labels</Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={() => router.push('/profile')}
      >
        <Ionicons 
          name={activeTab === 'profile' ? 'person' : 'person-outline'} 
          size={24} 
          color={activeTab === 'profile' ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, activeTab === 'profile' && styles.activeTabLabel]}>
          Profile
        </Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingBottom: Platform.OS === 'ios' ? 20 : 0,
    paddingHorizontal: 10,
    backgroundColor: '#fff',
    borderTopWidth: 1,
    borderTopColor: '#eee',
    height: Platform.OS === 'ios' ? 80 : 60,
  },
  tabButton: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: 8,
  },
  fabContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  fabButton: {
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 3,
    elevation: 3,
    marginBottom: 10,
  },
  saveButton: {
    backgroundColor: '#4CD964', // Green color for save button
  },
  tabLabel: {
    fontSize: 12,
    marginTop: 2,
    color: '#8E8E93',
  },
  activeTabLabel: {
    color: '#007AFF',
  },
}); 