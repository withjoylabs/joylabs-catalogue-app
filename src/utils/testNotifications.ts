import NotificationService from '../services/notificationService';
import logger from './logger';

const TAG = '[NotificationTest]';

/**
 * Test utility for demonstrating notification system functionality
 * This can be called from the debug screen or during development
 */
export class NotificationTester {
  
  public static async testWebhookNotifications(): Promise<void> {
    logger.info(TAG, 'Testing webhook notifications...');
    
    // Test webhook update notification
    NotificationService.addNotification({
      type: 'webhook_catalog_update',
      title: 'Test: Square Update Received',
      message: 'Catalog changes detected from Square',
      priority: 'normal',
      source: 'webhook'
    });

    // Test sync complete notification
    NotificationService.addNotification({
      type: 'sync_complete',
      title: 'Test: Sync Complete',
      message: '15 items synced from Square successfully',
      priority: 'normal',
      source: 'webhook'
    });

    // Test sync pending notification
    NotificationService.addNotification({
      type: 'sync_pending',
      title: 'Test: Sync Pending',
      message: '3 items waiting to sync (no internet connection)',
      priority: 'normal',
      source: 'internal'
    });

    // Test sync error notification
    NotificationService.addNotification({
      type: 'sync_error',
      title: 'Test: Sync Failed',
      message: 'Failed to sync catalog: Network timeout',
      priority: 'high',
      source: 'internal'
    });
  }

  public static async testAppNotifications(): Promise<void> {
    logger.info(TAG, 'Testing app notifications...');
    
    // Test reorder notification
    NotificationService.notifyReorderAdded('Premium Coffee Beans');

    // Test general info notification
    NotificationService.addNotification({
      type: 'general_info',
      title: 'Test: App Update',
      message: 'New features available in this version',
      priority: 'low',
      source: 'internal'
    });

    // Test system error notification
    NotificationService.addNotification({
      type: 'system_error',
      title: 'Test: System Error',
      message: 'Database connection temporarily unavailable',
      priority: 'high',
      source: 'internal'
    });
  }

  public static async testNotificationSettings(): Promise<void> {
    logger.info(TAG, 'Testing notification settings...');
    
    // Get current settings
    const currentSettings = await NotificationService.getNotificationSettings();
    logger.info(TAG, 'Current notification settings:', { currentSettings });

    // Test updating settings
    const testSettings = {
      ...currentSettings,
      webhookCatalogUpdate: false, // Disable webhook notifications for test
      syncComplete: true,
      syncError: true,
    };

    await NotificationService.updateNotificationSettings(testSettings);
    logger.info(TAG, 'Test settings updated:', { testSettings });

    // Restore original settings
    await NotificationService.updateNotificationSettings(currentSettings);
    logger.info(TAG, 'Original settings restored');
  }

