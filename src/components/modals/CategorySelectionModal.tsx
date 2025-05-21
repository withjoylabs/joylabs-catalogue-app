import React from 'react';
import {
  View,
  Text,
  Modal,
  FlatList,
  TouchableOpacity,
  TextInput,
  TouchableWithoutFeedback,
  StyleSheet,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { lightTheme } from '../../themes';

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
      <View style={styles.modalOverlay}> 
        <TouchableWithoutFeedback onPress={onClose}>
          <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}> 
            <TouchableWithoutFeedback>
              <View style={styles.modalContent}>
                <Text style={styles.modalTitle}>Select Category</Text>
                <TextInput
                  style={styles.searchInput}
                  placeholder="Search categories..."
                  placeholderTextColor="#999"
                  value={categorySearch}
                  onChangeText={setCategorySearch}
                />
                <FlatList
                  data={filteredCategories}
                  keyExtractor={(cat) => cat.id}
                  renderItem={({ item: cat }) => (
                    <TouchableOpacity
                      style={styles.modalItem}
                      onPress={() => {
                        onSelectCategory(cat.id);
                      }}
                    >
                      <Text style={styles.modalItemText}>{cat.name}</Text>
                    </TouchableOpacity>
                  )}
                  ListEmptyComponent={<Text style={styles.emptyListText}>No matching categories</Text>}
                  style={styles.listStyle}
                />
                <TouchableOpacity
                  style={styles.closeButton}
                  onPress={onClose}
                >
                  <Text style={styles.closeButtonText}>Close</Text>
                </TouchableOpacity>
              </View>
            </TouchableWithoutFeedback>
          </View>
        </TouchableWithoutFeedback>
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 10,
    padding: 20,
    width: '90%',
    maxHeight: '80%',
    elevation: 5,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 15,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  searchInput: {
    height: 45,
    borderColor: lightTheme.colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 15,
    marginBottom: 15,
    fontSize: 16,
    backgroundColor: lightTheme.colors.background,
    color: lightTheme.colors.text,
  },
  listStyle: {
    maxHeight: '60%',
  },
  modalItem: {
    paddingVertical: 15,
    borderBottomWidth: 1,
    borderBottomColor: lightTheme.colors.border,
  },
  modalItemText: {
    fontSize: 17,
    color: lightTheme.colors.text,
  },
  emptyListText: {
    textAlign: 'center',
    color: '#888',
    fontSize: 16,
    marginTop: 20,
  },
  closeButton: {
    backgroundColor: lightTheme.colors.primary,
    borderRadius: 8,
    paddingVertical: 12,
    marginTop: 20,
    alignItems: 'center',
  },
  closeButtonText: {
    color: 'white',
    fontSize: 17,
    fontWeight: '600',
  },
});

export default CategorySelectionModal; 