import * as FileSystem from 'expo-file-system';
import { Image } from 'react-native';
import logger from '../utils/logger';

interface CacheEntry {
  url: string;
  localPath: string;
  timestamp: number;
  size: number;
}

interface CacheMetadata {
  entries: Record<string, CacheEntry>;
  totalSize: number;
  lastCleanup: number;
}

class ImageCacheService {
  private cacheDir: string;
  private metadataFile: string;
  private metadata: CacheMetadata;
  private maxCacheSize = 100 * 1024 * 1024; // 100MB
  private maxAge = 7 * 24 * 60 * 60 * 1000; // 7 days
  private initialized = false;
  private initPromise: Promise<void> | null = null;

  constructor() {
    this.cacheDir = `${FileSystem.cacheDirectory}images/`;
    this.metadataFile = `${this.cacheDir}metadata.json`;
    this.metadata = {
      entries: {},
      totalSize: 0,
      lastCleanup: Date.now()
    };
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;
    if (this.initPromise) return this.initPromise;

    this.initPromise = this._initialize();
    await this.initPromise;
  }

  private async _initialize(): Promise<void> {
    try {
      // Ensure cache directory exists
      const dirInfo = await FileSystem.getInfoAsync(this.cacheDir);
      if (!dirInfo.exists) {
        await FileSystem.makeDirectoryAsync(this.cacheDir, { intermediates: true });
        logger.info('ImageCacheService', 'Created cache directory');
      }

      // Load existing metadata
      const metadataInfo = await FileSystem.getInfoAsync(this.metadataFile);
      if (metadataInfo.exists) {
        try {
          const metadataContent = await FileSystem.readAsStringAsync(this.metadataFile);
          this.metadata = JSON.parse(metadataContent);
          logger.info('ImageCacheService', 'Loaded cache metadata', {
            entries: Object.keys(this.metadata.entries).length,
            totalSize: this.metadata.totalSize
          });
        } catch (error) {
          logger.error('ImageCacheService', 'Failed to parse metadata, resetting cache', error);
          await this.clearCache();
        }
      }

      // Clean up old entries if needed
      await this.cleanupIfNeeded();

      this.initialized = true;
      logger.info('ImageCacheService', 'Cache service initialized');
    } catch (error) {
      logger.error('ImageCacheService', 'Failed to initialize cache service', error);
      this.initialized = true; // Don't block the app
    }
  }

  private async saveMetadata(): Promise<void> {
    try {
      await FileSystem.writeAsStringAsync(this.metadataFile, JSON.stringify(this.metadata));
    } catch (error) {
      logger.error('ImageCacheService', 'Failed to save metadata', error);
    }
  }

  private getCacheKey(url: string): string {
    // Create a safe filename from URL
    return url.replace(/[^a-zA-Z0-9]/g, '_') + '_' + Date.now().toString(36);
  }

  private async cleanupIfNeeded(): Promise<void> {
    const now = Date.now();
    
    // Only cleanup once per day
    if (now - this.metadata.lastCleanup < 24 * 60 * 60 * 1000) {
      return;
    }

    logger.info('ImageCacheService', 'Starting cache cleanup');
    
    const entriesToRemove: string[] = [];
    let sizeToRemove = 0;

    // Remove expired entries
    for (const [key, entry] of Object.entries(this.metadata.entries)) {
      if (now - entry.timestamp > this.maxAge) {
        entriesToRemove.push(key);
        sizeToRemove += entry.size;
      }
    }

    // Remove oldest entries if cache is too large
    if (this.metadata.totalSize > this.maxCacheSize) {
      const sortedEntries = Object.entries(this.metadata.entries)
        .filter(([key]) => !entriesToRemove.includes(key))
        .sort(([, a], [, b]) => a.timestamp - b.timestamp);

      let currentSize = this.metadata.totalSize - sizeToRemove;
      for (const [key, entry] of sortedEntries) {
        if (currentSize <= this.maxCacheSize * 0.8) break; // Keep 80% of max size
        entriesToRemove.push(key);
        sizeToRemove += entry.size;
        currentSize -= entry.size;
      }
    }

    // Remove files and update metadata
    for (const key of entriesToRemove) {
      const entry = this.metadata.entries[key];
      try {
        const fileInfo = await FileSystem.getInfoAsync(entry.localPath);
        if (fileInfo.exists) {
          await FileSystem.deleteAsync(entry.localPath);
        }
      } catch (error) {
        logger.warn('ImageCacheService', 'Failed to delete cached file', { path: entry.localPath, error });
      }
      delete this.metadata.entries[key];
    }

    this.metadata.totalSize -= sizeToRemove;
    this.metadata.lastCleanup = now;
    await this.saveMetadata();

    logger.info('ImageCacheService', 'Cache cleanup completed', {
      removedEntries: entriesToRemove.length,
      sizeRemoved: sizeToRemove,
      remainingEntries: Object.keys(this.metadata.entries).length,
      remainingSize: this.metadata.totalSize
    });
  }

