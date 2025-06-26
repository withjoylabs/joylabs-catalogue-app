//IMPORTANT: THIS PAGE IS ACCESSED THROUGH THE NOTIFICATION BELL ICON IN THE HEADER OF INDEX.TSX - IT SHOULD BE HIDDEN FROM TAB FOOTER NAVIGATION BUT FOOTER SHOULD REMAIN VISIBLE

import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  StatusBar,
  Pressable,
  Alert,
  RefreshControl,
  StyleSheet,
  TouchableOpacity,
  Platform,
  Dimensions,
  SafeAreaView,
  ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';

import { lightTheme } from '../../../../src/themes';
import logger from '../../../../src/utils/logger';
import NotificationService, {
  AppNotification,
  NotificationServiceState,
  NotificationType
} from '../../../../src/services/notificationService';
import PushNotificationService from '../../../../src/services/pushNotificationService';
import { testPushNotifications } from '../../../../src/utils/testPushNotifications';
import tokenService from '../../../../src/services/tokenService';

// Notification type icons and colors
const NOTIFICATION_CONFIG: Record<NotificationType, { icon: string; color: string }> = {
  webhook_catalog_update: { icon: 'sync-outline', color: '#007AFF' },
  sync_complete: { icon: 'checkmark-circle-outline', color: '#34C759' },
  sync_error: { icon: 'alert-circle-outline', color: '#FF3B30' },
  sync_pending: { icon: 'time-outline', color: '#FF9500' },
  reorder_added: { icon: 'add-circle-outline', color: '#FF9500' },
  auth_success: { icon: 'person-circle-outline', color: '#34C759' },
  general_info: { icon: 'information-circle-outline', color: '#8E8E93' },
  system_error: { icon: 'warning-outline', color: '#FF3B30' },
};

const { width: screenWidth } = Dimensions.get('window');

// Custom Header Component with Back Button
const NotificationsHeader: React.FC<{ onBack: () => void }> = ({ onBack }) => {
  return (
    <View style={styles.customHeader}>
      <TouchableOpacity onPress={onBack} style={styles.backButton}>
        <Ionicons name="arrow-back" size={24} color="#000" />
      </TouchableOpacity>
      <Text style={styles.headerTitle}>Notifications</Text>
      <View style={styles.headerSpacer} />
    </View>
  );
};

// Square Token Debug Component
const SquareTokenDebugInfo: React.FC = () => {
  const [tokenInfo, setTokenInfo] = useState<{
    hasToken: boolean;
    tokenLength: number;
    status: string;
    error?: string;
  }>({
    hasToken: false,
    tokenLength: 0,
    status: 'checking...'
  });

  useEffect(() => {
    const checkTokenStatus = async () => {
      try {
        const token = await tokenService.getAccessToken();
        const status = await tokenService.checkTokenStatus();
        
        setTokenInfo({
          hasToken: !!token,
          tokenLength: token?.length || 0,
          status: status,
        });
      } catch (error) {
        setTokenInfo({
          hasToken: false,
          tokenLength: 0,
          status: 'error',
          error: error instanceof Error ? error.message : String(error)
        });
      }
    };

    checkTokenStatus();
  }, []);

  return (
    <>
      <Text style={styles.debugText}>
        Square Token: {tokenInfo.hasToken ? 'Available' : 'Missing'}
      </Text>
      <Text style={styles.debugText}>
        Token Length: {tokenInfo.tokenLength}
      </Text>
      <Text style={styles.debugText}>
        Token Status: {tokenInfo.status}
      </Text>
      {tokenInfo.error && (
        <Text style={[styles.debugText, { color: '#FF3B30' }]}>
          Error: {tokenInfo.error}
        </Text>
      )}
    </>
  );
};

