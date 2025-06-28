import React, { useState, useEffect, useCallback } from 'react';
import {
  Image,
  View,
  ActivityIndicator,
  StyleSheet,
  ImageStyle,
  ViewStyle,
  Text
} from 'react-native';
import { imageCacheService } from '../services/imageCacheService';
import { lightTheme } from '../themes';
import logger from '../utils/logger';

interface CachedImageProps {
  source: { uri: string };
  style?: ImageStyle;
  fallbackStyle?: ViewStyle;
  fallbackText?: string;
  resizeMode?: 'cover' | 'contain' | 'stretch' | 'repeat' | 'center';
  onLoad?: () => void;
  onError?: () => void;
  showLoadingIndicator?: boolean;
  placeholder?: React.ReactNode;
}

const CachedImage: React.FC<CachedImageProps> = ({
  source,
  style,
  fallbackStyle,
  fallbackText,
  resizeMode = 'cover',
  onLoad,
  onError,
  showLoadingIndicator = true,
  placeholder
}) => {
  const [imageState, setImageState] = useState<'loading' | 'loaded' | 'error' | 'cached'>('loading');
  const [cachedUri, setCachedUri] = useState<string | null>(null);

  const loadImage = useCallback(async () => {
    if (!source?.uri) {
      setImageState('error');
      return;
    }

    try {
      setImageState('loading');

      // Check if this is a local file URI (from image picker)
      if (source.uri.startsWith('file://')) {
        // For local files, use directly without caching
        setCachedUri(source.uri);
        setImageState('loaded');
        onLoad?.();
        return;
      }

      // For remote URLs, use caching
      // First check if already cached
      const cachedPath = await imageCacheService.getCachedImagePath(source.uri);
      if (cachedPath) {
        setCachedUri(cachedPath);
        setImageState('cached');
        onLoad?.();
        return;
      }

      // If not cached, try to cache it
      const newCachedPath = await imageCacheService.cacheImage(source.uri);
      if (newCachedPath) {
        setCachedUri(newCachedPath);
        setImageState('loaded');
        onLoad?.();
      } else {
        // Fallback to original URL if caching fails
        setCachedUri(source.uri);
        setImageState('loaded');
      }
    } catch (error) {
      logger.error('CachedImage', 'Error loading image', { uri: source.uri, error });
      setImageState('error');
      onError?.();
    }
  }, [source.uri, onLoad, onError]);

  useEffect(() => {
    loadImage();
  }, [loadImage]);

  const handleImageLoad = useCallback(() => {
    if (imageState === 'loading') {
      setImageState('loaded');
    }
    onLoad?.();
  }, [imageState, onLoad]);

  const handleImageError = useCallback(() => {
    logger.warn('CachedImage', 'Image failed to load', { uri: source.uri, cachedUri });
    setImageState('error');
    onError?.();
  }, [source.uri, cachedUri, onError]);

  // Show loading state
  if (imageState === 'loading') {
    if (placeholder) {
      return <View style={style}>{placeholder}</View>;
    }

    return (
      <View style={[styles.loadingContainer, style, fallbackStyle]}>
        {showLoadingIndicator && (
          <ActivityIndicator 
            size="small" 
            color={lightTheme.colors.primary} 
          />
        )}
      </View>
    );
  }

  // Show error state
  if (imageState === 'error') {
    return (
      <View style={[styles.errorContainer, style, fallbackStyle]}>
        {fallbackText ? (
          <Text style={styles.fallbackText}>{fallbackText}</Text>
        ) : (
          <Text style={styles.errorText}>?</Text>
        )}
      </View>
    );
  }

  // Show cached or loaded image
  if (cachedUri) {
    return (
      <Image
        source={{ uri: cachedUri }}
        style={style}
        resizeMode={resizeMode}
        onLoad={handleImageLoad}
        onError={handleImageError}
      />
    );
  }

  // Fallback
  return (
    <View style={[styles.errorContainer, style, fallbackStyle]}>
      {fallbackText ? (
        <Text style={styles.fallbackText}>{fallbackText}</Text>
      ) : (
        <Text style={styles.errorText}>?</Text>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    backgroundColor: '#f5f5f5',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 6,
  },
  errorContainer: {
    backgroundColor: '#f5f5f5',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  fallbackText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
  },
  errorText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#999',
  },
});

export default CachedImage;
