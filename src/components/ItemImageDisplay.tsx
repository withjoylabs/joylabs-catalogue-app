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
  ScrollView
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

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
  const [isModalVisible, setIsModalVisible] = useState(false);
  const [selectedImageIndex, setSelectedImageIndex] = useState(0);
  const [imageLoadErrors, setImageLoadErrors] = useState<Set<string>>(new Set());

  // Debug logging
  React.useEffect(() => {
    console.log('ItemImageDisplay: Received images:', images);
    console.log('ItemImageDisplay: Item name:', itemName);
  }, [images, itemName]);

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

  // Handle image press
  const handleImagePress = () => {
    if (primaryImage && onImagePress) {
      onImagePress(primaryImage, 0);
    } else if (hasMultipleImages) {
      setIsModalVisible(true);
    } else if (onManageImages) {
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
    <View style={styles.fallbackContainer}>
      <Text style={styles.fallbackText}>{generateFallbackIcon()}</Text>
      {onManageImages && (
        <View style={styles.addIconContainer}>
          <Ionicons name="add-circle" size={20} color={lightTheme.colors.primary} />
        </View>
      )}
    </View>
  );

  // Render image with error handling
  const renderImage = (image: ItemImage, size: number = 80) => {
    if (!image.url || hasImageError(image.id)) {
      return renderFallback();
    }

    return (
      <Image
        source={{ uri: image.url }}
        style={[styles.image, { width: size, height: size }]}
        onError={() => handleImageError(image.id)}
        resizeMode="cover"
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

      {/* Image gallery modal */}
      <Modal
        visible={isModalVisible}
        transparent={true}
        animationType="fade"
        onRequestClose={() => setIsModalVisible(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setIsModalVisible(false)}
        >
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Item Images</Text>
              <TouchableOpacity
                onPress={() => setIsModalVisible(false)}
                style={styles.closeButton}
              >
                <Ionicons name="close" size={24} color={lightTheme.colors.text} />
              </TouchableOpacity>
            </View>
            
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.imageGallery}
            >
              {images.map((image, index) => (
                <TouchableOpacity
                  key={image.id}
                  style={styles.galleryImageContainer}
                  onPress={() => handleModalImagePress(image, index)}
                >
                  {renderImage(image, 120)}
                  {image.name && (
                    <Text style={styles.imageName} numberOfLines={2}>
                      {image.name}
                    </Text>
                  )}
                </TouchableOpacity>
              ))}
            </ScrollView>
            
            {onManageImages && (
              <TouchableOpacity
                style={styles.manageImagesButton}
                onPress={() => {
                  setIsModalVisible(false);
                  onManageImages();
                }}
              >
                <Ionicons name="settings-outline" size={20} color={lightTheme.colors.primary} />
                <Text style={styles.manageImagesButtonText}>Manage Images</Text>
              </TouchableOpacity>
            )}
          </View>
        </Pressable>
      </Modal>
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
    width: 80,
    height: 80,
    borderRadius: 8,
  },
  fallbackContainer: {
    width: 80,
    height: 80,
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
