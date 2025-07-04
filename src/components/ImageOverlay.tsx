import React from 'react';
import {
  Modal,
  View,
  Pressable,
  Dimensions,
  StyleSheet,
  StatusBar,
  Text,
  ScrollView,
  PanGestureHandler,
  State,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PanGestureHandler as RNGHPanGestureHandler, State as RNGHState } from 'react-native-gesture-handler';
import CachedImage from './CachedImage';

interface ImageOverlayProps {
  visible: boolean;
  imageUrl: string;
  onClose: () => void;
  itemInfo?: {
    itemName: string;
    itemCategory?: string;
    itemBarcode?: string;
    itemPrice?: number;
    vendorCost?: number;
    vendor?: string;
    discontinued?: boolean;
    missingSquareData?: boolean;
    missingTeamData?: boolean;
  };
}

const ImageOverlay: React.FC<ImageOverlayProps> = ({ visible, imageUrl, onClose, itemInfo }) => {
  const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

  // Use the shorter dimension for both image and container to ensure they match
  const shorterDimension = Math.min(screenWidth, screenHeight);
  const containerWidth = shorterDimension * 0.9;
  const imageSize = containerWidth; // Image spans full container width

  // Handle swipe down to dismiss
  const handleGestureEvent = (event: any) => {
    const { translationY, velocityY } = event.nativeEvent;

    // Dismiss if swiped down significantly or with high velocity
    if (translationY > 100 || velocityY > 500) {
      onClose();
    }
  };

  const handleGestureStateChange = (event: any) => {
    if (event.nativeEvent.state === RNGHState.END) {
      const { translationY, velocityY } = event.nativeEvent;

      // Dismiss if swiped down significantly or with high velocity
      if (translationY > 100 || velocityY > 500) {
        onClose();
      }
    }
  };

  // Build item data line efficiently
  const buildItemDataLine = () => {
    if (!itemInfo) return '';

    return [
      // Category (if available)
      itemInfo.itemCategory,
      // UPC (if catalog data available)
      itemInfo.missingSquareData ? 'Missing Catalog' : (itemInfo.itemBarcode || 'N/A'),
      // Price (if catalog data available)
      itemInfo.missingSquareData ? 'Unknown' : (itemInfo.itemPrice ? `$${itemInfo.itemPrice.toFixed(2)}` : 'Variable'),
      // Vendor Cost (only if team data available and cost exists)
      (!itemInfo.missingTeamData && itemInfo.vendorCost) ? `$${itemInfo.vendorCost.toFixed(2)}/unit` : null,
      // Vendor (only if team data available and vendor exists)
      (!itemInfo.missingTeamData && itemInfo.vendor) ? itemInfo.vendor : null,
      // Discontinued flag (only if team data available and item is discontinued)
      (!itemInfo.missingTeamData && itemInfo.discontinued) ? 'DISCONTINUED' : null
    ].filter(Boolean).join(' • ');
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
      statusBarTranslucent
    >
      <StatusBar backgroundColor="rgba(0,0,0,0.9)" barStyle="light-content" />
      <View style={styles.overlay}>
        <Pressable style={styles.backdrop} onPress={onClose} />

        <RNGHPanGestureHandler
          onGestureEvent={handleGestureEvent}
          onHandlerStateChange={handleGestureStateChange}
        >
          <View style={[styles.contentContainer, { width: containerWidth }]}>
            {/* Image */}
            <View style={[styles.imageContainer, { width: imageSize, height: imageSize }]}>
              <CachedImage
                source={{ uri: imageUrl }}
                style={styles.image}
                fallbackStyle={styles.fallbackImage}
                fallbackText="📷"
                showLoadingIndicator={true}
              />
            </View>

            {/* Item Information */}
            {itemInfo && (
              <View style={styles.itemInfoContainer}>
                <Text style={styles.itemName}>{itemInfo.itemName}</Text>
                <Text style={styles.itemDetails}>{buildItemDataLine()}</Text>
              </View>
            )}

            {/* Close button */}
            <Pressable style={styles.closeButton} onPress={onClose}>
              <Ionicons name="close" size={24} color="#fff" />
            </Pressable>
          </View>
        </RNGHPanGestureHandler>
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.9)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  backdrop: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  contentContainer: {
    alignItems: 'center',
    maxHeight: '90%',
  },
  imageContainer: {
    borderRadius: 12,
    overflow: 'hidden',
    elevation: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    marginBottom: 16,
  },
  image: {
    width: '100%',
    height: '100%',
    borderRadius: 12,
  },
  fallbackImage: {
    width: '100%',
    height: '100%',
    backgroundColor: '#f5f5f5',
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  itemInfoContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderRadius: 12,
    padding: 16,
    width: '100%',
    alignItems: 'center',
  },
  itemName: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    textAlign: 'center',
    marginBottom: 8,
  },
  itemDetails: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    lineHeight: 20,
  },
  closeButton: {
    position: 'absolute',
    top: 12,
    right: 12,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
});

export default ImageOverlay;
