import * as Crypto from 'expo-crypto';
import { Buffer } from 'buffer';

// Generate a random code verifier string that meets the PKCE requirements
// Must be between 43-128 characters, using only A-Z, a-z, 0-9, and -._~
export const generateCodeVerifier = async (length: number = 64): Promise<string> => {
  // Allowed characters for code verifier (RFC 7636)
  const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  
  // Generate random bytes
  const randomValues = await Crypto.getRandomBytesAsync(length);
  const array = Array.from(randomValues);
  
  // Convert to string using only allowed characters
  let result = '';
  for (let i = 0; i < array.length; i++) {
    result += characters.charAt(array[i] % characters.length);
  }
  
  // Verify the code verifier meets the requirements
  const validVerifier = /^[A-Za-z0-9\-._~]{43,128}$/;
  if (!validVerifier.test(result)) {
    console.warn('Generated code verifier does not meet PKCE requirements, regenerating...');
    return generateCodeVerifier(length);
  }
  
  return result;
};

// Generate a code challenge from the code verifier using SHA-256
export const generateCodeChallenge = async (codeVerifier: string): Promise<string> => {
  try {
    // Generate SHA-256 hash of the code verifier
    const hash = await Crypto.digestStringAsync(
      Crypto.CryptoDigestAlgorithm.SHA256,
      codeVerifier
    );
    
    // Convert the hash to a base64url encoded string
    return Buffer.from(hash, 'hex')
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  } catch (error) {
    console.error('Error generating code challenge:', error);
    throw new Error('Failed to generate code challenge for PKCE');
  }
};

// Generate a random state string for CSRF protection
export const generateState = async (length: number = 48): Promise<string> => {
  return generateCodeVerifier(length);
}; 