import React, { useRef, useEffect } from 'react';
import { View, Text, StyleSheet, Alert, Animated } from 'react-native';
import { Swipeable, RectButton } from 'react-native-gesture-handler';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../themes';

// Keep track of the currently open swipeable globally
let currentlyOpenSwipeable: Swipeable | null = null;

interface SwipeableRowProps {
  children: React.ReactNode;
  onDelete: () => void;
  itemName?: string;
}

const SwipeableRow: React.FC<SwipeableRowProps> = ({
  children,
  onDelete,
  itemName = 'this item'
}) => {
  const swipeableRef = useRef<Swipeable>(null);

  useEffect(() => {
    const swipeable = swipeableRef.current;
    return () => {
      // Clean up when component unmounts
      if (currentlyOpenSwipeable === swipeable) {
        currentlyOpenSwipeable = null;
      }
      // Ensure swipeable is closed on unmount if it's the current one
      if (currentlyOpenSwipeable === swipeable) {
          swipeable?.close();
      }
    };
  }, []);

  const closeCurrentSwipeable = () => {
    if (currentlyOpenSwipeable && currentlyOpenSwipeable !== swipeableRef.current) {
      currentlyOpenSwipeable.close();
      currentlyOpenSwipeable = null; // Reset after closing
    }
  };

  const handleSwipeableWillOpen = () => {
    closeCurrentSwipeable();
    currentlyOpenSwipeable = swipeableRef.current;
  };

  const renderRightActions = (
    progress: Animated.AnimatedInterpolation<number>,
    dragX: Animated.AnimatedInterpolation<number>
  ) => {
    const scale = dragX.interpolate({
      inputRange: [-80, 0],
      outputRange: [1, 0],
      extrapolate: 'clamp',
    });

    // Translate the button into view smoothly
    const trans = dragX.interpolate({
      inputRange: [-80, 0],
      outputRange: [0, 80],
      extrapolate: 'clamp',
    });

    return (
      <View style={styles.rightActionContainer} pointerEvents="box-none">
        <Animated.View style={[styles.buttonContainer, { transform: [{ translateX: trans }] }]}>
          <RectButton style={styles.rightAction} onPress={confirmDelete}>
            <Ionicons name="trash-outline" size={24} color="white" style={styles.actionIcon} />
            <Text style={styles.actionText}>Delete</Text>
          </RectButton>
        </Animated.View>
      </View>
    );
  };

  const confirmDelete = () => {
    // Close the swipeable first
    swipeableRef.current?.close();
    currentlyOpenSwipeable = null;

    // Show confirmation dialog
    Alert.alert(
      'Remove from History',
      `Are you sure you want to remove ${itemName} from your scan history?`,
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Remove',
          style: 'destructive',
          // Ensure onDelete is only called after confirmation
          onPress: onDelete, 
        },
      ],
      { cancelable: true }
    );
  };

  return (
    <Swipeable
      ref={swipeableRef}
      friction={1} // Slightly reduced friction for a potentially quicker feel
      leftThreshold={30} // Standard iOS threshold
      rightThreshold={40}
      renderRightActions={renderRightActions}
      onSwipeableWillOpen={handleSwipeableWillOpen}
      overshootRight={false} // Prevents swiping beyond the button
      enableTrackpadTwoFingerGesture
    >
      {children}
    </Swipeable>
  );
};

const styles = StyleSheet.create({
  rightActionContainer: {
    width: 80, 
    height: '100%',
    overflow: 'hidden', // Prevents button content from showing before swipe
  },
  buttonContainer: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    width: 80,
  },
  rightAction: {
    flex: 1,
    backgroundColor: '#ff3b30',
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionIcon: {
    marginBottom: 2, // Space between icon and text
  },
  actionText: {
    color: 'white',
    fontSize: 12,
    fontWeight: '500',
  },
});

export default SwipeableRow; 