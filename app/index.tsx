import { View, Text, StyleSheet, TouchableOpacity, Image } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { Link } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

export default function HomeScreen() {
  return (
    <View style={styles.container}>
      <StatusBar style="auto" />
      <Text style={styles.title}>Welcome to JoyLabs</Text>
      <Text style={styles.subtitle}>Your modular React Native app</Text>
      
      <View style={styles.featuredModuleContainer}>
        <Text style={styles.sectionTitle}>Featured Module</Text>
        <Link href="/catalogue" asChild>
          <TouchableOpacity style={styles.featuredModule}>
            <View style={styles.featuredIconContainer}>
              <Ionicons name="list-outline" size={36} color="#fff" />
            </View>
            <View style={styles.featuredContent}>
              <Text style={styles.featuredTitle}>Catalogue Management</Text>
              <Text style={styles.featuredDescription}>
                Manage your Square product catalogue with ease. Scan, search, and organize your inventory.
              </Text>
            </View>
            <Ionicons name="chevron-forward" size={24} color="#3498db" />
          </TouchableOpacity>
        </Link>
      </View>
      
      <View style={styles.buttonContainer}>
        <Link href="/modules" asChild>
          <TouchableOpacity style={styles.button}>
            <Text style={styles.buttonText}>View All Modules</Text>
          </TouchableOpacity>
        </Link>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  subtitle: {
    fontSize: 18,
    color: '#666',
    marginBottom: 30,
    textAlign: 'center',
  },
  featuredModuleContainer: {
    width: '100%',
    alignItems: 'flex-start',
    marginBottom: 30,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333',
  },
  featuredModule: {
    width: '100%',
    flexDirection: 'row',
    backgroundColor: '#f8f9fa',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#e1e1e1',
  },
  featuredIconContainer: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#3498db',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  featuredContent: {
    flex: 1,
  },
  featuredTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 4,
    color: '#333',
  },
  featuredDescription: {
    fontSize: 14,
    color: '#666',
    lineHeight: 20,
  },
  buttonContainer: {
    width: '100%',
    marginTop: 20,
  },
  button: {
    backgroundColor: '#3498db',
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
}); 