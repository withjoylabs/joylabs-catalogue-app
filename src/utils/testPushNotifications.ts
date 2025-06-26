import { apiClientInstance } from '../api/client';
import logger from './logger';
import PushNotificationService from '../services/pushNotificationService';

interface TestPushResponse {
  success: boolean;
  message?: string;
  error?: string;
}

/**
 * Test push notifications by sending a test notification through the backend
 * Returns detailed error information for debugging in EAS builds
 */
export const testPushNotifications = async (): Promise<{ success: boolean; debugInfo: string }> => {
  const tag = 'testPushNotifications';
  let debugInfo = '';
  
  try {
    debugInfo += 'Starting push notification test...\n';
    logger.info(tag, 'Testing push notifications...');
    
    // Check if push notifications are registered
    const pushService = PushNotificationService.getInstance();
    const pushToken = pushService.getPushToken();
    
    debugInfo += `Push token available: ${pushToken ? 'YES' : 'NO'}\n`;
    debugInfo += `Push token length: ${pushToken ? pushToken.length : 0}\n`;
    debugInfo += `Token preview: ${pushToken ? pushToken.substring(0, 20) + '...' : 'None'}\n`;
    
    if (!pushToken) {
      debugInfo += 'ERROR: No push token available - push notifications not registered\n';
      logger.error(tag, 'No push token available - push notifications not registered');
      return { success: false, debugInfo };
    }
    
    const isRegistered = pushService.isRegisteredForPushNotifications();
    debugInfo += `Registered with backend: ${isRegistered ? 'YES' : 'NO'}\n`;
    
    if (!isRegistered) {
      debugInfo += 'ERROR: Push notifications not registered with backend\n';
      logger.error(tag, 'Push notifications not registered with backend');
      return { success: false, debugInfo };
    }
    
    debugInfo += 'Sending test push notification to backend...\n';
    logger.info(tag, 'Sending test push notification...');
    
    // Call backend test endpoint
    const requestPayload = {
      message: 'Test push notification from app',
      title: 'Push Test',
      data: {
        type: 'test',
        timestamp: new Date().toISOString()
      }
    };
    
    debugInfo += `Request payload: ${JSON.stringify(requestPayload, null, 2)}\n`;
    
    const response = await apiClientInstance.post<TestPushResponse>('/api/test/push-notification', requestPayload);
    
    debugInfo += `Response status: ${response.status}\n`;
    debugInfo += `Response data: ${JSON.stringify(response.data, null, 2)}\n`;
    
    if (response.data.success) {
      debugInfo += 'SUCCESS: Test push notification sent successfully\n';
      logger.info(tag, 'Test push notification sent successfully');
      return { success: true, debugInfo };
    } else {
      debugInfo += `ERROR: Backend returned failure\n`;
      debugInfo += `Backend message: ${response.data.message || 'No message'}\n`;
      debugInfo += `Backend error: ${response.data.error || 'No error details'}\n`;
      logger.error(tag, 'Failed to send test push notification', {
        message: response.data.message,
        error: response.data.error
      });
      return { success: false, debugInfo };
    }
    
  } catch (error: any) {
    debugInfo += `EXCEPTION: ${error.message}\n`;
    debugInfo += `Error type: ${error.constructor.name}\n`;
    debugInfo += `Error code: ${error.code || 'No code'}\n`;
    
    if (error.response) {
      debugInfo += `HTTP Status: ${error.response.status}\n`;
      debugInfo += `HTTP Status Text: ${error.response.statusText}\n`;
      debugInfo += `Response data: ${JSON.stringify(error.response.data, null, 2)}\n`;
    } else if (error.request) {
      debugInfo += `Network error - no response received\n`;
      debugInfo += `Request details: ${JSON.stringify(error.request, null, 2)}\n`;
    }
    
    logger.error(tag, 'Error testing push notifications', { error: error.message });
    return { success: false, debugInfo };
  }
};

/**
 * Get push notification status for debugging
 */
export const getPushNotificationStatus = () => {
  const pushService = PushNotificationService.getInstance();
  
  return {
    hasToken: !!pushService.getPushToken(),
    token: pushService.getPushToken(),
    isRegistered: pushService.isRegisteredForPushNotifications(),
    timestamp: new Date().toISOString()
  };
}; 