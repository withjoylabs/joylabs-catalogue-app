import React, { useState } from 'react';
import {
  View,
  Text,
  Image,
  TouchableOpacity,
  StyleSheet,
  Modal,
  Alert,
  ActivityIndicator,
  Pressable,
  ScrollView,
  useWindowDimensions
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import CachedImage from './CachedImage';

interface ItemImage {
  id: string;
  url: string;
  name: string;
}

interface ItemImageDisplayProps {
  images: ItemImage[];
  itemName: string;
  onImagePress?: (image: ItemImage, index: number) => void;
  onManageImages?: () => void;
  style?: any;
}

const ItemImageDisplay: React.FC<ItemImageDisplayProps> = ({
  images,
  itemName,
  onImagePress,
  onManageImages,
  style
}) => {

  const [imageLoadErrors, setImageLoadErrors] = useState<Set<string>>(new Set());
  const { width } = useWindowDimensions();

  // Determine if this is an iPad (tablet) based on screen width
  const isTablet = width >= 768;
  const imageSize = isTablet ? 240 : 160; // 3x bigger for iPad (80->240), 2x for iPhone (80->160)

  // Debug logging
  React.useEffect(() => {
    console.log('ItemImageDisplay: Received images:', images);
    console.log('ItemImageDisplay: Item name:', itemName);
    console.log('ItemImageDisplay: Device type:', isTablet ? 'iPad' : 'iPhone', 'Image size:', imageSize);
  }, [images, itemName, isTablet, imageSize]);

  // Get the first valid image or null
  const primaryImage = images && images.length > 0 ? images[0] : null;
  const hasMultipleImages = images && images.length > 1;

  // Handle image load error
  const handleImageError = (imageId: string) => {
    setImageLoadErrors(prev => new Set([...prev, imageId]));
  };

  // Check if image has error
  const hasImageError = (imageId: string) => {
    return imageLoadErrors.has(imageId);
  };

  // Generate fallback icon based on item name
  const generateFallbackIcon = () => {
    if (!itemName) return '📦';
    
    // Get first two letters of item name
    const letters = itemName.trim().substring(0, 2).toUpperCase();
    return letters;
  };

  // Handle image press - always go to management modal
  const handleImagePress = () => {
    if (onManageImages) {
      onManageImages();
    }
  };

  // Handle modal image press
  const handleModalImagePress = (image: ItemImage, index: number) => {
    setIsModalVisible(false);
    if (onImagePress) {
      onImagePress(image, index);
    }
  };

  // Render fallback when no images or image failed to load
  const renderFallback = () => (
    <View style={[styles.fallbackContainer, { width: imageSize, height: imageSize }]}>
      <Text style={[styles.fallbackText, { fontSize: imageSize * 0.3 }]}>{generateFallbackIcon()}</Text>
      {onManageImages && (
        <View style={styles.addIconContainer}>
          <Ionicons name="add-circle" size={Math.min(24, imageSize * 0.15)} color={lightTheme.colors.primary} />
        </View>
      )}
    </View>
  );

  // Render image with error handling
  const renderImage = (image: ItemImage, size: number = imageSize) => {
    if (!image.url || hasImageError(image.id)) {
      return renderFallback();
    }

    return (
      <CachedImage
        source={{ uri: image.url }}
        style={[styles.image, { width: size, height: size }]}
        fallbackStyle={[styles.fallbackContainer, { width: size, height: size }]}
        fallbackText={generateFallbackIcon()}
        onError={() => handleImageError(image.id)}
        resizeMode="cover"
        showLoadingIndicator={true}
      />
    );
  };

  return (
    <>
      <TouchableOpacity
        style={[styles.container, style]}
        onPress={handleImagePress}
        activeOpacity={0.7}
      >
        <View style={styles.imageContainer}>
          {primaryImage ? renderImage(primaryImage) : renderFallback()}
          
          {/* Multiple images indicator */}
          {hasMultipleImages && (
            <View style={styles.multipleIndicator}>
              <Text style={styles.multipleIndicatorText}>+{images.length - 1}</Text>
            </View>
          )}
          
          {/* Manage images button */}
          {onManageImages && (
            <TouchableOpacity
              style={styles.manageButton}
              onPress={(e) => {
                e.stopPropagation();
                onManageImages();
              }}
            >
              <Ionicons name="camera-outline" size={16} color={lightTheme.colors.primary} />
            </TouchableOpacity>
          )}
        </View>
      </TouchableOpacity>


    </>
  );
};

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  imageContainer: {
    position: 'relative',
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: lightTheme.colors.surface,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
  },
  image: {
    borderRadius: 8,
  },
  fallbackContainer: {
    backgroundColor: lightTheme.colors.surface,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
  },
  fallbackText: {
    fontSize: 24,
    fontWeight: '600',
    color: lightTheme.colors.textSecondary,
  },
  addIconContainer: {
    position: 'absolute',
    bottom: 4,
    right: 4,
    backgroundColor: lightTheme.colors.background,
    borderRadius: 10,
  },
  multipleIndicator: {
    position: 'absolute',
    top: 4,
    right: 4,
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 10,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  multipleIndicatorText: {
    color: 'white',
    fontSize: 10,
    fontWeight: '600',
  },
  manageButton: {
    position: 'absolute',
    bottom: 4,
    left: 4,
    backgroundColor: lightTheme.colors.background,
    borderRadius: 12,
    padding: 4,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    backgroundColor: lightTheme.colors.background,
    borderRadius: 12,
    padding: 20,
    maxWidth: '90%',
    maxHeight: '80%',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
  },
  closeButton: {
    padding: 4,
  },
  imageGallery: {
    flexDirection: 'row',
    gap: 12,
  },
  galleryImageContainer: {
    alignItems: 'center',
  },
  imageName: {
    marginTop: 8,
    fontSize: 12,
    color: lightTheme.colors.textSecondary,
    textAlign: 'center',
    maxWidth: 120,
  },
  manageImagesButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    padding: 12,
    backgroundColor: lightTheme.colors.surface,
    borderRadius: 8,
    gap: 8,
  },
  manageImagesButtonText: {
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },

});

export default ItemImageDisplay;
