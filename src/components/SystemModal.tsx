/**
 * SystemModal - A reusable modal component for system messages.
 * 
 * USAGE EXAMPLES:
 * 
 * 1. Success Notification (auto-closes, appears at bottom):
 *    <SystemModal
 *      visible={isVisible}
 *      onClose={() => setIsVisible(false)}
 *      message="Item created successfully"
 *      type="success"
 *      position="bottom"
 *      autoClose={true}
 *      autoCloseTime={3000}
 *    />
 * 
 * 2. Error Notification (stays until dismissed, appears at top):
 *    <SystemModal
 *      visible={isVisible}
 *      onClose={() => setIsVisible(false)}
 *      message="Failed to connect to printer"
 *      type="error"
 *      position="top"
 *    />
 * 
 * 3. Confirmation Dialog (centered, with action buttons):
 *    <SystemModal
 *      visible={isVisible}
 *      onClose={() => setIsVisible(false)}
 *      title="Delete Item?"
 *      message="Are you sure you want to delete this item? This action cannot be undone."
 *      type="confirm"
 *      primaryButtonText="Delete"
 *      secondaryButtonText="Cancel"
 *      onPrimaryAction={handleDeleteItem}
 *    />
 * 
 * 4. Info Modal (centered, with single button):
 *    <SystemModal
 *      visible={isVisible}
 *      onClose={() => setIsVisible(false)}
 *      title="Information"
 *      message="Here's some important information you should know about."
 *      type="info"
 *      primaryButtonText="Got it"
 *    />
 * 
 * 5. Warning Dialog (centered, with two buttons):
 *    <SystemModal
 *      visible={isVisible}
 *      onClose={() => setIsVisible(false)}
 *      title="Warning"
 *      message="This action may have unintended consequences. Are you sure you want to proceed?"
 *      type="warning"
 *      primaryButtonText="Continue"
 *      secondaryButtonText="Cancel"
 *      onPrimaryAction={handleContinue}
 *      onSecondaryAction={handleCancel}
 *    />
 * 
 * Props:
 * - visible: boolean - Controls visibility of the modal
 * - onClose: () => void - Called when modal is closed
 * - title?: string - Optional title (mainly for centered modals)
 * - message: string - The main message content to display
 * - type?: 'success' | 'error' | 'warning' | 'info' | 'confirm' - Sets the appearance
 * - primaryButtonText?: string - Text for primary action button
 * - onPrimaryAction?: () => void - Callback for primary button
 * - secondaryButtonText?: string - Text for secondary action button
 * - onSecondaryAction?: () => void - Callback for secondary button
 * - autoClose?: boolean - Whether the modal should close automatically after a delay
 * - autoCloseTime?: number - Delay in ms before auto-closing (default: 3000)
 * - position?: 'top' | 'center' | 'bottom' - Position of the modal
 * - closeOnBackdropPress?: boolean - Whether clicking background closes modal
 * - testID?: string - For testing
 */

