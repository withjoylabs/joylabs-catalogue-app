import React from 'react';
import {
  Modal,
  View,
  Pressable,
  Dimensions,
  StyleSheet,
  StatusBar,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import CachedImage from './CachedImage';

interface ImageOverlayProps {
  visible: boolean;
  imageUrl: string;
  onClose: () => void;
}

const ImageOverlay: React.FC<ImageOverlayProps> = ({ visible, imageUrl, onClose }) => {
  const { width: screenWidth, height: screenHeight } = Dimensions.get('window');
  
  // Use the shorter dimension to ensure the image fits on screen in both orientations
  const imageSize = Math.min(screenWidth, screenHeight) * 0.9;

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
        
        <View style={[styles.imageContainer, { width: imageSize, height: imageSize }]}>
          <CachedImage
            source={{ uri: imageUrl }}
            style={styles.image}
            fallbackStyle={styles.fallbackImage}
            fallbackText="📷"
            showLoadingIndicator={true}
          />
          
          {/* Close button */}
          <Pressable style={styles.closeButton} onPress={onClose}>
            <Ionicons name="close" size={24} color="#fff" />
          </Pressable>
        </View>
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
  },
  backdrop: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  imageContainer: {
    borderRadius: 12,
    overflow: 'hidden',
    elevation: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
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
