import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  StyleSheet,
  Image,
  ActivityIndicator,
  Alert,
  SafeAreaView,
  Dimensions
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';
import logger from '../utils/logger';
import { imageEnhancementService } from '../services/imageEnhancementService';

interface ImageEnhancementModalProps {
  visible: boolean;
  imageUri: string;
  onConfirm: (enhancedUri: string) => void;
  onCancel: () => void;
}

const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

const ImageEnhancementModal: React.FC<ImageEnhancementModalProps> = ({
  visible,
  imageUri,
  onConfirm,
  onCancel
}) => {
  const [isEnhanced, setIsEnhanced] = useState(false);
  const [enhancedUri, setEnhancedUri] = useState<string | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [previewUri, setPreviewUri] = useState<string>(imageUri);

  // Reset state when modal opens with new image
  useEffect(() => {
    if (visible && imageUri) {
      setIsEnhanced(false);
      setEnhancedUri(null);
      setIsProcessing(false);
      setPreviewUri(imageUri);
    }
  }, [visible, imageUri]);

  // Toggle enhancement
  const toggleEnhancement = async () => {
    if (isProcessing) return;

    try {
      setIsProcessing(true);

      if (isEnhanced) {
        // Turn off enhancement - show original
        setPreviewUri(imageUri);
        setIsEnhanced(false);
        logger.info('ImageEnhancementModal', 'Enhancement disabled');
      } else {
        // Turn on enhancement
        logger.info('ImageEnhancementModal', 'Starting image enhancement');
        
        // Create preview first (faster)
        const preview = await imageEnhancementService.createEnhancementPreview(
          imageUri,
          imageEnhancementService.getDefaultProductPhotoEnhancement()
        );
        
        setPreviewUri(preview.uri);
        setIsEnhanced(true);
        
        // Create full quality enhanced version in background
        const enhanced = await imageEnhancementService.autoEnhancePhoto(imageUri);
        setEnhancedUri(enhanced.uri);
        
        logger.info('ImageEnhancementModal', 'Enhancement completed', {
          originalUri: imageUri,
          previewUri: preview.uri,
          enhancedUri: enhanced.uri
        });
      }
    } catch (error) {
      logger.error('ImageEnhancementModal', 'Enhancement failed', error);
      Alert.alert('Error', 'Failed to enhance image. Please try again.');
      setIsEnhanced(false);
      setPreviewUri(imageUri);
    } finally {
      setIsProcessing(false);
    }
  };

  // Confirm and use the image
  const handleConfirm = () => {
    const finalUri = isEnhanced ? (enhancedUri || previewUri) : imageUri;
    logger.info('ImageEnhancementModal', 'Image confirmed', {
      isEnhanced,
      finalUri,
      originalUri: imageUri
    });
    onConfirm(finalUri);
  };

  // Cancel and go back
  const handleCancel = () => {
    logger.info('ImageEnhancementModal', 'Image enhancement cancelled');
    onCancel();
  };

  if (!visible) return null;

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="fullScreen"
      onRequestClose={handleCancel}
    >
      <SafeAreaView style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={handleCancel} style={styles.headerButton}>
            <Ionicons name="close" size={24} color={lightTheme.colors.text} />
          </TouchableOpacity>
          
          <Text style={styles.headerTitle}>Enhance Photo</Text>
          
          <TouchableOpacity onPress={handleConfirm} style={styles.headerButton}>
            <Text style={styles.confirmText}>Use Photo</Text>
          </TouchableOpacity>
        </View>

        {/* Image Preview */}
        <View style={styles.imageContainer}>
          <Image
            source={{ uri: previewUri }}
            style={styles.previewImage}
            resizeMode="contain"
          />
          
          {/* Processing overlay */}
          {isProcessing && (
            <View style={styles.processingOverlay}>
              <ActivityIndicator size="large" color="white" />
              <Text style={styles.processingText}>Enhancing...</Text>
            </View>
          )}
        </View>

        {/* Enhancement Controls */}
        <View style={styles.controls}>
          <TouchableOpacity
            style={[
              styles.enhanceButton,
              isEnhanced && styles.enhanceButtonActive,
              isProcessing && styles.enhanceButtonDisabled
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
          
          {/* Enhancement info */}
          <Text style={styles.enhanceInfo}>
            {isEnhanced 
              ? 'Auto-enhancement applied: brightness, contrast, and sharpening'
              : 'Tap to automatically improve brightness, contrast, and sharpness'
            }
          </Text>
        </View>
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
  confirmText: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.primary,
    textAlign: 'right',
  },
  imageContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#000',
    position: 'relative',
  },
  previewImage: {
    width: screenWidth,
    height: screenHeight * 0.7,
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
  controls: {
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
    marginBottom: 12,
  },
  enhanceButtonActive: {
    backgroundColor: lightTheme.colors.card,
    borderColor: lightTheme.colors.primary,
  },
  enhanceButtonDisabled: {
    opacity: 0.6,
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
  enhanceInfo: {
    fontSize: 14,
    color: lightTheme.colors.secondary,
    textAlign: 'center',
    lineHeight: 20,
  },
});

export default ImageEnhancementModal;
