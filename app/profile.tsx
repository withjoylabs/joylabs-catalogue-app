import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Switch } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../src/themes';
import BottomTabBar from '../src/components/BottomTabBar';
import ProfileTopTabs from '../src/components/ProfileTopTabs';

type SectionType = 'profile' | 'settings' | 'categories';

export default function ProfileScreen() {
  const router = useRouter();
  const [activeSection, setActiveSection] = useState<SectionType>('profile');
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);
  const [darkModeEnabled, setDarkModeEnabled] = useState(false);
  const [scanSoundEnabled, setScanSoundEnabled] = useState(true);
  
  // Dummy user data
  const user = {
    name: 'John Doe',
    email: 'john.doe@example.com',
    role: 'Store Manager',
    joinDate: 'January 2024',
  };
  
  const renderSection = () => {
    switch (activeSection) {
      case 'profile':
        return (
          <View style={styles.sectionContent}>
            <View style={styles.avatarContainer}>
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>JD</Text>
              </View>
            </View>
            
            <Text style={styles.userName}>{user.name}</Text>
            <Text style={styles.userEmail}>{user.email}</Text>
            
            <View style={styles.infoContainer}>
              <View style={styles.infoItem}>
                <Text style={styles.infoLabel}>Role</Text>
                <Text style={styles.infoValue}>{user.role}</Text>
              </View>
              
              <View style={styles.infoItem}>
                <Text style={styles.infoLabel}>Member Since</Text>
                <Text style={styles.infoValue}>{user.joinDate}</Text>
              </View>
              
              <View style={styles.infoItem}>
                <Text style={styles.infoLabel}>Status</Text>
                <Text style={styles.infoValue}>Active</Text>
              </View>
            </View>
            
            <TouchableOpacity style={styles.editButton}>
              <Text style={styles.editButtonText}>Edit Profile</Text>
            </TouchableOpacity>
          </View>
        );
        
      case 'settings':
        return (
          <View style={styles.sectionContent}>
            <View style={styles.settingItem}>
              <View style={styles.settingInfo}>
                <Ionicons name="moon-outline" size={24} color="#666" />
                <Text style={styles.settingLabel}>Dark Mode</Text>
              </View>
              <Switch
                value={darkModeEnabled}
                onValueChange={setDarkModeEnabled}
                trackColor={{ false: '#ddd', true: '#4CD964' }}
              />
            </View>
            
            <View style={styles.settingItem}>
              <View style={styles.settingInfo}>
                <Ionicons name="volume-high-outline" size={24} color="#666" />
                <Text style={styles.settingLabel}>Scan Sound</Text>
              </View>
              <Switch
                value={scanSoundEnabled}
                onValueChange={setScanSoundEnabled}
                trackColor={{ false: '#ddd', true: '#4CD964' }}
              />
            </View>
            
            <View style={styles.settingItem}>
              <View style={styles.settingInfo}>
                <Ionicons name="cloud-outline" size={24} color="#666" />
                <Text style={styles.settingLabel}>Auto Sync</Text>
              </View>
              <TouchableOpacity style={styles.settingButton}>
                <Text style={styles.settingButtonText}>Configure</Text>
              </TouchableOpacity>
            </View>
            
            <View style={styles.settingItem}>
              <View style={styles.settingInfo}>
                <Ionicons name="lock-closed-outline" size={24} color="#666" />
                <Text style={styles.settingLabel}>Security Settings</Text>
              </View>
              <TouchableOpacity style={styles.settingButton}>
                <Text style={styles.settingButtonText}>Configure</Text>
              </TouchableOpacity>
            </View>
            
            <View style={styles.settingGroup}>
              <Text style={styles.settingGroupTitle}>Notifications</Text>
              
              <View style={styles.settingItem}>
                <View style={styles.settingInfo}>
                  <Ionicons name="notifications-outline" size={24} color="#666" />
                  <Text style={styles.settingLabel}>Enable Notifications</Text>
                </View>
                <Switch
                  value={notificationsEnabled}
                  onValueChange={setNotificationsEnabled}
                  trackColor={{ false: '#ddd', true: '#4CD964' }}
                />
              </View>
              
              <View style={[styles.settingItem, !notificationsEnabled && styles.disabledItem]}>
                <View style={styles.settingInfo}>
                  <Ionicons name="pricetag-outline" size={24} color={notificationsEnabled ? "#666" : "#ccc"} />
                  <Text style={[styles.settingLabel, !notificationsEnabled && styles.disabledText]}>
                    Price Updates
                  </Text>
                </View>
                <Switch
                  value={notificationsEnabled && true}
                  onValueChange={() => {}}
                  disabled={!notificationsEnabled}
                  trackColor={{ false: '#ddd', true: '#4CD964' }}
                />
              </View>
              
              <View style={[styles.settingItem, !notificationsEnabled && styles.disabledItem]}>
                <View style={styles.settingInfo}>
                  <Ionicons name="bag-outline" size={24} color={notificationsEnabled ? "#666" : "#ccc"} />
                  <Text style={[styles.settingLabel, !notificationsEnabled && styles.disabledText]}>
                    Inventory Alerts
                  </Text>
                </View>
                <Switch
                  value={notificationsEnabled && true}
                  onValueChange={() => {}}
                  disabled={!notificationsEnabled}
                  trackColor={{ false: '#ddd', true: '#4CD964' }}
                />
              </View>
              
              <View style={[styles.settingItem, !notificationsEnabled && styles.disabledItem]}>
                <View style={styles.settingInfo}>
                  <Ionicons name="sync-outline" size={24} color={notificationsEnabled ? "#666" : "#ccc"} />
                  <Text style={[styles.settingLabel, !notificationsEnabled && styles.disabledText]}>
                    Sync Completion
                  </Text>
                </View>
                <Switch
                  value={notificationsEnabled && true}
                  onValueChange={() => {}}
                  disabled={!notificationsEnabled}
                  trackColor={{ false: '#ddd', true: '#4CD964' }}
                />
              </View>
            </View>
            
            <View style={styles.settingItem}>
              <View style={styles.settingInfo}>
                <Ionicons name="trash-outline" size={24} color="#666" />
                <Text style={styles.settingLabel}>Clear Cache</Text>
              </View>
              <TouchableOpacity style={styles.settingButtonWarning}>
                <Text style={styles.settingButtonTextWarning}>Clear</Text>
              </TouchableOpacity>
            </View>
          </View>
        );
        
      case 'categories':
        return (
          <View style={styles.sectionContent}>
            <View style={styles.categoryItem}>
              <View style={styles.categoryHeader}>
                <Ionicons name="fast-food-outline" size={24} color="#666" />
                <Text style={styles.categoryTitle}>Food & Beverages</Text>
              </View>
              <Text style={styles.categoryCount}>128 items</Text>
            </View>
            
            <View style={styles.categoryItem}>
              <View style={styles.categoryHeader}>
                <Ionicons name="shirt-outline" size={24} color="#666" />
                <Text style={styles.categoryTitle}>Clothing & Accessories</Text>
              </View>
              <Text style={styles.categoryCount}>95 items</Text>
            </View>
            
            <View style={styles.categoryItem}>
              <View style={styles.categoryHeader}>
                <Ionicons name="home-outline" size={24} color="#666" />
                <Text style={styles.categoryTitle}>Home & Kitchen</Text>
              </View>
              <Text style={styles.categoryCount}>74 items</Text>
            </View>
            
            <View style={styles.categoryItem}>
              <View style={styles.categoryHeader}>
                <Ionicons name="fitness-outline" size={24} color="#666" />
                <Text style={styles.categoryTitle}>Sports & Outdoors</Text>
              </View>
              <Text style={styles.categoryCount}>63 items</Text>
            </View>
            
            <View style={styles.categoryItem}>
              <View style={styles.categoryHeader}>
                <Ionicons name="desktop-outline" size={24} color="#666" />
                <Text style={styles.categoryTitle}>Electronics</Text>
              </View>
              <Text style={styles.categoryCount}>52 items</Text>
            </View>
            
            <TouchableOpacity style={styles.addButton}>
              <Ionicons name="add-circle-outline" size={20} color="#fff" style={{marginRight: 8}} />
              <Text style={styles.addButtonText}>Add New Category</Text>
            </TouchableOpacity>
          </View>
        );
    }
  };
  
  return (
    <View style={styles.container}>
      <StatusBar style="auto" />
      
      <View style={styles.mainContainer}>
        <View style={styles.header}>
          <TouchableOpacity 
            style={styles.backButton}
            onPress={() => router.back()}
          >
            <Ionicons name="arrow-back" size={24} color="#333" />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>My Account</Text>
          <View style={{ width: 24 }} />
        </View>
        
        <ProfileTopTabs 
          activeSection={activeSection} 
          onTabChange={(section) => setActiveSection(section as SectionType)} 
        />
        
        <ScrollView 
          style={styles.content}
          contentContainerStyle={styles.contentContainer}
        >
          {renderSection()}
          
          <View style={styles.bottomBarSpacer}>
            <TouchableOpacity 
              style={styles.logoutButton}
              onPress={() => console.log('Logout pressed')}
            >
              <Ionicons name="log-out-outline" size={20} color="#FF3B30" />
              <Text style={styles.logoutText}>Logout</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  mainContainer: {
    flex: 1,
    paddingBottom: 80, // Account for the tab bar height plus safe area padding
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: 60,
    paddingBottom: 16,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 8,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    paddingBottom: 20,
  },
  sectionContent: {
    padding: 20,
  },
  // Profile styles
  avatarContainer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  avatar: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: lightTheme.colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: 'white',
    fontSize: 36,
    fontWeight: 'bold',
  },
  userName: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 4,
  },
  userEmail: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 24,
  },
  infoContainer: {
    marginBottom: 24,
  },
  infoItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  infoLabel: {
    fontSize: 16,
    color: '#666',
  },
  infoValue: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
  },
  editButton: {
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  editButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  // Settings styles
  settingItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  settingInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  settingLabel: {
    fontSize: 16,
    marginLeft: 16,
    color: '#333',
  },
  settingButton: {
    backgroundColor: '#f0f0f0',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 6,
  },
  settingButtonText: {
    color: '#333',
    fontSize: 14,
  },
  settingButtonWarning: {
    backgroundColor: '#FFF0F0',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 6,
  },
  settingButtonTextWarning: {
    color: '#FF3B30',
    fontSize: 14,
  },
  disabledItem: {
    opacity: 0.5,
  },
  disabledText: {
    color: '#ccc',
  },
  // Bottom bar
  bottomBarSpacer: {
    padding: 16,
    marginBottom: 20,
  },
  logoutButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    backgroundColor: '#FFF0F0',
    borderRadius: 8,
  },
  logoutText: {
    color: '#FF3B30',
    fontSize: 16,
    fontWeight: '600',
    marginLeft: 8,
  },
  settingGroup: {
    marginTop: 10,
    marginBottom: 20,
    borderRadius: 10,
    backgroundColor: '#f9f9f9',
    padding: 15,
  },
  settingGroupTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 15,
  },
  // Category styles
  categoryItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  categoryHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  categoryTitle: {
    fontSize: 16,
    color: '#333',
    marginLeft: 16,
    fontWeight: '500',
  },
  categoryCount: {
    fontSize: 14,
    color: '#666',
  },
  addButton: {
    flexDirection: 'row',
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 20,
  },
  addButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
}); 