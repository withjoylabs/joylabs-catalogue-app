export const OAUTH_CONFIG = {
  // Square OAuth endpoints
  SQUARE_AUTH_URL: 'https://connect.squareup.com/oauth2/authorize',
  SQUARE_TOKEN_URL: 'https://connect.squareup.com/oauth2/token',
  
  // Backend API endpoints
  BACKEND_URL: 'https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production',
  AUTH_ENDPOINT: '/api/auth/square',
  TOKEN_EXCHANGE_ENDPOINT: '/api/auth/square/token',
  
  // AuthSession configuration
  CALLBACK_SCHEME: 'joylabs',
  CALLBACK_PATH: 'square-callback',
  
  // Square configuration
  CLIENT_ID: 'sq0idp-WFTYv3An7NPv6ovGFLld1Q',
  SCOPES: ['MERCHANT_PROFILE_READ', 'ITEMS_READ', 'ITEMS_WRITE'],
  
  // PKCE configuration
  CODE_CHALLENGE_METHOD: 'S256'
}; 