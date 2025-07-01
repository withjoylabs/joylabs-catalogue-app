import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  StyleSheet,
  Image,
  FlatList,
  Dimensions,
  SafeAreaView,
  Alert,
  ActivityIndicator
} from 'react-native';
import {
  PanGestureHandler,
  PinchGestureHandler,
  State
} from 'react-native-gesture-handler';
import Animated, {
  useAnimatedGestureHandler,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  runOnJS
} from 'react-native-reanimated';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as MediaLibrary from 'expo-media-library';
import * as ImageManipulator from 'expo-image-manipulator';
import { lightTheme } from '../themes';
import logger from '../utils/logger';
import { imageEnhancementService } from '../services/imageEnhancementService';

interface InstagramStyleImagePickerProps {
  visible: boolean;
  onClose: () => void;
  onImageSelected: (imageUri: string, imageName: string) => Promise<void>;
  itemName: string;
}

interface GalleryAsset {
  id: string;
  uri: string;
  filename: string;
  width: number;
  height: number;
}

const { width: screenWidth, height: screenHeight } = Dimensions.get('window');
const PREVIEW_SIZE = screenWidth; // Square preview
const GALLERY_HEIGHT = screenHeight - PREVIEW_SIZE - 120; // Remaining space for gallery

const InstagramStyleImagePicker: React.FC<InstagramStyleImagePickerProps> = ({
  visible,
  onClose,
  onImageSelected,
  itemName
}) => {
  const [currentStep, setCurrentStep] = useState<'gallery' | 'enhance'>('gallery');
  const [galleryAssets, setGalleryAssets] = useState<GalleryAsset[]>([]);
  const [selectedAsset, setSelectedAsset] = useState<GalleryAsset | null>(null);
  const [isLoadingGallery, setIsLoadingGallery] = useState(false);
  const [permissionResponse, requestPermission] = MediaLibrary.usePermissions();
  const [isEnhanced, setIsEnhanced] = useState(false);
  const [enhancedUri, setEnhancedUri] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [cropData, setCropData] = useState<{
    scale: number;
    translateX: number;
    translateY: number;
  }>({ scale: 1, translateX: 0, translateY: 0 });

  // Animated values for crop preview
  const scale = useSharedValue(1);
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const savedScale = useSharedValue(1);
  const savedTranslateX = useSharedValue(0);
  const savedTranslateY = useSharedValue(0);

  // Reset crop values when asset changes
  const resetCropValues = () => {
    scale.value = 1;
    translateX.value = 0;
    translateY.value = 0;
    savedScale.value = 1;
    savedTranslateX.value = 0;
    savedTranslateY.value = 0;
    setCropData({ scale: 1, translateX: 0, translateY: 0 });
  };

  // Load gallery assets when modal opens
  useEffect(() => {
    if (visible) {
      loadGalleryAssets();
      setCurrentStep('gallery');
      setSelectedAsset(null);
      setIsEnhanced(false);
      setEnhancedUri(null);
    }
  }, [visible]);

  const loadGalleryAssets = async () => {
    try {
      setIsLoadingGallery(true);

      // Check permissions using the hook
      if (permissionResponse?.status !== 'granted') {
        const newPermission = await requestPermission();
        if (newPermission.status !== 'granted') {
          Alert.alert('Permission Required', 'We need access to your photos to show the gallery.');
          return;
        }
      }

      // Get recent photos from the user's gallery using current API
      const result = await MediaLibrary.getAssetsAsync({
        mediaType: MediaLibrary.MediaType.photo,
        first: 200, // Load more photos like Instagram
        sortBy: MediaLibrary.SortBy.creationTime
      });

      if (result.assets.length === 0) {
        Alert.alert('No Photos', 'No photos found in your gallery.');
        return;
      }

      // Convert ph:// URIs to actual file URIs that React Native can display
      const assets: GalleryAsset[] = [];

      // Process first 20 assets immediately for faster initial load
      const assetsToProcess = result.assets.slice(0, 20);

      // Process in smaller batches with immediate UI updates
      const batchSize = 5;
      for (let i = 0; i < assetsToProcess.length; i += batchSize) {
        const batch = assetsToProcess.slice(i, i + batchSize);

        // Process batch
        const batchAssets = await Promise.all(
          batch.map(async (asset) => {
            try {
              const assetInfo = await MediaLibrary.getAssetInfoAsync(asset.id);
              return {
                id: asset.id,
                uri: assetInfo.localUri || asset.uri,
                filename: asset.filename || 'Photo',
                width: asset.width,
                height: asset.height
              };
            } catch (error) {
              return null;
            }
          })
        );

        // Add successful assets and update UI immediately
        const validAssets = batchAssets.filter(asset => asset !== null);
        assets.push(...validAssets);

        // Update UI with current batch
        if (assets.length > 0) {
          setGalleryAssets([...assets]);

          // Auto-select first photo on first batch
          if (i === 0 && assets.length > 0 && !selectedAsset) {
            setSelectedAsset(assets[0]);
          }
        }
      }

      // Final update with all assets
      setGalleryAssets(assets);
    } catch (error) {
      logger.error('InstagramStyleImagePicker', 'Failed to load gallery', {
        error: error instanceof Error ? error.message : 'Unknown error',
        errorName: error instanceof Error ? error.name : 'Unknown',
        errorStack: error instanceof Error ? error.stack : 'No stack',
        fullError: error
      });
      Alert.alert('Error', `Failed to load gallery: ${error instanceof Error ? error.message : 'Unknown error'}`);
    } finally {
      setIsLoadingGallery(false);
    }
  };

  const handleTakePhoto = async () => {
    try {
      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission Required', 'We need camera permissions to take photos.');
        return;
      }

      const result = await ImagePicker.launchCameraAsync({
        mediaTypes: ['images'],
        allowsEditing: true,
        aspect: [1, 1],
        quality: 0.8,
        base64: false,
      });

      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        const newAsset: GalleryAsset = {
          id: `camera_${Date.now()}`,
          uri: asset.uri,
          filename: `${itemName}_photo_${Date.now()}.jpg`,
          width: asset.width,
          height: asset.height
        };
        
        setSelectedAsset(newAsset);
        setCurrentStep('enhance');
      }
    } catch (error) {
      logger.error('InstagramStyleImagePicker', 'Camera error', error);
      Alert.alert('Error', 'Failed to take photo. Please try again.');
    }
  };

  const handleAssetSelect = (asset: GalleryAsset) => {
    setSelectedAsset(asset);
    resetCropValues(); // Reset crop when selecting new image
  };

  // Pinch gesture handler for zoom
  const pinchGestureHandler = useAnimatedGestureHandler({
    onStart: (_, context) => {
      context.startScale = scale.value;
    },
    onActive: (event, context) => {
      const newScale = context.startScale * event.scale;
      // Limit zoom between 1x and 3x
      scale.value = Math.max(1, Math.min(3, newScale));
    },
    onEnd: () => {
      savedScale.value = scale.value;

      // Save crop data for preservation
      runOnJS(setCropData)({
        scale: scale.value,
        translateX: translateX.value,
        translateY: translateY.value
      });
    },
  });

  // Pan gesture handler for moving the image
  const panGestureHandler = useAnimatedGestureHandler({
    onStart: (_, context) => {
      context.startX = translateX.value;
      context.startY = translateY.value;
    },
    onActive: (event, context) => {
      if (!selectedAsset) return;

      // Calculate bounds based on actual image dimensions and current scale
      const imageWidth = selectedAsset.width;
      const imageHeight = selectedAsset.height;
      const containerSize = PREVIEW_SIZE;

      // Calculate how the image fits in the container (using contain logic)
      const imageAspect = imageWidth / imageHeight;

      let displayWidth, displayHeight;
      if (imageAspect > 1) {
        // Image is wider - fit by height
        displayHeight = containerSize;
        displayWidth = displayHeight * imageAspect;
      } else {
        // Image is taller - fit by width
        displayWidth = containerSize;
        displayHeight = displayWidth / imageAspect;
      }

      // Apply current scale to get actual rendered size
      const scaledWidth = displayWidth * scale.value;
      const scaledHeight = displayHeight * scale.value;

      // Calculate max translation for each axis based on how much the scaled image exceeds container
      const maxTranslateX = Math.max(0, (scaledWidth - containerSize) / 2);
      const maxTranslateY = Math.max(0, (scaledHeight - containerSize) / 2);

      // Apply 1:1 movement with proper constraints
      const newTranslateX = context.startX + event.translationX;
      const newTranslateY = context.startY + event.translationY;

      translateX.value = Math.max(-maxTranslateX, Math.min(maxTranslateX, newTranslateX));
      translateY.value = Math.max(-maxTranslateY, Math.min(maxTranslateY, newTranslateY));
    },
    onEnd: () => {
      savedTranslateX.value = translateX.value;
      savedTranslateY.value = translateY.value;

      // Save crop data for preservation
      runOnJS(setCropData)({
        scale: scale.value,
        translateX: translateX.value,
        translateY: translateY.value
      });
    },
  });

  // Animated style for the image
  const animatedImageStyle = useAnimatedStyle(() => {
    return {
      transform: [
        { scale: scale.value },
        { translateX: translateX.value },
        { translateY: translateY.value },
      ],
    };
  });

  const handleNext = () => {
    if (selectedAsset && selectedAsset.uri) {
      setCurrentStep('enhance');
    }
  };

  const toggleEnhancement = async () => {
    if (!selectedAsset || isProcessing) return;

    try {
      setIsProcessing(true);

      logger.info('InstagramStyleImagePicker', 'Starting enhancement toggle', {
        isEnhanced,
        selectedAssetUri: selectedAsset.uri,
        selectedAssetId: selectedAsset.id
      });

      if (isEnhanced) {
        // Turn off enhancement
        logger.info('InstagramStyleImagePicker', 'Turning off enhancement');
        setIsEnhanced(false);
        setEnhancedUri(null);
      } else {
        // Turn on enhancement
        logger.info('InstagramStyleImagePicker', 'Starting image enhancement', {
          uri: selectedAsset.uri
        });

        const enhanced = await imageEnhancementService.autoEnhancePhoto(selectedAsset.uri);

        logger.info('InstagramStyleImagePicker', 'Enhancement completed', {
          originalUri: selectedAsset.uri,
          enhancedUri: enhanced.uri,
          dimensions: { width: enhanced.width, height: enhanced.height }
        });

        setEnhancedUri(enhanced.uri);
        setIsEnhanced(true);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('InstagramStyleImagePicker', 'Enhancement failed', {
        error: errorMessage,
        fullError: error,
        selectedAsset: selectedAsset ? {
          id: selectedAsset.id,
          uri: selectedAsset.uri,
          filename: selectedAsset.filename
        } : null
      });
      Alert.alert('Error', `Failed to enhance image: ${errorMessage}`);

      // Reset enhancement state on error
      setIsEnhanced(false);
      setEnhancedUri(null);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleUpload = async () => {
    if (!selectedAsset) return;

    try {
      setIsUploading(true);
      const finalUri = isEnhanced ? (enhancedUri || selectedAsset.uri) : selectedAsset.uri;
      await onImageSelected(finalUri, selectedAsset.filename);
      onClose();
    } catch (error) {
      logger.error('InstagramStyleImagePicker', 'Upload failed', error);
      Alert.alert('Error', 'Failed to upload image. Please try again.');
    } finally {
      setIsUploading(false);
    }
  };

  const renderGalleryItem = ({ item }: { item: GalleryAsset }) => (
    <TouchableOpacity
      style={[
        styles.galleryItem,
        selectedAsset?.id === item.id && styles.galleryItemSelected
      ]}
      onPress={() => handleAssetSelect(item)}
    >
      <Image source={{ uri: item.uri }} style={styles.galleryImage} />
      {selectedAsset?.id === item.id && (
        <View style={styles.selectedOverlay}>
          <Ionicons name="checkmark-circle" size={24} color="white" />
        </View>
      )}
    </TouchableOpacity>
  );

  if (!visible) return null;

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="fullScreen"
      onRequestClose={onClose}
    >
      <SafeAreaView style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={onClose} style={styles.headerButton}>
            <Ionicons name="close" size={24} color={lightTheme.colors.text} />
          </TouchableOpacity>
          
          <Text style={styles.headerTitle}>
            {currentStep === 'gallery' ? 'Select Photo' : 'Enhance Photo'}
          </Text>
          
          {currentStep === 'gallery' ? (
            <TouchableOpacity 
              onPress={handleNext} 
              style={styles.headerButton}
              disabled={!selectedAsset}
            >
              <Text style={[
                styles.nextText,
                !selectedAsset && styles.nextTextDisabled
              ]}>
                Next
              </Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity 
              onPress={handleUpload} 
              style={styles.headerButton}
              disabled={isUploading}
            >
              <Text style={styles.uploadText}>
                {isUploading ? 'Uploading...' : 'Upload'}
              </Text>
            </TouchableOpacity>
          )}
        </View>

        {currentStep === 'gallery' ? (
          <>
            {/* Square Crop Preview Area */}
            <View style={styles.previewContainer}>
              {selectedAsset ? (
                <View style={styles.cropContainer}>
                  <PinchGestureHandler onGestureEvent={pinchGestureHandler}>
                    <Animated.View style={styles.gestureContainer}>
                      <PanGestureHandler onGestureEvent={panGestureHandler}>
                        <Animated.View style={styles.gestureContainer}>
                          <Animated.Image
                            source={{ uri: selectedAsset.uri }}
                            style={[styles.cropImage, animatedImageStyle]}
                            resizeMode="contain"
                          />
                        </Animated.View>
                      </PanGestureHandler>
                    </Animated.View>
                  </PinchGestureHandler>

                  {/* Crop overlay */}
                  <View style={styles.cropOverlay}>
                    <Text style={styles.cropInstructions}>
                      Pinch to zoom • Drag to reposition
                    </Text>
                  </View>
                </View>
              ) : (
                <View style={styles.previewPlaceholder}>
                  <Ionicons name="image-outline" size={64} color={lightTheme.colors.secondary} />
                  <Text style={styles.previewPlaceholderText}>Select a photo from below</Text>
                </View>
              )}
            </View>

            {/* Gallery Grid */}
            <View style={styles.galleryContainer}>
              <View style={styles.galleryHeader}>
                <Text style={styles.galleryTitle}>Recent</Text>
                <TouchableOpacity onPress={handleTakePhoto} style={styles.cameraButton}>
                  <Ionicons name="camera" size={20} color={lightTheme.colors.primary} />
                  <Text style={styles.cameraButtonText}>Camera</Text>
                </TouchableOpacity>
              </View>
              
              {isLoadingGallery ? (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color={lightTheme.colors.primary} />
                </View>
              ) : (
                <FlatList
                  data={galleryAssets}
                  renderItem={renderGalleryItem}
                  keyExtractor={(item) => item.id}
                  numColumns={4}
                  showsVerticalScrollIndicator={false}
                  contentContainerStyle={styles.galleryGrid}
                />
              )}
            </View>
          </>
        ) : (
          /* Enhancement Screen */
          <View style={styles.enhanceContainer}>
            <View style={styles.enhancePreview}>
              {/* Show cropped preview with same transforms as gallery */}
              <View style={styles.enhanceCropContainer}>
                <Animated.Image
                  source={{ uri: isEnhanced ? (enhancedUri || selectedAsset?.uri) : selectedAsset?.uri }}
                  style={[
                    styles.enhanceCropImage,
                    {
                      transform: [
                        { scale: cropData.scale },
                        { translateX: cropData.translateX },
                        { translateY: cropData.translateY },
                      ],
                    }
                  ]}
                  resizeMode="contain"
                />
              </View>

              {isProcessing && (
                <View style={styles.processingOverlay}>
                  <ActivityIndicator size="large" color="white" />
                  <Text style={styles.processingText}>Enhancing...</Text>
                </View>
              )}
            </View>

            <View style={styles.enhanceControls}>
              <TouchableOpacity
                style={[
                  styles.enhanceButton,
                  isEnhanced && styles.enhanceButtonActive
                ]}
                onPress={toggleEnhancement}
                disabled={isProcessing}
              >
                <Ionicons 
                  name="sparkles" 
                  size={24} 
                  color={isEnhanced ? lightTheme.colors.primary : lightTheme.colors.secondary} 
                />
                <Text style={[
                  styles.enhanceButtonText,
                  isEnhanced && styles.enhanceButtonTextActive
                ]}>
                  {isEnhanced ? 'Enhanced' : 'Auto-Enhance'}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
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
  headerButton: {
    padding: 8,
    minWidth: 80,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
  },
  nextText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    textAlign: 'right',
  },
  nextTextDisabled: {
    color: lightTheme.colors.secondary,
  },
  uploadText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    textAlign: 'right',
  },
  previewContainer: {
    width: screenWidth,
    height: PREVIEW_SIZE,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  cropContainer: {
    width: PREVIEW_SIZE,
    height: PREVIEW_SIZE,
    overflow: 'hidden',
    position: 'relative',
  },
  gestureContainer: {
    width: PREVIEW_SIZE,
    height: PREVIEW_SIZE,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cropImage: {
    width: PREVIEW_SIZE * 1.5, // Make image larger than container
    height: PREVIEW_SIZE * 1.5, // So user can reposition it
  },
  cropOverlay: {
    position: 'absolute',
    bottom: 16,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  cropInstructions: {
    color: 'white',
    fontSize: 14,
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    overflow: 'hidden',
  },
  previewPlaceholder: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  previewPlaceholderText: {
    color: lightTheme.colors.secondary,
    fontSize: 16,
    marginTop: 8,
  },
  galleryContainer: {
    flex: 1,
    backgroundColor: lightTheme.colors.background,
  },
  galleryHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  galleryTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
  },
  cameraButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  cameraButtonText: {
    fontSize: 14,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  cameraButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  cameraButtonText: {
    fontSize: 14,
    color: lightTheme.colors.primary,
    fontWeight: '500',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  galleryGrid: {
    padding: 2,
  },
  galleryItem: {
    width: (screenWidth - 8) / 4,
    height: (screenWidth - 8) / 4,
    margin: 1,
    position: 'relative',
  },
  galleryItemSelected: {
    borderWidth: 2,
    borderColor: lightTheme.colors.primary,
  },
  galleryImage: {
    width: '100%',
    height: '100%',
  },
  selectedOverlay: {
    position: 'absolute',
    top: 4,
    right: 4,
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 12,
  },
  enhanceContainer: {
    flex: 1,
  },
  enhancePreview: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  enhanceImage: {
    width: screenWidth,
    height: '100%',
  },
  enhanceCropContainer: {
    width: screenWidth,
    height: screenWidth, // Square like the crop preview
    overflow: 'hidden',
    justifyContent: 'center',
    alignItems: 'center',
  },
  enhanceCropImage: {
    width: screenWidth * 1.5,
    height: screenWidth * 1.5,
  },
  processingOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  processingText: {
    color: 'white',
    fontSize: 16,
    marginTop: 12,
    fontWeight: '500',
  },
  enhanceControls: {
    padding: 20,
    backgroundColor: lightTheme.colors.card,
  },
  enhanceButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 16,
    paddingHorizontal: 24,
    borderRadius: 12,
    backgroundColor: lightTheme.colors.background,
    borderWidth: 2,
    borderColor: lightTheme.colors.border,
  },
  enhanceButtonActive: {
    backgroundColor: lightTheme.colors.card,
    borderColor: lightTheme.colors.primary,
  },
  enhanceButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.secondary,
    marginLeft: 8,
  },
  enhanceButtonTextActive: {
    color: lightTheme.colors.primary,
  },
});

export default InstagramStyleImagePicker;
