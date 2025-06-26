import logger from '../utils/logger';
import AsyncStorage from '@react-native-async-storage/async-storage';

interface AppSyncRequestLog {
  operation: string;
  source: string;
  timestamp: number;
  userId?: string;
  variables?: any;
}

interface DailyUsage {
  date: string;
  requestCount: number;
  operations: Record<string, number>;
  sources: Record<string, number>;
}

class AppSyncMonitor {
  private static instance: AppSyncMonitor;
  private requestCount = 0;
  private dailyLimit = 500; // Even more conservative daily limit since no polling
  private requestLogs: AppSyncRequestLog[] = [];
  private lastResetDate = new Date().toDateString();

  static getInstance(): AppSyncMonitor {
    if (!AppSyncMonitor.instance) {
      AppSyncMonitor.instance = new AppSyncMonitor();
    }
    return AppSyncMonitor.instance;
  }

  async initialize() {
    try {
      // Load today's usage from storage
      const today = new Date().toDateString();
      const storedUsage = await AsyncStorage.getItem(`appsync_usage_${today}`);
      
      if (storedUsage) {
        const usage: DailyUsage = JSON.parse(storedUsage);
        this.requestCount = usage.requestCount;
        logger.info('AppSyncMonitor', `Loaded today's usage: ${this.requestCount} requests`);
      }
      
      // Clean up old usage data (keep last 7 days)
      this.cleanupOldUsageData();
    } catch (error) {
      logger.error('AppSyncMonitor', 'Failed to initialize', { error });
    }
  }

  async beforeRequest(operation: string, source: string, variables?: any, userId?: string): Promise<void> {
    try {
      // Check if we need to reset daily counter
      const today = new Date().toDateString();
      if (today !== this.lastResetDate) {
        await this.resetDailyCounter();
        this.lastResetDate = today;
      }

      // Check daily limit
      if (this.requestCount >= this.dailyLimit) {
        const error = new Error(`AppSync daily limit exceeded: ${this.requestCount}/${this.dailyLimit}`);
        logger.error('AppSyncMonitor', 'Daily limit exceeded', { 
          count: this.requestCount, 
          limit: this.dailyLimit,
          operation,
          source 
        });
        throw error;
      }

      // Log the request
      const requestLog: AppSyncRequestLog = {
        operation,
        source,
        timestamp: Date.now(),
        userId,
        variables: variables ? Object.keys(variables) : undefined // Don't log actual values for privacy
      };

      this.requestLogs.push(requestLog);
      this.requestCount++;

      // Keep only last 100 requests in memory
      if (this.requestLogs.length > 100) {
        this.requestLogs = this.requestLogs.slice(-100);
      }

      // Save usage to storage
      await this.saveUsageToStorage();

      logger.info('AppSyncMonitor', 'Request logged', {
        operation,
        source,
        dailyCount: this.requestCount,
        limit: this.dailyLimit
      });

      // Warn when approaching limit
      if (this.requestCount > this.dailyLimit * 0.8) {
        logger.warn('AppSyncMonitor', 'Approaching daily limit', {
          count: this.requestCount,
          limit: this.dailyLimit,
          percentage: Math.round((this.requestCount / this.dailyLimit) * 100)
        });
      }
    } catch (error) {
      logger.error('AppSyncMonitor', 'Error in beforeRequest', { error, operation, source });
      throw error;
    }
  }

  async afterRequest(operation: string, source: string, success: boolean, error?: any): Promise<void> {
    try {
      logger.debug('AppSyncMonitor', 'Request completed', {
        operation,
        source,
        success,
        error: error?.message
      });
    } catch (err) {
      logger.error('AppSyncMonitor', 'Error in afterRequest', { err });
    }
  }

  getDailyUsage(): { count: number; limit: number; percentage: number } {
    return {
      count: this.requestCount,
      limit: this.dailyLimit,
      percentage: Math.round((this.requestCount / this.dailyLimit) * 100)
    };
  }

  getRecentRequests(limit = 20): AppSyncRequestLog[] {
    return this.requestLogs.slice(-limit);
  }

  async getUsageHistory(days = 7): Promise<DailyUsage[]> {
    try {
      const history: DailyUsage[] = [];
      const today = new Date();
      
      for (let i = 0; i < days; i++) {
        const date = new Date(today);
        date.setDate(date.getDate() - i);
        const dateString = date.toDateString();
        
        const storedUsage = await AsyncStorage.getItem(`appsync_usage_${dateString}`);
        if (storedUsage) {
          history.push(JSON.parse(storedUsage));
        } else {
          history.push({
            date: dateString,
            requestCount: 0,
            operations: {},
            sources: {}
          });
        }
      }
      
      return history.reverse(); // Oldest first
    } catch (error) {
      logger.error('AppSyncMonitor', 'Failed to get usage history', { error });
      return [];
    }
  }

  private async resetDailyCounter(): Promise<void> {
    try {
      logger.info('AppSyncMonitor', 'Resetting daily counter', { 
        previousCount: this.requestCount,
        date: this.lastResetDate 
      });
      
      this.requestCount = 0;
      this.requestLogs = [];
    } catch (error) {
      logger.error('AppSyncMonitor', 'Failed to reset daily counter', { error });
    }
  }

  private async saveUsageToStorage(): Promise<void> {
    try {
      const today = new Date().toDateString();
      
      // Aggregate operations and sources
      const operations: Record<string, number> = {};
      const sources: Record<string, number> = {};
      
      this.requestLogs.forEach(log => {
        operations[log.operation] = (operations[log.operation] || 0) + 1;
        sources[log.source] = (sources[log.source] || 0) + 1;
      });

      const usage: DailyUsage = {
        date: today,
        requestCount: this.requestCount,
        operations,
        sources
      };

      await AsyncStorage.setItem(`appsync_usage_${today}`, JSON.stringify(usage));
    } catch (error) {
      logger.error('AppSyncMonitor', 'Failed to save usage to storage', { error });
    }
  }

  private async cleanupOldUsageData(): Promise<void> {
    try {
      const keys = await AsyncStorage.getAllKeys();
      const usageKeys = keys.filter(key => key.startsWith('appsync_usage_'));
      
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - 7); // Keep 7 days
      
      const keysToDelete = usageKeys.filter(key => {
        const dateString = key.replace('appsync_usage_', '');
        const date = new Date(dateString);
        return date < cutoffDate;
      });
      
      if (keysToDelete.length > 0) {
        await AsyncStorage.multiRemove(keysToDelete);
        logger.info('AppSyncMonitor', `Cleaned up ${keysToDelete.length} old usage records`);
      }
    } catch (error) {
      logger.error('AppSyncMonitor', 'Failed to cleanup old usage data', { error });
    }
  }

  // Emergency circuit breaker
  enableEmergencyMode(): void {
    this.dailyLimit = 100; // Drastically reduce limit
    logger.warn('AppSyncMonitor', 'Emergency mode enabled - daily limit reduced to 100');
  }

  disableEmergencyMode(): void {
    this.dailyLimit = 1000; // Restore normal limit
    logger.info('AppSyncMonitor', 'Emergency mode disabled - daily limit restored to 1000');
  }
}

export default AppSyncMonitor.getInstance();
