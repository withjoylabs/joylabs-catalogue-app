import { View, StyleSheet, FlatList, TouchableOpacity, Text } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { Link, useRouter } from 'expo-router';
import { Module } from '../src/types';
import ModuleCard from '../src/components/ModuleCard';
import { lightTheme } from '../src/themes';
import { Ionicons } from '@expo/vector-icons';

// Mock data for modules
const modules: Module[] = [
  { 
    id: '1', 
    name: 'Profile', 
    description: 'User profile management', 
    route: '/profile',
    icon: 'person-circle-outline'
  },
  { 
    id: '2', 
    name: 'Settings', 
    description: 'App configuration', 
    route: '/settings',
    icon: 'settings-outline'
  },
  { 
    id: '3', 
    name: 'Notifications', 
    description: 'Push notification setup', 
    route: '/notifications',
    icon: 'notifications-outline'
  },
  { 
    id: '4', 
    name: 'Analytics', 
    description: 'Usage statistics', 
    route: '/analytics',
    icon: 'bar-chart-outline'
  },
];

export default function ModulesScreen() {
  const router = useRouter();
  
  const renderModuleItem = ({ item }: { item: Module }) => (
    <ModuleCard 
      module={item} 
      onPress={() => router.push(item.route)} 
    />
  );
  
  return (
    <View style={styles.container}>
      <StatusBar style="auto" />
      <View style={styles.header}>
        <Link href="/" asChild>
          <TouchableOpacity style={styles.backButton}>
            <Text style={styles.backButtonText}>← Back</Text>
          </TouchableOpacity>
        </Link>
        <Text style={styles.title}>Available Modules</Text>
      </View>
      
      <FlatList
        data={modules}
        renderItem={renderModuleItem}
        keyExtractor={item => item.id}
        style={styles.list}
        contentContainerStyle={styles.listContent}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  header: {
    padding: lightTheme.spacing.md,
    paddingTop: 60,
    backgroundColor: lightTheme.colors.card,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  backButton: {
    marginBottom: lightTheme.spacing.md,
  },
  backButtonText: {
    fontSize: lightTheme.fontSizes.medium,
    color: lightTheme.colors.primary,
  },
  title: {
    fontSize: lightTheme.fontSizes.xlarge,
    fontWeight: 'bold',
    color: lightTheme.colors.text,
  },
  list: {
    flex: 1,
  },
  listContent: {
    padding: lightTheme.spacing.md,
  },
}); 