  async getCachedImagePath(url: string): Promise<string | null> {
    await this.initialize();

    // For local files, return as-is
    if (url.startsWith('file://')) {
      return url;
    }

    // Find existing cache entry
    const existingEntry = Object.values(this.metadata.entries).find(entry => entry.url === url);
    if (existingEntry) {
      // Check if file still exists
      const fileInfo = await FileSystem.getInfoAsync(existingEntry.localPath);
      if (fileInfo.exists) {
        // Update timestamp for LRU
        existingEntry.timestamp = Date.now();
        await this.saveMetadata();
        return existingEntry.localPath;
      } else {
        // File was deleted, remove from metadata
        const key = Object.keys(this.metadata.entries).find(k => this.metadata.entries[k] === existingEntry);
        if (key) {
          delete this.metadata.entries[key];
          this.metadata.totalSize -= existingEntry.size;
          await this.saveMetadata();
        }
      }
    }

    return null;
  }

  async cacheImage(url: string): Promise<string | null> {
    await this.initialize();

    try {
      // Don't cache local file URIs
      if (url.startsWith('file://')) {
        logger.info('ImageCacheService', 'Skipping cache for local file URI', { url });
        return url;
      }

      // Check if already cached
      const cachedPath = await this.getCachedImagePath(url);
      if (cachedPath) {
        return cachedPath;
      }

      // Download and cache the image
      const cacheKey = this.getCacheKey(url);
      const localPath = `${this.cacheDir}${cacheKey}.jpg`;

      logger.info('ImageCacheService', 'Downloading image', { url, localPath });

      const downloadResult = await FileSystem.downloadAsync(url, localPath);

      if (downloadResult.status === 200) {
        const fileInfo = await FileSystem.getInfoAsync(localPath);
        const size = fileInfo.size || 0;

        // Add to metadata
        this.metadata.entries[cacheKey] = {
          url,
          localPath,
          timestamp: Date.now(),
          size
        };
        this.metadata.totalSize += size;
        await this.saveMetadata();

        logger.info('ImageCacheService', 'Image cached successfully', { url, size });
        return localPath;
      } else {
        logger.warn('ImageCacheService', 'Failed to download image', { url, status: downloadResult.status });
        return null;
      }
    } catch (error) {
      logger.error('ImageCacheService', 'Error caching image', { url, error });
      return null;
    }
  }

  async preloadImage(url: string): Promise<void> {
    try {
      // For local files, just prefetch directly
      if (url.startsWith('file://')) {
        Image.prefetch(url);
        return;
      }

      // For remote URLs, cache then prefetch
      const cachedPath = await this.cacheImage(url);
      if (cachedPath) {
        // Preload into React Native's image cache
        Image.prefetch(cachedPath);
      }
    } catch (error) {
      logger.error('ImageCacheService', 'Error preloading image', { url, error });
    }
  }

  async clearCache(): Promise<void> {
    try {
      const dirInfo = await FileSystem.getInfoAsync(this.cacheDir);
      if (dirInfo.exists) {
        await FileSystem.deleteAsync(this.cacheDir);
        await FileSystem.makeDirectoryAsync(this.cacheDir, { intermediates: true });
      }
      
      this.metadata = {
        entries: {},
        totalSize: 0,
        lastCleanup: Date.now()
      };
      await this.saveMetadata();
      
      logger.info('ImageCacheService', 'Cache cleared');
    } catch (error) {
      logger.error('ImageCacheService', 'Error clearing cache', error);
    }
  }

  getCacheStats(): { entries: number; totalSize: number; maxSize: number } {
    return {
      entries: Object.keys(this.metadata.entries).length,
      totalSize: this.metadata.totalSize,
      maxSize: this.maxCacheSize
    };
  }
}

export const imageCacheService = new ImageCacheService();
