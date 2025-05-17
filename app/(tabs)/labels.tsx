import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Image, Platform, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useAppStore } from '../../src/store';
import * as ImagePicker from 'expo-image-picker';
import * as Font from 'expo-font';
import { Barcode } from 'expo-barcode-generator';
import AsyncStorage from '@react-native-async-storage/async-storage';
import logger from '../../src/utils/logger';
import { format } from 'date-fns';
import { printItemLabel, getLabelPrinterStatus, LabelData } from '../../src/utils/printLabel';

// Sample data for label preview
const SAMPLE_ITEM = {
  id: "12345",
  name: "RMT Cream Blusher",
  price: 4.49,
  sku: "SKU-9876",
  barcode: "987654321098",
  tagline: "Premium Quality",
  quantifier: "each"
};

// Enum for template types
enum LabelTemplate {
  STANDARD = 'standard',
  COMPACT = 'compact',
  BARCODE = 'barcode',
  JOY = 'joy',
  CUSTOM = 'custom'
}

// Define interface for elements to match labelDesigner
interface ElementBase {
  id: string;
  type: string;
  x: number;
  y: number;
  width: number;
  height: number;
  isSelected: boolean;
}

interface TextElement extends ElementBase {
  type: 'text';
  value: string;
  fontSize: number;
  fontWeight: string;
}

interface LogoElement extends ElementBase {
  type: 'logo';
  value: string | null;
}

interface BarcodeElement extends ElementBase {
  type: 'barcode';
  value: string;
}

interface PriceElement extends ElementBase {
  type: 'price';
  value: string;
  quantifier: string;
}

interface DateElement extends ElementBase {
  type: 'date';
  value: string;
  fontSize: number;
  fontWeight: string;
}

type Element = TextElement | LogoElement | BarcodeElement | PriceElement | DateElement;

