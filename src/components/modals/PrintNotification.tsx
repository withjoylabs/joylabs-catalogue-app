import React, { useEffect } from 'react';
import { Modal, View, Text, StyleSheet, TouchableOpacity, Animated } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../../themes'; // Assuming your themes are in a folder named 'themes' at the root of src

interface PrintNotificationProps {
  visible: boolean;
  message: string;
  type: 'success' | 'error';
  onClose: () => void;
  nonBlocking?: boolean; // Add nonBlocking prop
}

const PrintNotification: React.FC<PrintNotificationProps> = ({ visible, message, type, onClose, nonBlocking = false }) => {
  const animatedValue = React.useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (visible) {
      Animated.timing(animatedValue, {
        toValue: 1,
        duration: 300,
        useNativeDriver: true,
      }).start();
    } else {
      Animated.timing(animatedValue, {
        toValue: 0,
        duration: 300,
        useNativeDriver: true,
      }).start(() => {
        // Only call onClose after animation completes
        if (!visible) {
          onClose();
        }
      });
    }
  }, [visible, animatedValue, onClose]);

  const backgroundColor = type === 'success' ? lightTheme.colors.secondary : lightTheme.colors.notification;
  const iconName = type === 'success' ? 'checkmark-circle-outline' : 'alert-circle-outline';

  return (
    <Modal 
      transparent 
      visible={visible} 
      animationType="none" 
      onRequestClose={onClose}
      statusBarTranslucent={true}
      hardwareAccelerated={true}
      presentationStyle="overFullScreen"
    >
      <Animated.View
        style={[
          styles.container,
          {
            backgroundColor,
            opacity: animatedValue,
            transform: [
              {
                translateY: animatedValue.interpolate({
                  inputRange: [0, 1],
                  outputRange: [-100, 0], // Animate from top
                }),
              },
            ],
          },
        ]}
        pointerEvents={nonBlocking ? 'none' : 'auto'}
      >
        <Ionicons name={iconName as keyof typeof Ionicons.glyphMap} size={24} color="white" style={styles.icon} />
        <Text style={styles.message}>{message}</Text>
        {/* Optional: Add a close button if needed later */}
        {/* <TouchableOpacity onPress={onClose} style={styles.closeButton}>
          <Ionicons name="close-outline" size={24} color="white" />
        </TouchableOpacity> */}
      </Animated.View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0, // Adjust if you have a specific status bar height or prefer bottom
    left: 0,
    right: 0,
    paddingHorizontal: 20,
    paddingVertical: 15,
    flexDirection: 'row',
    alignItems: 'center',
    // elevation: 5, // Android shadow
    // shadowColor: '#000', // iOS shadow
    // shadowOffset: { width: 0, height: 2 },
    // shadowOpacity: 0.2,
    // shadowRadius: 2,
    minHeight: 60, // Ensure it has some height
    zIndex: 9999,
  },
  icon: {
    marginRight: 10,
  },
  message: {
    color: 'white',
    fontSize: 16,
    flex: 1, // Allow message to take remaining space
  },
  // closeButton: {
  //   marginLeft: 10,
  // },
});

export default PrintNotification; 