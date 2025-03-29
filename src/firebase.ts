import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import config from './config';

// Initialize Firebase
const app = initializeApp(config.firebase);
const auth = getAuth(app);
const firestore = getFirestore(app);

// Function to get custom token for merchant authentication
export const getCustomToken = async (merchantId: string) => {
  try {
    const response = await fetch(`${config.apiUrl}/getCustomToken?merchant_id=${merchantId}`);
    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.error || 'Failed to get custom token');
    }
    
    return data.customToken;
  } catch (error) {
    console.error('Error getting custom token:', error);
    throw error;
  }
};

export { app, auth, firestore }; 