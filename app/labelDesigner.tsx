import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Platform,
  PanResponder,
  Animated,
  TextInput,
  Image,
  Dimensions,
  Alert,
  ViewStyle,
  TextStyle,
  ActivityIndicator,
  KeyboardAvoidingView
} from 'react-native';
import { useAppStore } from '../src/store';
import { lightTheme } from '../src/themes';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import * as ImagePicker from 'expo-image-picker';
import { format } from 'date-fns';
import { Barcode } from 'expo-barcode-generator';
import * as Font from 'expo-font';
import logger from '../src/utils/logger';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Get window dimensions
const windowWidth = Dimensions.get('window').width;

// Element types
enum ElementType {
  TEXT = 'text',
  LOGO = 'logo',
  BARCODE = 'barcode',
  PRICE = 'price',
  DATE = 'date'
}

// Define types for font weights to resolve TypeScript issues
type FontWeightType = 'normal' | 'bold' | '100' | '200' | '300' | '400' | '500' | '600' | '700' | '800' | '900';

// Define interface for elements
interface ElementBase {
  id: string;
  type: ElementType;
  x: number;
  y: number;
  width: number;
  height: number;
  isSelected: boolean;
}

interface TextElement extends ElementBase {
  type: ElementType.TEXT;
  value: string;
  fontSize: number;
  fontWeight: FontWeightType;
}

interface LogoElement extends ElementBase {
  type: ElementType.LOGO;
  value: string | null;
}

interface BarcodeElement extends ElementBase {
  type: ElementType.BARCODE;
  value: string;
}

interface PriceElement extends ElementBase {
  type: ElementType.PRICE;
  value: string;
  quantifier: string;
}

interface DateElement extends ElementBase {
  type: ElementType.DATE;
  value: string; // This will be the date format pattern
  fontSize: number;
  fontWeight: FontWeightType;
}

type Element = TextElement | LogoElement | BarcodeElement | PriceElement | DateElement;

// Sample data
const SAMPLE_ITEM = {
  name: 'RMT Cream Blusher',
  price: 4.49,
  sku: 'SKU12345',
  barcode: '694180421093',
  id: '250425',
  tagline: 'Everyday Low Price',
  quantifier: 'each'
};

// Initial elements for the label
const initialElements: Element[] = [
  {
    id: '1',
    type: ElementType.TEXT,
    x: 10,
    y: 10,
    width: 100,
    height: 30,
    value: SAMPLE_ITEM.id,
    fontSize: 12,
    fontWeight: '500',
    isSelected: false,
  },
  {
    id: '2',
    type: ElementType.DATE,
    x: 260,
    y: 10,
    width: 100,
    height: 20,
    value: 'MM/dd/yyyy',
    fontSize: 10,
    fontWeight: '400',
    isSelected: false,
  },
  {
    id: '3',
    type: ElementType.TEXT,
    x: 10,
    y: 40,
    width: 300,
    height: 40,
    value: SAMPLE_ITEM.name,
    fontSize: 26,
    fontWeight: 'bold',
    isSelected: false,
  },
  {
    id: '4',
    type: ElementType.LOGO,
    x: 10,
    y: 100,
    width: 36,
    height: 36,
    value: null,
    isSelected: false,
  },
  {
    id: '5',
    type: ElementType.TEXT,
    x: 10,
    y: 140,
    width: 80,
    height: 20,
    value: SAMPLE_ITEM.tagline,
    fontSize: 10,
    fontWeight: '400',
    isSelected: false,
  },
  {
    id: '6',
    type: ElementType.BARCODE,
    x: 100,
    y: 110,
    width: 120,
    height: 50,
    value: SAMPLE_ITEM.barcode,
    isSelected: false,
  },
  {
    id: '7',
    type: ElementType.PRICE,
    x: 230,
    y: 110,
    width: 80,
    height: 60,
    value: SAMPLE_ITEM.price.toString(),
    quantifier: SAMPLE_ITEM.quantifier,
    isSelected: false,
  },
];

interface PreviewDimensions {
  width: number;
  height: number;
}

