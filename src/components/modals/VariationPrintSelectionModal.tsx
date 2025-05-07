import React from 'react';
import {
  View,
  Text,
  Modal,
  FlatList,
  TouchableOpacity,
  TouchableWithoutFeedback,
} from 'react-native';
import { styles as itemStyles } from '../../../app/item/itemStyles'; // Adjust path as needed
import { ItemVariation } from '../../../app/item/[id]'; // Assuming ItemVariation is exported or re-defined here

// Re-define ItemVariation if not easily importable, or ensure it's exported from its original location
// For now, let's assume a simplified version for the props
/* // Commenting out ModalItemVariation as we'll use the imported ItemVariation
interface ModalItemVariation {
    id?: string;
    name: string | null;
    sku?: string | null;
    price?: number;
}
*/

interface VariationPrintSelectionModalProps {
  visible: boolean;
  onClose: () => void;
  variations: ItemVariation[]; // Use imported ItemVariation
  onSelectVariation: (index: number) => void; // Passes index to the parent to call initiatePrint
}

const VariationPrintSelectionModal: React.FC<VariationPrintSelectionModalProps> = ({
  visible,
  onClose,
  variations,
  onSelectVariation,
}) => {
  return (
    <Modal
      animationType="slide"
      transparent={true}
      visible={visible}
      onRequestClose={onClose}
    >
      <TouchableWithoutFeedback onPress={onClose}>
        <View style={itemStyles.modalOverlay}>
          <TouchableWithoutFeedback> 
            <View style={itemStyles.variationModalContent}> 
              <Text style={itemStyles.modalTitle}>Select Variation to Print</Text>
              <FlatList
                data={variations}
                keyExtractor={(v, index) => v.id || `variation-${index}`}
                renderItem={({ item: variationItem, index }) => (
                  <TouchableOpacity
                    style={itemStyles.modalItem}
                    onPress={() => {
                      onSelectVariation(index);
                      onClose(); // Close modal after selection
                    }}
                  >
                    <Text style={itemStyles.modalItemText}>{variationItem.name || `Variation ${index + 1}`}</Text>
                    {variationItem.sku && <Text style={itemStyles.modalItemSubText}>SKU: {variationItem.sku}</Text>}
                    {variationItem.price !== undefined && <Text style={itemStyles.modalItemSubText}>Price: ${variationItem.price.toFixed(2)}</Text>}
                  </TouchableOpacity>
                )}
                ItemSeparatorComponent={() => <View style={itemStyles.modalSeparator} />} 
                ListEmptyComponent={<Text style={itemStyles.emptyListText}>No variations found</Text>}
              />
              <TouchableOpacity
                style={itemStyles.closeButton} // Assuming this style exists and is appropriate
                onPress={onClose}
              >
                <Text style={itemStyles.closeButtonText}>Cancel</Text>
              </TouchableOpacity>
            </View>
          </TouchableWithoutFeedback>
        </View>
      </TouchableWithoutFeedback>
    </Modal>
  );
};

export default VariationPrintSelectionModal; 