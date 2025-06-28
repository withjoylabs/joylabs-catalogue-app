import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Alert,
  ActivityIndicator,
  Image,
  Pressable,
  SafeAreaView
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { lightTheme } from '../themes';
import logger from '../utils/logger';
import CachedImage from './CachedImage';
import { imageCacheService } from '../services/imageCacheService';

interface ItemImage {
  id: string;
  url: string;
  name: string;
}

interface ImageManagementModalProps {
  visible: boolean;
  onClose: () => void;
  images: ItemImage[];
  itemId: string;
  itemName: string;
  onImageUpload?: (imageUri: string, imageName: string) => Promise<void>;
  onImageUpdate?: (imageId: string, imageUri: string, imageName: string) => Promise<void>;
  onImageDelete?: (imageId: string) => Promise<void>;
}

const ImageManagementModal: React.FC<ImageManagementModalProps> = ({
  visible,
  onClose,
  images,
  itemId,
  itemName,
  onImageUpload,
  onImageUpdate,
  onImageDelete
}) => {
  const [isUploading, setIsUploading] = useState(false);
  const [deletingImageId, setDeletingImageId] = useState<string | null>(null);
  const [updatingImageId, setUpdatingImageId] = useState<string | null>(null);

  // Preload images when modal becomes visible
  useEffect(() => {
    if (visible && images.length > 0) {
      logger.info('ImageManagementModal', 'Preloading images for modal', { count: images.length });
      images.forEach(image => {
        if (image.url) {
          imageCacheService.preloadImage(image.url);
        }
      });
    }
  }, [visible, images]);

  // Request camera/gallery permissions
  const requestPermissions = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert(
        'Permission Required',
        'Sorry, we need camera roll permissions to upload images.'
      );
      return false;
    }
    return true;
  };

  // Handle image selection from gallery
  const handleSelectImage = async () => {
    try {
      logger.info('ImageManagementModal', 'Starting gallery image selection');

      const hasPermission = await requestPermissions();
      if (!hasPermission) {
        logger.warn('ImageManagementModal', 'Gallery permission denied');
        return;
      }

      logger.info('ImageManagementModal', 'Launching image library picker');
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ImagePicker.MediaType.Images,
        allowsEditing: true,
        aspect: [1, 1], // Square crop
        quality: 0.8,
        base64: false,
      });

      logger.info('ImageManagementModal', 'Image picker result', {
        canceled: result.canceled,
        hasAssets: result.assets?.length > 0,
        firstAsset: result.assets?.[0] ? {
          uri: result.assets[0].uri,
          fileName: result.assets[0].fileName,
          type: result.assets[0].type
        } : null
      });

      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        logger.info('ImageManagementModal', 'Processing selected image', {
          uri: asset.uri,
          fileName: asset.fileName
        });
        await handleUploadImage(asset.uri, asset.fileName || 'image.jpg');
      } else {
        logger.info('ImageManagementModal', 'Image selection canceled or no asset');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('ImageManagementModal', 'Error selecting image', {
        error: errorMessage,
        fullError: error,
        errorType: typeof error,
        errorKeys: error ? Object.keys(error) : []
      });
      Alert.alert('Error', `Failed to select image: ${errorMessage}`);
    }
  };

  // Handle camera capture
  const handleTakePhoto = async () => {
    try {
      const hasPermission = await requestPermissions();
      if (!hasPermission) return;

      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert(
          'Permission Required',
          'Sorry, we need camera permissions to take photos.'
        );
        return;
      }

      const result = await ImagePicker.launchCameraAsync({
        allowsEditing: true,
        aspect: [1, 1], // Square crop
        quality: 0.8,
        base64: false,
      });

      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        await handleUploadImage(asset.uri, `${itemName}_photo_${Date.now()}.jpg`);
      }
    } catch (error) {
      logger.error('ImageManagementModal', 'Error taking photo', error);
      Alert.alert('Error', 'Failed to take photo. Please try again.');
    }
  };

  // Handle image upload
  const handleUploadImage = async (imageUri: string, imageName: string) => {
    if (!onImageUpload) {
      Alert.alert('Error', 'Image upload not available');
      return;
    }

    setIsUploading(true);
    try {
      await onImageUpload(imageUri, imageName);

      // Preload the uploaded image for better performance
      imageCacheService.preloadImage(imageUri);

      Alert.alert('Success', 'Image uploaded successfully!');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('ImageManagementModal', 'Error uploading image', { error: errorMessage, fullError: error });
      Alert.alert('Error', `Failed to upload image: ${errorMessage}`);
    } finally {
      setIsUploading(false);
    }
  };

  // Handle image update
  const handleUpdateImage = async (imageId: string) => {
    if (!onImageUpdate) {
      Alert.alert('Error', 'Image update not available');
      return;
    }

    try {
      const hasPermission = await requestPermissions();
      if (!hasPermission) return;

      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ImagePicker.MediaType.Images,
        allowsEditing: true,
        aspect: [1, 1], // Square crop
        quality: 0.8,
        base64: false,
      });

      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        setUpdatingImageId(imageId);
        
        try {
          await onImageUpdate(imageId, asset.uri, asset.fileName || 'updated_image.jpg');

          // Preload the updated image for better performance
          imageCacheService.preloadImage(asset.uri);

          Alert.alert('Success', 'Image updated successfully!');
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : 'Unknown error';
          logger.error('ImageManagementModal', 'Error updating image', { error: errorMessage, fullError: error });
          Alert.alert('Error', `Failed to update image: ${errorMessage}`);
        } finally {
          setUpdatingImageId(null);
        }
      }
    } catch (error) {
      logger.error('ImageManagementModal', 'Error selecting image for update', error);
      Alert.alert('Error', 'Failed to select image. Please try again.');
    }
  };

  // Handle image deletion
  const handleDeleteImage = async (imageId: string) => {
    if (!onImageDelete) {
      Alert.alert('Error', 'Image deletion not available');
      return;
    }

    Alert.alert(
      'Delete Image',
      'Are you sure you want to delete this image? This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            setDeletingImageId(imageId);
            try {
              await onImageDelete(imageId);
              Alert.alert('Success', 'Image deleted successfully!');
            } catch (error) {
              logger.error('ImageManagementModal', 'Error deleting image', error);
              Alert.alert('Error', 'Failed to delete image. Please try again.');
            } finally {
              setDeletingImageId(null);
            }
          }
        }
      ]
    );
  };

  // Show action options for image
  const showImageOptions = (image: ItemImage) => {
    Alert.alert(
      'Image Options',
      `What would you like to do with this image?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Update',
          onPress: () => handleUpdateImage(image.id)
        },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => handleDeleteImage(image.id)
        }
      ]
    );
  };

  return (
    <Modal
      visible={visible}
      animationType="fade"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <SafeAreaView style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Ionicons name="close" size={24} color={lightTheme.colors.text} />
          </TouchableOpacity>
          <Text style={styles.title}>Manage Images</Text>
          <View style={styles.placeholder} />
        </View>

        {/* Content */}
        <ScrollView style={styles.content} contentContainerStyle={styles.contentContainer}>
          {/* Item Info */}
          <View style={styles.itemInfo}>
            <Text style={styles.itemName}>{itemName}</Text>
            <Text style={styles.itemId}>ID: {itemId}</Text>
          </View>

          {/* Add Image Buttons */}
          <View style={styles.addImageSection}>
            <Text style={styles.sectionTitle}>Add New Image</Text>
            <View style={styles.addImageButtons}>
              <TouchableOpacity
                style={styles.addImageButton}
                onPress={handleTakePhoto}
                disabled={isUploading}
              >
                <Ionicons name="camera" size={24} color={lightTheme.colors.primary} />
                <Text style={styles.addImageButtonText}>Take Photo</Text>
              </TouchableOpacity>
              
              <TouchableOpacity
                style={styles.addImageButton}
                onPress={handleSelectImage}
                disabled={isUploading}
              >
                <Ionicons name="image" size={24} color={lightTheme.colors.primary} />
                <Text style={styles.addImageButtonText}>Choose from Gallery</Text>
              </TouchableOpacity>
            </View>
            
            {isUploading && (
              <View style={styles.uploadingContainer}>
                <ActivityIndicator size="small" color={lightTheme.colors.primary} />
                <Text style={styles.uploadingText}>Uploading image...</Text>
              </View>
            )}
          </View>

          {/* Existing Images */}
          <View style={styles.existingImagesSection}>
            <Text style={styles.sectionTitle}>
              Current Images ({images.length})
            </Text>
            
            {images.length === 0 ? (
              <View style={styles.noImagesContainer}>
                <Ionicons name="image-outline" size={48} color={lightTheme.colors.textSecondary} />
                <Text style={styles.noImagesText}>No images yet</Text>
                <Text style={styles.noImagesSubtext}>Add your first image using the buttons above</Text>
              </View>
            ) : (
              <View style={styles.imagesGrid}>
                {images.map((image, index) => (
                  <TouchableOpacity
                    key={image.id}
                    style={styles.imageItem}
                    onPress={() => showImageOptions(image)}
                  >
                    <CachedImage
                      source={{ uri: image.url }}
                      style={styles.imagePreview}
                      fallbackStyle={styles.imagePreviewFallback}
                      fallbackText={image.name ? image.name.substring(0, 2).toUpperCase() : '📷'}
                      showLoadingIndicator={true}
                      resizeMode="cover"
                    />
                    <Text style={styles.imageName} numberOfLines={2}>
                      {image.name || `Image ${index + 1}`}
                    </Text>
                    
                    {/* Loading overlay */}
                    {(deletingImageId === image.id || updatingImageId === image.id) && (
                      <View style={styles.imageLoadingOverlay}>
                        <ActivityIndicator size="small" color="white" />
                      </View>
                    )}
                    
                    {/* Primary image indicator */}
                    {index === 0 && (
                      <View style={styles.primaryIndicator}>
                        <Text style={styles.primaryIndicatorText}>Primary</Text>
                      </View>
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            )}
          </View>
        </ScrollView>
      </SafeAreaView>
    </Modal>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  closeButton: {
    padding: 8,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
  },
  placeholder: {
    width: 40,
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    padding: 16,
  },
  itemInfo: {
    backgroundColor: lightTheme.colors.surface,
    padding: 16,
    borderRadius: 8,
    marginBottom: 24,
  },
  itemName: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 4,
  },
  itemId: {
    fontSize: 14,
    color: lightTheme.colors.textSecondary,
  },
  addImageSection: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 12,
  },
  addImageButtons: {
    flexDirection: 'row',
    gap: 12,
  },
  addImageButton: {
    flex: 1,
    alignItems: 'center',
    padding: 16,
    backgroundColor: lightTheme.colors.surface,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: lightTheme.colors.border,
    gap: 8,
  },
  addImageButtonText: {
    fontSize: 14,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  uploadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
    gap: 8,
  },
  uploadingText: {
    fontSize: 14,
    color: lightTheme.colors.textSecondary,
  },
  existingImagesSection: {
    flex: 1,
  },
  noImagesContainer: {
    alignItems: 'center',
    padding: 32,
    backgroundColor: lightTheme.colors.surface,
    borderRadius: 8,
  },
  noImagesText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.textSecondary,
    marginTop: 12,
  },
  noImagesSubtext: {
    fontSize: 14,
    color: lightTheme.colors.textSecondary,
    textAlign: 'center',
    marginTop: 4,
  },
  imagesGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  imageItem: {
    width: '48%',
    backgroundColor: lightTheme.colors.surface,
    borderRadius: 8,
    padding: 8,
    position: 'relative',
  },
  imagePreview: {
    width: '100%',
    aspectRatio: 1,
    borderRadius: 4,
    backgroundColor: lightTheme.colors.border,
  },
  imagePreviewFallback: {
    width: '100%',
    aspectRatio: 1,
    borderRadius: 4,
    backgroundColor: '#f5f5f5',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  imageName: {
    fontSize: 12,
    color: lightTheme.colors.textSecondary,
    marginTop: 8,
    textAlign: 'center',
  },
  imageLoadingOverlay: {
    position: 'absolute',
    top: 8,
    left: 8,
    right: 8,
    bottom: 8,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryIndicator: {
    position: 'absolute',
    top: 12,
    right: 12,
    backgroundColor: lightTheme.colors.primary,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  primaryIndicatorText: {
    fontSize: 10,
    color: 'white',
    fontWeight: '600',
  },
});

export default ImageManagementModal;
