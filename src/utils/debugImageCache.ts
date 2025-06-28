import { imageCacheService } from '../services/imageCacheService';
import logger from './logger';

export const debugImageCache = {
  /**
   * Log current cache statistics
   */
  logStats: () => {
    const stats = imageCacheService.getCacheStats();
    logger.info('ImageCache:Debug', 'Cache Statistics', {
      entries: stats.entries,
      totalSize: `${(stats.totalSize / 1024 / 1024).toFixed(2)} MB`,
      maxSize: `${(stats.maxSize / 1024 / 1024).toFixed(2)} MB`,
      usage: `${((stats.totalSize / stats.maxSize) * 100).toFixed(1)}%`
    });
    
    console.log('🖼️ Image Cache Stats:', {
      entries: stats.entries,
      totalSize: `${(stats.totalSize / 1024 / 1024).toFixed(2)} MB`,
      maxSize: `${(stats.maxSize / 1024 / 1024).toFixed(2)} MB`,
      usage: `${((stats.totalSize / stats.maxSize) * 100).toFixed(1)}%`
    });
  },

  /**
   * Clear the entire cache
   */
  clearCache: async () => {
    try {
      await imageCacheService.clearCache();
      logger.info('ImageCache:Debug', 'Cache cleared successfully');
      console.log('🖼️ Image cache cleared');
    } catch (error) {
      logger.error('ImageCache:Debug', 'Failed to clear cache', error);
      console.error('❌ Failed to clear image cache:', error);
    }
  },

  /**
   * Test cache performance with a sample URL
   */
  testCachePerformance: async (url: string) => {
    const startTime = Date.now();
    
    try {
      // First load (should cache)
      const firstLoadStart = Date.now();
      const cachedPath1 = await imageCacheService.cacheImage(url);
      const firstLoadTime = Date.now() - firstLoadStart;
      
      // Second load (should be from cache)
      const secondLoadStart = Date.now();
      const cachedPath2 = await imageCacheService.getCachedImagePath(url);
      const secondLoadTime = Date.now() - secondLoadStart;
      
      const totalTime = Date.now() - startTime;
      
      const results = {
        url,
        firstLoad: `${firstLoadTime}ms`,
        secondLoad: `${secondLoadTime}ms`,
        totalTime: `${totalTime}ms`,
        cached: !!cachedPath1,
        fromCache: !!cachedPath2,
        speedImprovement: firstLoadTime > 0 ? `${((firstLoadTime - secondLoadTime) / firstLoadTime * 100).toFixed(1)}%` : 'N/A'
      };
      
      logger.info('ImageCache:Debug', 'Performance test results', results);
      console.log('🖼️ Cache Performance Test:', results);
      
      return results;
    } catch (error) {
      logger.error('ImageCache:Debug', 'Performance test failed', { url, error });
      console.error('❌ Cache performance test failed:', error);
      return null;
    }
  }
};

// Make it available globally for debugging
if (__DEV__) {
  (global as any).debugImageCache = debugImageCache;
  console.log('🖼️ Image cache debug utilities available as global.debugImageCache');
}
