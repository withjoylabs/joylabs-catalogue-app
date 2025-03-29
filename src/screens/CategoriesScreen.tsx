import React from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, ActivityIndicator, RefreshControl } from 'react-native';
import { useCatalogCategories } from '../hooks/useCatalogCategories';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { Image } from 'react-native';
import { useSquareAuth } from '../hooks/useSquareAuth';

// Define category interface to match the hook
interface Category {
  id: string;
  name: string;
  imageUrl?: string;
}

// Define navigation type
type NavigationProp = any; // Simplified for now

// Default placeholder image
const PLACEHOLDER_IMAGE = 'https://placehold.co/600x400/e0e0e0/CCCCCC?text=No+Image';

const CategoriesScreen: React.FC = () => {
  const navigation = useNavigation<NavigationProp>();
  const { categories, isLoading, error, refreshCategories } = useCatalogCategories();
  const { isConnected } = useSquareAuth();
  
  const renderItem = ({ item }: { item: Category }) => (
    <TouchableOpacity
      style={styles.categoryCard}
      onPress={() => {
        // Navigate to products filtered by this category
        navigation.navigate('Products', { categoryId: item.id, categoryName: item.name });
      }}
    >
      <Image
        source={{ uri: item.imageUrl || PLACEHOLDER_IMAGE }}
        style={styles.categoryImage}
      />
      <View style={styles.categoryInfo}>
        <Text style={styles.categoryName}>{item.name}</Text>
        <Ionicons name="chevron-forward" size={20} color="#888" />
      </View>
    </TouchableOpacity>
  );

  // Show connection screen if not connected to Square
  if (!isConnected) {
    return (
      <View style={styles.container}>
        <View style={styles.errorContainer}>
          <Ionicons name="cloud-offline" size={64} color="#ccc" />
          <Text style={styles.errorTitle}>Not Connected to Square</Text>
          <Text style={styles.errorText}>
            Please connect your Square account in the Profile tab to view your categories.
          </Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => navigation.navigate('Profile')}
          >
            <Text style={styles.buttonText}>Go to Profile</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show loading state
  if (isLoading && categories.length === 0) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0066cc" />
        <Text style={styles.loadingText}>Loading categories...</Text>
      </View>
    );
  }

  // Show error state
  if (error && categories.length === 0) {
    return (
      <View style={styles.container}>
        <View style={styles.errorContainer}>
          <Ionicons name="alert-circle-outline" size={64} color="#cc0000" />
          <Text style={styles.errorTitle}>Error Loading Categories</Text>
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => refreshCategories()}
          >
            <Text style={styles.buttonText}>Retry</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show empty state
  if (categories.length === 0) {
    return (
      <View style={styles.container}>
        <View style={styles.errorContainer}>
          <Ionicons name="folder-open-outline" size={64} color="#ccc" />
          <Text style={styles.errorTitle}>No Categories Found</Text>
          <Text style={styles.errorText}>
            You don't have any categories in your Square catalog yet.
          </Text>
          <TouchableOpacity
            style={styles.buttonPrimary}
            onPress={() => refreshCategories()}
          >
            <Text style={styles.buttonText}>Refresh</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Show categories list
  return (
    <View style={styles.container}>
      <FlatList
        data={categories}
        renderItem={renderItem}
        keyExtractor={(item: Category) => item.id}
        contentContainerStyle={styles.list}
        refreshControl={
          <RefreshControl refreshing={isLoading} onRefresh={refreshCategories} />
        }
        ListHeaderComponent={
          <Text style={styles.headerText}>Categories</Text>
        }
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f8f8',
    paddingTop: 10,
  },
  list: {
    padding: 15,
  },
  headerText: {
    fontSize: 22,
    fontWeight: 'bold',
    marginBottom: 15,
    color: '#333',
  },
  categoryCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    marginBottom: 15,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  categoryImage: {
    width: '100%',
    height: 120,
    backgroundColor: '#f0f0f0',
  },
  categoryInfo: {
    padding: 15,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  categoryName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  loadingText: {
    marginTop: 20,
    fontSize: 16,
    color: '#666',
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 30,
  },
  errorTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    marginTop: 20,
    marginBottom: 10,
    color: '#333',
  },
  errorText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 20,
  },
  buttonPrimary: {
    backgroundColor: '#0066cc',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
    marginTop: 10,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
    textAlign: 'center',
  },
});

export default CategoriesScreen; 