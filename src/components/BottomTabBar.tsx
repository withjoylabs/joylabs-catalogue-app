import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter, usePathname } from 'expo-router';
import { useAppStore } from '../store';

type BottomTabBarProps = {
  activeTab: string;
  setActiveTab: React.Dispatch<React.SetStateAction<string>>;
  setActiveScreen: React.Dispatch<React.SetStateAction<string>>;
};

export default function BottomTabBar({ activeTab, setActiveTab, setActiveScreen }: BottomTabBarProps) {
  const router = useRouter();
  const pathname = usePathname();
  const isItemDetails = pathname.startsWith('/item/');
  const triggerItemSave = useAppStore((state) => state.triggerItemSave);
  
  console.log("BOTTOM_TAB_BAR - Current pathname:", pathname);
  console.log("BOTTOM_TAB_BAR - Active tab from prop:", activeTab);
  
  // Helper function to check if a tab should be active
  // This now SOLELY relies on the activeTab prop from RootLayout
  const isTabActive = (tabName: string) => {
    return activeTab === tabName;
  };
  
  // Handle save action when on item details page
  const handleSaveAction = () => {
    if (isItemDetails) {
      // Trigger save via Zustand store action
      triggerItemSave();
    } else {
      router.push('/item/new');
    }
  };

  // Force-navigate home with extra options
  const navigateToHome = () => {
    console.log("NAV_EVENT - DIAGNOSTIC: Attempting to PUSH HOME ('/(tabs)/(scan)') from pathname:", pathname, "via BottomTabBar");
    setActiveTab('scan');
    setActiveScreen('index');
    router.push('/(tabs)/(scan)'); // Updated to new scan location
  };
  
  const navigateToSearch = () => {
    console.log("NAV_EVENT - Navigating to Search from:", pathname);
    setActiveTab('search');
    setActiveScreen('search');
    router.push("/search"); // push is okay for these as they are distinct main sections
  };
  
  const navigateToLabels = () => {
    console.log("NAV_EVENT - Navigating to Labels from:", pathname);
    setActiveTab('labels');
    setActiveScreen('labels');
    router.push("/labels"); // push is okay
  };
  
  const navigateToProfile = () => {
    console.log("NAV_EVENT - Navigating to Profile from:", pathname);
    setActiveTab('profile');
    setActiveScreen('profile');
    router.replace("/(profile)"); // replace is good here to not stack profile on profile
  };
  
  return (
    <View style={styles.container}>
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={navigateToHome}
        accessibilityState={{ selected: isTabActive('scan') }}
      >
        <Ionicons 
          name={isTabActive('scan') ? 'barcode' : 'barcode-outline'} 
          size={24} 
          color={isTabActive('scan') ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, isTabActive('scan') && styles.activeTabLabel]}>
          Scan
        </Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={navigateToSearch}
        accessibilityState={{ selected: isTabActive('search') }}
      >
        <Ionicons 
          name={isTabActive('search') ? 'search' : 'search-outline'} 
          size={24} 
          color={isTabActive('search') ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, isTabActive('search') && styles.activeTabLabel]}>
          Search
        </Text>
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
        onPress={navigateToLabels}
        accessibilityState={{ selected: isTabActive('labels') }}
      >
        <Ionicons 
          name={isTabActive('labels') ? 'pricetag' : 'pricetag-outline'} 
          size={24} 
          color={isTabActive('labels') ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, isTabActive('labels') && styles.activeTabLabel]}>
          Labels
        </Text>
      </TouchableOpacity>
      
      <TouchableOpacity 
        style={styles.tabButton} 
        onPress={navigateToProfile}
        accessibilityState={{ selected: isTabActive('profile') }}
      >
        <Ionicons 
          name={isTabActive('profile') ? 'person' : 'person-outline'} 
          size={24} 
          color={isTabActive('profile') ? '#007AFF' : '#8E8E93'} 
        />
        <Text style={[styles.tabLabel, isTabActive('profile') && styles.activeTabLabel]}>
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