import React, { useState, useEffect, useMemo } from 'react';
import {
  Modal,
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TouchableWithoutFeedback,
  Animated,
  Dimensions,
  Platform,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

export type ModalType = 'success' | 'error' | 'warning' | 'info' | 'confirm';

export interface SystemModalProps {
  // Visibility control
  visible: boolean;
  onClose: () => void;
  
  // Content
  title?: string;
  message: string;
  
  // Type and appearance
  type?: ModalType;
  
  // Action buttons
  primaryButtonText?: string;
  onPrimaryAction?: () => void;
  secondaryButtonText?: string;
  onSecondaryAction?: () => void;
  
  // Options
  autoClose?: boolean;
  autoCloseTime?: number;
  position?: 'top' | 'center' | 'bottom';
  closeOnBackdropPress?: boolean;
  testID?: string;
}

const { height } = Dimensions.get('window');

const SystemModal: React.FC<SystemModalProps> = ({
  visible,
  onClose,
  title,
  message,
  type = 'info',
  primaryButtonText,
  onPrimaryAction,
  secondaryButtonText,
  onSecondaryAction,
  autoClose = false,
  autoCloseTime = 3000,
  position = 'center',
  closeOnBackdropPress = true,
  testID,
}) => {
  const [animatedValue] = useState(new Animated.Value(0));
  
  // Determine icon based on type
  const iconConfig = useMemo(() => {
    switch (type) {
      case 'success':
        return { name: 'checkmark-circle-outline', color: lightTheme.colors.secondary };
      case 'error':
        return { name: 'alert-circle-outline', color: '#ff3b30' };
      case 'warning':
        return { name: 'warning-outline', color: lightTheme.colors.notification };
      case 'confirm':
        return { name: 'help-circle-outline', color: lightTheme.colors.primary };
      case 'info':
      default:
        return { name: 'information-circle-outline', color: lightTheme.colors.primary };
    }
  }, [type]);

  // Handle animation and auto-close
  useEffect(() => {
    if (visible) {
      // Slide down animation
      Animated.timing(animatedValue, {
        toValue: 1,
        duration: 300,
        useNativeDriver: true,
      }).start();
      
      // Set up auto-close if enabled
      if (autoClose && !onPrimaryAction) {
        const timer = setTimeout(() => {
          // Start slide up animation
          Animated.timing(animatedValue, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
          }).start(() => {
            onClose();
          });
        }, 2000); // Changed from autoCloseTime to 2000ms
        
        return () => clearTimeout(timer);
      }
    } else {
      // Slide up animation when manually closed
      Animated.timing(animatedValue, {
        toValue: 0,
        duration: 300,
        useNativeDriver: true,
      }).start();
    }
  }, [visible, autoClose]);

  const handleClose = () => {
    // Start slide up animation
    Animated.timing(animatedValue, {
      toValue: 0,
      duration: 300,
      useNativeDriver: true,
    }).start(() => {
      onClose();
    });
  };

  const handlePrimaryAction = () => {
    if (onPrimaryAction) {
      onPrimaryAction();
    }
    handleClose();
  };

  const handleSecondaryAction = () => {
    if (onSecondaryAction) {
      onSecondaryAction();
    }
    handleClose();
  };

  const handleBackdropPress = () => {
    if (closeOnBackdropPress) {
      handleClose();
    }
  };

  // Animation styles based on position
  const getAnimationStyle = () => {
    const opacity = animatedValue;
    let transform;

    switch (position) {
      case 'top':
        transform = [{
          translateY: animatedValue.interpolate({
            inputRange: [0, 1],
            outputRange: [-100, 0],
          }),
        }];
        break;
      case 'bottom':
        transform = [{
          translateY: animatedValue.interpolate({
            inputRange: [0, 1],
            outputRange: [100, 0],
          }),
        }];
        break;
      case 'center':
      default:
        transform = [{
          scale: animatedValue.interpolate({
            inputRange: [0, 1],
            outputRange: [0.9, 1],
          }),
        }];
        break;
    }

    return { opacity, transform };
  };

  // Determine container style based on position and type
  const getContainerStyle = () => {
    switch (position) {
      case 'top':
        return [
          styles.modalContainer, 
          styles.topContainer,
          type === 'success' && styles.successBackground,
          type === 'error' && styles.errorBackground,
          type === 'warning' && styles.warningBackground,
          (type === 'info' || type === 'confirm') && styles.infoBackground,
        ];
      case 'bottom':
        return [
          styles.modalContainer, 
          styles.bottomContainer,
          type === 'success' && styles.successBackground,
          type === 'error' && styles.errorBackground,
          type === 'warning' && styles.warningBackground,
          (type === 'info' || type === 'confirm') && styles.infoBackground,
        ];
      case 'center':
      default:
        return [
          styles.modalContainer, 
          styles.centerContainer,
          { backgroundColor: '#fff' }, // Center modals always have white background
        ];
    }
  };

  return (
    <Modal
      transparent
      visible={visible}
      animationType="none"
      onRequestClose={handleClose}
      testID={testID}
    >
      <TouchableWithoutFeedback onPress={handleBackdropPress}>
        <View style={[
          styles.overlay,
          (position === 'top' || position === 'bottom') && { backgroundColor: 'transparent' }
        ]}>
          <TouchableWithoutFeedback>
            <Animated.View style={[getContainerStyle(), getAnimationStyle()]}>
              {/* For top/bottom notifications */}
              {(position === 'top' || position === 'bottom') && (
                <View style={styles.notificationContent}>
                  <Ionicons 
                    name={iconConfig.name as keyof typeof Ionicons.glyphMap} 
                    size={24} 
                    color={'#fff'} 
                    style={styles.icon} 
                  />
                  <Text 
                    style={[
                      styles.message, 
                      (position === 'top' || position === 'bottom') && styles.notificationMessage
                    ]}
                    numberOfLines={2}
                  >
                    {message}
                  </Text>
                  {!autoClose && (
                    <TouchableOpacity style={styles.closeButton} onPress={handleClose}>
                      <Ionicons name="close" size={20} color={(position === 'top' || position === 'bottom') ? '#fff' : '#999'} />
                    </TouchableOpacity>
                  )}
                </View>
              )}

              {/* For center modals with title and buttons */}
              {position === 'center' && (
                <>
                  <View style={styles.iconContainer}>
                    <Ionicons 
                      name={iconConfig.name as keyof typeof Ionicons.glyphMap} 
                      size={40} 
                      color={iconConfig.color} 
                    />
                  </View>
                  
                  {title && <Text style={styles.title}>{title}</Text>}
                  
                  <Text style={styles.message}>{message}</Text>
                  
                  <View style={styles.buttonContainer}>
                    {secondaryButtonText && (
                      <TouchableOpacity 
                        style={[styles.button, styles.secondaryButton]} 
                        onPress={handleSecondaryAction}
                      >
                        <Text style={styles.secondaryButtonText}>{secondaryButtonText}</Text>
                      </TouchableOpacity>
                    )}
                    
                    {primaryButtonText && (
                      <TouchableOpacity 
                        style={[
                          styles.button, 
                          styles.primaryButton,
                          type === 'error' && styles.errorButton,
                          type === 'success' && styles.successButton,
                          type === 'warning' && styles.warningButton,
                          secondaryButtonText ? { flex: 1 } : { minWidth: 120 }
                        ]} 
                        onPress={handlePrimaryAction}
                      >
                        <Text style={styles.primaryButtonText}>{primaryButtonText}</Text>
                      </TouchableOpacity>
                    )}
                  </View>
                </>
              )}
            </Animated.View>
          </TouchableWithoutFeedback>
        </View>
      </TouchableWithoutFeedback>
    </Modal>
  );
};

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContainer: {
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  topContainer: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 54 : 20,
    left: 20,
    right: 20,
    minHeight: 60,
    borderRadius: 8,
  },
  bottomContainer: {
    position: 'absolute',
    bottom: 20,
    left: 20,
    right: 20,
    minHeight: 60,
    borderRadius: 8,
  },
  centerContainer: {
    width: '85%',
    maxWidth: 340,
    borderRadius: 12,
    alignItems: 'center',
  },
  notificationContent: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconContainer: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: 'rgba(0, 122, 255, 0.1)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
  },
  icon: {
    marginRight: 12,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    marginBottom: 10,
    textAlign: 'center',
  },
  message: {
    fontSize: 16,
    color: '#333',
    textAlign: 'center',
    marginBottom: 20,
  },
  notificationMessage: {
    color: '#fff',
    flex: 1,
    marginBottom: 0,
    textAlign: 'left',
  },
  buttonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    width: '100%',
  },
  button: {
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: lightTheme.colors.primary,
    minWidth: 120,
  },
  errorButton: {
    backgroundColor: '#ff3b30',
  },
  successButton: {
    backgroundColor: lightTheme.colors.secondary,
  },
  warningButton: {
    backgroundColor: lightTheme.colors.notification,
  },
  secondaryButton: {
    backgroundColor: '#f2f2f2',
    marginRight: 8,
    flex: 1,
  },
  primaryButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 16,
  },
  secondaryButtonText: {
    color: '#333',
    fontWeight: '500',
    fontSize: 16,
  },
  closeButton: {
    padding: 8,
    marginLeft: 8,
  },
  successBackground: {
    backgroundColor: lightTheme.colors.secondary,
  },
  errorBackground: {
    backgroundColor: '#ff3b30',
  },
  warningBackground: {
    backgroundColor: lightTheme.colors.notification,
  },
  infoBackground: {
    backgroundColor: lightTheme.colors.primary,
  },
});

export default SystemModal; 