export default function LabelDesignerScreen() {
  const router = useRouter();
  const [elements, setElements] = useState<Element[]>(initialElements);
  const [selectedElement, setSelectedElement] = useState<string | null>(null);
  const [logoUri, setLogoUri] = useState<string | null>(null);
  const [editingText, setEditingText] = useState<string | null>(null);
  const [editingValue, setEditingValue] = useState('');
  const [showElementOptions, setShowElementOptions] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [fontsLoaded, setFontsLoaded] = useState(false);
  const [designName, setDesignName] = useState('');
  const [saving, setSaving] = useState(false);
  const [showSaveModal, setShowSaveModal] = useState(false);
  const [loading, setLoading] = useState(false);
  
  // Ref for the label container
  const labelContainerRef = useRef(null);

  // Load saved design
  const loadSavedDesign = async () => {
    try {
      // Show loading indicator
      setLoading(true);
      
      // Get saved designs
      const savedDesignsJson = await AsyncStorage.getItem('savedLabelDesigns');
      
      if (savedDesignsJson) {
        const savedDesigns = JSON.parse(savedDesignsJson);
        
        if (savedDesigns.length === 0) {
          // No saved designs
          Alert.alert('No Saved Designs', 'You have no saved designs to load.');
          setLoading(false);
          return;
        }
        
        if (savedDesigns.length === 1) {
          // Only one design, load it directly
          const design = savedDesigns[0];
          setElements(design.elements);
          setDesignName(design.name);
          
          // Update logo URI if present
          const logoElement = design.elements.find((el: Element) => el.type === 'logo') as LogoElement | undefined;
          if (logoElement && logoElement.value) {
            setLogoUri(logoElement.value);
          }
          
          logger.info('LabelDesigner', 'Design loaded', { name: design.name });
          Alert.alert('Success', `Design "${design.name}" loaded successfully.`);
        } else {
          // Multiple designs, show selection dialog
          setLoading(false);
          
          // Prepare design options for Alert
          const options = savedDesigns.map((design: { name: string, elements: Element[] }) => ({
            text: design.name,
            onPress: () => {
              setElements(design.elements);
              setDesignName(design.name);
              
              // Update logo URI if present
              const logoElement = design.elements.find((el: Element) => el.type === 'logo') as LogoElement | undefined;
              if (logoElement && logoElement.value) {
                setLogoUri(logoElement.value);
              }
              
              logger.info('LabelDesigner', 'Design loaded', { name: design.name });
              Alert.alert('Success', `Design "${design.name}" loaded successfully.`);
            }
          }));
          
          // Add cancel button
          options.push({
            text: 'Cancel',
            style: 'cancel'
          });
          
          // Show selection dialog
          Alert.alert(
            'Select Design',
            'Choose a design to load:',
            options as any
          );
          
          return;
        }
      } else {
        // No saved designs
        Alert.alert('No Saved Designs', 'You have no saved designs to load.');
      }
      
      setLoading(false);
    } catch (error) {
      logger.error('LabelDesigner', 'Error loading saved design', { error });
      Alert.alert('Error', 'Failed to load saved design. Please try again.');
      setLoading(false);
    }
  };

  // Load custom fonts
  useEffect(() => {
    async function loadFonts() {
      try {
        await Font.loadAsync({
          'Fredoka-Regular': require('../assets/fonts/Fredoka-Regular.ttf'),
        });
        setFontsLoaded(true);
      } catch (error) {
        console.error('Error loading fonts:', error);
      }
    }
    
    loadFonts();
  }, []);

  // Update logo URI for the logo element when it changes
  useEffect(() => {
    if (logoUri) {
      setElements(prev => 
        prev.map(el => 
          el.type === ElementType.LOGO ? { ...el, value: logoUri } : el
        )
      );
    }
  }, [logoUri]);

  // Format date based on the provided pattern
  const formatDate = (pattern: string): string => {
    try {
      return format(new Date(), pattern);
    } catch (error) {
      console.error('Error formatting date:', error);
      return format(new Date(), 'MM/dd/yyyy');
    }
  };

  // Function to pick an image for logo
  const pickImage = async () => {
    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ImagePicker.MediaTypeOptions.Images,
        allowsEditing: true,
        aspect: [1, 1],
        quality: 1,
      });

      if (!result.canceled && result.assets && result.assets.length > 0) {
        const imageUri = result.assets[0].uri;
        setLogoUri(imageUri);
        
        // Update the logo element in the elements array
        setElements(prevElements => 
          prevElements.map(element => {
            if (element.type === 'logo') {
              return {
                ...element,
                value: imageUri
              };
            }
            return element;
          })
        );
        
        logger.info('LabelDesigner', 'Logo image selected', { uri: imageUri });
      }
    } catch (error) {
      logger.error('LabelDesigner', 'Error picking logo image', { error });
      Alert.alert('Error', 'Failed to select logo image. Please try again.');
    }
  };

  // Create PanResponders for each element
  const createPanResponder = (id: string) => {
    return PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onPanResponderGrant: () => {
        // Select this element
        handleElementSelect(id);
        setIsDragging(true);
      },
      onPanResponderMove: (_, gestureState) => {
        setElements(prev => {
          return prev.map(el => {
            if (el.id === id) {
              // Update position, constrained to label boundaries
              const newX = Math.max(0, Math.min(el.x + gestureState.dx, 324 - el.width));
              const newY = Math.max(0, Math.min(el.y + gestureState.dy, 180 - el.height));
              
              return {
                ...el,
                x: newX,
                y: newY,
              };
            }
            return el;
          });
        });
      },
      onPanResponderRelease: () => {
        setIsDragging(false);
      },
    });
  };

  // Handle element selection
  const handleElementSelect = (id: string) => {
    if (editingText) {
      // Finish any current text editing before selecting a new element
      finishTextEditing();
    }
    
    setSelectedElement(id);
    setElements(prev => 
      prev.map(el => ({
        ...el,
        isSelected: el.id === id,
      }))
    );
  };

  // Edit text content
  const startTextEditing = (id: string, currentValue: string) => {
    setEditingText(id);
    setEditingValue(currentValue);
  };

  // Finish text editing
  const finishTextEditing = () => {
    if (editingText) {
      setElements(prev => 
        prev.map(el => 
          el.id === editingText ? { ...el, value: editingValue } : el
        )
      );
      setEditingText(null);
      setEditingValue('');
    }
  };

  // Add a new element to the label
  const addElement = (type: ElementType) => {
    // Generate a unique ID for the new element
    // Get current highest ID and increment by 1
    const highestId = Math.max(...elements.map(el => parseInt(el.id)));
    const newId = (highestId + 1).toString();
    
    let newElement: Element;
    
    switch (type) {
      case ElementType.TEXT:
        newElement = {
          id: newId,
          type,
          x: 50,
          y: 50,
          width: 100,
          height: 30,
          value: 'New Text',
          fontSize: 16,
          fontWeight: 'normal',
          isSelected: true,
        };
        break;
      case ElementType.LOGO:
        newElement = {
          id: newId,
          type,
          x: 50,
          y: 50,
          width: 48,
          height: 48,
          value: null,
          isSelected: true,
        };
        break;
      case ElementType.BARCODE:
        newElement = {
          id: newId,
          type,
          x: 50,
          y: 50,
          width: 120,
          height: 50,
          value: '123456789012',
          isSelected: true,
        };
        break;
      case ElementType.PRICE:
        newElement = {
          id: newId,
          type,
          x: 50,
          y: 50,
          width: 80,
          height: 60,
          value: '9.99',
          quantifier: 'each',
          isSelected: true,
        };
        break;
      case ElementType.DATE:
        newElement = {
          id: newId,
          type,
          x: 50,
          y: 50,
          width: 100,
          height: 20,
          value: 'MM/dd/yyyy',
          fontSize: 10,
          fontWeight: '400',
          isSelected: true,
        };
        break;
      default:
        // This should never happen due to TypeScript, but needed for type safety
        throw new Error(`Unsupported element type: ${type}`);
    }
    
    // Deselect any previously selected elements
    const updatedElements = elements.map(el => ({ ...el, isSelected: false }));
    
    // Add the new element
    setElements([...updatedElements, newElement]);
    setSelectedElement(newId);
  };

  // Delete the currently selected element
  const deleteSelectedElement = () => {
    if (!selectedElement) return;
    
    // Don't allow deleting core elements
    const elementToDelete = elements.find(el => el.id === selectedElement);
    if (elementToDelete?.id && ['1', '2', '3', '4', '5', '6', '7'].includes(elementToDelete.id)) {
      Alert.alert('Cannot Delete', 'Core label elements cannot be deleted.');
      return;
    }
    
    setElements(prev => prev.filter(el => el.id !== selectedElement));
    setSelectedElement(null);
  };

  // Adjust element size
  const adjustElementSize = (amount: number, direction: 'width' | 'height') => {
    if (!selectedElement) return;
    
    setElements(prev => 
      prev.map(el => {
        if (el.id === selectedElement) {
          const newSize = Math.max(10, el[direction] + amount);
          return {
            ...el,
            [direction]: newSize
          };
        }
        return el;
      })
    );
  };

  // Adjust element font size
  const adjustFontSize = (amount: number) => {
    if (!selectedElement) return;
    
    setElements(prev => 
      prev.map(el => {
        if (el.id === selectedElement && el.type === ElementType.TEXT) {
          return {
            ...el,
            fontSize: Math.max(8, el.fontSize + amount)
          };
        }
        return el;
      })
    );
  };

  // Save the current design
  const saveDesign = async () => {
    try {
      if (!designName) {
        Alert.alert('Error', 'Please enter a design name');
        return;
      }

      // Show saving indicator
      setSaving(true);

      // Save the current elements state
      const designToSave = {
        name: designName,
        elements: elements,
        dateCreated: new Date().toISOString(),
      };

      // Get existing saved designs or initialize empty array
      const existingSavedDesignsJson = await AsyncStorage.getItem('savedLabelDesigns');
      let savedDesigns = existingSavedDesignsJson 
        ? JSON.parse(existingSavedDesignsJson) 
        : [];

      // Check if design with same name exists
      const existingIndex = savedDesigns.findIndex((design: { name: string }) => design.name === designName);
      if (existingIndex >= 0) {
        // Replace existing design
        savedDesigns[existingIndex] = designToSave;
      } else {
        // Add new design
        savedDesigns.push(designToSave);
      }

      // Save updated designs array
      await AsyncStorage.setItem('savedLabelDesigns', JSON.stringify(savedDesigns));
      
      // Log success
      logger.info('LabelDesigner', 'Design saved successfully', { name: designName });
      
      // Hide saving indicator and show confirmation
      setSaving(false);
      setShowSaveModal(false);
      
      // Show confirmation message
      Alert.alert(
        'Success',
        `Design "${designName}" saved successfully. It can now be used in the Labels screen.`,
        [{ text: 'OK' }]
      );
    } catch (error) {
      logger.error('LabelDesigner', 'Error saving design', { error });
      setSaving(false);
      Alert.alert('Error', 'Failed to save design. Please try again.');
    }
  };

  // Render the elements on the label
  const renderElement = (element: Element) => {
    const panResponder = createPanResponder(element.id);
    
    // Common styles for all elements
    const elementStyle: ViewStyle = {
      position: 'absolute',
      left: element.x,
      top: element.y,
      width: element.width,
      height: element.height,
      borderWidth: element.isSelected ? 1 : 0,
      borderColor: lightTheme.colors.primary,
      backgroundColor: element.isSelected ? 'rgba(0, 120, 255, 0.1)' : 'transparent',
    };
    
    // If fonts aren't loaded yet and this element needs a font, show a loading indicator
    if (!fontsLoaded && (element.type === ElementType.TEXT || element.type === ElementType.DATE || element.type === ElementType.PRICE)) {
      return (
        <Animated.View key={element.id} style={elementStyle}>
          <ActivityIndicator size="small" color={lightTheme.colors.primary} />
        </Animated.View>
      );
    }
    
    switch (element.type) {
      case ElementType.TEXT:
        // If currently editing this text element
        if (editingText === element.id) {
          return (
            <Animated.View
              key={element.id}
              style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            >
              <TextInput
                style={[
                  styles.textInput,
                  {
                    fontSize: element.fontSize,
                    fontWeight: element.fontWeight,
                    fontFamily: 'Fredoka-Regular',
                  } as TextStyle
                ]}
                value={editingValue}
                onChangeText={setEditingValue}
                autoFocus
                onBlur={finishTextEditing}
                onSubmitEditing={finishTextEditing}
              />
            </Animated.View>
          );
        }
        
        // Regular text display
        return (
          <Animated.View
            key={element.id}
            style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            {...panResponder.panHandlers}
          >
            <Text
              style={{
                fontSize: element.fontSize,
                fontWeight: element.fontWeight,
                color: '#000',
                fontFamily: 'Fredoka-Regular',
              } as TextStyle}
              onPress={() => element.isSelected && startTextEditing(element.id, element.value)}
            >
              {element.value}
            </Text>
          </Animated.View>
        );
      
      case ElementType.DATE:
        // If currently editing this date element
        if (editingText === element.id) {
          return (
            <Animated.View
              key={element.id}
              style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            >
              <TextInput
                style={[
                  styles.textInput,
                  {
                    fontSize: element.fontSize,
                    fontWeight: element.fontWeight,
                    fontFamily: 'Fredoka-Regular',
                  } as TextStyle
                ]}
                value={editingValue}
                onChangeText={setEditingValue}
                autoFocus
                onBlur={finishTextEditing}
                onSubmitEditing={finishTextEditing}
                placeholder="date format (e.g. MM/dd/yyyy)"
              />
            </Animated.View>
          );
        }
        
        // Regular date display
        return (
          <Animated.View
            key={element.id}
            style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            {...panResponder.panHandlers}
          >
            <Text
              style={{
                fontSize: element.fontSize,
                fontWeight: element.fontWeight,
                color: '#000',
                fontFamily: 'Fredoka-Regular',
              } as TextStyle}
              onPress={() => element.isSelected && startTextEditing(element.id, element.value)}
            >
              {formatDate(element.value)}
            </Text>
          </Animated.View>
        );
      
      case ElementType.LOGO:
        return (
          <Animated.View
            key={element.id}
            style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            {...panResponder.panHandlers}
          >
            {element.value ? (
              <Image
                source={{ uri: element.value }}
                style={{ width: '100%', height: '100%', borderRadius: element.width / 2 }}
              />
            ) : (
              <TouchableOpacity
                style={[
                  styles.logoPlaceholder,
                  { borderRadius: element.width / 2 }
                ]}
                onPress={pickImage}
              >
                <Text style={styles.logoText}>JOY</Text>
              </TouchableOpacity>
            )}
          </Animated.View>
        );
      
      case ElementType.BARCODE:
        const barcodeElement = element as BarcodeElement;
        return (
          <Animated.View style={elementStyle} {...panResponder.panHandlers}>
            <TouchableOpacity onPress={() => handleElementSelect(element.id)} activeOpacity={1}>
              <Barcode 
                value={barcodeElement.value || " "}
                options={{
                  format: 'CODE128',
                  background: 'transparent',
                  lineColor: '#000000',
                  width: element.width / (barcodeElement.value?.length || 100),
                  height: element.height,
                  displayValue: false,
                  margin: 0
                }}
              />
            </TouchableOpacity>
          </Animated.View>
        );
      
      case ElementType.PRICE:
        return (
          <Animated.View
            key={element.id}
            style={[elementStyle, { zIndex: element.isSelected ? 100 : 1 }]}
            {...panResponder.panHandlers}
          >
            <View style={styles.priceContainer}>
              <View style={styles.priceRow}>
                <Text style={[styles.pricePrefix, { fontFamily: 'Fredoka-Regular' }]}>$</Text>
                <Text style={[styles.priceWhole, { fontFamily: 'Fredoka-Regular' }]}>
                  {Math.floor(parseFloat(element.value))}
                </Text>
                <Text style={[styles.priceCents, { fontFamily: 'Fredoka-Regular' }]}>
                  {(parseFloat(element.value) % 1).toFixed(2).substring(2)}
                </Text>
              </View>
              <Text style={[styles.priceQuantifier, { fontFamily: 'Fredoka-Regular' }]}>
                {element.quantifier}
              </Text>
            </View>
          </Animated.View>
        );
    }
  };

  return (
    <View style={styles.container}>
      <StatusBar style="dark" />
      
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color="#333" />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Label Designer</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity onPress={loadSavedDesign} style={styles.loadButton}>
            <Ionicons name="folder-open-outline" size={24} color={lightTheme.colors.primary} />
          </TouchableOpacity>
          <TouchableOpacity onPress={() => setShowSaveModal(true)} style={styles.saveButton}>
            <Ionicons name="save-outline" size={24} color={lightTheme.colors.primary} />
          </TouchableOpacity>
        </View>
      </View>
      
      {/* Main Content */}
      <ScrollView style={styles.contentScrollView}>
        {/* Design Canvas */}
        <View style={styles.designSection}>
          <Text style={styles.sectionTitle}>Label Design</Text>
          
          {/* Label Preview Canvas */}
          <View style={styles.labelContainer} ref={labelContainerRef}>
            <View style={styles.labelCanvas}>
              {elements.map((element) => renderElement(element))}
            </View>
          </View>
          
          {/* Element Controls */}
          {selectedElement && (
            <View style={styles.controlsContainer}>
              <Text style={styles.controlsTitle}>Element Controls</Text>
              
              <View style={styles.controlsRow}>
                <TouchableOpacity 
                  style={styles.controlButton}
                  onPress={() => adjustElementSize(-5, 'width')}
                >
                  <Ionicons name="remove-circle-outline" size={24} color="#666" />
                  <Text style={styles.controlButtonText}>Width</Text>
                </TouchableOpacity>
                
                <TouchableOpacity 
                  style={styles.controlButton}
                  onPress={() => adjustElementSize(5, 'width')}
                >
                  <Ionicons name="add-circle-outline" size={24} color="#666" />
                  <Text style={styles.controlButtonText}>Width</Text>
                </TouchableOpacity>
                
                <TouchableOpacity 
                  style={styles.controlButton}
                  onPress={() => adjustElementSize(-5, 'height')}
                >
                  <Ionicons name="remove-circle-outline" size={24} color="#666" />
                  <Text style={styles.controlButtonText}>Height</Text>
                </TouchableOpacity>
                
                <TouchableOpacity 
                  style={styles.controlButton}
                  onPress={() => adjustElementSize(5, 'height')}
                >
                  <Ionicons name="add-circle-outline" size={24} color="#666" />
                  <Text style={styles.controlButtonText}>Height</Text>
                </TouchableOpacity>
              </View>
              
              {/* Font Size Controls - Only for Text elements */}
              {elements.find(el => el.id === selectedElement)?.type === ElementType.TEXT && (
                <View style={styles.controlsRow}>
                  <TouchableOpacity 
                    style={styles.controlButton}
                    onPress={() => adjustFontSize(-1)}
                  >
                    <Ionicons name="remove-circle-outline" size={24} color="#666" />
                    <Text style={styles.controlButtonText}>Font</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={styles.controlButton}
                    onPress={() => adjustFontSize(1)}
                  >
                    <Ionicons name="add-circle-outline" size={24} color="#666" />
                    <Text style={styles.controlButtonText}>Font</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={styles.controlButton}
                    onPress={() => {
                      const element = elements.find(el => el.id === selectedElement);
                      if (element?.type === ElementType.TEXT) {
                        startTextEditing(element.id, element.value);
                      }
                    }}
                  >
                    <Ionicons name="create-outline" size={24} color="#666" />
                    <Text style={styles.controlButtonText}>Edit</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={[styles.controlButton, styles.deleteButton]}
                    onPress={deleteSelectedElement}
                  >
                    <Ionicons name="trash-outline" size={24} color="#d32f2f" />
                    <Text style={[styles.controlButtonText, { color: '#d32f2f' }]}>Delete</Text>
                  </TouchableOpacity>
                </View>
              )}
              
              {/* Other element type controls */}
              {elements.find(el => el.id === selectedElement)?.type !== ElementType.TEXT && (
                <View style={styles.controlsRow}>
                  <TouchableOpacity 
                    style={[styles.controlButton, styles.deleteButton]}
                    onPress={deleteSelectedElement}
                  >
                    <Ionicons name="trash-outline" size={24} color="#d32f2f" />
                    <Text style={[styles.controlButtonText, { color: '#d32f2f' }]}>Delete</Text>
                  </TouchableOpacity>
                </View>
              )}
            </View>
          )}
          
          {/* Add Element Button */}
          <View style={styles.addElementContainer}>
            <TouchableOpacity 
              style={styles.addElementButton}
              onPress={() => setShowElementOptions(!showElementOptions)}
            >
              <Ionicons 
                name={showElementOptions ? "close-circle-outline" : "add-circle-outline"} 
                size={24} 
                color={lightTheme.colors.primary} 
              />
              <Text style={styles.addElementText}>
                {showElementOptions ? "Cancel" : "Add Element"}
              </Text>
            </TouchableOpacity>
            
            {/* Element Options - shown when Add button is clicked */}
            {showElementOptions && (
              <View style={styles.elementOptionsContainer}>
                <TouchableOpacity 
                  style={styles.closeOptionsButton}
                  onPress={() => setShowElementOptions(false)}
                >
                  <Ionicons name="close-circle" size={24} color="#e74c3c" />
                </TouchableOpacity>
                
                <View style={styles.elementOptionsGrid}>
                  <TouchableOpacity 
                    style={styles.elementOptionButton}
                    onPress={() => addElement(ElementType.TEXT)}
                  >
                    <Ionicons name="text-outline" size={24} color="#666" />
                    <Text style={styles.elementOptionText}>Text</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={styles.elementOptionButton}
                    onPress={() => addElement(ElementType.BARCODE)}
                  >
                    <Ionicons name="barcode-outline" size={24} color="#666" />
                    <Text style={styles.elementOptionText}>Barcode</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={styles.elementOptionButton}
                    onPress={() => addElement(ElementType.PRICE)}
                  >
                    <Ionicons name="pricetag-outline" size={24} color="#666" />
                    <Text style={styles.elementOptionText}>Price</Text>
                  </TouchableOpacity>
                 
                  <TouchableOpacity 
                    style={styles.elementOptionButton}
                    onPress={() => addElement(ElementType.DATE)}
                  >
                    <Ionicons name="calendar-outline" size={24} color="#666" />
                    <Text style={styles.elementOptionText}>Date</Text>
                  </TouchableOpacity>
                  
                  <TouchableOpacity 
                    style={styles.elementOptionButton}
                    onPress={() => addElement(ElementType.LOGO)}
                  >
                    <Ionicons name="image-outline" size={24} color="#666" />
                    <Text style={styles.elementOptionText}>Logo</Text>
                  </TouchableOpacity>
                </View>
              </View>
            )}
          </View>
        </View>
        
        {/* Instructions */}
        <View style={styles.instructionsSection}>
          <Text style={styles.sectionTitle}>Instructions</Text>
          <Text style={styles.instructionText}>
            • Tap an element to select it{'\n'}
            • Drag elements to position them{'\n'}
            • Use controls to resize or modify elements{'\n'}
            • Tap the text while selected to edit it{'\n'}
            • Add new elements with the "Add Element" button{'\n'}
            • Tap the save icon when you're done
          </Text>
        </View>
        
        {/* Dimensions Information */}
        <View style={styles.dimensionsSection}>
          <Text style={styles.sectionTitle}>Label Information</Text>
          <Text style={styles.dimensionText}>
            Dimensions: 2.25" × 1.25"{'\n'}
            Resolution: 203 DPI{'\n'}
            Color: Black only
          </Text>
        </View>
      </ScrollView>

      {/* Save Design Modal */}
      {showSaveModal && (
        <View style={styles.saveModal}>
          <Text style={styles.saveModalTitle}>Save Design</Text>
          <TextInput
            style={styles.designNameInput}
            placeholder="Design Name"
            value={designName}
            onChangeText={setDesignName}
          />
          <View style={styles.saveModalButtons}>
            <TouchableOpacity
              style={styles.cancelButton}
              onPress={() => setShowSaveModal(false)}
            >
              <Text style={styles.cancelButtonText}>Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.saveModalButton}
              onPress={saveDesign}
            >
              <Text style={styles.saveButtonText}>Save</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: Platform.OS === 'ios' ? 60 : 40,
    paddingBottom: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 8,
  },
  saveButton: {
    padding: 8,
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
    textAlign: 'center',
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  loadButton: {
    padding: 8,
  },
  contentScrollView: {
    flex: 1,
    padding: 16,
  },
  designSection: {
    marginBottom: 24,
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    color: lightTheme.colors.primary,
  },
  labelContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    backgroundColor: '#f9f9f9',
    borderRadius: 8,
    marginBottom: 16,
  },
  labelCanvas: {
    width: 324, // 2.25 inches * 144 (factor for preview)
    height: 180, // 1.25 inches * 144 (factor for preview)
    backgroundColor: 'white',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 4,
    position: 'relative',
    overflow: 'hidden',
  },
  controlsContainer: {
    padding: 12,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
    marginBottom: 16,
  },
  controlsTitle: {
    fontSize: 16,
    fontWeight: '500',
    marginBottom: 8,
    color: '#444',
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  controlButton: {
    flex: 1,
    alignItems: 'center',
    padding: 8,
    marginHorizontal: 4,
    backgroundColor: '#fff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
  },
  deleteButton: {
    borderColor: '#ffcdd2',
    backgroundColor: '#ffebee',
  },
  controlButtonText: {
    fontSize: 12,
    marginTop: 4,
    color: '#666',
  },
  textInput: {
    flex: 1,
    padding: 0,
    color: '#000',
  },
  addElementContainer: {
    marginTop: 8,
  },
  addElementButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 12,
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
  },
  addElementText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.primary,
    marginLeft: 8,
  },
  elementOptionsContainer: {
    padding: 12,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
  },
  closeOptionsButton: {
    alignItems: 'flex-end',
    padding: 8,
  },
  elementOptionsGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 12,
  },
  elementOptionButton: {
    alignItems: 'center',
    padding: 8,
    backgroundColor: '#fff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    width: '23%',
  },
  elementOptionText: {
    fontSize: 12,
    marginTop: 4,
    color: '#666',
  },
  instructionsSection: {
    marginBottom: 24,
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  instructionText: {
    fontSize: 14,
    lineHeight: 22,
    color: '#444',
  },
  dimensionsSection: {
    marginBottom: 24,
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  dimensionText: {
    fontSize: 14,
    lineHeight: 22,
    color: '#444',
  },
  logoPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  logoText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  barcodeContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  barcode: {
    height: 40,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'center',
    width: '100%',
  },
  barcodeLine: {
    width: 1.2,
    backgroundColor: '#000',
    marginHorizontal: 0.5,
  },
  barcodeText: {
    fontSize: 10,
    color: '#000',
    marginTop: 2,
  },
  priceContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  priceRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  pricePrefix: {
    fontSize: 18,
    color: '#000',
    fontWeight: 'bold',
    alignSelf: 'flex-start',
    marginTop: 5,
  },
  priceWhole: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#000',
    lineHeight: 36,
  },
  priceCents: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#000',
    lineHeight: 20,
    marginTop: 2,
  },
  priceQuantifier: {
    fontSize: 14,
    color: '#000',
    textAlign: 'center',
  },
  saveModal: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  saveModalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 16,
  },
  designNameInput: {
    width: '80%',
    height: 40,
    borderColor: '#ccc',
    borderWidth: 1,
    padding: 8,
    marginBottom: 16,
  },
  saveModalButtons: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  cancelButton: {
    padding: 12,
    backgroundColor: '#ffcdd2',
    borderRadius: 8,
  },
  cancelButtonText: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#d32f2f',
  },
  saveModalButton: {
    padding: 12,
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
  },
  saveButtonText: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#fff',
  },
}); 