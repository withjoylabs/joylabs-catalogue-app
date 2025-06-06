import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  Modal,
  FlatList,
  TouchableOpacity,
  TouchableWithoutFeedback,
  StyleSheet,
  Dimensions,
  Platform,
  KeyboardAvoidingView,
} from 'react-native';
import { ItemVariation } from '../../../app/item/[id]';
import { lightTheme } from '../../themes';

interface VariationPrintSelectionModalProps {
  visible: boolean;
  onClose: () => void;
  variations: ItemVariation[];
  onSelectVariation: (index: number) => void;
}

const { height: screenHeight } = Dimensions.get('window');

const VariationPrintSelectionModal: React.FC<VariationPrintSelectionModalProps> = ({
  visible,
  onClose,
  variations,
  onSelectVariation,
}) => {
  return (
    <Modal
      animationType="fade"
      transparent={true}
      visible={visible}
      onRequestClose={onClose}
    >
      <TouchableWithoutFeedback onPress={onClose} accessible={false}>
        <View style={styles.modalOverlay}>
          <KeyboardAvoidingView
            behavior={Platform.OS === "ios" ? "padding" : "height"}
            style={styles.kavWrapper}
            keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 0}
          >
            <TouchableWithoutFeedback onPress={(e) => e.stopPropagation()} accessible={false}>
              <View style={styles.modalContent}>
                <Text style={styles.modalTitle}>Select Variation to Print</Text>
              <FlatList
                data={variations}
                keyExtractor={(v, index) => v.id || `variation-${index}`}
                  renderItem={({ item: variationItem, index }) => {
                    const formattedPrice = typeof variationItem.price === 'number'
                      ? `$${variationItem.price.toFixed(2)}`
                      : (variationItem.price ? String(variationItem.price) : 'N/A');

                    return (
                  <TouchableOpacity
                        style={styles.variationItemButton}
                    onPress={() => {
                      onSelectVariation(index);
                        }}
                      >
                        <View style={styles.variationItemContainer}>
                          <View style={styles.variationDetails}>
                            <Text style={styles.variationName} numberOfLines={1}>
                              {variationItem.name || `Variation ${index + 1}`}
                            </Text>
                            <View style={styles.variationMeta}>
                              {variationItem.sku && (
                                <Text style={styles.variationSku} numberOfLines={1}>
                                  SKU: {variationItem.sku}
                                </Text>
                              )}
                              {variationItem.barcode && (
                                <Text style={styles.variationBarcode} numberOfLines={1}>
                                  UPC: {variationItem.barcode}
                                </Text>
                              )}
                            </View>
                          </View>
                          <View style={styles.variationPriceContainer}>
                            <Text style={styles.variationPriceText}>{formattedPrice}</Text>
                          </View>
                        </View>
                  </TouchableOpacity>
                    );
                  }}
                  ListEmptyComponent={<View style={styles.emptyListContainer}><Text style={styles.emptyListText}>No variations found</Text></View>}
                  style={styles.listStyle}
                  contentContainerStyle={styles.listContentContainer}
              />
              <TouchableOpacity
                  style={styles.closeButton}
                onPress={onClose}
              >
                  <Text style={styles.closeButtonText}>Cancel</Text>
              </TouchableOpacity>
            </View>
          </TouchableWithoutFeedback>
          </KeyboardAvoidingView>
        </View>
      </TouchableWithoutFeedback>
    </Modal>
  );
};

const styles = StyleSheet.create({
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  kavWrapper: {
    width: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 15,
    padding: 20,
    width: '90%',
    maxWidth: 500,
    maxHeight: screenHeight * 0.70,
    minHeight: screenHeight * 0.25,
    elevation: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    display: 'flex',
    flexDirection: 'column',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 18,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  listStyle: {
    flex: 1,
    marginTop: 10,
  },
  listContentContainer: {
    paddingBottom: 5,
  },
  variationItemButton: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  variationItemContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  variationDetails: {
    flex: 1,
    marginRight: 10,
  },
  variationName: {
    fontSize: 16,
    fontWeight: '600',
    color: lightTheme.colors.text,
    marginBottom: 3,
  },
  variationMeta: {
  },
  variationSku: {
    fontSize: 13,
    color: lightTheme.colors.text,
    marginBottom: 2,
  },
  variationBarcode: {
    fontSize: 13,
    color: lightTheme.colors.text,
  },
  variationPriceContainer: {
  },
  variationPriceText: {
    fontSize: 16,
    fontWeight: '500',
    color: lightTheme.colors.text,
  },
  closeButton: {
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 10,
    paddingVertical: 14,
    paddingHorizontal: 25,
    marginTop: 18,
    alignSelf: 'center',
  },
  closeButtonText: {
    color: 'white',
    fontSize: 17,
    fontWeight: '500',
  },
  emptyListContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 20,
  },
  emptyListText: {
    textAlign: 'center',
    color: '#777',
    fontSize: 16,
  },
});

export default VariationPrintSelectionModal; 