export default function LabelsScreen() {
  const router = useRouter();

  // Get state values from store using useMemo to prevent re-renders
  const labelLiveHost = useMemo(() => useAppStore.getState().labelLiveHost, []);
  const labelLivePrinter = useMemo(() => useAppStore.getState().labelLivePrinter, []);

  // State for selected template
  const [selectedTemplate, setSelectedTemplate] = useState<LabelTemplate>(LabelTemplate.JOY);
  const [logoUri, setLogoUri] = useState<string | null>(null);
  const [isFontLoaded, setIsFontLoaded] = useState(false);
  const [savedDesigns, setSavedDesigns] = useState<{ name: string, elements: Element[] }[]>([]);
  const [selectedDesign, setSelectedDesign] = useState<Element[] | null>(null);
  const [isLoadingDesigns, setIsLoadingDesigns] = useState(false);
  const [isPrinting, setIsPrinting] = useState(false);
  const [printerAvailable, setPrinterAvailable] = useState<boolean | null>(null);

  // Navigation function
  const navigateToSettings = useCallback(() => {
    router.push('/labelSettings');
  }, [router]);

  // Navigation to label designer
  const navigateToDesigner = useCallback(() => {
    router.push('/labelDesigner');
  }, [router]);

  // Check if printer is configured
  const isPrinterConfigured = useMemo(() => {
    return !!labelLiveHost && !!labelLivePrinter;
  }, [labelLiveHost, labelLivePrinter]);

  // Determine status color
  const statusColor = isPrinterConfigured ? '#4CAF50' : '#F44336';

  // Function to pick an image for logo
  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [1, 1],
      quality: 1,
    });

    if (!result.canceled && result.assets && result.assets.length > 0) {
      setLogoUri(result.assets[0].uri);
    }
  };

  // Load Fredoka font
  const loadFontsAsync = async () => {
    try {
      await Font.loadAsync({
        'Fredoka-Regular': require('../../assets/fonts/Fredoka-Regular.ttf'),
      });
      setIsFontLoaded(true);
    } catch (error) {
      console.error('Error loading fonts:', error);
    }
  };

  // Function to load saved designs from asyncStorage
  const loadSavedDesigns = async () => {
    try {
      setIsLoadingDesigns(true);
      const designsJson = await AsyncStorage.getItem('savedLabelDesigns');
      if (designsJson) {
        const designs = JSON.parse(designsJson);
        setSavedDesigns(designs);
        logger.info('Labels', 'Loaded saved designs', { count: designs.length });
      }
    } catch (error) {
      logger.error('Labels', 'Error loading saved designs', { error });
      Alert.alert('Error', 'Failed to load saved designs');
    } finally {
      setIsLoadingDesigns(false);
    }
  };

  // Select a saved design
  const selectDesign = (elements: Element[]) => {
    setSelectedDesign(elements);
    setSelectedTemplate(LabelTemplate.CUSTOM);
    
    // Extract logo URI if present
    const logoElement = elements.find(el => el.type === 'logo') as LogoElement | undefined;
    if (logoElement && logoElement.value) {
      setLogoUri(logoElement.value);
    }
  };

  // Load font and saved designs when component mounts
  useEffect(() => {
    loadFontsAsync();
    loadSavedDesigns();
  }, []);

  // Format price with superscript cents
  const formatPrice = (price: number) => {
    const [dollars, cents] = price.toFixed(2).split('.');
    return (
      <View style={styles.priceContainer}>
        <Text style={styles.dollarSign}>$</Text>
        <Text style={styles.dollars}>{dollars}</Text>
        <Text style={styles.cents}>{cents}</Text>
      </View>
    );
  };

  // Render custom design preview
  const renderCustomDesign = () => {
    if (!selectedDesign) return null;
    
    // Get approximate dimensions for the container
    const containerWidth = 300; // approximate width in pixels
    const containerHeight = containerWidth / 2.25 * 1.25; // maintain aspect ratio
    
    return (
      <View style={styles.customDesignContainer}>
        {/* We'd need a more sophisticated renderer here to match labelDesigner */}
        <Text style={styles.customDesignText}>Custom Design</Text>
        {selectedDesign.map(element => {
          if (element.type === 'text') {
            const textElement = element as TextElement;
            // Scale position based on dimensions
            const scaledLeft = (element.x / 400) * containerWidth;
            const scaledTop = (element.y / 225) * containerHeight;
            
            return (
              <Text 
                key={element.id}
                style={{
                  position: 'absolute',
                  left: scaledLeft,
                  top: scaledTop,
                  fontSize: textElement.fontSize,
                  fontWeight: textElement.fontWeight as any,
                }}
              >
                {textElement.value}
              </Text>
            );
          }
          return null;
        })}
      </View>
    );
  };

  // Check printer availability
  const checkPrinterStatus = useCallback(async () => {
    try {
      const available = await getLabelPrinterStatus();
      setPrinterAvailable(available);
      return available;
    } catch (error) {
      logger.error('Labels', 'Error checking printer status', { error });
      setPrinterAvailable(false);
      return false;
    }
  }, []);

  // Print current template
  const handlePrint = async () => {
    try {
      // Check printer status first
      const available = await checkPrinterStatus();
      if (!available) {
        Alert.alert(
          'Printer Not Available',
          'The configured printer is not available. Please check printer settings and ensure it is connected.',
          [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Open Settings', onPress: navigateToSettings }
          ]
        );
        return;
      }

      setIsPrinting(true);

      // Prepare label data from sample
      const labelData: LabelData = {
        itemName: SAMPLE_ITEM.name,
        price: SAMPLE_ITEM.price,
        sku: SAMPLE_ITEM.sku,
        barcode: SAMPLE_ITEM.barcode
      };

      // Send print request
      const success = await printItemLabel(labelData);

      if (success) {
        Alert.alert('Success', 'Label sent to printer successfully.');
      } else {
        Alert.alert('Print Failed', 'Failed to send label to printer. Please check printer settings and try again.');
      }
    } catch (error) {
      logger.error('Labels', 'Error printing label', { error });
      Alert.alert('Error', 'An error occurred while trying to print. Please try again.');
    } finally {
      setIsPrinting(false);
    }
  };

  // Check printer status when component mounts
  useEffect(() => {
    checkPrinterStatus();
  }, [checkPrinterStatus]);

  return (
    <View style={styles.container}>
      {/* Header with settings button */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Label Designer</Text>
        <View style={styles.headerButtons}>
          <TouchableOpacity onPress={navigateToDesigner} style={styles.designerButton}>
            <Ionicons name="create-outline" size={24} color="#333" />
          </TouchableOpacity>
          <TouchableOpacity onPress={navigateToSettings} style={styles.settingsButton}>
            <Ionicons name="settings-outline" size={24} color="#333" />
          </TouchableOpacity>
        </View>
      </View>

      {/* Printer connection status */}
      <View style={styles.statusBar}>
        <View style={[styles.statusIndicator, { backgroundColor: statusColor }]} />
        <Text style={styles.statusText}>
          {isPrinterConfigured 
            ? `Connected to ${labelLivePrinter} at ${labelLiveHost}` 
            : 'Printer not configured'}
        </Text>
      </View>

      {/* Template selection */}
      <View style={styles.templateContainer}>
        <Text style={styles.sectionTitle}>Select Template</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          <TouchableOpacity 
            style={[styles.templateCard, selectedTemplate === LabelTemplate.JOY && styles.selectedTemplate]}
            onPress={() => setSelectedTemplate(LabelTemplate.JOY)}>
            <Text style={styles.templateName}>Joy Label</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.templateCard, selectedTemplate === LabelTemplate.STANDARD && styles.selectedTemplate]}
            onPress={() => setSelectedTemplate(LabelTemplate.STANDARD)}>
            <Text style={styles.templateName}>Standard</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.templateCard, selectedTemplate === LabelTemplate.COMPACT && styles.selectedTemplate]}
            onPress={() => setSelectedTemplate(LabelTemplate.COMPACT)}>
            <Text style={styles.templateName}>Compact</Text>
          </TouchableOpacity>
          <TouchableOpacity 
            style={[styles.templateCard, selectedTemplate === LabelTemplate.BARCODE && styles.selectedTemplate]}
            onPress={() => setSelectedTemplate(LabelTemplate.BARCODE)}>
            <Text style={styles.templateName}>Barcode</Text>
          </TouchableOpacity>
          {selectedDesign && (
            <TouchableOpacity 
              style={[styles.templateCard, selectedTemplate === LabelTemplate.CUSTOM && styles.selectedTemplate]}
              onPress={() => setSelectedTemplate(LabelTemplate.CUSTOM)}>
              <Text style={styles.templateName}>Custom</Text>
            </TouchableOpacity>
          )}
        </ScrollView>
      </View>

      {/* Saved designs */}
      <View style={styles.savedDesignsSection}>
        <View style={styles.sectionHeaderRow}>
          <Text style={styles.sectionTitle}>Saved Designs</Text>
          <TouchableOpacity onPress={loadSavedDesigns} style={styles.refreshButton}>
            <Ionicons name="refresh" size={20} color="#007BFF" />
          </TouchableOpacity>
        </View>
        
        {isLoadingDesigns ? (
          <ActivityIndicator size="small" color="#007BFF" style={styles.loader} />
        ) : savedDesigns.length > 0 ? (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.savedDesignsScroll}>
            {savedDesigns.map((design, index) => (
              <TouchableOpacity 
                key={index} 
                style={styles.savedDesignCard}
                onPress={() => selectDesign(design.elements)}
              >
                <Text style={styles.savedDesignName} numberOfLines={1}>{design.name}</Text>
                <Text style={styles.savedDesignDetails}>{design.elements.length} elements</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        ) : (
          <Text style={styles.noDesignsText}>No saved designs found. Create one in the Label Designer.</Text>
        )}
      </View>

      {/* Label preview */}
      <View style={styles.previewContainer}>
        <Text style={styles.sectionTitle}>Preview</Text>
        
        {/* Custom Design Template */}
        {selectedTemplate === LabelTemplate.CUSTOM && renderCustomDesign()}
        
        {/* Joy Label Template */}
        {selectedTemplate === LabelTemplate.JOY && (
          <View style={styles.joyLabelContainer}>
            {!isFontLoaded ? (
              <ActivityIndicator size="small" color="#0000ff" />
            ) : (
              <>
                {/* Top row with logo and product info */}
                <View style={styles.joyLabelTopRow}>
                  {/* Logo section */}
                  <TouchableOpacity onPress={pickImage} style={styles.logoContainer}>
                    {logoUri ? (
                      <Image source={{ uri: logoUri }} style={styles.logo} />
                    ) : (
                      <View style={styles.logoPlaceholder}>
                        <Text style={styles.logoPlaceholderText}>JOY</Text>
                        <Text style={styles.logoUploadText}>Tap to upload</Text>
                      </View>
                    )}
                  </TouchableOpacity>
                  
                  {/* Product info */}
                  <View style={styles.productInfoContainer}>
                    <Text style={styles.productId}>{SAMPLE_ITEM.id}</Text>
                    <Text style={[styles.productName, { fontFamily: 'Fredoka-Regular' }]} numberOfLines={2}>
                      {SAMPLE_ITEM.name}
                    </Text>
                    <Text style={styles.tagline}>{SAMPLE_ITEM.tagline}</Text>
                  </View>
                </View>
                
                {/* Bottom row with barcode and price */}
                <View style={styles.joyLabelBottomRow}>
                  {/* Barcode */}
                  <View style={styles.barcodeContainer}>
                    <Barcode
                      value={SAMPLE_ITEM.barcode || " "}
                      options={{
                        format: 'CODE128',
                        background: '#FFFFFF',
                        lineColor: '#000000',
                        height: 40,
                        width: 1.5,
                        displayValue: false,
                        margin: 0
                      }}
                    />
                    <Text style={styles.joyLabelBarcodeText}>{SAMPLE_ITEM.barcode}</Text>
                  </View>
                  
                  {/* Price */}
                  <View style={styles.joyLabelPriceContainer}>
                    {formatPrice(SAMPLE_ITEM.price)}
                    <Text style={styles.quantifier}>{SAMPLE_ITEM.quantifier}</Text>
                  </View>
                </View>
              </>
            )}
          </View>
        )}
        
        {/* Standard Template */}
        {selectedTemplate === LabelTemplate.STANDARD && (
          <View style={styles.labelPreview}>
            <Text style={styles.previewTitle}>{SAMPLE_ITEM.name}</Text>
            <Text style={styles.previewPrice}>${SAMPLE_ITEM.price.toFixed(2)}</Text>
            <Text style={styles.previewSku}>SKU: {SAMPLE_ITEM.sku}</Text>
          </View>
        )}
        
        {/* Compact Template */}
        {selectedTemplate === LabelTemplate.COMPACT && (
          <View style={styles.compactLabelPreview}>
            <Text style={styles.compactName} numberOfLines={1}>{SAMPLE_ITEM.name}</Text>
            <Text style={styles.compactPrice}>${SAMPLE_ITEM.price.toFixed(2)}</Text>
          </View>
        )}
        
        {/* Barcode Template */}
        {selectedTemplate === LabelTemplate.BARCODE && (
          <View style={styles.barcodeLabelPreview}>
            <Text style={styles.barcodeName}>{SAMPLE_ITEM.name}</Text>
            <View style={styles.barcodePreview}>
              <Barcode
                value={SAMPLE_ITEM.barcode || " "}
                options={{
                  format: 'CODE128',
                  background: '#FFFFFF',
                  lineColor: '#000000',
                  width: 2,
                  height: 80,
                  displayValue: false
                }}
              />
            </View>
            <Text style={styles.barcodeText}>{SAMPLE_ITEM.barcode}</Text>
          </View>
        )}
      </View>
      
      {/* Replace the Future feature - direct printing section with: */}
      <View style={styles.printSection}>
        <Text style={styles.sectionTitle}>Printing</Text>
        
        {isPrinterConfigured ? (
          <View style={styles.printControls}>
            <Text style={[styles.statusText, { marginBottom: 10 }]}>
              Printer status: {printerAvailable === null ? 'Checking...' : printerAvailable ? 'Ready' : 'Not Available'}
            </Text>
            
            <TouchableOpacity 
              style={[
                styles.printButton, 
                (!printerAvailable || isPrinting) && styles.disabledButton
              ]} 
              onPress={handlePrint}
              disabled={!printerAvailable || isPrinting}
            >
              {isPrinting ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <>
                  <Ionicons name="print" size={20} color="#fff" style={styles.printIcon} />
                  <Text style={styles.printButtonText}>Print Label</Text>
                </>
              )}
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.refreshButton}
              onPress={checkPrinterStatus}
              disabled={isPrinting}
            >
              <Ionicons name="refresh" size={20} color="#007BFF" />
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.printNotConfigured}>
            <Text style={styles.printInfo}>
              Printer not configured. Set up your printer in Settings to enable printing.
            </Text>
            <TouchableOpacity 
              style={styles.settingsLink}
              onPress={navigateToSettings}
            >
              <Text style={styles.settingsLinkText}>Open Settings</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
    padding: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
  },
  headerButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  designerButton: {
    padding: 8,
  },
  settingsButton: {
    padding: 8,
  },
  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    padding: 10,
    borderRadius: 8,
    marginBottom: 16,
  },
  statusIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 8,
  },
  statusText: {
    fontSize: 14,
    color: '#555',
  },
  templateContainer: {
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#333',
  },
  templateCard: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    marginRight: 10,
    minWidth: 100,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
  },
  selectedTemplate: {
    borderColor: '#007BFF',
    backgroundColor: '#E6F2FF',
  },
  templateName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  savedDesignsSection: {
    marginBottom: 16,
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  refreshButton: {
    padding: 4,
  },
  savedDesignsScroll: {
    flexGrow: 0,
  },
  savedDesignCard: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    marginRight: 10,
    width: 120,
    borderWidth: 1,
    borderColor: '#ddd',
  },
  savedDesignName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  savedDesignDetails: {
    fontSize: 12,
    color: '#666',
  },
  noDesignsText: {
    fontSize: 14,
    color: '#666',
    fontStyle: 'italic',
    paddingVertical: 10,
  },
  loader: {
    paddingVertical: 10,
  },
  previewContainer: {
    marginBottom: 16,
  },
  labelPreview: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    width: '100%',
    aspectRatio: 2.25 / 1.25,
  },
  previewTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    textAlign: 'center',
  },
  previewPrice: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  previewSku: {
    fontSize: 12,
    color: '#666',
  },
  compactLabelPreview: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    width: '100%',
    height: 60,
  },
  compactName: {
    fontSize: 14,
    fontWeight: '600',
    flex: 1,
    marginRight: 8,
  },
  compactPrice: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  barcodeLabelPreview: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    width: '100%',
    aspectRatio: 2.25 / 1.25,
  },
  barcodeName: {
    fontSize: 14,
    fontWeight: 'bold',
    marginBottom: 8,
    textAlign: 'center',
  },
  barcodePreview: {
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 8,
    width: '100%',
  },
  barcodeText: {
    fontSize: 12,
    letterSpacing: 1,
  },
  printSection: {
    marginBottom: 20,
  },
  printControls: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    borderRadius: 8,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#ddd',
  },
  printButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#4CAF50',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
  },
  disabledButton: {
    backgroundColor: '#9E9E9E',
    opacity: 0.6,
  },
  printButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  printIcon: {
    marginRight: 8,
  },
  printNotConfigured: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    borderRadius: 8,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#ddd',
  },
  settingsLink: {
    marginTop: 10,
    padding: 8,
  },
  settingsLinkText: {
    color: '#007BFF',
    fontSize: 14,
    fontWeight: '600',
  },
  printInfo: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  joyLabelContainer: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    borderWidth: 1,
    borderColor: '#ddd',
    width: '100%',
    aspectRatio: 2.25 / 1.25,
    justifyContent: 'space-between',
  },
  joyLabelTopRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  logoContainer: {
    width: 50,
    height: 50,
    borderRadius: 4,
    overflow: 'hidden',
    marginRight: 8,
  },
  logo: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  logoPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: '#eee',
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoPlaceholderText: {
    fontWeight: 'bold',
    fontSize: 16,
  },
  logoUploadText: {
    fontSize: 6,
    color: '#999',
  },
  productInfoContainer: {
    flex: 1,
  },
  productId: {
    fontSize: 10,
    color: '#999',
  },
  productName: {
    fontSize: 14,
    fontWeight: 'bold',
    marginVertical: 2,
  },
  tagline: {
    fontSize: 10,
    color: '#666',
    fontStyle: 'italic',
  },
  joyLabelBottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
  },
  barcodeContainer: {
    flex: 2,
    alignItems: 'center',
  },
  barcode: {
    marginBottom: 2,
  },
  joyLabelBarcodeText: {
    fontSize: 8,
    letterSpacing: 0.5,
    color: '#333',
  },
  joyLabelPriceContainer: {
    flex: 1,
    alignItems: 'flex-end',
  },
  priceContainer: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  dollarSign: {
    fontSize: 14,
    fontWeight: 'bold',
  },
  dollars: {
    fontSize: 22,
    fontWeight: 'bold',
  },
  cents: {
    fontSize: 14,
    fontWeight: 'bold',
    lineHeight: 18,
  },
  quantifier: {
    fontSize: 10,
    color: '#666',
  },
  customDesignContainer: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    borderWidth: 1,
    borderColor: '#ddd',
    width: '100%',
    aspectRatio: 2.25 / 1.25,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  customDesignText: {
    fontSize: 14,
    color: '#666',
    position: 'absolute',
    top: 5,
    left: 5,
  },
}); 