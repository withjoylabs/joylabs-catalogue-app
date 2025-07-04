import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Alert,
  ActivityIndicator,
  SafeAreaView,
  Dimensions,
  Image,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { lightTheme } from '../themes';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  useAnimatedGestureHandler,
} from 'react-native-reanimated';
import {
  PinchGestureHandler,
  PanGestureHandler,
} from 'react-native-gesture-handler';
import * as ImageManipulator from 'expo-image-manipulator';

interface SimpleImagePickerProps {
  visible: boolean;
  onClose: () => void;
  onImageSelected: (uri: string) => void;
  itemName?: string;
  preSelectedImage?: string | null;
}

// Constants for layout
const HEADER_HEIGHT = 60;
const BOTTOM_PADDING = 120;
const SIDE_PADDING = 20;

// Get screen dimensions and calculate responsive crop size
const getResponsiveCropSize = () => {
  const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

  const availableHeight = screenHeight - HEADER_HEIGHT - BOTTOM_PADDING;
  const availableWidth = screenWidth - (SIDE_PADDING * 2);

  // Ensure minimum size and maximum size
  const minSize = 250;
  const maxSize = Math.min(screenWidth * 0.8, screenHeight * 0.6);

  return Math.max(minSize, Math.min(maxSize, Math.min(availableWidth, availableHeight)));
};

const { width: screenWidth, height: screenHeight } = Dimensions.get('window');
const CROP_SIZE = getResponsiveCropSize();