  /**
   * Test the complete catch-up sync notification flow
   */
  public static async testCatchUpSyncFlow(): Promise<void> {
    logger.info(TAG, 'Testing catch-up sync notification flow...');
    
    // 1. Simulate catch-up sync check starting
    NotificationService.addNotification({
      type: 'sync_pending',
      title: 'Test: Checking for Updates',
      message: 'Checking if any catalog changes were missed while app was closed...',
      priority: 'low',
      source: 'internal'
    });

    // 2. Simulate catch-up sync needed
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'sync_pending',
        title: 'Test: Running Catch-up Sync',
        message: 'App was closed for 15 minutes - syncing missed changes...',
        priority: 'normal',
        source: 'internal'
      });
    }, 1000);

    // 3. Simulate 403 error
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'sync_error',
        title: 'Test: Authorization Error (403)',
        message: 'Square API access denied. Your authentication token may have expired. Try reconnecting to Square.',
        priority: 'high',
        source: 'internal'
      });
    }, 3000);

    logger.info(TAG, 'Catch-up sync flow test notifications added');
  }

  /**
   * Test webhook notification flow - matches real webhook notifications
   */
  public static async testWebhookFlow(): Promise<void> {
    logger.info(TAG, 'Testing webhook notification flow...');
    
    const mockEventId = 'test-' + Date.now().toString(36);
    
    // 1. Simulate webhook received (matches real notification)
    NotificationService.addNotification({
      type: 'webhook_catalog_update',
      title: '🔔 Square Webhook Received!',
      message: `Webhook event: catalog.version.updated | Event ID: ${mockEventId.substring(0, 8)}... | Processing catalog changes...`,
      priority: 'high',
      source: 'webhook'
    });

    // 2. Simulate webhook sync success (matches real notification)
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'sync_complete',
        title: '✅ Webhook Sync Complete',
        message: `Successfully processed Square webhook ${mockEventId.substring(0, 8)}... | Catalog updated with latest changes`,
        priority: 'normal',
        source: 'webhook'
      });
    }, 2000);

    logger.info(TAG, 'Webhook flow test notifications added - matches real webhook flow');
  }
  
  /**
   * Test webhook connection status notifications
   */
  public static async testWebhookConnection(): Promise<void> {
    logger.info(TAG, 'Testing webhook connection notifications...');
    
    // 1. Simulate connection established
    NotificationService.addNotification({
      type: 'general_info',
      title: '🔗 Webhook Connection Active',
      message: 'AppSync subscription established - ready to receive Square webhooks',
      priority: 'low',
      source: 'internal'
    });
    
    // 2. Simulate connection issue
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'system_error',
        title: '⚠️ Webhook Connection Lost',
        message: 'AppSync subscription error: Connection timeout | Attempting reconnect in 5s...',
        priority: 'high',
        source: 'internal'
      });
    }, 2000);
    
    // 3. Simulate reconnecting
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'general_info',
        title: '🔄 Reconnecting Webhooks',
        message: 'Attempting to restore webhook connection...',
        priority: 'normal',
        source: 'internal'
      });
    }, 4000);
    
         logger.info(TAG, 'Webhook connection test completed');
  }
  
  /**
   * Test push notification flow - simulates Square sending push notification
   */
  public static async testPushNotificationFlow(): Promise<void> {
    logger.info(TAG, 'Testing push notification flow...');
    
    // 1. Simulate push notification received from Square
    NotificationService.addNotification({
      type: 'webhook_catalog_update',
      title: '📱 Push Notification Received!',
      message: 'Square sent push notification: Catalog Updated | Triggering catch-up sync...',
      priority: 'high',
      source: 'push'
    });
    
    // 2. Simulate catch-up sync starting
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'sync_pending',
        title: 'Intelligent Sync Check',
        message: 'Checking if any webhook events were missed (webhook-first architecture)...',
        priority: 'low',
        source: 'internal'
      });
    }, 1000);
    
    // 3. Simulate catch-up sync completing
    setTimeout(() => {
      NotificationService.addNotification({
        type: 'sync_complete',
        title: '✅ Push Sync Complete',
        message: 'Successfully processed push notification trigger | Catalog is now up to date',
        priority: 'normal',
        source: 'push'
      });
    }, 3000);
    
    logger.info(TAG, 'Push notification flow test completed');
  }

  public static async runAllTests(): Promise<void> {
    logger.info(TAG, 'Running all notification tests...');
    
    try {
      await this.testWebhookNotifications();
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
      
      await this.testAppNotifications();
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
      
      await this.testNotificationSettings();
      
      logger.info(TAG, 'All notification tests completed successfully');
    } catch (error) {
      logger.error(TAG, 'Notification tests failed', { error });
    }
  }

  public static getTestInstructions(): string {
    return `
🔔 NOTIFICATION SYSTEM TEST INSTRUCTIONS

1. **Test Webhook Notifications:**
   - Go to debug screen and run webhook notification tests
   - Check notification center for webhook, sync complete, sync pending, and sync error notifications

2. **Test App Notifications:**
   - Run app notification tests to see reorder, general info, and system error notifications

3. **Test Notification Settings:**
   - Go to Profile > Settings > Notification Settings
   - Toggle different notification types on/off
   - Verify settings are saved and loaded correctly

4. **Test Real Webhook Flow:**
   - Make changes in Square Dashboard
   - Webhook should trigger sync and create notifications
   - Check notification center for real-time updates

5. **Test Offline Behavior:**
   - Turn off internet connection
   - Webhook events should create "sync pending" notifications
   - Turn internet back on to see sync complete notifications

6. **Test Notification Center:**
   - Open notification center from bell icon
   - Test mark as read/unread, delete, and clear all functions
   - Test filtering between all/unread notifications
    `;
  }
}

export default NotificationTester; 