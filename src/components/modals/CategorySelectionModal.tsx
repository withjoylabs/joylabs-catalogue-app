import React from 'react';
import {
  View,
  Text,
  Modal,
  FlatList,
  TouchableOpacity,
  TextInput,
  TouchableWithoutFeedback,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { styles as itemStyles } from '../../../app/item/itemStyles';

export interface CategoryPickerItemType { id: string; name: string };

interface CategorySelectionModalProps {
  visible: boolean;
  onClose: () => void;
  filteredCategories: CategoryPickerItemType[];
  onSelectCategory: (categoryId: string) => void;
  categorySearch: string;
  setCategorySearch: (search: string) => void;
}

const CategorySelectionModal: React.FC<CategorySelectionModalProps> = ({
  visible,
  onClose,
  filteredCategories,
  onSelectCategory,
  categorySearch,
  setCategorySearch,
}) => {
  return (
    <Modal
      animationType="slide"
      transparent={true}
      visible={visible}
      onRequestClose={onClose}
    >
      <View style={{ flex: 1 }}>
        <TouchableWithoutFeedback onPress={onClose}>
          <View style={itemStyles.modalOverlay}>
            <TouchableWithoutFeedback>
              <View style={itemStyles.modalContent}>
                <Text style={itemStyles.modalTitle}>Select Category</Text>
                <TextInput
                  style={itemStyles.searchInput}
                  placeholder="Search categories..."
                  value={categorySearch}
                  onChangeText={setCategorySearch}
                />
                <FlatList
                  data={filteredCategories}
                  keyExtractor={(cat) => cat.id}
                  renderItem={({ item: cat }) => (
                    <TouchableOpacity
                      style={itemStyles.modalItem}
                      onPress={() => {
                        onSelectCategory(cat.id);
                      }}
                    >
                      <Text style={itemStyles.modalItemText}>{cat.name}</Text>
                    </TouchableOpacity>
                  )}
                  ListEmptyComponent={<Text style={itemStyles.emptyListText}>No matching categories</Text>}
                  style={{ marginTop: 10 }}
                />
                <TouchableOpacity
                  style={itemStyles.closeButton}
                  onPress={onClose}
                >
                  <Text style={itemStyles.closeButtonText}>Close</Text>
                </TouchableOpacity>
              </View>
            </TouchableWithoutFeedback>
          </View>
        </TouchableWithoutFeedback>
      </View>
    </Modal>
  );
};

export default CategorySelectionModal; 