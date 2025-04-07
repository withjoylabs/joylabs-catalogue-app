import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, FlatList, StyleSheet, TouchableOpacity, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as modernDb from '../database/modernDb';
import logger from '../utils/logger';
import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { useFocusEffect } from '@react-navigation/native';

interface LogEntry {
  id: number;
  timestamp: string;
  level: string;
  message: string;
  data?: string;
}

export default function SyncLogsView() {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [exporting, setExporting] = useState<boolean>(false);

  // Load logs from database
  const loadLogs = useCallback(async () => {
    try {
      setLoading(true);
      const db = await modernDb.getDatabase();
      
      // Check if logs table exists
      const tablesResult = await db.getAllAsync<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_logs'"
      );
      
      // Create table if it doesn't exist
      if (!tablesResult.some(t => t.name === 'sync_logs')) {
        await db.runAsync(`
          CREATE TABLE IF NOT EXISTS sync_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            level TEXT NOT NULL,
            message TEXT NOT NULL,
            data TEXT
          )
        `);
        setLogs([]);
        return;
      }
      
      // Fetch logs ordered by newest first
      const result = await db.getAllAsync<LogEntry>(
        `SELECT id, timestamp, level, message, data 
         FROM sync_logs 
         ORDER BY timestamp DESC 
         LIMIT 100`
      );
      
      setLogs(result);
    } catch (error) {
      logger.error('SyncLogsView', 'Failed to load logs', { error });
      Alert.alert('Error', 'Failed to load sync logs');
    } finally {
      setLoading(false);
    }
  }, []);

  // Reload logs when the component gains focus
  useFocusEffect(
    useCallback(() => {
      loadLogs();
    }, [loadLogs])
  );

  // Export logs to a file
  const exportLogs = async () => {
    try {
      setExporting(true);
      
      // Check if sharing is available
      const isSharingAvailable = await Sharing.isAvailableAsync();
      if (!isSharingAvailable) {
        Alert.alert('Error', 'Sharing is not available on this device');
        return;
      }
      
      // Format logs as JSON
      const logsJson = JSON.stringify(logs, null, 2);
      
      // Create a temporary file
      const fileUri = `${FileSystem.cacheDirectory}sync_logs_${new Date().toISOString().replace(/[:\.]/g, '_')}.json`;
      await FileSystem.writeAsStringAsync(fileUri, logsJson);
      
      // Share the file
      await Sharing.shareAsync(fileUri, {
        mimeType: 'application/json',
        dialogTitle: 'Export Sync Logs',
        UTI: 'public.json'
      });
    } catch (error) {
      logger.error('SyncLogsView', 'Failed to export logs', { error });
      Alert.alert('Error', 'Failed to export logs');
    } finally {
      setExporting(false);
    }
  };

  // Clear all logs
  const clearLogs = async () => {
    Alert.alert(
      'Clear Logs',
      'Are you sure you want to clear all sync logs?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear',
          style: 'destructive',
          onPress: async () => {
            try {
              setLoading(true);
              const db = await modernDb.getDatabase();
              await db.runAsync('DELETE FROM sync_logs');
              setLogs([]);
              Alert.alert('Success', 'All logs have been cleared');
            } catch (error) {
              logger.error('SyncLogsView', 'Failed to clear logs', { error });
              Alert.alert('Error', 'Failed to clear logs');
            } finally {
              setLoading(false);
            }
          }
        }
      ]
    );
  };

  // Format the timestamp
  const formatTimestamp = (timestamp: string) => {
    try {
      const date = new Date(timestamp);
      return date.toLocaleString();
    } catch (e) {
      return timestamp;
    }
  };

  // Get color based on log level
  const getLevelColor = (level: string) => {
    switch (level.toLowerCase()) {
      case 'error':
        return '#d32f2f';
      case 'warn':
        return '#ff9800';
      case 'info':
        return '#2196f3';
      case 'debug':
        return '#4caf50';
      default:
        return '#757575';
    }
  };

  // Render a single log entry
  const renderLogItem = ({ item }: { item: LogEntry }) => (
    <View style={styles.logItem}>
      <View style={styles.logHeader}>
        <Text style={styles.timestamp}>{formatTimestamp(item.timestamp)}</Text>
        <Text style={[styles.level, { color: getLevelColor(item.level) }]}>
          {item.level.toUpperCase()}
        </Text>
      </View>
      <Text style={styles.message}>{item.message}</Text>
      {item.data && (
        <Text style={styles.data} numberOfLines={3}>
          {item.data}
        </Text>
      )}
    </View>
  );

  // Render empty state if no logs
  const renderEmptyState = () => (
    <View style={styles.emptyState}>
      <Ionicons name="document-text-outline" size={48} color="#bdbdbd" />
      <Text style={styles.emptyText}>No sync logs available</Text>
    </View>
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Sync Logs</Text>
        <View style={styles.actions}>
          <TouchableOpacity 
            style={styles.actionButton} 
            onPress={loadLogs}
            disabled={loading}
          >
            <Ionicons name="refresh" size={20} color="#333" />
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={styles.actionButton} 
            onPress={exportLogs}
            disabled={exporting || logs.length === 0}
          >
            {exporting ? (
              <ActivityIndicator size="small" color="#333" />
            ) : (
              <Ionicons name="download" size={20} color="#333" />
            )}
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={styles.actionButton} 
            onPress={clearLogs}
            disabled={loading || logs.length === 0}
          >
            <Ionicons name="trash" size={20} color="#333" />
          </TouchableOpacity>
        </View>
      </View>
      
      {loading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#0000ff" />
        </View>
      ) : (
        <FlatList
          data={logs}
          renderItem={renderLogItem}
          keyExtractor={(item) => String(item.id)}
          contentContainerStyle={logs.length === 0 ? styles.flatListEmptyContent : styles.flatListContent}
          ListEmptyComponent={renderEmptyState}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    borderRadius: 8,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
  },
  actionButton: {
    padding: 8,
    marginLeft: 8,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  flatListContent: {
    paddingBottom: 20,
  },
  flatListEmptyContent: {
    flex: 1,
  },
  logItem: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  logHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  timestamp: {
    fontSize: 12,
    color: '#757575',
  },
  level: {
    fontSize: 12,
    fontWeight: '700',
  },
  message: {
    fontSize: 14,
    marginBottom: 4,
  },
  data: {
    fontSize: 12,
    color: '#757575',
    backgroundColor: '#f5f5f5',
    padding: 8,
    borderRadius: 4,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  emptyText: {
    fontSize: 16,
    color: '#9e9e9e',
    marginTop: 8,
  },
}); 