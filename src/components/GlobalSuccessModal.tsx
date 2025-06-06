import React from 'react';
import { useAppStore } from '../store';
import SystemModal from './SystemModal';

const GlobalSuccessModal = () => {
  const showSuccessNotification = useAppStore(state => state.showSuccessNotification);
  const successMessage = useAppStore(state => state.successMessage);
  const setShowSuccessNotification = useAppStore(state => state.setShowSuccessNotification);

  if (!showSuccessNotification) {
    return null;
  }

  return (
    <SystemModal
      visible={showSuccessNotification}
      onClose={() => setShowSuccessNotification(false)}
      message={successMessage || 'Operation successful!'}
      type="success"
      position="top"
      autoClose={true}
      autoCloseTime={2000}
    />
  );
};

export default GlobalSuccessModal; 