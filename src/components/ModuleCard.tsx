import React from 'react';
import { TouchableOpacity, Text, StyleSheet, View } from 'react-native';
import { Module } from '../types';
import { lightTheme } from '../themes';
import { Ionicons } from '@expo/vector-icons';

interface ModuleCardProps {
  module: Module;
  onPress: () => void;
}

const ModuleCard: React.FC<ModuleCardProps> = ({ module, onPress }) => {
  return (
    <TouchableOpacity style={styles.container} onPress={onPress}>
      <View style={styles.iconContainer}>
        {module.icon && (
          <Ionicons 
            name={module.icon as any} 
            size={24} 
            color={lightTheme.colors.primary} 
          />
        )}
      </View>
      <View style={styles.content}>
        <Text style={styles.name}>{module.name}</Text>
        <Text style={styles.description}>{module.description}</Text>
      </View>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: lightTheme.colors.card,
    padding: lightTheme.spacing.md,
    borderRadius: 10,
    marginBottom: lightTheme.spacing.md,
    borderLeftWidth: 4,
    borderLeftColor: lightTheme.colors.primary,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconContainer: {
    marginRight: lightTheme.spacing.md,
  },
  content: {
    flex: 1,
  },
  name: {
    fontSize: lightTheme.fontSizes.medium,
    fontWeight: 'bold',
    marginBottom: lightTheme.spacing.xs,
    color: lightTheme.colors.text,
  },
  description: {
    fontSize: lightTheme.fontSizes.small,
    color: '#666',
  },
});

export default ModuleCard; 