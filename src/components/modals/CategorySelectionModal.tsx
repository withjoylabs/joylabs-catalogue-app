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
  KeyboardAvoidingView,
  Platform,
  Dimensions,
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

const { height: screenHeight, width: screenWidth } = Dimensions.get('window');

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
      animationType="fade"
      transparent={true}
      visible={visible}
      onRequestClose={onClose}
    >
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        style={styles.kavOuterWrapper}
      >
        <TouchableWithoutFeedback onPress={onClose}>
          <View style={styles.modalOverlay}>
            <TouchableWithoutFeedback onPress={(e) => e.stopPropagation()}>
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
                  ListEmptyComponent={<View style={styles.emptyListContainer}><Text style={styles.emptyListText}>No matching categories</Text></View>}
                  style={styles.listStyle}
                  contentContainerStyle={styles.listContentContainer}
                  keyboardShouldPersistTaps="handled"
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
      </KeyboardAvoidingView>
    </Modal>
  );
};

const styles = StyleSheet.create({
  kavOuterWrapper: {
    flex: 1,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  modalContent: {
    backgroundColor: lightTheme.colors.card,
    borderRadius: 15,
    padding: 20,
    width: '90%',
    maxWidth: 600,
    maxHeight: screenHeight * 0.75,
    minHeight: screenHeight * 0.6,
    elevation: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 6,
    display: 'flex',
    flexDirection: 'column',
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 18,
    textAlign: 'center',
    color: lightTheme.colors.text,
  },
  searchInput: {
    height: 48,
    borderColor: lightTheme.colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    marginBottom: 18,
    fontSize: 16,
    backgroundColor: lightTheme.colors.background,
    color: lightTheme.colors.text,
  },
  listStyle: {
    flex: 1,
  },
  listContentContainer: {
    paddingBottom: 5,
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
});

export default CategorySelectionModal; 