export default function NotificationsScreen() {
  const router = useRouter();
  const [state, setState] = useState<NotificationServiceState>(NotificationService.getState());
  const [filter, setFilter] = useState<'all' | 'unread'>('all');
  const [refreshing, setRefreshing] = useState(false);
  const [showDebugInfo, setShowDebugInfo] = useState(false);
  const [testingPush, setTestingPush] = useState(false);





  // Subscribe to notification service updates
  useEffect(() => {
    const unsubscribe = NotificationService.subscribe(setState);
    return unsubscribe;
  }, []);

  // Filter notifications based on current filter
  const filteredNotifications = filter === 'unread' 
    ? state.notifications.filter(n => !n.read)
    : state.notifications;

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    setTimeout(() => {
      setRefreshing(false);
    }, 1000);
  }, []);

  const handleNotificationPress = useCallback((notification: AppNotification) => {
    if (!notification.read) {
      NotificationService.markAsRead(notification.id);
    }

    switch (notification.type) {
      case 'reorder_added':
        router.push('/(tabs)/reorders');
        break;
      default:
        logger.info('NotificationsScreen', 'Notification pressed', { type: notification.type });
    }
  }, [router]);

  const handleDeleteNotification = useCallback((notification: AppNotification) => {
    Alert.alert(
      'Delete Notification',
      'Are you sure you want to delete this notification?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => NotificationService.deleteNotification(notification.id),
        },
      ]
    );
  }, []);

  const handleMarkAllAsRead = useCallback(() => {
    NotificationService.markAllAsRead();
  }, []);

  const handleClearAll = useCallback(() => {
    Alert.alert(
      'Clear All Notifications',
      'Are you sure you want to delete all notifications?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Clear All',
          style: 'destructive',
          onPress: () => NotificationService.clearAllNotifications(),
        },
      ]
    );
  }, []);

  const handleTestPushNotifications = useCallback(async () => {
    setTestingPush(true);
    try {
      const result = await testPushNotifications();
      
      // Show detailed debug info in alert
      Alert.alert(
        'Push Notification Test',
        result.success 
          ? `✅ Test notification sent successfully!\n\nDebug Info:\n${result.debugInfo}`
          : `❌ Test failed. Debug Info:\n\n${result.debugInfo}`,
        [{ text: 'OK' }],
        { 
          // Make alert scrollable for long debug info
          userInterfaceStyle: 'light'
        }
      );
    } catch (error) {
      Alert.alert(
        'Push Notification Test Error', 
        `Unexpected error during test:\n${error instanceof Error ? error.message : String(error)}`,
        [{ text: 'OK' }]
      );
    } finally {
      setTestingPush(false);
    }
  }, []);

  const formatTimestamp = useCallback((timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    
    return date.toLocaleDateString();
  }, []);

  const renderNotificationItem = useCallback(({ item }: { item: AppNotification }) => {
    const config = NOTIFICATION_CONFIG[item.type] || NOTIFICATION_CONFIG.general_info;
    
    return (
      <Pressable
        style={[styles.notificationItem, !item.read && styles.unreadNotification]}
        onPress={() => handleNotificationPress(item)}
      >
        <View style={styles.notificationContent}>
          <View style={styles.notificationHeader}>
            <View style={styles.iconContainer}>
              <Ionicons 
                name={config.icon as any} 
                size={24} 
                color={config.color} 
              />
              {!item.read && <View style={styles.unreadDot} />}
            </View>
            <View style={styles.notificationDetails}>
              <Text style={[styles.notificationTitle, !item.read && styles.unreadTitle]}>
                {item.title}
              </Text>
              <Text style={styles.notificationMessage} numberOfLines={2}>
                {item.message}
              </Text>
              <View style={styles.notificationMeta}>
                <Text style={styles.timestamp}>{formatTimestamp(item.timestamp)}</Text>
                <Text style={styles.source}>{item.source}</Text>
                {item.priority === 'high' && (
                  <View style={styles.priorityBadge}>
                    <Text style={styles.priorityText}>High</Text>
                  </View>
                )}
              </View>
            </View>
            <Pressable
              style={styles.deleteButton}
              onPress={() => handleDeleteNotification(item)}
            >
              <Ionicons name="trash-outline" size={20} color="#FF3B30" />
            </Pressable>
          </View>
        </View>
      </Pressable>
    );
  }, [handleNotificationPress, handleDeleteNotification, formatTimestamp]);

  const renderEmptyState = useCallback(() => {
    const isFiltered = filter === 'unread';
    return (
      <View style={styles.emptyContainer}>
        <Ionicons 
          name={isFiltered ? "checkmark-circle-outline" : "notifications-outline"} 
          size={64} 
          color="#C7C7CC" 
        />
        <Text style={styles.emptyTitle}>
          {isFiltered ? 'All Caught Up!' : 'No Notifications'}
        </Text>
        <Text style={styles.emptyMessage}>
          {isFiltered 
            ? 'You have no unread notifications.' 
            : 'Notifications will appear here when you receive them.'
          }
        </Text>
      </View>
    );
  }, [filter]);

    return (
      <View style={styles.container}>
        <StatusBar barStyle="dark-content" backgroundColor={lightTheme.colors.background} />
            
            {/* Filter Section - Clean and Consistent */}
            <View style={styles.filterSection}>
              <View style={styles.filterRow}>
                <View style={styles.filterButtons}>
                  <Pressable
                    style={[styles.filterButton, filter === 'all' && styles.activeFilterButton]}
                    onPress={() => setFilter('all')}
                  >
                    <Text style={[styles.filterButtonText, filter === 'all' && styles.activeFilterButtonText]}>
                      All ({state.notifications.length})
                    </Text>
                  </Pressable>
                  <Pressable
                    style={[styles.filterButton, filter === 'unread' && styles.activeFilterButton]}
                    onPress={() => setFilter('unread')}
                  >
                    <Text style={[styles.filterButtonText, filter === 'unread' && styles.activeFilterButtonText]}>
                      Unread ({state.unreadCount})
                    </Text>
                  </Pressable>
                </View>

                  <View style={styles.actionButtons}>
                  {state.notifications.length > 0 && state.unreadCount > 0 && (
                      <Pressable style={styles.actionButton} onPress={handleMarkAllAsRead}>
                        <Text style={styles.actionButtonText}>Mark All Read</Text>
                      </Pressable>
                    )}
                  {state.notifications.length > 0 && (
                    <Pressable style={styles.actionButton} onPress={handleClearAll}>
                      <Text style={[styles.actionButtonText, styles.destructiveText]}>Clear All</Text>
                    </Pressable>
                  )}
                  <Pressable 
                    style={styles.actionButton} 
                    onPress={() => setShowDebugInfo(!showDebugInfo)}
                  >
                    <Text style={styles.actionButtonText}>Debug</Text>
                    </Pressable>
                  </View>
              </View>
            </View>

            {/* Debug Info Section */}
            {showDebugInfo && (
              <ScrollView style={styles.debugSection} contentContainerStyle={styles.debugScrollContent}>
                <Text style={styles.debugTitle}>Debug Information</Text>
                
                {/* Push Notification Debug */}
                <Text style={styles.debugSubtitle}>Push Notifications</Text>
                <Text style={styles.debugText}>
                  Push Token: {PushNotificationService.getInstance().getPushToken() ? 'Available' : 'Not registered'}
                </Text>
                <Text style={styles.debugText}>
                  Token Length: {PushNotificationService.getInstance().getPushToken()?.length || 0}
                </Text>
                <Text style={styles.debugText}>
                  Registered: {PushNotificationService.getInstance().isRegisteredForPushNotifications() ? 'Yes' : 'No'}
                </Text>
                
                {/* Square API Debug */}
                <Text style={styles.debugSubtitle}>Square API Status</Text>
                <SquareTokenDebugInfo />
                
                {/* Notification Stats */}
                <Text style={styles.debugSubtitle}>Notification Stats</Text>
                <Text style={styles.debugText}>
                  Total Notifications: {state.notifications.length}
                </Text>
                <Text style={styles.debugText}>
                  Unread Count: {state.unreadCount}
                </Text>
                <Text style={styles.debugText}>
                  Service Initialized: {state.isInitialized ? 'Yes' : 'No'}
                </Text>
                
                {/* Sync Trigger Info */}
                <Text style={styles.debugSubtitle}>Sync Architecture (Webhook-First)</Text>
                <Text style={styles.debugText}>
                  Primary: Webhooks/Push notifications
                </Text>
                <Text style={styles.debugText}>
                  Catch-up: Only when webhooks missed
                </Text>
                <Text style={styles.debugText}>
                  • First app launch (initial sync)
                </Text>
                <Text style={styles.debugText}>
                  • App closed &gt;30min + no webhooks &gt;6hrs
                </Text>
                <Text style={styles.debugText}>
                  • Push notification fallback
                </Text>
                <Text style={styles.debugText}>
                  No routine polling - webhooks handle all updates
                </Text>
                
                {/* Test Buttons */}
                <TouchableOpacity 
                  style={[styles.testButton, testingPush && styles.testButtonDisabled]}
                  onPress={handleTestPushNotifications}
                  disabled={testingPush}
                >
                  <Text style={styles.testButtonText}>
                    {testingPush ? 'Testing...' : 'Test Push Notification'}
                  </Text>
                </TouchableOpacity>
                
                <TouchableOpacity
                  style={styles.testButton}
                  onPress={() => {
                    import('../../../../src/utils/testNotifications').then(({ NotificationTester }) => {
                      NotificationTester.testCatchUpSyncFlow();
                    });
                  }}
                >
                  <Text style={styles.testButtonText}>Test Catch-up Flow</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={() => {
                    import('../../../../src/utils/testNotifications').then(({ NotificationTester }) => {
                      NotificationTester.testWebhookFlow();
                    });
                  }}
                >
                  <Text style={styles.testButtonText}>Test Webhook Flow</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={() => {
                    import('../../../../src/utils/testNotifications').then(({ NotificationTester }) => {
                      NotificationTester.testWebhookConnection();
                    });
                  }}
                >
                  <Text style={styles.testButtonText}>Test Webhook Connection</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={() => {
                    import('../../../../src/utils/testNotifications').then(({ NotificationTester }) => {
                      NotificationTester.testPushNotificationFlow();
                    });
                  }}
                >
                  <Text style={styles.testButtonText}>Test Push Notification Flow</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={async () => {
                    try {
                      const { status } = await import('expo-notifications').then(mod => mod.getPermissionsAsync());
                      const pushService = PushNotificationService.getInstance();
                      const detailedStatus = await pushService.getDetailedStatus();

                      const debugInfo = `Permission: ${status}
Has Token: ${detailedStatus.hasToken ? 'YES' : 'NO'}
Registered: ${detailedStatus.isRegistered ? 'YES' : 'NO'}
Merchant ID: ${detailedStatus.merchantId || 'MISSING'}
Token Preview: ${detailedStatus.token ? detailedStatus.token.substring(0, 20) + '...' : 'None'}`;

                      Alert.alert(
                        'Push Notification Debug',
                        debugInfo,
                        [{ text: 'OK' }]
                      );

                      logger.info('NotificationDebug', 'Push notification detailed status', {
                        permissionStatus: status,
                        detailedStatus,
                        timestamp: new Date().toISOString()
                      });
                    } catch (error) {
                      Alert.alert('Error', `Failed to check status: ${error}`);
                    }
                  }}
                >
                  <Text style={styles.testButtonText}>Check Push Status</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={async () => {
                    try {
                      // Send a local test notification to see if the app can handle notifications at all
                      const Notifications = await import('expo-notifications');

                      await Notifications.scheduleNotificationAsync({
                        content: {
                          title: '🧪 Local Test Notification',
                          body: 'Testing if app can receive notifications',
                          data: {
                            type: 'catalog_updated',
                            eventType: 'catalog.version.updated',
                            test: true
                          }
                        },
                        trigger: { seconds: 1 }
                      });

                      Alert.alert(
                        'Local Test Sent',
                        'A local test notification will appear in 1 second. Check if it triggers the sync.',
                        [{ text: 'OK' }]
                      );

                      logger.info('NotificationDebug', 'Local test notification scheduled');
                    } catch (error) {
                      const errorMessage = `Failed to send test notification: ${error}`;

                      Alert.alert(
                        'Local Test Error',
                        errorMessage,
                        [
                          {
                            text: 'Show Full Error',
                            onPress: () => {
                              console.log('FULL ERROR DETAILS:', errorMessage);
                              logger.error('LocalTestNotification', 'Full error details', { errorMessage });
                              Alert.alert('Error Logged', 'Full error details logged to console and app logs');
                            }
                          },
                          { text: 'OK' }
                        ]
                      );
                    }
                  }}
                >
                  <Text style={styles.testButtonText}>Send Local Test Notification</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.testButton}
                  onPress={async () => {
                    try {
                      const pushService = PushNotificationService.getInstance();
                      const detailedStatus = await pushService.getDetailedStatus();

                      if (detailedStatus.token) {
                        Alert.alert(
                          'Push Token Details',
                          `Token: ${detailedStatus.token}\n\nMerchant ID: ${detailedStatus.merchantId}\n\nCompare this token with what your backend has stored.`,
                          [
                            {
                              text: 'Log to Console',
                              onPress: () => {
                                console.log('PUSH TOKEN FOR BACKEND COMPARISON:', detailedStatus.token);
                                console.log('MERCHANT ID:', detailedStatus.merchantId);
                              }
                            },
                            { text: 'OK' }
                          ]
                        );

                        logger.info('NotificationDebug', 'Full push token for comparison', {
                          token: detailedStatus.token,
                          merchantId: detailedStatus.merchantId
                        });
                      } else {
                        Alert.alert('No Token', 'No push token found');
                      }
                    } catch (error) {
                      Alert.alert('Error', `Failed to get token: ${error}`);
                    }
                  }}
                >
                  <Text style={styles.testButtonText}>Show Push Token</Text>
                </TouchableOpacity>
              </ScrollView>
            )}

      <FlatList
        data={filteredNotifications}
        renderItem={renderNotificationItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContainer}
        ListEmptyComponent={renderEmptyState}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={lightTheme.colors.primary}
          />
        }
        showsVerticalScrollIndicator={false}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },

  // Clean filter section styles
  filterSection: {
    backgroundColor: lightTheme.colors.background,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
    paddingVertical: 12,
  },
  filterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
  },


  filterButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  filterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    backgroundColor: lightTheme.colors.background,
    marginRight: 8,
  },
  activeFilterButton: {
    backgroundColor: lightTheme.colors.primary,
    borderColor: lightTheme.colors.primary,
  },
  filterButtonText: {
    fontSize: 13,
    color: lightTheme.colors.text,
    fontWeight: '500',
  },
  activeFilterButtonText: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
  actionButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginLeft: 8,
    borderRadius: 6,
    backgroundColor: 'rgba(0, 122, 255, 0.1)',
  },
  actionButtonText: {
    fontSize: 13,
    fontWeight: '500',
    color: lightTheme.colors.primary,
  },
  destructiveText: {
    color: '#FF3B30',
  },
  listContainer: {
    flexGrow: 1,
  },
  notificationItem: {
    backgroundColor: '#FFFFFF',
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
  },
  unreadNotification: {
    backgroundColor: '#F8F9FA',
  },
  notificationContent: {
    padding: 16,
  },
  notificationHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  iconContainer: {
    position: 'relative',
    marginRight: 12,
    paddingTop: 2,
  },
  unreadDot: {
    position: 'absolute',
    top: -2,
    right: -2,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#FF3B30',
  },
  notificationDetails: {
    flex: 1,
    marginRight: 12,
  },
  notificationTitle: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.text,
    marginBottom: 4,
  },
  unreadTitle: {
    fontWeight: '600',
  },
  notificationMessage: {
    fontSize: 14,
    color: '#8E8E93',
    lineHeight: 20,
    marginBottom: 8,
  },
  notificationMeta: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  timestamp: {
    fontSize: 12,
    color: '#C7C7CC',
    marginRight: 12,
  },
  source: {
    fontSize: 12,
    color: '#C7C7CC',
    textTransform: 'capitalize',
    marginRight: 12,
  },
  priorityBadge: {
    backgroundColor: '#FF3B30',
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  priorityText: {
    fontSize: 10,
    fontWeight: '600',
    color: '#FFFFFF',
  },
  deleteButton: {
    padding: 8,
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 40,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 16,
    marginBottom: 8,
  },
  emptyMessage: {
    fontSize: 16,
    color: '#8E8E93',
    textAlign: 'center',
    lineHeight: 22,
  },
  debugSection: {
    backgroundColor: '#F8F9FA',
    maxHeight: 400, // Limit height so it's scrollable
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
  },
  debugScrollContent: {
    padding: 16,
    paddingBottom: 32, // Extra padding at bottom
  },
  debugTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 8,
  },
  debugSubtitle: {
    fontSize: 14,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 12,
    marginBottom: 6,
  },
  debugText: {
    fontSize: 12,
    color: '#8E8E93',
    marginBottom: 4,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  testButton: {
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 16,
    marginTop: 12,
    alignItems: 'center',
  },
  testButtonDisabled: {
    backgroundColor: '#C7C7CC',
  },
  testButtonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
}); 