const SimpleImagePicker: React.FC<SimpleImagePickerProps> = ({
  visible,
  onClose,
  onImageSelected,
  itemName,
  preSelectedImage
}) => {
  const [selectedImageUri, setSelectedImageUri] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [cropSize, setCropSize] = useState(getResponsiveCropSize());
  const [imageDimensions, setImageDimensions] = useState<{width: number, height: number} | null>(null);

  // Animated values for crop preview
  const scale = useSharedValue(1);
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const savedScale = useSharedValue(1);
  const savedTranslateX = useSharedValue(0);
  const savedTranslateY = useSharedValue(0);
  const cropSizeShared = useSharedValue(cropSize);
  const imageDisplayWidth = useSharedValue(cropSize);
  const imageDisplayHeight = useSharedValue(cropSize);

  // Handle orientation changes
  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', () => {
      const newCropSize = getResponsiveCropSize();
      setCropSize(newCropSize);
      cropSizeShared.value = newCropSize;
      resetCropValues(); // Reset crop when orientation changes
    });

    return () => subscription?.remove();
  }, []);

  // Update shared values when cropSize changes
  useEffect(() => {
    cropSizeShared.value = cropSize;

    // Recalculate image display size if we have dimensions
    if (imageDimensions) {
      const aspectRatio = imageDimensions.width / imageDimensions.height;
      if (aspectRatio > 1) {
        // Landscape
        imageDisplayWidth.value = cropSize * aspectRatio;
        imageDisplayHeight.value = cropSize;
      } else {
        // Portrait or square
        imageDisplayWidth.value = cropSize;
        imageDisplayHeight.value = cropSize / aspectRatio;
      }
    }
  }, [cropSize, imageDimensions]);

  // Get image dimensions
  const getImageDimensions = (uri: string) => {
    Image.getSize(uri, (width, height) => {
      setImageDimensions({ width, height });

      // Calculate and update shared values for gesture handlers
      const aspectRatio = width / height;
      if (aspectRatio > 1) {
        // Landscape
        imageDisplayWidth.value = cropSize * aspectRatio;
        imageDisplayHeight.value = cropSize;
      } else {
        // Portrait or square
        imageDisplayWidth.value = cropSize;
        imageDisplayHeight.value = cropSize / aspectRatio;
      }
    }, (error) => {
      console.error('Failed to get image dimensions:', error);
      // Fallback to square
      setImageDimensions({ width: cropSize, height: cropSize });
      imageDisplayWidth.value = cropSize;
      imageDisplayHeight.value = cropSize;
    });
  };

  // Set pre-selected image when provided
  useEffect(() => {
    if (preSelectedImage) {
      setSelectedImageUri(preSelectedImage);
      getImageDimensions(preSelectedImage);
      resetCropValues();
    }
  }, [preSelectedImage]);

  // Reset crop values when image changes
  const resetCropValues = () => {
    scale.value = 1; // Start at 1x scale fitting crop area
    translateX.value = 0;
    translateY.value = 0;
    savedScale.value = 1;
    savedTranslateX.value = 0;
    savedTranslateY.value = 0;
  };

  // Handle camera
  const handleTakePhoto = async () => {
    try {
      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission Required', 'We need camera permission to take photos.');
        return;
      }

      const result = await ImagePicker.launchCameraAsync({
        mediaTypes: ['images'],
        allowsEditing: false,
        quality: 0.8,
      });

      if (!result.canceled && result.assets[0]) {
        const uri = result.assets[0].uri;
        setSelectedImageUri(uri);
        getImageDimensions(uri);
        resetCropValues();
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to take photo. Please try again.');
    }
  };

  // Handle gallery selection
  const handleSelectFromGallery = async () => {
    try {
      const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission Required', 'We need photo library permission to select images.');
        return;
      }

      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: false,
        quality: 0.8,
      });

      if (!result.canceled && result.assets[0]) {
        const uri = result.assets[0].uri;
        setSelectedImageUri(uri);
        getImageDimensions(uri);
        resetCropValues();
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to select image. Please try again.');
    }
  };

  // Handle upload
  const handleUpload = async () => {
    if (!selectedImageUri) return;

    setIsUploading(true);
    try {
      // Calculate crop parameters based on image display size and transforms
      if (!imageDimensions) return;

      const displaySize = getImageDisplaySize();
      const scaledWidth = displaySize.width * scale.value;
      const scaledHeight = displaySize.height * scale.value;

      // Calculate crop area relative to the original image
      const cropX = ((scaledWidth - cropSize) / 2 - translateX.value) / scale.value;
      const cropY = ((scaledHeight - cropSize) / 2 - translateY.value) / scale.value;
      const calculatedCropSize = cropSize / scale.value;

      // Crop the image
      const croppedImage = await ImageManipulator.manipulateAsync(
        selectedImageUri,
        [
          {
            crop: {
              originX: Math.max(0, cropX),
              originY: Math.max(0, cropY),
              width: calculatedCropSize,
              height: calculatedCropSize,
            },
          },
          { resize: { width: 800, height: 800 } }, // Resize to 800x800
        ],
        { compress: 0.8, format: ImageManipulator.SaveFormat.JPEG }
      );

      onImageSelected(croppedImage.uri);
      handleClose();
    } catch (error) {
      Alert.alert('Error', 'Failed to process image. Please try again.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleClose = () => {
    setSelectedImageUri(null);
    resetCropValues();
    onClose();
  };

  // Calculate image display size based on aspect ratio
  const getImageDisplaySize = () => {
    if (!imageDimensions) {
      return { width: cropSize, height: cropSize };
    }

    const { width: imgWidth, height: imgHeight } = imageDimensions;
    const aspectRatio = imgWidth / imgHeight;

    if (aspectRatio > 1) {
      // Landscape: fit height to crop area, width will be larger
      const displayHeight = cropSize;
      const displayWidth = displayHeight * aspectRatio;
      return { width: displayWidth, height: displayHeight };
    } else {
      // Portrait or square: fit width to crop area, height will be larger
      const displayWidth = cropSize;
      const displayHeight = displayWidth / aspectRatio;
      return { width: displayWidth, height: displayHeight };
    }
  };

  const imageDisplaySize = getImageDisplaySize();

  // Dynamic styles based on current crop size and image dimensions
  const dynamicStyles = {
    cropArea: {
      width: cropSize,
      height: cropSize,
      position: 'relative' as const,
      backgroundColor: '#e0e0e0',
      borderRadius: 8,
      borderWidth: 2,
      borderColor: '#333',
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.25,
      shadowRadius: 4,
      elevation: 5,
    },
    imageContainer: {
      width: cropSize,
      height: cropSize,
      justifyContent: 'center' as const,
      alignItems: 'center' as const,
      overflow: 'hidden' as const,
      borderRadius: 6,
    },
    gestureContainer: {
      width: cropSize,
      height: cropSize,
      justifyContent: 'center' as const,
      alignItems: 'center' as const,
    },
    cropImage: {
      width: imageDisplaySize.width,
      height: imageDisplaySize.height,
    },
  };

  // Gesture handlers
  const pinchGestureHandler = useAnimatedGestureHandler({
    onStart: () => {
      savedScale.value = scale.value;
    },
    onActive: (event) => {
      scale.value = Math.max(1, Math.min(3, savedScale.value * event.scale));
    },
  });

  const panGestureHandler = useAnimatedGestureHandler({
    onStart: () => {
      savedTranslateX.value = translateX.value;
      savedTranslateY.value = translateY.value;
    },
    onActive: (event) => {
      // For true 1:1 movement, we need to scale finger movement by inverse of zoom
      // This makes it feel like you're directly moving the image at its actual size
      const scaledTranslationX = event.translationX / scale.value;
      const scaledTranslationY = event.translationY / scale.value;

      // Calculate new translate values
      const newTranslateX = savedTranslateX.value + scaledTranslationX;
      const newTranslateY = savedTranslateY.value + scaledTranslationY;

      // Calculate bounds based on the base image size (not scaled)
      const maxPanX = Math.max(0, (imageDisplayWidth.value - cropSizeShared.value) / 2);
      const maxPanY = Math.max(0, (imageDisplayHeight.value - cropSizeShared.value) / 2);

      // Constrain to image bounds
      translateX.value = Math.max(-maxPanX, Math.min(maxPanX, newTranslateX));
      translateY.value = Math.max(-maxPanY, Math.min(maxPanY, newTranslateY));
    },
  });

  const animatedImageStyle = useAnimatedStyle(() => {
    return {
      transform: [
        { scale: scale.value },
        { translateX: translateX.value },
        { translateY: translateY.value },
      ],
    };
  });

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={handleClose}
    >
      <SafeAreaView style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={handleClose} style={styles.headerButton}>
            <Text style={styles.cancelText}>Cancel</Text>
          </TouchableOpacity>
          <Text style={styles.headerTitle}>
            {selectedImageUri ? 'Crop Photo' : 'Add Photo'}
          </Text>
          {selectedImageUri && (
            <TouchableOpacity 
              onPress={handleUpload} 
              style={styles.headerButton}
              disabled={isUploading}
            >
              {isUploading ? (
                <ActivityIndicator size="small" color={lightTheme.colors.primary} />
              ) : (
                <Text style={styles.uploadText}>Upload</Text>
              )}
            </TouchableOpacity>
          )}
        </View>

        {/* Content */}
        <View style={styles.content}>
          {selectedImageUri && imageDimensions ? (
            // Proper crop interface
            <View style={styles.cropContainer}>
              {/* Crop area with image */}
              <View style={dynamicStyles.cropArea}>
                <View style={dynamicStyles.imageContainer}>
                  <PinchGestureHandler onGestureEvent={pinchGestureHandler}>
                    <Animated.View style={dynamicStyles.gestureContainer}>
                      <PanGestureHandler onGestureEvent={panGestureHandler}>
                        <Animated.View style={dynamicStyles.gestureContainer}>
                          <Animated.Image
                            source={{ uri: selectedImageUri }}
                            style={[dynamicStyles.cropImage, animatedImageStyle]}
                            resizeMode="cover"
                          />
                        </Animated.View>
                      </PanGestureHandler>
                    </Animated.View>
                  </PinchGestureHandler>
                </View>

                {/* Crop grid overlay */}
                <View style={styles.cropGrid} pointerEvents="none">
                  {/* Vertical lines */}
                  <View style={[styles.gridLine, styles.verticalLine, { left: '33.33%' }]} />
                  <View style={[styles.gridLine, styles.verticalLine, { left: '66.66%' }]} />
                  {/* Horizontal lines */}
                  <View style={[styles.gridLine, styles.horizontalLine, { top: '33.33%' }]} />
                  <View style={[styles.gridLine, styles.horizontalLine, { top: '66.66%' }]} />
                </View>

                {/* Corner indicators only */}
                <View style={styles.cornerContainer} pointerEvents="none">
                  <View style={[styles.cornerIndicator, styles.topLeft]} />
                  <View style={[styles.cornerIndicator, styles.topRight]} />
                  <View style={[styles.cornerIndicator, styles.bottomLeft]} />
                  <View style={[styles.cornerIndicator, styles.bottomRight]} />
                </View>
              </View>

              {/* Instructions */}
              <View style={styles.instructionsContainer}>
                <Text style={styles.cropInstructions}>
                  Pinch to zoom • Drag to reposition
                </Text>
              </View>
            </View>
          ) : (
            // Selection buttons
            <View style={styles.selectionContainer}>
              <TouchableOpacity style={styles.optionButton} onPress={handleTakePhoto}>
                <Ionicons name="camera" size={48} color={lightTheme.colors.primary} />
                <Text style={styles.optionText}>Take Photo</Text>
              </TouchableOpacity>
              
              <TouchableOpacity style={styles.optionButton} onPress={handleSelectFromGallery}>
                <Ionicons name="images" size={48} color={lightTheme.colors.primary} />
                <Text style={styles.optionText}>Choose from Gallery</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
      </SafeAreaView>
    </Modal>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5', // Gray background
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
    backgroundColor: lightTheme.colors.background,
    height: HEADER_HEIGHT,
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
  cancelText: {
    fontSize: 16,
    color: lightTheme.colors.secondary,
  },
  uploadText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    textAlign: 'right',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  selectionContainer: {
    alignItems: 'center',
    gap: 40,
  },
  optionButton: {
    alignItems: 'center',
    padding: 32,
    borderRadius: 16,
    backgroundColor: lightTheme.colors.card,
    minWidth: 200,
  },
  optionText: {
    fontSize: 18,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginTop: 12,
  },
  // Proper crop interface - using dynamic sizing
  cropContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  cropGrid: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 5, // Above image but below corners
  },
  gridLine: {
    position: 'absolute',
    backgroundColor: 'rgba(255, 255, 255, 0.3)',
  },
  verticalLine: {
    width: 1,
    height: '100%',
  },
  horizontalLine: {
    height: 1,
    width: '100%',
  },
  cornerContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 10, // Above image
  },
  cornerIndicator: {
    position: 'absolute',
    width: 20,
    height: 20,
    borderColor: '#fff',
    borderWidth: 3,
  },
  topLeft: {
    top: -2,
    left: -2,
    borderRightWidth: 0,
    borderBottomWidth: 0,
    borderTopLeftRadius: 8,
  },
  topRight: {
    top: -2,
    right: -2,
    borderLeftWidth: 0,
    borderBottomWidth: 0,
    borderTopRightRadius: 8,
  },
  bottomLeft: {
    bottom: -2,
    left: -2,
    borderRightWidth: 0,
    borderTopWidth: 0,
    borderBottomLeftRadius: 8,
  },
  bottomRight: {
    bottom: -2,
    right: -2,
    borderLeftWidth: 0,
    borderTopWidth: 0,
    borderBottomRightRadius: 8,
  },
  instructionsContainer: {
    marginTop: 20,
    alignItems: 'center',
  },
  cropInstructions: {
    color: lightTheme.colors.text,
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
    opacity: 0.7,
  },
});

export default SimpleImagePicker;
