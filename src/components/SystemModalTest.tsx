import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, SafeAreaView, ScrollView } from 'react-native';
import SystemModal, { ModalType } from './SystemModal';
import { lightTheme } from '../themes';

const SystemModalTest: React.FC = () => {
  // Modal visibility states
  const [successVisible, setSuccessVisible] = useState(false);
  const [errorVisible, setErrorVisible] = useState(false);
  const [warningVisible, setWarningVisible] = useState(false);
  const [infoVisible, setInfoVisible] = useState(false);
  const [confirmVisible, setConfirmVisible] = useState(false);
  
  // Position variants
  const [topNotificationVisible, setTopNotificationVisible] = useState(false);
  const [bottomNotificationVisible, setBottomNotificationVisible] = useState(false);
  
  // More complex examples
  const [autoCloseVisible, setAutoCloseVisible] = useState(false);
  const [customActionVisible, setCustomActionVisible] = useState(false);

  // Function to handle the confirm action
  const handleConfirmAction = () => {
    console.log('Confirm action triggered');
    // In a real app, this would do something meaningful
  };

  // Function to handle custom action
  const handleCustomAction = () => {
    console.log('Custom action triggered');
    // In a real app, this would do something meaningful
  };

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>System Modal Examples</Text>
      
      <ScrollView style={styles.scrollView}>
        <Text style={styles.sectionTitle}>Modal Types</Text>
        
        {/* Success modal button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setSuccessVisible(true)}
        >
          <Text style={styles.buttonText}>Show Success Modal</Text>
        </TouchableOpacity>
        
        {/* Error modal button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setErrorVisible(true)}
        >
          <Text style={styles.buttonText}>Show Error Modal</Text>
        </TouchableOpacity>
        
        {/* Warning modal button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setWarningVisible(true)}
        >
          <Text style={styles.buttonText}>Show Warning Modal</Text>
        </TouchableOpacity>
        
        {/* Info modal button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setInfoVisible(true)}
        >
          <Text style={styles.buttonText}>Show Info Modal</Text>
        </TouchableOpacity>
        
        {/* Confirm modal button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setConfirmVisible(true)}
        >
          <Text style={styles.buttonText}>Show Confirm Modal</Text>
        </TouchableOpacity>
        
        <Text style={styles.sectionTitle}>Position Variants</Text>
        
        {/* Top notification button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setTopNotificationVisible(true)}
        >
          <Text style={styles.buttonText}>Show Top Notification</Text>
        </TouchableOpacity>
        
        {/* Bottom notification button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setBottomNotificationVisible(true)}
        >
          <Text style={styles.buttonText}>Show Bottom Notification</Text>
        </TouchableOpacity>
        
        <Text style={styles.sectionTitle}>Other Examples</Text>
        
        {/* Auto-close notification button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setAutoCloseVisible(true)}
        >
          <Text style={styles.buttonText}>Show Auto-close Notification</Text>
        </TouchableOpacity>
        
        {/* Custom action button */}
        <TouchableOpacity
          style={styles.button}
          onPress={() => setCustomActionVisible(true)}
        >
          <Text style={styles.buttonText}>Show Modal with Custom Action</Text>
        </TouchableOpacity>
      </ScrollView>
      
      {/* Success Modal */}
      <SystemModal
        visible={successVisible}
        onClose={() => setSuccessVisible(false)}
        title="Success"
        message="The operation was completed successfully."
        type="success"
        primaryButtonText="OK"
      />
      
      {/* Error Modal */}
      <SystemModal
        visible={errorVisible}
        onClose={() => setErrorVisible(false)}
        title="Error"
        message="An error occurred while processing your request. Please try again."
        type="error"
        primaryButtonText="OK"
      />
      
      {/* Warning Modal */}
      <SystemModal
        visible={warningVisible}
        onClose={() => setWarningVisible(false)}
        title="Warning"
        message="This action may have unintended consequences. Are you sure you want to proceed?"
        type="warning"
        primaryButtonText="Continue"
        secondaryButtonText="Cancel"
      />
      
      {/* Info Modal */}
      <SystemModal
        visible={infoVisible}
        onClose={() => setInfoVisible(false)}
        title="Information"
        message="Here's some important information you should know about."
        type="info"
        primaryButtonText="Got it"
      />
      
      {/* Confirm Modal */}
      <SystemModal
        visible={confirmVisible}
        onClose={() => setConfirmVisible(false)}
        title="Confirmation"
        message="Are you sure you want to delete this item? This action cannot be undone."
        type="confirm"
        primaryButtonText="Delete"
        secondaryButtonText="Cancel"
        onPrimaryAction={handleConfirmAction}
      />
      
      {/* Top Notification */}
      <SystemModal
        visible={topNotificationVisible}
        onClose={() => setTopNotificationVisible(false)}
        message="New update available"
        type="info"
        position="top"
      />
      
      {/* Bottom Notification */}
      <SystemModal
        visible={bottomNotificationVisible}
        onClose={() => setBottomNotificationVisible(false)}
        message="Item has been saved"
        type="success"
        position="bottom"
      />
      
      {/* Auto-close Notification */}
      <SystemModal
        visible={autoCloseVisible}
        onClose={() => setAutoCloseVisible(false)}
        message="This notification will close automatically"
        type="info"
        position="top"
        autoClose={true}
        autoCloseTime={3000}
      />
      
      {/* Custom Action Modal */}
      <SystemModal
        visible={customActionVisible}
        onClose={() => setCustomActionVisible(false)}
        title="Custom Action"
        message="This modal demonstrates a custom action with a callback function."
        type="info"
        primaryButtonText="Do Something"
        secondaryButtonText="Cancel"
        onPrimaryAction={handleCustomAction}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  scrollView: {
    flex: 1,
    padding: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginVertical: 16,
    color: '#333',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 24,
    marginBottom: 12,
    color: '#333',
  },
  button: {
    backgroundColor: lightTheme.colors.primary,
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 8,
    marginBottom: 12,
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
});

export default SystemModalTest; 