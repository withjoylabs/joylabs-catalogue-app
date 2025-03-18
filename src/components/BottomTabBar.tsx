import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type TabBarProps = {
  activeTab: string;
};

export default function BottomTabBar({ activeTab }: TabBarProps) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  
  const isActive = (tabName: string) => {
    return activeTab === tabName;
  };

  return (
    <View style={[styles.container, { paddingBottom: insets.bottom > 0 ? insets.bottom : 10 }]}>
      <View style={styles.tabBar}>
        <TouchableOpacity 
          style={styles.tabItem} 
          onPress={() => router.push('/')}
        >
          <Ionicons 
            name="barcode-outline" 
            size={24} 
            color={isActive('scan') ? "#0D6EFD" : "#888"} 
          />
          <Text 
            style={[
              styles.tabLabel,
              isActive('scan') && { color: '#0D6EFD' }
            ]}
          >
            Scan
          </Text>
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={styles.tabItem}
          onPress={() => router.push('/')}
        >
          <Ionicons 
            name="search-outline" 
            size={24} 
            color={isActive('search') ? "#0D6EFD" : "#888"} 
          />
          <Text 
            style={[
              styles.tabLabel,
              isActive('search') && { color: '#0D6EFD' }
            ]}
          >
            Search
          </Text>
        </TouchableOpacity>
        
        <View style={styles.fabContainer}>
          <TouchableOpacity 
            style={styles.fab}
            onPress={() => {}}
          >
            <Ionicons name="add" size={28} color="#fff" />
          </TouchableOpacity>
        </View>
        
        <TouchableOpacity 
          style={styles.tabItem}
          onPress={() => router.push('/')}
        >
          <Ionicons 
            name="grid-outline" 
            size={24} 
            color={isActive('categories') ? "#0D6EFD" : "#888"} 
          />
          <Text 
            style={[
              styles.tabLabel,
              isActive('categories') && { color: '#0D6EFD' }
            ]}
          >
            Categories
          </Text>
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={styles.tabItem} 
          onPress={() => router.push('/profile')}
        >
          <Ionicons 
            name="person-outline" 
            size={24} 
            color={isActive('profile') ? "#0D6EFD" : "#888"} 
          />
          <Text 
            style={[
              styles.tabLabel,
              isActive('profile') && { color: '#0D6EFD' }
            ]}
          >
            Profile
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    position: 'absolute',
    bottom: 0,
    backgroundColor: '#fff',
  },
  tabBar: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: '#e1e1e1',
    paddingTop: 8,
    backgroundColor: '#fff',
    height: 70,
    position: 'relative',
  },
  tabItem: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 4,
  },
  tabLabel: {
    fontSize: 12,
    marginTop: 4,
    color: '#888',
  },
  fabContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'flex-start',
  },
  fab: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#0D6EFD',
    justifyContent: 'center',
    alignItems: 'center',
    position: 'absolute',
    top: -30,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
}); 